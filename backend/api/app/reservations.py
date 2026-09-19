import asyncio
import uuid
from datetime import date, datetime, timedelta
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

# At 08:00 many reservations come due at once: submit them in parallel, but cap how many
# Chromium instances run together (~160MB peak each on the 961MB / 1 vCPU VPS). Every real
# submit goes through _submit, so this one semaphore covers the scheduler and immediate paths.
MAX_CONCURRENT_SUBMITS = 2
_submit_slots = asyncio.Semaphore(MAX_CONCURRENT_SUBMITS)

# Set when a reservation is created so the scheduler re-plans its sleep: one made at 07:59:50
# for an 08:00:00 class must not wait out a sleep that was planned before it existed.
new_pending = asyncio.Event()

# Safety cap, independent of the per-reservation guards above: for a given (employee, class
# date, class time, class name) — i.e. "this person's booking for this specific class on this
# specific day" — no more than this many real POSTs to Google Forms in any rolling window of this
# length, successful or not (this counts *attempts*, since Google gives no reliable success
# signal to distinguish them). Scoped per employee/day/class rather than globally, so booking
# one class never eats into the attempt budget for a different one. And once any attempt for
# that combination has actually succeeded, no further attempt is ever made for it again,
# regardless of the window — there's nothing left to retry. Self-healing: once an attempt ages
# out of the window it stops counting toward the cap, so no manual reset is needed — but it
# means a genuine runaway bug is mathematically capped at this many real submissions per
# window, per (employee, day, class), forever, no matter how long the bug goes unnoticed.
# The one deliberate way out is a human: cancelling a *failed* reservation (see
# cancel_reservation) clears that class's failed attempts so they can book it again by hand.
MAX_ATTEMPTS_PER_WINDOW = 2
ATTEMPT_WINDOW = timedelta(days=6)


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
    """Idempotent per (course, employee): a second call for a class that this person already
    has a reservation for just returns the existing one instead of creating a duplicate — both
    via an upfront check and a UNIQUE (course_id, employee_id) constraint to close the race if
    two requests land at the same time. Different people booking the same class each get their
    own reservation."""
    reporter_name, employee_id = reporter_name.strip(), employee_id.strip()
    async with connect() as db:
        cursor = await db.execute(
            "SELECT * FROM reservations WHERE course_id = ? AND employee_id = ?", (course_id, employee_id)
        )
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
            new_pending.set()
        except aiosqlite.IntegrityError:
            cursor = await db.execute(
                "SELECT * FROM reservations WHERE course_id = ? AND employee_id = ?", (course_id, employee_id)
            )
            row = await cursor.fetchone()
            return _row_to_dict(row)

    if fire_date <= now:
        return await _submit(reservation_id)

    async with connect() as db:
        cursor = await db.execute("SELECT * FROM reservations WHERE id = ?", (reservation_id,))
        row = await cursor.fetchone()
    return _row_to_dict(row)


async def list_reservations(employee_id: str | None = None) -> list[dict[str, Any]]:
    """`employee_id=None` means everyone's — callers must only pass that for an admin."""
    where, args = ("WHERE employee_id = ?", (employee_id.strip(),)) if employee_id is not None else ("", ())
    async with connect() as db:
        cursor = await db.execute(f"SELECT * FROM reservations {where} ORDER BY course_date, course_time", args)
        rows = await cursor.fetchall()
    return [_row_to_dict(r) for r in rows]


