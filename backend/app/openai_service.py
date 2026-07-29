from __future__ import annotations

import base64
import json
from datetime import date
from typing import Any

import httpx

from .config import Settings
from .schemas import ContentItem, ExtractedContents, ReplanRequest, Schedule, ScheduleRequest


class OpenAIServiceError(Exception):
    """A safe, user-facing error raised for upstream OpenAI failures."""


CONTENT_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": ["items"],
    "properties": {
        "items": {
            "type": "array",
            "minItems": 1,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["id", "chapter", "section", "title", "estimated_minutes"],
                "properties": {
                    "id": {"type": "string"},
                    "chapter": {"type": "string"},
                    "section": {"type": ["string", "null"]},
                    "title": {"type": "string"},
                    "estimated_minutes": {"type": ["integer", "null"]},
                },
            },
        }
    },
}

SCHEDULE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": ["days", "summary", "warnings"],
    "properties": {
        "days": {
            "type": "array",
            "minItems": 1,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["date", "blocks", "review_minutes", "buffer_minutes", "note"],
                "properties": {
                    "date": {"type": "string"},
                    "blocks": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "additionalProperties": False,
                            "required": ["content_ids", "title", "start_time", "duration_minutes", "break_after_minutes"],
                            "properties": {
                                "content_ids": {"type": "array", "items": {"type": "string"}, "minItems": 1},
                                "title": {"type": "string"},
                                "start_time": {"type": "string"},
                                "duration_minutes": {"type": "integer"},
                                "break_after_minutes": {"type": "integer"},
                            },
                        },
                    },
                    "review_minutes": {"type": "integer"},
                    "buffer_minutes": {"type": "integer"},
                    "note": {"type": "string"},
                },
            },
        },
        "summary": {"type": "string"},
        "warnings": {"type": "array", "items": {"type": "string"}},
    },
}


class OpenAIService:
    def __init__(self, settings: Settings):
        self.settings = settings

    async def extract_contents(self, image_bytes: bytes, mime_type: str) -> ExtractedContents:
        encoded_image = base64.b64encode(image_bytes).decode("ascii")
        payload = {
            "model": self.settings.openai_model,
            "input": [{"role": "user", "content": [
                {"type": "input_text", "text": (
                    "Read this book table-of-contents image. Return every visible chapter and section in order. "
                    "Keep original Korean or other-language wording. Create stable short IDs such as c1-s2. "
                    "Use null for section when no section label is present. Estimate minutes only when strongly implied; otherwise null."
                )},
                {"type": "input_image", "image_url": f"data:{mime_type};base64,{encoded_image}"},
            ]}],
            "text": {"format": {"type": "json_schema", "name": "table_of_contents", "strict": True, "schema": CONTENT_SCHEMA}},
        }
        result = await self._create_response(payload)
        try:
            return ExtractedContents.model_validate(json.loads(result))
        except Exception as exc:  # Pydantic/JSON errors are never leaked to the client.
            raise OpenAIServiceError("목차를 읽지 못했습니다. 사진을 더 선명하게 찍거나 직접 입력해 주세요.") from exc

    async def generate_schedule(self, request: ScheduleRequest, replan: ReplanRequest | None = None) -> Schedule:
        plan_context = request.model_dump(mode="json")
        if replan:
            plan_context["completed_content_ids"] = replan.completed_content_ids
            plan_context["original_schedule"] = replan.original_schedule.model_dump(mode="json") if replan.original_schedule else None
        instruction = (
            "Create a realistic study schedule from the supplied JSON. Schedule only on days with available minutes, "
            "never exceed each day's available minutes when blocks, breaks, review, and buffer are combined, and assign every remaining content id. "
            "Use the preferred start time, split long work around focus/break preferences, balance workload, and keep a modest review/buffer near the deadline when feasible. "
            "If completion is impossible, still make the best possible schedule and explain the shortfall in warnings. "
            "Do not schedule completed_content_ids. Write titles, notes, summary, and warnings in Korean."
        )
        payload = {
            "model": self.settings.openai_model,
            "input": [{"role": "system", "content": instruction}, {"role": "user", "content": json.dumps(plan_context, ensure_ascii=False)}],
            "text": {"format": {"type": "json_schema", "name": "study_schedule", "strict": True, "schema": SCHEDULE_SCHEMA}},
        }
        result = await self._create_response(payload)
        try:
            schedule = Schedule.model_validate(json.loads(result))
            _validate_schedule(schedule, request, set(replan.completed_content_ids) if replan else set())
            return schedule
        except Exception as exc:
            if isinstance(exc, OpenAIServiceError):
                raise
            raise OpenAIServiceError("일정 형식이 올바르지 않습니다. 잠시 후 다시 생성해 주세요.") from exc

    async def _create_response(self, payload: dict[str, Any]) -> str:
        if not self.settings.openai_api_key or self.settings.openai_api_key.startswith("replace_"):
            raise OpenAIServiceError("서버에 OPENAI_API_KEY가 설정되지 않았습니다.")
        try:
            async with httpx.AsyncClient(timeout=60) as client:
                response = await client.post(
                    f"{self.settings.openai_base_url.rstrip('/')}/responses",
                    headers={"Authorization": f"Bearer {self.settings.openai_api_key}", "Content-Type": "application/json"},
                    json=payload,
                )
                response.raise_for_status()
                data = response.json()
        except httpx.TimeoutException as exc:
            raise OpenAIServiceError("AI 응답 시간이 초과되었습니다. 다시 시도해 주세요.") from exc
        except httpx.HTTPStatusError as exc:
            raise OpenAIServiceError("AI 서비스를 사용할 수 없습니다. API 키와 사용 한도를 확인해 주세요.") from exc
        except httpx.HTTPError as exc:
            raise OpenAIServiceError("AI 서비스에 연결할 수 없습니다. 네트워크를 확인해 주세요.") from exc
        output_text = data.get("output_text")
        if not isinstance(output_text, str) or not output_text.strip():
            raise OpenAIServiceError("AI가 빈 응답을 반환했습니다. 다시 시도해 주세요.")
        return output_text


def _validate_schedule(schedule: Schedule, request: ScheduleRequest, completed_ids: set[str]) -> None:
    """Reject model output that would create an unusable or misleading schedule."""
    available_by_weekday = {entry.weekday: entry.available_minutes for entry in request.preferences.daily_availability}
    valid_ids = {item.id for item in request.contents}
    remaining_ids = valid_ids - completed_ids
    scheduled_ids: list[str] = []
    dates: set[date] = set()

    for day in schedule.days:
        if day.date in dates:
            raise OpenAIServiceError("AI가 같은 날짜에 중복된 일정을 만들었습니다. 다시 생성해 주세요.")
        dates.add(day.date)
        if day.date < date.today() or day.date > request.preferences.deadline:
            raise OpenAIServiceError("AI가 학습 기간 밖의 일정을 만들었습니다. 다시 생성해 주세요.")
        daily_limit = available_by_weekday.get(day.date.weekday(), 0)
        used_minutes = day.review_minutes + day.buffer_minutes
        for block in day.blocks:
            scheduled_ids.extend(block.content_ids)
            used_minutes += block.duration_minutes + block.break_after_minutes
        if used_minutes > daily_limit:
            raise OpenAIServiceError("AI가 하루 학습 가능 시간을 초과했습니다. 다시 생성해 주세요.")

    if set(scheduled_ids) != remaining_ids or len(scheduled_ids) != len(set(scheduled_ids)):
        raise OpenAIServiceError("AI가 모든 목차를 정확히 배정하지 못했습니다. 다시 생성해 주세요.")
