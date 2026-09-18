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
"""


async def init_db() -> None:
    async with aiosqlite.connect(DB_PATH) as db:
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
