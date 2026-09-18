from datetime import date, datetime, time as dtime, timedelta
from zoneinfo import ZoneInfo

TAIPEI = ZoneInfo("Asia/Taipei")


def compute_fire_date(course_date: date, now: datetime | None = None) -> datetime:
    """The form only accepts bookings up to 6 days ahead of the class date, so registration
    opens at 08:00 (Asia/Taipei) on (class date - 6 days). If that moment has already passed —
    the class is less than 6 days out — the reservation should fire right away."""
    now = now or datetime.now(TAIPEI)
    open_day = course_date - timedelta(days=6)
    candidate = datetime.combine(open_day, dtime(hour=8, minute=0), tzinfo=TAIPEI)
    return max(candidate, now)
