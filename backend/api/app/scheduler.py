import asyncio

from . import reservations

POLL_INTERVAL_SECONDS = 30


async def run_scheduler_loop() -> None:
    while True:
        try:
            await reservations.process_due()
        except Exception as exc:
            print(f"[scheduler] error: {exc}")
        await asyncio.sleep(POLL_INTERVAL_SECONDS)
