from __future__ import annotations

import logging

from fastapi import Depends, FastAPI, File, HTTPException, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings, get_settings
from .openai_service import OpenAIService, OpenAIServiceError
from .schemas import ExtractedContents, ReplanRequest, Schedule, ScheduleRequest

app = FastAPI(title="AI Study Scheduler API", version="0.1.0")
logger = logging.getLogger(__name__)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict this to deployed app origins when a web client is added.
    allow_credentials=False,
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)


def get_service(settings: Settings = Depends(get_settings)) -> OpenAIService:
    return OpenAIService(settings)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/contents/extract", response_model=ExtractedContents)
async def extract_contents(
    image: UploadFile | None = File(default=None),
    images: list[UploadFile] | None = File(default=None),
    service: OpenAIService = Depends(get_service),
    settings: Settings = Depends(get_settings),
) -> ExtractedContents:
    uploads = ([image] if image is not None else []) + (images or [])
    if not uploads:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="이미지를 한 장 이상 선택해 주세요.")
    if len(uploads) > 8:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="이미지는 한 번에 최대 8장까지 업로드할 수 있습니다.")

    validated_images: list[tuple[bytes, str]] = []
    for upload in uploads:
        image_bytes = await upload.read()
        if not image_bytes:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="빈 이미지 파일입니다.")
        if len(image_bytes) > settings.max_upload_mb * 1024 * 1024:
            raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail=f"이미지는 장당 {settings.max_upload_mb}MB 이하여야 합니다.")
        detected_type = _detect_image_type(image_bytes)
        if detected_type is None:
            raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail="JPG, PNG 또는 WEBP 이미지만 업로드할 수 있습니다.")
        validated_images.append((image_bytes, detected_type))
    try:
        return await service.extract_contents_images(validated_images)
    except OpenAIServiceError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


def _detect_image_type(data: bytes) -> str | None:
    """Detect supported images by file signature instead of unreliable upload MIME."""
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


@app.post("/schedules/generate", response_model=Schedule)
async def generate_schedule(request: ScheduleRequest, service: OpenAIService = Depends(get_service)) -> Schedule:
    try:
        return await service.generate_schedule(request)
    except OpenAIServiceError as exc:
        logger.warning("Schedule generation failed: %s", exc, exc_info=True)
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@app.post("/schedules/replan", response_model=Schedule)
async def replan_schedule(request: ReplanRequest, service: OpenAIService = Depends(get_service)) -> Schedule:
    try:
        return await service.generate_schedule(request, replan=request)
    except OpenAIServiceError as exc:
        logger.warning("Schedule replanning failed: %s", exc, exc_info=True)
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
