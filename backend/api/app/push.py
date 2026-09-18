import os
import time

import httpx
import jwt

APNS_KEY_ID = os.environ.get("APNS_KEY_ID")
APNS_TEAM_ID = os.environ.get("APNS_TEAM_ID")
APNS_KEY_PATH = os.environ.get("APNS_KEY_PATH", "/run/secrets/apns_key.p8")
APNS_BUNDLE_ID = os.environ.get("APNS_BUNDLE_ID", "com.jofit.autobooking")
APNS_USE_SANDBOX = os.environ.get("APNS_USE_SANDBOX", "false").lower() == "true"

_cached_token: str | None = None
_cached_token_time: float = 0.0


def _configured() -> bool:
    return bool(APNS_KEY_ID and APNS_TEAM_ID and os.path.exists(APNS_KEY_PATH))


def _provider_token() -> str:
    """APNs provider tokens are valid up to an hour; cache and rotate a bit before that."""
    global _cached_token, _cached_token_time
    now = time.time()
    if _cached_token and now - _cached_token_time < 1800:
        return _cached_token

    with open(APNS_KEY_PATH) as f:
        private_key = f.read()

    token = jwt.encode(
        {"iss": APNS_TEAM_ID, "iat": int(now)},
        private_key,
        algorithm="ES256",
        headers={"kid": APNS_KEY_ID},
    )
    _cached_token = token
    _cached_token_time = now
    return token


async def send_push(device_token: str, title: str, body: str) -> None:
    if not _configured():
        print(f"[push] APNs not configured, skipping notification: {title} - {body}")
        return

    host = "api.sandbox.push.apple.com" if APNS_USE_SANDBOX else "api.push.apple.com"
    url = f"https://{host}/3/device/{device_token}"
    headers = {
        "authorization": f"bearer {_provider_token()}",
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
    }
    payload = {"aps": {"alert": {"title": title, "body": body}, "sound": "default"}}
    try:
        async with httpx.AsyncClient(http2=True, timeout=10) as client:
            response = await client.post(url, headers=headers, json=payload)
            if response.status_code != 200:
                print(f"[push] APNs error {response.status_code}: {response.text}")
    except Exception as exc:
        print(f"[push] APNs request failed: {exc}")
