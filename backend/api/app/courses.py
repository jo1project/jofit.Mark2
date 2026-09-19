from .storage import connect


async def list_courses() -> list[dict]:
    async with connect() as db:
        cursor = await db.execute("SELECT id, weekday, time, name FROM course_templates ORDER BY position")
        return [dict(r) for r in await cursor.fetchall()]


async def replace_courses(templates: list[dict]) -> None:
    """The whole list is replaced in one transaction, so readers never see a half-edited
    timetable. Existing reservations keep their own copy of the course name/time."""
    async with connect() as db:
        await db.execute("DELETE FROM course_templates")
        await db.executemany(
            "INSERT INTO course_templates (id, weekday, time, name, position) VALUES (?, ?, ?, ?, ?)",
            [(t["id"], t["weekday"], t["time"], t["name"], i) for i, t in enumerate(templates)],
        )
        await db.commit()