async def cancel_reservation(reservation_id: str, employee_id: str | None = None) -> bool:
    """Deleting the row is the whole cancel: the scheduler only ever reads this table, so a
    deleted reservation can't fire. Only pending (not yet sent) and failed (nothing to undo)
    rows can go — submitting is mid-POST and submitted can't be recalled from Google Forms.
    `employee_id` restricts it to that person's own row (a mismatch looks like "not found");
    None is the admin override.

    Cancelling a failed row also forgets that class's failed attempts: it's the human "I've
    checked, let me retry" signal, so the safety cap no longer locks them out for days."""
    owner, args = ("AND employee_id = ?", (employee_id.strip(),)) if employee_id is not None else ("", ())
    async with connect() as db:
        cursor = await db.execute(
            f"SELECT * FROM reservations WHERE id = ? AND status IN ('pending', 'failed') {owner}",
            (reservation_id, *args),
        )
        row = await cursor.fetchone()
        if row is None:
            return False
        cursor = await db.execute(
            "DELETE FROM reservations WHERE id = ? AND status IN ('pending', 'failed')", (reservation_id,)
        )
        if cursor.rowcount and row["status"] == "failed":
            await db.execute(
                """DELETE FROM submission_attempts WHERE succeeded = 0 AND employee_id = ?
                   AND course_date = ? AND course_time = ? AND course_name = ?""",
                (row["employee_id"], row["course_date"], row["course_time"], row["course_name"]),
            )
        await db.commit()
        return cursor.rowcount > 0


async def cancel_pending(ids: list[str]) -> int:
    """Bulk cancel for the admin screen. Pending only (not failed): "cancel everything
    scheduled". Anything already submitting/submitted is left alone, same as a single cancel."""
    if not ids:
        return 0
    marks = ",".join("?" * len(ids))
    async with connect() as db:
        cursor = await db.execute(
            f"DELETE FROM reservations WHERE status = 'pending' AND id IN ({marks})", ids
        )
        await db.commit()
        return cursor.rowcount


async def process_due() -> None:
    now = datetime.now(TAIPEI).replace(microsecond=0)
    async with connect() as db:
        cursor = await db.execute(
            "SELECT id FROM reservations WHERE status = 'pending' AND fire_date <= ?",
            (now.isoformat(),),
        )
        due_ids = [r["id"] for r in await cursor.fetchall()]

    await asyncio.gather(*(_submit(reservation_id) for reservation_id in due_ids))


async def seconds_until_next_due() -> float:
    """How long the scheduler may sleep: until the earliest pending fire_date, at most 30s (a
    safety net for anything that slips past new_pending). The small pad keeps a wake-up that
    lands a hair early from finding nothing due yet, since process_due truncates to seconds."""
    async with connect() as db:
        cursor = await db.execute("SELECT MIN(fire_date) AS f FROM reservations WHERE status = 'pending'")
        earliest = (await cursor.fetchone())["f"]
    if earliest is None:
        return 30
    gap = (datetime.fromisoformat(earliest) - datetime.now(TAIPEI)).total_seconds()
    # gap <= 0 with rows still pending means a sweep just failed; don't spin on it.
    return 1 if gap <= 0 else min(gap + 0.02, 30)


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


async def register_device(token: str, employee_id: str) -> None:
    """One device belongs to one person: re-registering a token under another employee (the
    app's employee ID changed) moves it, so pushes follow the current owner only."""
    async with connect() as db:
        await db.execute(
            "INSERT INTO devices (token, employee_id, registered_at) VALUES (?, ?, ?) "
            "ON CONFLICT(token) DO UPDATE SET employee_id = excluded.employee_id, "
            "registered_at = excluded.registered_at",
            (token, employee_id.strip(), datetime.now(TAIPEI).replace(microsecond=0).isoformat()),
        )
        await db.commit()


