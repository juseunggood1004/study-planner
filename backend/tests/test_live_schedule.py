"""Opt-in end-to-end check for the running FastAPI schedule endpoint.

Run from backend/ with:
  RUN_OPENAI_INTEGRATION=1 python -m pytest -q tests/test_live_schedule.py -s
"""

import os
from datetime import date, timedelta

import httpx
import pytest


@pytest.mark.skipif(
    os.getenv("RUN_OPENAI_INTEGRATION") != "1",
    reason="Set RUN_OPENAI_INTEGRATION=1 to call the running server and OpenAI.",
)
def test_running_server_generates_a_minimal_schedule() -> None:
    """Exercise the same HTTP path the Android app uses, including OpenAI."""
    today = date.today()
    payload = {
        "book_title": "통신 테스트",
        "goal_type": "book",
        "contents": [
            {
                "id": "network-test-1",
                "chapter": "1장",
                "section": None,
                "title": "짧은 테스트 학습",
                "estimated_minutes": 15,
            }
        ],
        "preferences": {
            "start_date": str(today),
            "deadline": str(today + timedelta(days=2)),
            "daily_availability": [
                {"weekday": weekday, "available_minutes": 180}
                for weekday in range(7)
            ],
            "preferred_start_time": "19:00:00",
            "focus_minutes": 25,
            "break_minutes": 5,
            "buffer_minutes": 0,
            "date_overrides": [],
        },
    }
    base_url = os.getenv("TEST_API_BASE_URL", "http://127.0.0.1:8000")

    response = httpx.post(
        f"{base_url.rstrip('/')}/schedules/generate",
        json=payload,
        timeout=180,
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["days"]
    assert body["days"][0]["blocks"][0]["content_ids"] == ["network-test-1"]
