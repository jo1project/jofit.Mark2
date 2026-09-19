import asyncio
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Body, Depends, FastAPI, HTTPException

from . import courses, reservations, scheduler, storage
from .auth import require_admin, require_auth
from .models import CancelIn, CourseTemplateIO, DeviceTokenIn, ReservationIn, ReservationOut


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
        raise HTTPException(status_code=404, detail="Not found, or already submitting/submitted")
    return {"ok": True}


@app.post("/device-token", dependencies=[Depends(require_auth)])
async def post_device_token(body: DeviceTokenIn) -> dict:
    await reservations.register_device(body.token)
    return {"ok": True}


@app.post("/reservations/cancel", dependencies=[Depends(require_auth), Depends(require_admin)])
async def cancel_reservations(body: CancelIn) -> dict:
    return {"cancelled": await reservations.cancel_pending(body.ids)}


@app.get("/courses", response_model=list[CourseTemplateIO], dependencies=[Depends(require_auth)])
async def get_courses() -> list[dict]:
    # Empty until an admin first saves; the app then falls back to the repo's courses.json.
    return await courses.list_courses()


@app.put("/courses", dependencies=[Depends(require_auth), Depends(require_admin)])
async def put_courses(body: Annotated[list[CourseTemplateIO], Body(min_length=1)]) -> dict:
    if len({t.id for t in body}) != len(body):
        raise HTTPException(status_code=422, detail="Duplicate course id")
    await courses.replace_courses([t.model_dump() for t in body])
    return {"ok": True}
