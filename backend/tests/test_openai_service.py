import asyncio
import json

import httpx
import pytest

from app.config import Settings
from app.openai_service import OpenAIService, OpenAIServiceError, _extract_output_text


EXTRACTED_JSON = json.dumps({
    "items": [{
        "id": "c1-s1",
        "chapter": "I 다항식",
        "section": "01",
        "title": "다항식의 연산",
        "estimated_minutes": None,
    }],
}, ensure_ascii=False)


def raw_responses_payload(text: str = EXTRACTED_JSON) -> dict:
    """The shape returned by POST /v1/responses when using raw HTTP."""
    return {
        "id": "resp_test",
        "object": "response",
        "status": "completed",
        "output": [{
            "id": "msg_test",
            "type": "message",
            "status": "completed",
            "role": "assistant",
            "content": [{
                "type": "output_text",
                "text": text,
                "annotations": [],
            }],
        }],
    }


def test_extract_output_text_from_raw_responses_api_shape() -> None:
    assert _extract_output_text(raw_responses_payload()) == EXTRACTED_JSON


def test_extract_output_text_keeps_gateway_shortcut_compatibility() -> None:
    assert _extract_output_text({"output_text": EXTRACTED_JSON}) == EXTRACTED_JSON


def test_extract_output_text_reports_refusal_instead_of_empty_response() -> None:
    payload = raw_responses_payload()
    payload["output"][0]["content"] = [{"type": "refusal", "refusal": "Cannot comply"}]

    with pytest.raises(OpenAIServiceError, match="거부"):
        _extract_output_text(payload)


def test_extract_output_text_reports_incomplete_response() -> None:
    payload = raw_responses_payload('{"items":')
    payload["status"] = "incomplete"
    payload["incomplete_details"] = {"reason": "max_output_tokens"}

    with pytest.raises(OpenAIServiceError, match="중단"):
        _extract_output_text(payload)


def test_create_response_parses_raw_http_response(monkeypatch: pytest.MonkeyPatch) -> None:
    class FakeAsyncClient:
        def __init__(self, **_: object):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_: object):
            return None

        async def post(self, *_: object, **__: object) -> httpx.Response:
            return httpx.Response(
                200,
                json=raw_responses_payload(),
                request=httpx.Request("POST", "https://api.openai.com/v1/responses"),
            )

    monkeypatch.setattr(httpx, "AsyncClient", FakeAsyncClient)
    service = OpenAIService(Settings(openai_api_key="test-key"))

    result = asyncio.run(service._create_response({"model": "test-model"}))

    assert result == EXTRACTED_JSON


def test_multiple_images_are_sent_in_one_ordered_request() -> None:
    class CapturingService(OpenAIService):
        payload: dict | None = None

        async def _create_response(self, payload: dict) -> str:
            self.payload = payload
            return EXTRACTED_JSON

    service = CapturingService(Settings(openai_api_key="test-key"))
    asyncio.run(service.extract_contents_images([
        (b"first", "image/jpeg"),
        (b"second", "image/png"),
    ]))

    assert service.payload is not None
    content = service.payload["input"][0]["content"]
    image_parts = [part for part in content if part["type"] == "input_image"]
    assert len(image_parts) == 2
    assert image_parts[0]["image_url"].startswith("data:image/jpeg;base64,")
    assert image_parts[1]["image_url"].startswith("data:image/png;base64,")
