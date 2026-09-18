from pydantic import BaseModel


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
