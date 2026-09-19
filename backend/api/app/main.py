import asyncio
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Body, Depends, FastAPI, Header, HTTPException

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


async def _owner(employee_id: str | None, x_admin_pin: str | None) -> str | None:
    """Whose reservations this request may touch. The bearer token is shared by every install,
    so it says nothing about who is asking: a normal caller must name their own employee_id and
    is confined to it; a valid admin PIN lifts the confinement (returns None = everyone)."""
    employee_id = (employee_id or "").strip() or None
    if x_admin_pin is not None:
        await require_admin(x_admin_pin)
        return employee_id
    if employee_id is None:
        raise HTTPException(status_code=422, detail="employee_id is required")
    return employee_id


@app.get("/reservations", response_model=list[ReservationOut], dependencies=[Depends(require_auth)])
async def get_reservations(
    employee_id: str | None = None, x_admin_pin: Annotated[str | None, Header()] = None
) -> list[dict]:
    return await reservations.list_reservations(await _owner(employee_id, x_admin_pin))


@app.delete("/reservations/{reservation_id}", dependencies=[Depends(require_auth)])
async def delete_reservation(
    reservation_id: str, employee_id: str | None = None, x_admin_pin: Annotated[str | None, Header()] = None
) -> dict:
    # With a PIN the employee_id is optional: an admin may cancel anyone's.
    if x_admin_pin is not None:
        await require_admin(x_admin_pin)
        owner = None
    else:
        owner = await _owner(employee_id, None)
    ok = await reservations.cancel_reservation(reservation_id, owner)
    if not ok:
        raise HTTPException(status_code=404, detail="Not found, or already submitting/submitted")
    return {"ok": True}


@app.post("/device-token", dependencies=[Depends(require_auth)])
async def post_device_token(body: DeviceTokenIn) -> dict:
    await reservations.register_device(body.token, body.employee_id)
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
