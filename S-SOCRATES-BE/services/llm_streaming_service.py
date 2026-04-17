"""
LLM Streaming Service — OpenRouter Streaming + Sentence Chunking
Stream tokens từ OpenRouter API, gom thành từng câu hoàn chỉnh và yield ra.
"""

import os
import json
import asyncio
from concurrent.futures import ThreadPoolExecutor

import requests

from utils.logger import log

_executor = ThreadPoolExecutor(max_workers=2)

SENTENCE_DELIMITERS = {".", "!", "?", "。", ";"}

OPENROUTER_API_BASE = os.getenv("OPENROUTER_API_BASE", "https://openrouter.ai/api/v1").strip()
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "").strip()
OPENROUTER_STREAM_TIMEOUT_S = float(os.getenv("OPENROUTER_STREAM_TIMEOUT_S", "60"))
OPENROUTER_TEMPERATURE = float(os.getenv("OPENROUTER_TEMPERATURE", "0.3"))
OPENROUTER_MAX_TOKENS = int(os.getenv("OPENROUTER_MAX_TOKENS", "300"))
OPENROUTER_HTTP_REFERER = os.getenv("OPENROUTER_HTTP_REFERER", "").strip()
OPENROUTER_APP_NAME = os.getenv("OPENROUTER_APP_NAME", "S-SOCRATES").strip()


def _openrouter_headers() -> dict:
    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
    }
    if OPENROUTER_HTTP_REFERER:
        headers["HTTP-Referer"] = OPENROUTER_HTTP_REFERER
    if OPENROUTER_APP_NAME:
        headers["X-Title"] = OPENROUTER_APP_NAME
    return headers


def _stream_openrouter_sync(prompt: str, model_name: str):
    """Synchronous generator: gọi OpenRouter stream API và yield từng câu."""
    if not OPENROUTER_API_KEY:
        raise Exception("OPENROUTER_API_KEY not set in .env")

    url = f"{OPENROUTER_API_BASE.rstrip('/')}/chat/completions"
    payload = {
        "model": model_name,
        "messages": [{"role": "user", "content": prompt}],
        "stream": True,
        "temperature": OPENROUTER_TEMPERATURE,
        "max_tokens": OPENROUTER_MAX_TOKENS,
    }

    log.info("🧠 OpenRouter streaming: model=%s", model_name)

    with requests.post(
        url,
        headers=_openrouter_headers(),
        json=payload,
        stream=True,
        timeout=OPENROUTER_STREAM_TIMEOUT_S if OPENROUTER_STREAM_TIMEOUT_S > 0 else None,
    ) as resp:
        resp.encoding = "utf-8"
        if resp.status_code >= 400:
            detail = resp.text
            try:
                body = resp.json()
                detail = body.get("error", {}).get("message") or body.get("message") or detail
            except Exception:
                pass
            raise Exception(f"OpenRouter stream HTTP {resp.status_code}: {detail}")

        buffer = ""
        for raw_line in resp.iter_lines(decode_unicode=True):
            if not raw_line:
                continue

            line = raw_line.strip()
            if not line.startswith("data:"):
                continue

            data_chunk = line[5:].strip()
            if data_chunk == "[DONE]":
                break

            try:
                event = json.loads(data_chunk)
            except Exception:
                continue

            delta = (((event.get("choices") or [{}])[0]).get("delta") or {}).get("content", "")
            if not delta:
                continue

            buffer += delta

            while True:
                earliest_idx = -1
                for delim in SENTENCE_DELIMITERS:
                    idx = buffer.find(delim)
                    if idx != -1:
                        if earliest_idx == -1 or idx < earliest_idx:
                            earliest_idx = idx

                if earliest_idx == -1:
                    break

                sentence = buffer[:earliest_idx + 1].strip()
                buffer = buffer[earliest_idx + 1:]
                if sentence:
                    yield sentence

        remaining = buffer.strip()
        if remaining:
            yield remaining


async def stream_openrouter_sentences(prompt: str, model_name: str):
    """Async generator: yield từng câu hoàn chỉnh từ OpenRouter streaming API."""
    loop = asyncio.get_event_loop()
    queue = asyncio.Queue()
    _DONE = object()

    def _run_in_thread():
        try:
            for sentence in _stream_openrouter_sync(prompt, model_name):
                loop.call_soon_threadsafe(queue.put_nowait, sentence)
        except Exception as e:
            loop.call_soon_threadsafe(queue.put_nowait, e)
        finally:
            loop.call_soon_threadsafe(queue.put_nowait, _DONE)

    future = _executor.submit(_run_in_thread)

    try:
        while True:
            item = await queue.get()
            if item is _DONE:
                break
            if isinstance(item, Exception):
                raise item
            yield item
    finally:
        future.result(timeout=1.0) if future.done() else None
