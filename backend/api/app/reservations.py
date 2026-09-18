import asyncio
import uuid
from datetime import date, datetime
from typing import Any

import aiosqlite

from . import google_form, push
from .formatting import submission_text
from .scheduling import TAIPEI, compute_fire_date
from .storage import connect

# Guards the pending -> submitting claim below. This process is the only writer of that
# transition, so an in-process lock is sufficient (and simpler to reason about than relying on
# cross-connection SQLite locking) to guarantee a reservation is never claimed by two concurrent
# submit attempts at once.
_submit_lock = asyncio.Lock()


def _row_to_dict(row: aiosqlite.Row) -> dict[str, Any]:
    d = dict(row)
    d["submission_text"] = submission_text(
        date.fromisoformat(d["course_date"]), d["course_time"], d["course_name"]
    )
    return d


async def create_reservation(
    course_id: str, course_date: str, course_time: str, course_name: str,
    reporter_name: str, employee_id: str,
) -> dict[str, Any]:
    """Idempotent per course: a second call for a course that already has a reservation just
    returns the existing one instead of creating a duplicate — both via an upfront check and a
    UNIQUE constraint on course_id to close the race if two requests land at the same time."""
    async with connect() as db:
        cursor = await db.execute("SELECT * FROM reservations WHERE course_id = ?", (course_id,))
        existing = await cursor.fetchone()
        if existing:
            return _row_to_dict(existing)

        cdate = date.fromisoformat(course_date)
        now = datetime.now(TAIPEI).replace(microsecond=0)
        fire_date = compute_fire_date(cdate, now=now)
        reservation_id = str(uuid.uuid4())

        try:
            await db.execute(
                """INSERT INTO reservations
                   (id, course_id, course_date, course_time, course_name, reporter_name,
                    employee_id, fire_date, status, submitted_at, http_status, last_error, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', NULL, NULL, NULL, ?)""",
                (reservation_id, course_id, course_date, course_time, course_name,
                 reporter_name, employee_id, fire_date.isoformat(), now.isoformat()),
            )
            await db.commit()
        except aiosqlite.IntegrityError:
            cursor = await db.execute("SELECT * FROM reservations WHERE course_id = ?", (course_id,))
            row = await cursor.fetchone()
            return _row_to_dict(row)

    if fire_date <= now:
        return await _submit(reservation_id)

    async with connect() as db:
        cursor = await db.execute("SELECT * FROM reservations WHERE id = ?", (reservation_id,))
        row = await cursor.fetchone()
    return _row_to_dict(row)


async def list_reservations() -> list[dict[str, Any]]:
    async with connect() as db:
        cursor = await db.execute("SELECT * FROM reservations ORDER BY course_date, course_time")
        rows = await cursor.fetchall()
    return [_row_to_dict(r) for r in rows]


async def cancel_reservation(reservation_id: str) -> bool:
    async with connect() as db:
        cursor = await db.execute(
            "DELETE FROM reservations WHERE id = ? AND status != 'submitting'", (reservation_id,)
        )
        await db.commit()
        return cursor.rowcount > 0


async def process_due() -> None:
    now = datetime.now(TAIPEI).replace(microsecond=0)
    async with connect() as db:
        cursor = await db.execute(
            "SELECT id FROM reservations WHERE status = 'pending' AND fire_date <= ?",
            (now.isoformat(),),
        )
        due_ids = [r["id"] for r in await cursor.fetchall()]

    for reservation_id in due_ids:
        await _submit(reservation_id)


async def recover_stuck_submissions() -> None:
    """A reservation left in `submitting` means the process died mid-request last run — the
    POST's outcome is unknown, so it's marked failed rather than silently retried: retrying an
    ambiguous outcome risks a real duplicate booking, since Google Forms has no de-duplication."""
    async with connect() as db:
        await db.execute(
            """UPDATE reservations SET status = 'failed',
               last_error = '上次送出時服務被中止，無法確認是否已成功報名，請手動確認，避免重複送出'
               WHERE status = 'submitting'"""
        )
        await db.commit()


async def register_device(token: str) -> None:
    async with connect() as db:
        await db.execute(
            "INSERT INTO devices (token, registered_at) VALUES (?, ?) "
            "ON CONFLICT(token) DO UPDATE SET registered_at = excluded.registered_at",
            (token, datetime.now(TAIPEI).replace(microsecond=0).isoformat()),
        )
        await db.commit()


async def _submit(reservation_id: str) -> dict[str, Any]:
    """Atomically claims the reservation (pending -> submitting) before doing anything that
    awaits, so two overlapping sweeps (or a request landing at the exact fire moment) can never
    both submit the same reservation — the UPDATE...WHERE status='pending' only succeeds once."""
    async with _submit_lock:
        async with connect() as db:
            cursor = await db.execute(
                "UPDATE reservations SET status = 'submitting' WHERE id = ? AND status = 'pending'",
                (reservation_id,),
            )
            await db.commit()
            claimed = cursor.rowcount > 0

            cursor = await db.execute("SELECT * FROM reservations WHERE id = ?", (reservation_id,))
            row = await cursor.fetchone()

    if not claimed:
        return _row_to_dict(row)

    course_text = submission_text(
        date.fromisoformat(row["course_date"]), row["course_time"], row["course_name"]
    )

    status = "failed"
    http_status = None
    last_error = None
    try:
        http_status = await google_form.submit_form(row["reporter_name"], row["employee_id"], course_text)
        ok = 200 <= http_status < 300
        status = "submitted" if ok else "failed"
        last_error = None if ok else f"表單回應狀態碼 {http_status}"
    except Exception as exc:
        last_error = str(exc)

    submitted_at = datetime.now(TAIPEI).replace(microsecond=0).isoformat()
    async with connect() as db:
        await db.execute(
            """UPDATE reservations SET status = ?, submitted_at = ?, http_status = ?, last_error = ?
               WHERE id = ?""",
            (status, submitted_at, http_status, last_error, reservation_id),
        )
        await db.commit()
        cursor = await db.execute("SELECT * FROM reservations WHERE id = ?", (reservation_id,))
        row = await cursor.fetchone()

    await _notify_result(course_text, status, last_error)
    return _row_to_dict(row)


async def _notify_result(course_text: str, status: str, last_error: str | None) -> None:
    async with connect() as db:
        cursor = await db.execute("SELECT token FROM devices")
        tokens = [r["token"] for r in await cursor.fetchall()]

    if status == "submitted":
        title, body = "報名已送出", f"{course_text} 已送出"
    else:
        title, body = "報名送出失敗", f"{course_text}：{last_error or '請打開 App 查看'}"

    for token in tokens:
        await push.send_push(token, title, body)
