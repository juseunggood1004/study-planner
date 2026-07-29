from __future__ import annotations

from fastapi import Depends, FastAPI, File, HTTPException, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings, get_settings
from .openai_service import OpenAIService, OpenAIServiceError
from .schemas import ExtractedContents, ReplanRequest, Schedule, ScheduleRequest

app = FastAPI(title="AI Study Scheduler API", version="0.1.0")
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
    image: UploadFile = File(...),
    service: OpenAIService = Depends(get_service),
    settings: Settings = Depends(get_settings),
) -> ExtractedContents:
    if image.content_type not in {"image/jpeg", "image/png", "image/webp"}:
        raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail="JPG, PNG 또는 WEBP 이미지만 업로드할 수 있습니다.")
    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="빈 이미지 파일입니다.")
    if len(image_bytes) > settings.max_upload_mb * 1024 * 1024:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail=f"이미지는 {settings.max_upload_mb}MB 이하여야 합니다.")
    try:
        return await service.extract_contents(image_bytes, image.content_type)
    except OpenAIServiceError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@app.post("/schedules/generate", response_model=Schedule)
async def generate_schedule(request: ScheduleRequest, service: OpenAIService = Depends(get_service)) -> Schedule:
    try:
        return await service.generate_schedule(request)
    except OpenAIServiceError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@app.post("/schedules/replan", response_model=Schedule)
async def replan_schedule(request: ReplanRequest, service: OpenAIService = Depends(get_service)) -> Schedule:
    try:
        return await service.generate_schedule(request, replan=request)
    except OpenAIServiceError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
