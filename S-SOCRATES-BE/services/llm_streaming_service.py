"""
LLM Streaming Service — Gemini Streaming + Sentence Chunking
Stream tokens từ Gemini API, gom thành từng câu hoàn chỉnh và yield ra.
"""
import os
import asyncio
from concurrent.futures import ThreadPoolExecutor
from utils.logger import log

_executor = ThreadPoolExecutor(max_workers=2)

SENTENCE_DELIMITERS = {".", "!", "?", "。", ";"}


def _stream_gemini_sync(prompt: str, model_name: str = "gemini-2.0-flash"):
    """
    Synchronous generator: Gọi Gemini streaming API, yield từng câu hoàn chỉnh.
    Chạy trong thread để không block event loop.
    """
    import google.generativeai as genai

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise Exception("GEMINI_API_KEY not set in .env")

    genai.configure(api_key=api_key)

    # Chuẩn hóa model name
    clean_name = model_name.replace("models/", "")
    model = genai.GenerativeModel(clean_name)

    log.info(f"🧠 Gemini streaming: model={clean_name}")

    response = model.generate_content(prompt, stream=True)

    buffer = ""
    for chunk in response:
        if not chunk.text:
            continue
        buffer += chunk.text

        # Tìm dấu kết thúc câu
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

    # Flush phần còn lại
    remaining = buffer.strip()
    if remaining:
        yield remaining


async def stream_gemini_sentences(prompt: str, model_name: str = "gemini-2.0-flash"):
    """
    Async generator: Yield từng câu hoàn chỉnh từ Gemini streaming API.
    
    Usage:
        async for sentence in stream_gemini_sentences(prompt, model):
            print(sentence)
    """
    loop = asyncio.get_event_loop()

    # Chạy sync generator trong thread, đẩy sentences qua queue
    queue = asyncio.Queue()
    _DONE = object()

    def _run_in_thread():
        try:
            for sentence in _stream_gemini_sync(prompt, model_name):
                loop.call_soon_threadsafe(queue.put_nowait, sentence)
        except Exception as e:
            loop.call_soon_threadsafe(queue.put_nowait, e)
        finally:
            loop.call_soon_threadsafe(queue.put_nowait, _DONE)

    # Chạy trong thread pool
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
        # Đảm bảo thread kết thúc
        future.result(timeout=1.0) if future.done() else None
