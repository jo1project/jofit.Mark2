import os
from contextlib import asynccontextmanager

import aiosqlite

DB_PATH = os.environ.get("DB_PATH", "/data/jofit.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS reservations (
  id TEXT PRIMARY KEY,
  course_id TEXT NOT NULL UNIQUE,
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
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS devices (
  token TEXT PRIMARY KEY,
  registered_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS submission_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  employee_id TEXT NOT NULL,
  course_date TEXT NOT NULL,
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
