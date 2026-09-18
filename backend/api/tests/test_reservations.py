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

    # Global safety cap: no more than MAX_ATTEMPTS_PER_WINDOW real POSTs to Google Forms within
    # ATTEMPT_WINDOW, across every reservation combined, regardless of what triggers them.
    # The two scenarios above already logged 2 real attempts of their own — clear those first
    # so this section starts from a clean slate.
    async with storage.connect() as db:
        await db.execute("DELETE FROM submission_attempts")
        await db.commit()
    fake_submit_form.calls.clear()
    google_form.submit_form = fake_submit_form
    assert reservations.MAX_ATTEMPTS_PER_WINDOW == 2, "test assumes the cap is 2"

    results = []
    for i in range(3):
        course_date = (date.today() + timedelta(days=2)).isoformat()
        results.append(await reservations.create_reservation(
            course_id=f"cap-test-{i}", course_date=course_date, course_time="0900",
            course_name=f"上限測試{i}", reporter_name="測試", employee_id="E004",
        ))

    assert results[0]["status"] == "submitted", results[0]
    assert results[1]["status"] == "submitted", results[1]
    assert results[2]["status"] == "failed", results[2]
    assert "安全上限" in (results[2]["last_error"] or ""), results[2]
    assert len(fake_submit_form.calls) == 2, f"expected exactly 2 real submits, got {len(fake_submit_form.calls)}"
    print("PASS: 3rd submission within the window is blocked by the global safety cap")


asyncio.run(main())
