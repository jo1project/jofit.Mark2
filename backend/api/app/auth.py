import os

from fastapi import Header, HTTPException

BEARER_TOKEN = os.environ["BEARER_TOKEN"]


async def require_auth(authorization: str | None = Header(default=None)) -> None:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization[len("Bearer "):]
    if token != BEARER_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid token")
