from typing import Literal

from pydantic import BaseModel, Field


class CourseIn(BaseModel):
    id: str
    date: str  # "YYYY-MM-DD"
    time: str  # "HHmm", 24-hour, e.g. "1120"
    name: str


class ReservationIn(BaseModel):
    course: CourseIn
    name: str
    employee_id: str


class ReservationOut(BaseModel):
    id: str
    course_id: str
    course_date: str
    course_time: str
    course_name: str
    submission_text: str
    reporter_name: str
    employee_id: str
    status: str
    fire_date: str
    submitted_at: str | None = None
    http_status: int | None = None
    last_error: str | None = None
    created_at: str


class DeviceTokenIn(BaseModel):
    token: str


class CourseTemplateIO(BaseModel):
    """One weekly-recurring class slot, same shape as an entry in the repo's courses.json."""
    id: str = Field(min_length=1)
    weekday: Literal["週日", "週一", "週二", "週三", "週四", "週五", "週六"]
    time: str = Field(pattern=r"^([01][0-9]|2[0-3])[0-5][0-9]$")  # "HHmm", 24-hour
    name: str = Field(min_length=1)


class CancelIn(BaseModel):
    ids: list[str]
