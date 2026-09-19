import asyncio

from . import reservations


async def run_scheduler_loop() -> None:
    while True:
        # Cleared before the sweep so a reservation created during it still wakes the wait below.
        reservations.new_pending.clear()
        try:
            await reservations.process_due()
            timeout = await reservations.seconds_until_next_due()
        except Exception as exc:
            print(f"[scheduler] error: {exc}")
            timeout = 1
        try:
            await asyncio.wait_for(reservations.new_pending.wait(), timeout)
        except asyncio.TimeoutError:
            pass
