"""Opt-in test for a real table-of-contents image and OpenAI API call.

Run with:
RUN_OPENAI_INTEGRATION=1 TEST_TOC_IMAGE=/absolute/path/to/image.jpg \
  venv/bin/python -m pytest -q tests/test_live_extraction.py -s
"""

import asyncio
import os
from pathlib import Path

import pytest

from app.config import Settings
from app.openai_service import OpenAIService


@pytest.mark.skipif(
    os.getenv("RUN_OPENAI_INTEGRATION") != "1" or not os.getenv("TEST_TOC_IMAGE"),
    reason="Set RUN_OPENAI_INTEGRATION=1 and TEST_TOC_IMAGE to run the paid live test.",
)
def test_live_korean_math_table_of_contents() -> None:
    image_path = Path(os.environ["TEST_TOC_IMAGE"])
    image_bytes = image_path.read_bytes()
    result = asyncio.run(OpenAIService(Settings()).extract_contents(image_bytes, "image/jpeg"))

    assert len(result.items) >= 12
    titles = [item.title for item in result.items]
    assert any("다항식의 연산" in title for title in titles)
    assert any("도형의 이동" in title for title in titles)


@pytest.mark.skipif(
    os.getenv("RUN_OPENAI_INTEGRATION") != "1" or not os.getenv("TEST_TOC_IMAGE"),
    reason="Set RUN_OPENAI_INTEGRATION=1 and TEST_TOC_IMAGE to run the paid live test.",
)
def test_live_overlapping_images_are_deduplicated() -> None:
    image_bytes = Path(os.environ["TEST_TOC_IMAGE"]).read_bytes()
    result = asyncio.run(OpenAIService(Settings()).extract_contents_images([
        (image_bytes, "image/jpeg"),
        (image_bytes, "image/jpeg"),
    ]))

    identities = [(item.chapter, item.section, item.title) for item in result.items]
    assert len(identities) >= 12
    assert len(identities) == len(set(identities))
