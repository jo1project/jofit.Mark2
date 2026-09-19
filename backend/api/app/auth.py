import hmac
import os
import time

from fastapi import Header, HTTPException

BEARER_TOKEN = os.environ["BEARER_TOKEN"]
# Guards the admin-only endpoints (bulk cancel, editing the course list). Unset = those
# endpoints always refuse, rather than silently falling open.
ADMIN_PIN = os.environ.get("ADMIN_PIN", "")

# ponytail: in-process, global (not per-IP — Caddy fronts every request), so someone hammering
# wrong PINs can lock the owner out for LOCK_SECONDS too. Per-client tracking if that bites.
MAX_WRONG_PINS = 5
LOCK_SECONDS = 15 * 60
_wrong_pin_times: list[float] = []


async def require_auth(authorization: str | None = Header(default=None)) -> None:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization[len("Bearer "):]
    if token != BEARER_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid token")


async def require_admin(x_admin_pin: str | None = Header(default=None)) -> None:
    """The bearer token is public (it's in the app binary and repo), so a 4-digit PIN alone
    would be brute-forceable in minutes; hence the lockout after MAX_WRONG_PINS misses."""
    now = time.monotonic()
    _wrong_pin_times[:] = [t for t in _wrong_pin_times if now - t < LOCK_SECONDS]
    if len(_wrong_pin_times) >= MAX_WRONG_PINS:
        raise HTTPException(status_code=429, detail="Too many wrong PINs, try again later")
    if not ADMIN_PIN or not x_admin_pin or not hmac.compare_digest(x_admin_pin.encode(), ADMIN_PIN.encode()):
        _wrong_pin_times.append(now)
        raise HTTPException(status_code=403, detail="Wrong admin PIN")