async def _submit(reservation_id: str) -> dict[str, Any] | None:
    """Atomically claims the reservation (pending -> submitting) before doing anything that
    awaits, so two overlapping sweeps (or a request landing at the exact fire moment) can never
    both submit the same reservation — the UPDATE...WHERE status='pending' only succeeds once.
    Also enforces the per-(employee, day, class) MAX_ATTEMPTS_PER_WINDOW cap: claiming and the
    attempt-count check+log happen under the same lock so the count itself can't be raced."""
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
            # row is None if it was cancelled after the caller picked this id up.
            return _row_to_dict(row) if row else None

        now = datetime.now(TAIPEI).replace(microsecond=0)
        cutoff = (now - ATTEMPT_WINDOW).isoformat()
        scope = (row["employee_id"], row["course_date"], row["course_time"], row["course_name"])
        async with connect() as db:
            cursor = await db.execute(
                """SELECT COUNT(*) AS n FROM submission_attempts
                   WHERE employee_id = ? AND course_date = ? AND course_time = ? AND course_name = ?
                   AND succeeded = 1""",
                scope,
            )
            already_succeeded = (await cursor.fetchone())["n"] > 0

            cursor = await db.execute(
                """SELECT COUNT(*) AS n FROM submission_attempts
                   WHERE employee_id = ? AND course_date = ? AND course_time = ? AND course_name = ?
                   AND attempted_at >= ?""",
                (*scope, cutoff),
            )
            recent_attempts = (await cursor.fetchone())["n"]

            blocked_reason = None
            if already_succeeded:
                blocked_reason = "already_succeeded"
            elif recent_attempts >= MAX_ATTEMPTS_PER_WINDOW:
                blocked_reason = "max_attempts"

            attempt_id = None
            if blocked_reason is None:
                cursor = await db.execute(
                    """INSERT INTO submission_attempts
                       (employee_id, course_date, course_time, course_name, attempted_at, succeeded)
                       VALUES (?, ?, ?, ?, ?, 0)""",
                    (*scope, now.isoformat()),
                )
                await db.commit()
                attempt_id = cursor.lastrowid

    if blocked_reason is not None:
        return await _mark_blocked(reservation_id, blocked_reason)

    course_text = submission_text(
        date.fromisoformat(row["course_date"]), row["course_time"], row["course_name"]
    )

    status = "failed"
    http_status = None
    last_error = None
    try:
        async with _submit_slots:
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
        if status == "submitted" and attempt_id is not None:
            await db.execute("UPDATE submission_attempts SET succeeded = 1 WHERE id = ?", (attempt_id,))
        await db.commit()
        cursor = await db.execute("SELECT * FROM reservations WHERE id = ?", (reservation_id,))
        row = await cursor.fetchone()

    await _notify_result(row["employee_id"], course_text, status, last_error)
    return _row_to_dict(row)


async def _mark_blocked(reservation_id: str, reason: str) -> dict[str, Any]:
    """Hit the safety cap — refuse to submit, and make sure it's loud (marked failed with an
    explicit reason, plus a push) rather than silently dropped, since hitting this at all is
    unusual enough to be worth a human's attention."""
    if reason == "already_succeeded":
        message = "這位員工這一天的這堂課先前已經成功送出過了，不會重複送出"
    else:
        message = (
            f"這位員工這一天這堂課，{ATTEMPT_WINDOW.days} 天內已經嘗試送出 {MAX_ATTEMPTS_PER_WINDOW} 次，"
            "這筆沒有送出，請確認沒有異常後，在 App 取消這筆再重新預約"
        )
    async with connect() as db:
        await db.execute(
            "UPDATE reservations SET status = 'failed', last_error = ? WHERE id = ?",
            (message, reservation_id),
        )
        await db.commit()
        cursor = await db.execute("SELECT * FROM reservations WHERE id = ?", (reservation_id,))
        row = await cursor.fetchone()

    course_text = submission_text(
        date.fromisoformat(row["course_date"]), row["course_time"], row["course_name"]
    )
    await _notify_result(row["employee_id"], course_text, "failed", message)
    return _row_to_dict(row)


async def _notify_result(employee_id: str, course_text: str, status: str, last_error: str | None) -> None:
    async with connect() as db:
        cursor = await db.execute("SELECT token FROM devices WHERE employee_id = ?", (employee_id,))
        tokens = [r["token"] for r in await cursor.fetchall()]

    if status == "submitted":
        title, body = "報名已送出", f"{course_text} 已送出"
    else:
        title, body = "報名送出失敗", f"{course_text}：{last_error or '請打開 App 查看'}"

    for token in tokens:
        await push.send_push(token, title, body)
