from datetime import date

import pytest
from fastapi.testclient import TestClient

from app.main import app, get_service
from app.openai_service import OpenAIServiceError, _daily_budgets, _validate_schedule
from app.schemas import ExtractedContents, Schedule, ScheduleRequest, StudyBlock


class FakeService:
    async def extract_contents(self, image_bytes: bytes, mime_type: str) -> ExtractedContents:
        return ExtractedContents.model_validate({"items": [{"id": "c1", "chapter": "1장", "section": None, "title": "시작", "estimated_minutes": 30}]})

    async def extract_contents_images(self, images: list[tuple[bytes, str]]) -> ExtractedContents:
        return await self.extract_contents(*images[0])

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
            "start_date": str(date.today()),
            "deadline": "2030-01-02",
            "daily_availability": [{"weekday": 0, "available_minutes": 60}],
            "preferred_start_time": "19:00:00",
            "focus_minutes": 25,
            "break_minutes": 5,
            "buffer_minutes": 15,
        },
    }


def test_extract_contents_returns_editable_items() -> None:
    response = client.post("/contents/extract", files={"image": ("toc.png", b"\x89PNG\r\n\x1a\nimage", "image/png")})
    assert response.status_code == 200
    assert response.json()["items"][0]["title"] == "시작"


def test_schedule_block_normalizes_seconds_from_ai_response() -> None:
    block = StudyBlock.model_validate({
        "content_ids": ["c1"],
        "title": "테스트",
        "start_time": "19:00:00",
        "duration_minutes": 25,
        "break_after_minutes": 0,
    })

    assert block.start_time == "19:00"


def test_extract_accepts_jpeg_with_generic_multipart_type() -> None:
    response = client.post("/contents/extract", files={"image": ("toc.jpg", b"\xff\xd8\xff\xe0image", "application/octet-stream")})
    assert response.status_code == 200


def test_extract_accepts_multiple_images_in_one_request() -> None:
    response = client.post("/contents/extract", files=[
        ("images", ("toc-1.jpg", b"\xff\xd8\xff\xe0first", "image/jpeg")),
        ("images", ("toc-2.png", b"\x89PNG\r\n\x1a\nsecond", "image/png")),
    ])
    assert response.status_code == 200


def test_extract_limits_image_count() -> None:
    response = client.post("/contents/extract", files=[
        ("images", (f"toc-{index}.jpg", b"\xff\xd8\xff\xe0image", "image/jpeg"))
        for index in range(9)
    ])
    assert response.status_code == 400


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


def test_date_override_allows_a_different_daily_limit() -> None:
    payload = schedule_payload()
    payload["preferences"]["date_overrides"] = [{
        "date": str(date.today()),
        "available_minutes": 90,
        "preferred_start_time": "08:30:00",
        "focus_minutes": 40,
        "break_minutes": 10,
    }]
    response = client.post("/schedules/generate", json=payload)
    assert response.status_code == 200


def test_duplicate_weekday_is_rejected() -> None:
    payload = schedule_payload()
    payload["preferences"]["daily_availability"].append({"weekday": 0, "available_minutes": 30})
    response = client.post("/schedules/generate", json=payload)
    assert response.status_code == 422


def test_invalid_school_or_academy_time_is_rejected() -> None:
    payload = schedule_payload()
    payload["preferences"]["blocked_times"] = [{
        "label": "학원",
        "weekday": 0,
        "start_time": "20:00:00",
        "end_time": "18:00:00",
    }]
    response = client.post("/schedules/generate", json=payload)
    assert response.status_code == 422


def test_learning_feedback_is_accepted_for_future_replanning() -> None:
    payload = schedule_payload()
    payload["learning_feedback"] = [{
        "date": str(date.today()), "fatigue": 4, "difficulty": 5,
    }]
    response = client.post("/schedules/generate", json=payload)
    assert response.status_code == 200


def test_schedule_validator_rejects_overbooked_day() -> None:
    today = date.today()
    request = ScheduleRequest.model_validate({
        **schedule_payload(),
        "preferences": {
            **schedule_payload()["preferences"],
            "deadline": str(today),
            "start_date": str(today),
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


def test_schedule_validator_keeps_a_feasible_partial_plan_with_warning() -> None:
    today = date.today()
    payload = schedule_payload()
    payload["contents"].append({"id": "c2", "chapter": "1장", "section": None, "title": "다음", "estimated_minutes": 30})
    payload["preferences"] = {
        **payload["preferences"],
        "start_date": str(today),
        "deadline": str(today),
        "daily_availability": [{"weekday": today.weekday(), "available_minutes": 30}],
    }
    request = ScheduleRequest.model_validate(payload)
    schedule = Schedule.model_validate({
        "days": [{"date": str(today), "blocks": [{"content_ids": ["c1"], "title": "1장 시작", "start_time": "19:00", "duration_minutes": 30, "break_after_minutes": 0}], "review_minutes": 0, "buffer_minutes": 0, "note": ""}],
        "summary": "테스트", "warnings": [],
    })

    _validate_schedule(schedule, request, set())

    assert "1개 항목" in schedule.warnings[0]


def test_daily_budgets_uses_date_override_before_weekday_default() -> None:
    today = date.today()
    payload = schedule_payload()
    payload["preferences"] = {
        **payload["preferences"],
        "start_date": str(today),
        "deadline": str(today),
        "daily_availability": [{"weekday": today.weekday(), "available_minutes": 30}],
        "date_overrides": [{
            "date": str(today),
            "available_minutes": 90,
            "preferred_start_time": "08:30:00",
            "focus_minutes": 40,
            "break_minutes": 10,
        }],
    }

    assert _daily_budgets(ScheduleRequest.model_validate(payload)) == [{
        "date": str(today), "available_minutes": 90, "blocked_times": [],
    }]


def test_schedule_validator_rejects_a_block_that_overlaps_academy() -> None:
    today = date.today()
    payload = schedule_payload()
    payload["preferences"] = {
        **payload["preferences"],
        "start_date": str(today),
        "deadline": str(today),
        "daily_availability": [{"weekday": today.weekday(), "available_minutes": 90}],
        "blocked_times": [{
            "label": "학원",
            "weekday": today.weekday(),
            "start_time": "19:00:00",
            "end_time": "20:00:00",
        }],
    }
    request = ScheduleRequest.model_validate(payload)
    schedule = Schedule.model_validate({
        "days": [{"date": str(today), "blocks": [{"content_ids": ["c1"], "title": "1장", "start_time": "19:30", "duration_minutes": 30, "break_after_minutes": 0}], "review_minutes": 0, "buffer_minutes": 0, "note": ""}],
        "summary": "테스트", "warnings": [],
    })

    with pytest.raises(OpenAIServiceError, match="학원"):
        _validate_schedule(schedule, request, set())
