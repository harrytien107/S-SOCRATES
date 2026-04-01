"""
Google Cloud TTS Streaming Service — Sentence Chunking
Dịch từng câu ngắn sang audio ngay lập tức, không chờ cả đoạn.
Sử dụng Chirp 3 HD voices.
"""
import os
import asyncio
from concurrent.futures import ThreadPoolExecutor
from google.cloud import texttospeech
from utils.logger import log

# Thread pool cho synchronous Google TTS calls
_executor = ThreadPoolExecutor(max_workers=3)

CHIRP3_HD_VOICES = ['Aoede', 'Kore', 'Leda', 'Zephyr', 'Puck', 'Charon', 'Fenrir', 'Orus']
DEFAULT_VOICE = "Aoede"
DEFAULT_LANGUAGE = "vi-VN"
DEFAULT_MODEL = "Chirp3-HD"

_tts_client = None


def _get_client():
    global _tts_client
    if _tts_client is None:
        _tts_client = texttospeech.TextToSpeechClient()
    return _tts_client


def _synthesize_sentence_sync(text: str, voice: str = DEFAULT_VOICE,
                               speed: float = 1.0, language: str = DEFAULT_LANGUAGE) -> bytes:
    """
    Synchronous: Dịch 1 câu ngắn → trả về audio bytes (MP3).
    Chạy trong thread pool để không block event loop.
    """
    client = _get_client()

    if voice not in CHIRP3_HD_VOICES:
        voice = DEFAULT_VOICE
    voice_name = f"{language}-{DEFAULT_MODEL}-{voice}"

    synthesis_input = texttospeech.SynthesisInput(text=text)
    voice_params = texttospeech.VoiceSelectionParams(
        language_code=language,
        name=voice_name,
    )
    audio_config = texttospeech.AudioConfig(
        audio_encoding=texttospeech.AudioEncoding.MP3,
        speaking_rate=max(0.25, min(4.0, speed)),
    )

    response = client.synthesize_speech(
        input=synthesis_input,
        voice=voice_params,
        audio_config=audio_config,
    )

    return response.audio_content


async def synthesize_sentence(text: str, voice: str = DEFAULT_VOICE,
                               speed: float = 1.0) -> bytes:
    """
    Async: Dịch 1 câu ngắn → trả về audio bytes (MP3).
    Wrapper async cho hàm sync, chạy trong thread pool.
    """
    loop = asyncio.get_event_loop()
    audio_bytes = await loop.run_in_executor(
        _executor,
        _synthesize_sentence_sync,
        text, voice, speed
    )
    log.info(f"🗣️ TTS chunk: \"{text[:50]}...\" → {len(audio_bytes)} bytes")
    return audio_bytes


def split_into_sentences(text: str) -> list[str]:
    """
    Chia đoạn văn thành danh sách câu dựa trên dấu câu.
    Giữ lại dấu câu ở cuối mỗi câu.
    """
    sentences = []
    current = ""

    for char in text:
        current += char
        if char in ".!?。;:":
            sentence = current.strip()
            if sentence:
                sentences.append(sentence)
            current = ""

    # Phần còn lại (không có dấu kết thúc)
    remaining = current.strip()
    if remaining:
        sentences.append(remaining)

    return sentences
