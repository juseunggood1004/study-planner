from __future__ import annotations

from datetime import date, time
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator


class ContentItem(BaseModel):
    id: str = Field(min_length=1, max_length=100)
    chapter: str = Field(min_length=1, max_length=200)
    section: str | None = Field(default=None, max_length=200)
    title: str = Field(min_length=1, max_length=300)
    estimated_minutes: int | None = Field(default=None, ge=5, le=600)


class DailyAvailability(BaseModel):
    weekday: int = Field(ge=0, le=6, description="Monday is 0 and Sunday is 6")
    available_minutes: int = Field(ge=0, le=1440)


class DateStudyOverride(BaseModel):
    date: date
    available_minutes: int = Field(ge=0, le=1440)
    preferred_start_time: time
    focus_minutes: int = Field(ge=10, le=180)
    break_minutes: int = Field(ge=0, le=60)


class BlockedTime(BaseModel):
    """A recurring school, academy, or other no-study period."""

    label: str = Field(min_length=1, max_length=80)
    weekday: int = Field(ge=0, le=6, description="Monday is 0 and Sunday is 6")
    start_time: time
    end_time: time

    @model_validator(mode="after")
    def ends_after_start(self) -> "BlockedTime":
        if self.end_time <= self.start_time:
            raise ValueError("Blocked time must end after it starts.")
        return self


class LearningFeedback(BaseModel):
    date: date
    fatigue: int = Field(ge=1, le=5)
    difficulty: int = Field(ge=1, le=5)


class StudyPreferences(BaseModel):
    start_date: date
    deadline: date
    daily_availability: list[DailyAvailability] = Field(min_length=1, max_length=7)
    preferred_start_time: time
    focus_minutes: int = Field(ge=10, le=180)
    break_minutes: int = Field(ge=0, le=60)
    buffer_minutes: int = Field(default=15, ge=0, le=180)
    date_overrides: list[DateStudyOverride] = Field(default_factory=list, max_length=366)
    blocked_times: list[BlockedTime] = Field(default_factory=list, max_length=30)

    @model_validator(mode="after")
    def unique_weekdays(self) -> "StudyPreferences":
        if self.start_date > self.deadline:
            raise ValueError("Start date cannot be after the deadline.")
        weekdays = [entry.weekday for entry in self.daily_availability]
        if len(weekdays) != len(set(weekdays)):
            raise ValueError("Each weekday may only appear once.")
        dates = [entry.date for entry in self.date_overrides]
        if len(dates) != len(set(dates)):
            raise ValueError("Each date may only have one override.")
        if any(override.date < self.start_date or override.date > self.deadline for override in self.date_overrides):
            raise ValueError("Date overrides must be within the study period.")
        return self


class ScheduleRequest(BaseModel):
    book_title: str = Field(min_length=1, max_length=200)
    goal_type: Literal["book", "goal"] = "book"
    contents: list[ContentItem] = Field(min_length=1, max_length=500)
    preferences: StudyPreferences
    learning_feedback: list[LearningFeedback] = Field(default_factory=list, max_length=90)


class StudyBlock(BaseModel):
    content_ids: list[str] = Field(min_length=1)
    title: str = Field(min_length=1, max_length=500)
    start_time: str = Field(
        pattern=r"^([01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$"
    )
    duration_minutes: int = Field(ge=5, le=600)
    break_after_minutes: int = Field(default=0, ge=0, le=60)

    @field_validator("start_time")
    @classmethod
    def normalize_start_time(cls, value: str) -> str:
        """Responses often return an ISO-like HH:MM:SS despite asking for HH:MM."""
        return value[:5]


class ScheduleDay(BaseModel):
    date: date
    blocks: list[StudyBlock] = Field(default_factory=list)
    review_minutes: int = Field(default=0, ge=0, le=300)
    buffer_minutes: int = Field(default=0, ge=0, le=300)
    note: str = Field(default="", max_length=500)


class Schedule(BaseModel):
    days: list[ScheduleDay] = Field(min_length=1)
    summary: str = Field(min_length=1, max_length=1000)
    warnings: list[str] = Field(default_factory=list, max_length=10)


class ReplanRequest(ScheduleRequest):
    completed_content_ids: list[str] = Field(default_factory=list)
    original_schedule: Schedule | None = None


class ExtractedContents(BaseModel):
    items: list[ContentItem] = Field(min_length=1, max_length=500)


class ApiError(BaseModel):
    detail: str
