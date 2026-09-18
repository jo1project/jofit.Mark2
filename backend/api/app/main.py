import asyncio
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException

from . import reservations, scheduler, storage
from .auth import require_auth
from .models import DeviceTokenIn, ReservationIn, ReservationOut


@asynccontextmanager
async def lifespan(app: FastAPI):
    await storage.init_db()
    await reservations.recover_stuck_submissions()
    task = asyncio.create_task(scheduler.run_scheduler_loop())
    try:
        yield
    finally:
        task.cancel()


app = FastAPI(title="Jofit Backend", lifespan=lifespan)


@app.get("/health")
async def health() -> dict:
    return {"ok": True}


@app.post("/reservations", response_model=ReservationOut, dependencies=[Depends(require_auth)])
async def post_reservation(body: ReservationIn) -> dict:
    return await reservations.create_reservation(
        course_id=body.course.id,
        course_date=body.course.date,
        course_time=body.course.time,
        course_name=body.course.name,
        reporter_name=body.name,
        employee_id=body.employee_id,
    )


@app.get("/reservations", response_model=list[ReservationOut], dependencies=[Depends(require_auth)])
async def get_reservations() -> list[dict]:
    return await reservations.list_reservations()


@app.delete("/reservations/{reservation_id}", dependencies=[Depends(require_auth)])
async def delete_reservation(reservation_id: str) -> dict:
    ok = await reservations.cancel_reservation(reservation_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Not found, already submitted, or currently submitting")
    return {"ok": True}


@app.post("/device-token", dependencies=[Depends(require_auth)])
async def post_device_token(body: DeviceTokenIn) -> dict:
    await reservations.register_device(body.token)
    return {"ok": True}
