import asyncio
import os
import sys
import tempfile

os.environ.setdefault("BEARER_TOKEN", "test-token-123")
_db_fd, _db_path = tempfile.mkstemp(suffix=".db", prefix="jofit_test_")
os.close(_db_fd)
os.remove(_db_path)
os.environ["DB_PATH"] = _db_path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from datetime import date, timedelta

from app import google_form, reservations, storage


async def fake_submit_form(name, employee_id, course_text):
    fake_submit_form.calls.append((name, employee_id, course_text))
    await asyncio.sleep(0.05)
    return 200


fake_submit_form.calls = []


async def main():
    google_form.submit_form = fake_submit_form
    await storage.init_db()

    near_date = (date.today() + timedelta(days=2)).isoformat()

    # Course is only 2 days away (< 6-day window), so this should submit immediately.
    result = await reservations.create_reservation(
        course_id="near-1", course_date=near_date, course_time="0900",
        course_name="近期課程", reporter_name="測試", employee_id="E002",
    )
    assert result["status"] == "submitted", result
    assert result["http_status"] == 200, result
    assert len(fake_submit_form.calls) == 1, fake_submit_form.calls
    print("PASS: immediate submit ->", result["status"], result["submission_text"])

    # Duplicate-submit guard: fire two concurrent process_due sweeps against a reservation
    # whose fire_date is already due, using a slow fake submit — only one should actually POST.
    fake_submit_form.calls.clear()

    async def slow_submit_form(name, employee_id, course_text):
        await asyncio.sleep(0.3)
        fake_submit_form.calls.append((name, employee_id, course_text))
        return 200

    google_form.submit_form = slow_submit_form

    past_date = (date.today() - timedelta(days=10)).isoformat()  # already well past fire time
    # Insert a pending row directly (bypassing create_reservation, which would submit it
    # immediately on its own) so process_due is the only thing racing to claim it.
    async with storage.connect() as db:
        await db.execute(
            """INSERT INTO reservations
               (id, course_id, course_date, course_time, course_name, reporter_name,
                employee_id, fire_date, status, submitted_at, http_status, last_error, created_at)
               VALUES ('race-id', 'race-1', ?, '0900', '搶課測試', '測試', 'E003',
                       '2020-01-01T00:00:00+08:00', 'pending', NULL, NULL, NULL, '2020-01-01T00:00:00+08:00')""",
            (past_date,),
        )
        await db.commit()

    await asyncio.gather(reservations.process_due(), reservations.process_due())
    assert len(fake_submit_form.calls) == 1, f"expected exactly 1 submit, got {len(fake_submit_form.calls)}"
    print("PASS: overlapping process_due sweeps only submitted once")

    # Safety cap is scoped per (employee, class date, class name) — starting clean.
    async with storage.connect() as db:
        await db.execute("DELETE FROM submission_attempts")
        await db.commit()
    assert reservations.MAX_ATTEMPTS_PER_WINDOW == 2, "test assumes the cap is 2"
    cap_date = (date.today() + timedelta(days=2)).isoformat()

    # A: max-attempts branch — every attempt fails (never "succeeds"), so the 3rd attempt for
    # the same (employee, date, name) should be blocked on attempt count, not on already-succeeded.
    async def always_fail(name, employee_id, course_text):
        fake_submit_form.calls.append((name, employee_id, course_text))
        return 400

    google_form.submit_form = always_fail
    fake_submit_form.calls.clear()

    results_a = []
    for i in range(3):
        results_a.append(await reservations.create_reservation(
            course_id=f"cap-a-{i}", course_date=cap_date, course_time="0900",
            course_name="上限測試A", reporter_name="測試", employee_id="E004",
        ))
    assert results_a[0]["status"] == "failed" and results_a[0]["http_status"] == 400, results_a[0]
    assert results_a[1]["status"] == "failed" and results_a[1]["http_status"] == 400, results_a[1]
    assert results_a[2]["status"] == "failed" and results_a[2]["http_status"] is None, results_a[2]
    assert "已經嘗試送出" in (results_a[2]["last_error"] or ""), results_a[2]
    assert len(fake_submit_form.calls) == 2, f"expected exactly 2 real attempts, got {len(fake_submit_form.calls)}"
    print("PASS: 3rd attempt for the same employee+day+class is blocked (max attempts)")

    # B: already-succeeded branch — first attempt succeeds, so a *second* attempt for the same
    # (employee, date, name) should be blocked immediately, without needing to reach the count cap.
    google_form.submit_form = fake_submit_form
    fake_submit_form.calls.clear()

    result_b1 = await reservations.create_reservation(
        course_id="cap-b-0", course_date=cap_date, course_time="1000",
        course_name="上限測試B", reporter_name="測試", employee_id="E005",
    )
    result_b2 = await reservations.create_reservation(
        course_id="cap-b-1", course_date=cap_date, course_time="1000",
        course_name="上限測試B", reporter_name="測試", employee_id="E005",
    )
    assert result_b1["status"] == "submitted", result_b1
    assert result_b2["status"] == "failed", result_b2
    assert "已經成功送出過" in (result_b2["last_error"] or ""), result_b2
    assert len(fake_submit_form.calls) == 1, f"expected exactly 1 real submit, got {len(fake_submit_form.calls)}"
    print("PASS: a second attempt after one already succeeded is blocked immediately")

    # C: scoping — a *different* employee/class isn't affected by A's or B's attempt history.
    fake_submit_form.calls.clear()
    result_c = await reservations.create_reservation(
        course_id="cap-c-0", course_date=cap_date, course_time="1100",
        course_name="上限測試C", reporter_name="測試", employee_id="E006",
    )
    assert result_c["status"] == "submitted", result_c
    assert len(fake_submit_form.calls) == 1, fake_submit_form.calls
    print("PASS: a different employee+class combination is unaffected by others' attempt history")

    # Cancel: a deleted reservation must never fire, even if it's already due.
    fake_submit_form.calls.clear()
    async with storage.connect() as db:
        await db.execute(
            """INSERT INTO reservations
               (id, course_id, course_date, course_time, course_name, reporter_name,
                employee_id, fire_date, status, submitted_at, http_status, last_error, created_at)
               VALUES ('cancel-id', 'cancel-1', ?, '0900', '取消測試', '測試', 'E007',
                       '2020-01-01T00:00:00+08:00', 'pending', NULL, NULL, NULL, '2020-01-01T00:00:00+08:00')""",
            (past_date,),
        )
        await db.commit()
    assert await reservations.cancel_reservation("cancel-id") is True
    await reservations.process_due()
    assert not fake_submit_form.calls, fake_submit_form.calls
    assert await reservations.cancel_reservation("cancel-id") is False  # already gone
    assert await reservations._submit("cancel-id") is None  # cancelled between select and claim
    print("PASS: cancelled reservation never fires; late claim on it is a no-op")

    # Cancel refuses submitted (result_c above), allows failed (results_a[0]).
    assert await reservations.cancel_reservation(result_c["id"]) is False
    assert any(r["id"] == result_c["id"] for r in await reservations.list_reservations())
    assert await reservations.cancel_reservation(results_a[0]["id"]) is True
    print("PASS: submitted can't be cancelled, failed can")


asyncio.run(main())
