from __future__ import annotations

import base64
import json
import logging
from datetime import date, timedelta
from typing import Any

import httpx

from .config import Settings
from .schemas import ContentItem, ExtractedContents, ReplanRequest, Schedule, ScheduleRequest


logger = logging.getLogger(__name__)


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
                            "start_time": {
                                "type": "string",
                                "pattern": "^([01]\\d|2[0-3]):[0-5]\\d(?::[0-5]\\d)?$",
                            },
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
        return await self.extract_contents_images([(image_bytes, mime_type)])

    async def extract_contents_images(self, images: list[tuple[bytes, str]]) -> ExtractedContents:
        image_parts = [
            {
                "type": "input_image",
                "image_url": f"data:{mime_type};base64,{base64.b64encode(image_bytes).decode('ascii')}",
            }
            for image_bytes, mime_type in images
        ]
        payload = {
            "model": self.settings.openai_model,
            "input": [{"role": "user", "content": [
                {"type": "input_text", "text": (
                    "Read these book table-of-contents images in the order provided. Images may be consecutive or overlap. "
                    "Return one item for every visible numbered section, in book order, and remove duplicates caused by overlapping pages. "
                    "Set chapter to the full parent chapter label and title, such as 'I 다항식'. "
                    "Set section to the printed section number and title to the section title. "
                    "Do not emit a separate chapter-only item when numbered child sections are visible. "
                    "Only when a chapter has no visible child sections, return one item with section null. "
                    "Keep original Korean or other-language wording and create stable short IDs such as c1-s2. "
                    "Estimate minutes only when strongly implied; otherwise null."
                )},
                *image_parts,
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
        plan_context["daily_budgets"] = _daily_budgets(request)
        if replan:
            plan_context["completed_content_ids"] = replan.completed_content_ids
            plan_context["original_schedule"] = replan.original_schedule.model_dump(mode="json") if replan.original_schedule else None
        instruction = (
            "Create a realistic study schedule for either a book or an arbitrary learning goal from the supplied JSON. "
            "Treat book_title as the plan title for backward compatibility and use goal_type to understand its kind. "
            "When goal_type is goal, treat each content item's chapter as the subject and section/title as the unit, then make a practical daily subject-and-unit study plan. "
            "learning_feedback contains the user's completed-day ratings from 1 (low/easy) to 5 (high/hard). "
            "Use recent high fatigue or difficulty ratings to shorten future focus blocks, add more buffer and breaks, and avoid concentrating the hardest work on consecutive days. "
            "Schedule only from preferences.start_date through preferences.deadline, and only on days with available minutes. "
            "daily_budgets is the source of truth for each date's total available minutes and its blocked_times. "
            "Never place a study block during a blocked_times interval (school, academy, or another no-study commitment). "
            "For every scheduled date, calculate used_minutes as the sum of all block duration_minutes, all break_after_minutes, review_minutes, and buffer_minutes. "
            "used_minutes must never exceed that date's available_minutes. Do not add a break after the final block of a day, and set review or buffer to zero when there is no room. "
            "Date-specific overrides take priority over weekday defaults for available time, start time, focus length, and breaks. "
            "Use the applicable preferred start time, split long work around focus/break preferences, balance workload, and keep a modest review/buffer near the deadline when feasible. "
            "If completion is impossible, still make the best possible schedule and explain the shortfall in warnings. "
            "Do not schedule completed_content_ids. Write titles, notes, summary, and warnings in Korean."
        )
        payload = {
            "model": self.settings.openai_model,
            "reasoning": {"effort": "low"},
            "input": [{"role": "system", "content": instruction}, {"role": "user", "content": json.dumps(plan_context, ensure_ascii=False)}],
            "text": {"format": {"type": "json_schema", "name": "study_schedule", "strict": True, "schema": SCHEDULE_SCHEMA}},
        }
        result = await self._create_response(payload)
        try:
            return _parse_and_validate_schedule(result, request, set(replan.completed_content_ids) if replan else set())
        except OpenAIServiceError as exc:
            # Models occasionally miscount a break or buffer. Retry once with the
            # failed validation constraint made explicit before exposing an error.
            logger.warning("Schedule draft rejected; retrying once: %s", exc)
            retry_payload = {
                **payload,
                "input": [
                    {
                        "role": "system",
                        "content": instruction + " Your previous draft was invalid. Recalculate every daily used_minutes total before responding. Return a corrected full schedule that stays within every daily_budgets limit.",
                    },
                    payload["input"][1],
                ],
            }
            retry_result = await self._create_response(retry_payload)
            return _parse_and_validate_schedule(
                retry_result,
                request,
                set(replan.completed_content_ids) if replan else set(),
            )

    async def _create_response(self, payload: dict[str, Any]) -> str:
        if not self.settings.openai_api_key or self.settings.openai_api_key.startswith("replace_"):
            raise OpenAIServiceError("서버에 OPENAI_API_KEY가 설정되지 않았습니다.")
        try:
            async with httpx.AsyncClient(timeout=40) as client:
                response = await client.post(
                    f"{self.settings.openai_base_url.rstrip('/')}/responses",
                    headers={"Authorization": f"Bearer {self.settings.openai_api_key}", "Content-Type": "application/json"},
                    json=payload,
                )
                response.raise_for_status()
                data = response.json()
        except httpx.TimeoutException as exc:
            logger.warning("OpenAI Responses request timed out after 20 seconds.")
            raise OpenAIServiceError("AI 응답 시간이 초과되었습니다. 다시 시도해 주세요.") from exc
        except httpx.HTTPStatusError as exc:
            response_body = exc.response.text[:1000].replace("\n", " ")
            logger.warning(
                "OpenAI Responses request failed: status=%s body=%s",
                exc.response.status_code,
                response_body,
            )
            raise OpenAIServiceError("AI 서비스를 사용할 수 없습니다. API 키와 사용 한도를 확인해 주세요.") from exc
        except httpx.HTTPError as exc:
            logger.warning("OpenAI Responses network error: %s", exc)
            raise OpenAIServiceError("AI 서비스에 연결할 수 없습니다. 네트워크를 확인해 주세요.") from exc
        try:
            return _extract_output_text(data)
        except OpenAIServiceError:
            raw_output = data.get("output")
            output_items = raw_output if isinstance(raw_output, list) else []
            logger.warning(
                "OpenAI response contained no usable text (response_id=%s, status=%s, output_types=%s)",
                data.get("id"),
                data.get("status"),
                [item.get("type") for item in output_items if isinstance(item, dict)],
            )
            raise


def _extract_output_text(data: dict[str, Any]) -> str:
    """Read text from both SDK-style and raw Responses API payloads."""
    if data.get("status") == "incomplete":
        raise OpenAIServiceError("AI 응답이 완료되기 전에 중단되었습니다. 다시 시도해 주세요.")
    if data.get("status") == "failed" or data.get("error"):
        raise OpenAIServiceError("AI가 요청 처리에 실패했습니다. 다시 시도해 주세요.")

    # Some compatible gateways and SDK-serialized objects expose this helper.
    shortcut = data.get("output_text")
    if isinstance(shortcut, str) and shortcut.strip():
        return shortcut

    text_parts: list[str] = []
    refused = False
    raw_output = data.get("output")
    output_items = raw_output if isinstance(raw_output, list) else []
    for item in output_items:
        if not isinstance(item, dict) or item.get("type") != "message":
            continue
        for part in item.get("content", []):
            if not isinstance(part, dict):
                continue
            if part.get("type") == "output_text" and isinstance(part.get("text"), str):
                text_parts.append(part["text"])
            elif part.get("type") == "refusal":
                refused = True

    output_text = "".join(text_parts)
    if output_text.strip():
        return output_text
    if refused:
        raise OpenAIServiceError("AI가 이 이미지의 처리를 거부했습니다. 다른 이미지를 사용해 주세요.")
    raise OpenAIServiceError("AI가 텍스트 없이 응답했습니다. 다시 시도해 주세요.")


def _parse_and_validate_schedule(result: str, request: ScheduleRequest, completed_ids: set[str]) -> Schedule:
    try:
        schedule = Schedule.model_validate(json.loads(result))
        _validate_schedule(schedule, request, completed_ids)
        return schedule
    except OpenAIServiceError:
        raise
    except Exception as exc:
        logger.warning("Schedule response could not be parsed or validated: %s", exc)
        raise OpenAIServiceError("일정 형식이 올바르지 않습니다. 잠시 후 다시 생성해 주세요.") from exc


def _daily_budgets(request: ScheduleRequest) -> list[dict[str, Any]]:
    """Materialize weekday preferences so the model does not have to infer dates."""
    available_by_weekday = {
        entry.weekday: entry.available_minutes
        for entry in request.preferences.daily_availability
    }
    override_by_date = {
        entry.date: entry for entry in request.preferences.date_overrides
    }
    current = max(date.today(), request.preferences.start_date)
    budgets: list[dict[str, Any]] = []
    while current <= request.preferences.deadline:
        override = override_by_date.get(current)
        available = (
            override.available_minutes
            if override
            else available_by_weekday.get(current.weekday(), 0)
        )
        if available > 0:
            budgets.append(
                {
                    "date": current.isoformat(),
                    "available_minutes": available,
                    "blocked_times": [
                        {
                            "label": blocked.label,
                            "start_time": blocked.start_time.isoformat(),
                            "end_time": blocked.end_time.isoformat(),
                        }
                        for blocked in request.preferences.blocked_times
                        if blocked.weekday == current.weekday()
                    ],
                }
            )
        current += timedelta(days=1)
    return budgets


def _validate_schedule(schedule: Schedule, request: ScheduleRequest, completed_ids: set[str]) -> None:
    """Reject model output that would create an unusable or misleading schedule."""
    available_by_weekday = {entry.weekday: entry.available_minutes for entry in request.preferences.daily_availability}
    override_by_date = {entry.date: entry for entry in request.preferences.date_overrides}
    blocked_by_weekday: dict[int, list[Any]] = {}
    for blocked in request.preferences.blocked_times:
        blocked_by_weekday.setdefault(blocked.weekday, []).append(blocked)
    valid_ids = {item.id for item in request.contents}
    remaining_ids = valid_ids - completed_ids
    scheduled_ids: list[str] = []
    dates: set[date] = set()

    for day in schedule.days:
        if day.date in dates:
            raise OpenAIServiceError("AI가 같은 날짜에 중복된 일정을 만들었습니다. 다시 생성해 주세요.")
        dates.add(day.date)
        earliest_date = max(date.today(), request.preferences.start_date)
        if day.date < earliest_date or day.date > request.preferences.deadline:
            raise OpenAIServiceError("AI가 학습 기간 밖의 일정을 만들었습니다. 다시 생성해 주세요.")
        override = override_by_date.get(day.date)
        daily_limit = override.available_minutes if override else available_by_weekday.get(day.date.weekday(), 0)
        used_minutes = day.review_minutes + day.buffer_minutes
        for block in day.blocks:
            scheduled_ids.extend(block.content_ids)
            used_minutes += block.duration_minutes + block.break_after_minutes
            start_minutes = _minutes_from_time(block.start_time)
            end_minutes = start_minutes + block.duration_minutes
            if end_minutes > 24 * 60:
                raise OpenAIServiceError("AI가 자정을 넘는 학습 블록을 만들었습니다. 다시 생성해 주세요.")
            for blocked in blocked_by_weekday.get(day.date.weekday(), []):
                blocked_start = blocked.start_time.hour * 60 + blocked.start_time.minute
                blocked_end = blocked.end_time.hour * 60 + blocked.end_time.minute
                if start_minutes < blocked_end and end_minutes > blocked_start:
                    raise OpenAIServiceError(
                        f"AI가 {blocked.label} 시간과 겹치는 학습 블록을 만들었습니다. 다시 생성해 주세요."
                    )
        if used_minutes > daily_limit:
            raise OpenAIServiceError("AI가 하루 학습 가능 시간을 초과했습니다. 다시 생성해 주세요.")

    if len(scheduled_ids) != len(set(scheduled_ids)) or not set(scheduled_ids).issubset(remaining_ids):
        raise OpenAIServiceError("AI가 목차를 중복 또는 잘못 배정했습니다. 다시 생성해 주세요.")

    unscheduled_ids = remaining_ids - set(scheduled_ids)
    if unscheduled_ids:
        schedule.warnings.append(
            f"학습 가능 시간이 부족해 {len(unscheduled_ids)}개 항목은 마감일까지 배정하지 못했습니다. 학습 시간을 늘리거나 마감일을 조정해 주세요."
        )


def _minutes_from_time(value: str) -> int:
    hours, minutes = value.split(":")[:2]
    return int(hours) * 60 + int(minutes)
