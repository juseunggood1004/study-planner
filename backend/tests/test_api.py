from datetime import date

from fastapi.testclient import TestClient

from app.main import app, get_service
from app.openai_service import OpenAIServiceError, _validate_schedule
from app.schemas import ExtractedContents, Schedule, ScheduleRequest


class FakeService:
    async def extract_contents(self, image_bytes: bytes, mime_type: str) -> ExtractedContents:
        return ExtractedContents.model_validate({"items": [{"id": "c1", "chapter": "1장", "section": None, "title": "시작", "estimated_minutes": 30}]})

    async def generate_schedule(self, request, replan=None) -> Schedule:
        return Schedule.model_validate({
            "days": [{
                "date": str(date.today()),
                "blocks": [{"content_ids": ["c1"], "title": "1장 시작", "start_time": "19:00", "duration_minutes": 30, "break_after_minutes": 0}],
                "review_minutes": 0,
                "buffer_minutes": 15,
                "note": "첫날은 가볍게 시작하세요.",
            }],
            "summary": "한 번에 시작합니다.",
            "warnings": [],
        })


app.dependency_overrides[get_service] = lambda: FakeService()
client = TestClient(app)


def schedule_payload() -> dict:
    return {
        "book_title": "테스트 책",
        "contents": [{"id": "c1", "chapter": "1장", "section": None, "title": "시작", "estimated_minutes": 30}],
        "preferences": {
            "deadline": "2030-01-02",
            "daily_availability": [{"weekday": 0, "available_minutes": 60}],
            "preferred_start_time": "19:00:00",
            "focus_minutes": 25,
            "break_minutes": 5,
            "buffer_minutes": 15,
        },
    }


def test_extract_contents_returns_editable_items() -> None:
    response = client.post("/contents/extract", files={"image": ("toc.png", b"image", "image/png")})
    assert response.status_code == 200
    assert response.json()["items"][0]["title"] == "시작"


def test_extract_rejects_non_image() -> None:
    response = client.post("/contents/extract", files={"image": ("toc.txt", b"text", "text/plain")})
    assert response.status_code == 415


def test_generate_schedule() -> None:
    response = client.post("/schedules/generate", json=schedule_payload())
    assert response.status_code == 200
    assert response.json()["days"][0]["blocks"][0]["content_ids"] == ["c1"]


def test_replan_accepts_completed_ids() -> None:
    payload = schedule_payload() | {"completed_content_ids": ["c1"]}
    response = client.post("/schedules/replan", json=payload)
    assert response.status_code == 200


def test_duplicate_weekday_is_rejected() -> None:
    payload = schedule_payload()
    payload["preferences"]["daily_availability"].append({"weekday": 0, "available_minutes": 30})
    response = client.post("/schedules/generate", json=payload)
    assert response.status_code == 422


def test_schedule_validator_rejects_overbooked_day() -> None:
    today = date.today()
    request = ScheduleRequest.model_validate({
        **schedule_payload(),
        "preferences": {
            **schedule_payload()["preferences"],
            "deadline": str(today),
            "daily_availability": [{"weekday": today.weekday(), "available_minutes": 30}],
        },
    })
    schedule = Schedule.model_validate({
        "days": [{"date": str(today), "blocks": [{"content_ids": ["c1"], "title": "1장", "start_time": "19:00", "duration_minutes": 31, "break_after_minutes": 0}], "review_minutes": 0, "buffer_minutes": 0, "note": ""}],
        "summary": "테스트", "warnings": [],
    })
    try:
        _validate_schedule(schedule, request, set())
        assert False, "An overbooked schedule must fail validation."
    except OpenAIServiceError:
        pass
