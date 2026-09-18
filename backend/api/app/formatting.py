from datetime import date

# Index by Python's date.weekday() (Monday=0 .. Sunday=6).
WEEKDAY_LABELS = ["週一", "週二", "週三", "週四", "週五", "週六", "週日"]


def weekday_label(d: date) -> str:
    return WEEKDAY_LABELS[d.weekday()]


def date_text(d: date) -> str:
    return f"{d.month}/{d.day:02d}"


def submission_text(d: date, time: str, name: str) -> str:
    """Must match the format the Jofit admin parses by hand, e.g. "1/16 週六 1120 燃脂泰拳"."""
    return f"{date_text(d)} {weekday_label(d)} {time} {name}"
