from playwright.async_api import async_playwright

# Jofit 模擬表單 (test form). Swap this URL when Jofit switches the real registration form in
# — and re-run backend/api/tests/diagnose_browser.py against it once, since the field order /
# submit button text this relies on could differ on a different form.
VIEWFORM_URL = "https://docs.google.com/forms/d/e/1FAIpQLSfkfXdRQzbU37S56equARw25SIM4XatGt14TgPCny5_ri9Bog/viewform"

# Google Forms rejects a raw HTTP POST to /formResponse outright — verified by testing with
# correct data, deliberately wrong data, and even a nonexistent field ID, all producing an
# identical generic "validation failed" 400, while a real phone browser submission succeeds
# immediately. So this drives an actual headless Chromium through the real page instead,
# indistinguishable from a human filling it in. Confirmed working on the VPS (961MB RAM, 1
# vCPU) with headroom to spare: peak ~160MB for one browser instance.
_LAUNCH_ARGS = [
    "--disable-gpu",
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--single-process",
    "--disable-extensions",
    "--disable-background-networking",
    "--mute-audio",
    "--no-first-run",
]

# The confirmation page's wording has varied by locale/A-B test in practice ("我們已經收到您回覆
# 的表單" was observed; "回應已記錄" is the more commonly documented phrasing) — checking for
# several known-good phrases is more robust than betting on one exact string.
_SUCCESS_MARKERS = [
    "我們已經收到您回覆的表單",
    "回應已記錄",
    "has been recorded",
    "提交其他回應",
]


async def submit_form(name: str, employee_id: str, course_text: str) -> int:
    """Returns 200 on a confirmed successful submission (the confirmation page actually
    appeared). Raises on any failure — page didn't load, fields weren't found, or no
    confirmation text after clicking submit — which `reservations._submit` already treats as
    a failed attempt (no different handling needed there for this to plug in cleanly)."""
    async with async_playwright() as p:
        browser = await p.chromium.launch(args=_LAUNCH_ARGS)
        try:
            page = await browser.new_page(viewport={"width": 480, "height": 1000}, locale="zh-TW")
            await page.goto(VIEWFORM_URL, wait_until="networkidle", timeout=30000)

            textboxes = page.get_by_role("textbox")
            count = await textboxes.count()
            if count < 3:
                raise RuntimeError(f"expected 3 form fields, found {count} — has the form changed?")

            await textboxes.nth(0).fill(name)
            await textboxes.nth(1).fill(employee_id)
            await textboxes.nth(2).fill(course_text)

            submit_button = page.get_by_role("button", name="Submit")
            if await submit_button.count() == 0:
                submit_button = page.get_by_role("button", name="提交")
            await submit_button.click()

            await page.wait_for_load_state("networkidle", timeout=15000)
            body_text = await page.locator("body").inner_text()

            if not any(marker in body_text for marker in _SUCCESS_MARKERS):
                raise RuntimeError(f"no confirmation text found after submit: {body_text[:200]!r}")

            return 200
        except Exception:
            try:
                await page.screenshot(path="/tmp/last_submit_failure.png", full_page=True)
            except Exception:
                pass
            raise
        finally:
            await browser.close()
