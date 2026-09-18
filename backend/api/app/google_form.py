import httpx

# Jofit 模擬表單 (test form). Swap this URL + the entry IDs below when Jofit switches the real
# registration form in — open the new form's page source and search for `entry.` to find the
# replacement IDs. Must be kept in sync with Jofit/Services/FormSubmissionService.swift.
FORM_URL = "https://docs.google.com/forms/d/e/1FAIpQLSfkfXdRQzbU37S56equARw25SIM4XatGt14TgPCny5_ri9Bog/formResponse"

ENTRY_NAME = "entry.954137713"
ENTRY_EMPLOYEE_ID = "entry.698318826"
ENTRY_COURSE = "entry.1514588416"


async def submit_form(name: str, employee_id: str, course_text: str) -> int:
    """Returns the HTTP status code. Google Forms doesn't return a machine-readable success
    flag, so a 200 is the best available signal that the response was recorded."""
    data = {
        ENTRY_NAME: name,
        ENTRY_EMPLOYEE_ID: employee_id,
        ENTRY_COURSE: course_text,
        "fvv": "1",
        "pageHistory": "0",
    }
    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(FORM_URL, data=data)
        return response.status_code
