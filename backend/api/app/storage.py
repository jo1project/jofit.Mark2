import os
from contextlib import asynccontextmanager

import aiosqlite

DB_PATH = os.environ.get("DB_PATH", "/data/jofit.db")

# One reservation per person per class (a class has many students), so uniqueness is on the
# pair, not on course_id alone.
RESERVATIONS_COLUMNS = """
  id TEXT PRIMARY KEY,
  course_id TEXT NOT NULL,
  course_date TEXT NOT NULL,
  course_time TEXT NOT NULL,
  course_name TEXT NOT NULL,
  reporter_name TEXT NOT NULL,
  employee_id TEXT NOT NULL,
  fire_date TEXT NOT NULL,
  status TEXT NOT NULL,
  submitted_at TEXT,
  http_status INTEGER,
  last_error TEXT,
  created_at TEXT NOT NULL,
  UNIQUE (course_id, employee_id)
"""

SCHEMA = f"""
CREATE TABLE IF NOT EXISTS reservations ({RESERVATIONS_COLUMNS});
CREATE TABLE IF NOT EXISTS course_templates (
  id TEXT PRIMARY KEY,
  weekday TEXT NOT NULL,
  time TEXT NOT NULL,
  name TEXT NOT NULL,
  position INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS devices (
  token TEXT PRIMARY KEY,
  employee_id TEXT NOT NULL DEFAULT '',
  registered_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS submission_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  employee_id TEXT NOT NULL,
  course_date TEXT NOT NULL,
  course_time TEXT NOT NULL DEFAULT '',
  course_name TEXT NOT NULL,
  attempted_at TEXT NOT NULL,
  succeeded INTEGER NOT NULL DEFAULT 0
);
"""


async def init_db() -> None:
    async with aiosqlite.connect(DB_PATH) as db:
        # Migrate: the original submission_attempts schema (just id+attempted_at, a global
        # counter) is incompatible with the per-employee/day/course scoped one — safe to drop,
        # since those rows only ever fed a counter, never referenced by anything else.
        cursor = await db.execute("PRAGMA table_info(submission_attempts)")
        columns = {row[1] for row in await cursor.fetchall()}
        if columns and "employee_id" not in columns:
            await db.execute("DROP TABLE submission_attempts")
        # Migrate: devices gained employee_id (pushes go only to the booking's owner) and
        # submission_attempts gained course_time (scope). ADD COLUMN rather than drop: old
        # attempt rows keep counting ('' just won't match a real time, so they stop guarding —
        # at most one re-attempt of an already-attempted class).
        for table, column, ddl in (
            ("devices", "employee_id", "TEXT NOT NULL DEFAULT ''"),
            ("submission_attempts", "course_time", "TEXT NOT NULL DEFAULT ''"),
        ):
            cursor = await db.execute(f"PRAGMA table_info({table})")
            columns = {row[1] for row in await cursor.fetchall()}
            if columns and column not in columns:
                await db.execute(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}")
        # Migrate: the original table had course_id TEXT NOT NULL UNIQUE (one reservation per
        # class in total). SQLite can't drop a constraint, so rebuild the table, in one
        # transaction, copying every row across in the same column order.
        cursor = await db.execute("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'reservations'")
        row = await cursor.fetchone()
        if row and "course_id TEXT NOT NULL UNIQUE" in row[0]:
            await db.executescript(
                f"""BEGIN;
                ALTER TABLE reservations RENAME TO reservations_old;
                CREATE TABLE reservations ({RESERVATIONS_COLUMNS});
                INSERT INTO reservations SELECT * FROM reservations_old;
                DROP TABLE reservations_old;
                COMMIT;"""
            )
        await db.executescript(SCHEMA)
        await db.commit()


@asynccontextmanager
async def connect():
    db = await aiosqlite.connect(DB_PATH)
    db.row_factory = aiosqlite.Row
    try:
        yield db
    finally:
        await db.close()
