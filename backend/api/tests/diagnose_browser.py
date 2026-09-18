"""Diagnostic tool for `google_form.py`'s browser-automation approach — not an automated test
(it actually submits a clearly-marked test entry to the real form). Re-run this whenever the
target form changes (a new form, or the existing one gets edited) to check that the field
count/order and submit button text still match what `submit_form()` assumes.

Run inside the api container, e.g.:
    docker cp diagnose_browser.py jofit-backend-api-1:/tmp/diagnose_browser.py
    docker exec jofit-backend-api-1 python /tmp/diagnose_browser.py
Screenshots land in /tmp inside the container; `docker cp` them back out to inspect.
"""

import asyncio

from playwright.async_api import async_playwright

VIEWFORM_URL = "https://docs.google.com/forms/d/e/1FAIpQLSfkfXdRQzbU37S56equARw25SIM4XatGt14TgPCny5_ri9Bog/viewform"

LAUNCH_ARGS = [
    "--disable-gpu",
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--single-process",
    "--disable-extensions",
    "--disable-background-networking",
    "--mute-audio",
    "--no-first-run",
]

SUCCESS_MARKERS = [
    "我們已經收到您回覆的表單",
    "回應已記錄",
    "has been recorded",
    "提交其他回應",
]


async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(args=LAUNCH_ARGS)
        page = await browser.new_page(viewport={"width": 480, "height": 1000}, locale="zh-TW")
        try:
            await page.goto(VIEWFORM_URL, wait_until="networkidle", timeout=30000)
            print("loaded, title:", await page.title())

            textboxes = page.get_by_role("textbox")
            count = await textboxes.count()
            print(f"textbox count: {count} (submit_form() assumes exactly 3, in this order)")
            for i in range(count):
                print(f"  [{i}] aria-label={await textboxes.nth(i).get_attribute('aria-label')!r}")

            buttons = page.get_by_role("button")
            for i in range(await buttons.count()):
                text = (await buttons.nth(i).inner_text()).strip()
                print(f"  button [{i}] text={text!r}")

            if count < 3:
                print("STOP: fewer than 3 fields found, not attempting a test submission.")
                return

            await textboxes.nth(0).fill("瀏覽器自動化測試")
            await textboxes.nth(1).fill("TEST-0000")
            await textboxes.nth(2).fill("瀏覽器自動化測試-請忽略-可刪除")
            await page.screenshot(path="/tmp/diag_filled.png", full_page=True)

            submit = page.get_by_role("button", name="Submit")
            if await submit.count() == 0:
                submit = page.get_by_role("button", name="提交")
            await submit.click()

            await page.wait_for_load_state("networkidle", timeout=15000)
            await page.screenshot(path="/tmp/diag_after_submit.png", full_page=True)

            body_text = await page.locator("body").inner_text()
            recorded = any(marker in body_text for marker in SUCCESS_MARKERS)
            print("submitted, confirmation detected:", recorded)
            print("--- body text snippet ---")
            print(body_text[:500])

        except Exception as exc:
            print("ERROR:", repr(exc))
            await page.screenshot(path="/tmp/diag_error.png", full_page=True)
        finally:
            await browser.close()


asyncio.run(main())
