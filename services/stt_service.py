import os
import httpx
from utils.logger import log

# =========================
# Deepgram STT Service (REST API)
# =========================

DEEPGRAM_API_URL = "https://api.deepgram.com/v1/listen"


def get_deepgram_api_key() -> str:
    api_key = os.getenv("DEEPGRAM_API_KEY")
    if not api_key:
        raise Exception("DEEPGRAM_API_KEY is not set in .env")
    return api_key


def transcribe_file(wav_path: str) -> str:
    """
    Đọc file WAV từ disk, gửi lên Deepgram REST API, trả về transcript.
    Dùng cho desktop app (ghi âm bằng sounddevice → lưu WAV → gọi hàm này).
    """
    api_key = get_deepgram_api_key()

    url = f"{DEEPGRAM_API_URL}?model=nova-2&language=vi&smart_format=true"
    headers = {
        "Authorization": f"Token {api_key}",
        "Content-Type": "audio/wav",
    }

    log.info(f"Gửi file audio tới Deepgram API: {wav_path}")

    with open(wav_path, "rb") as audio_file:
        audio_data = audio_file.read()

    # Sử dụng httpx synchronous client (vì chạy trong QThread, không cần async)
    with httpx.Client(timeout=120.0) as client:
        response = client.post(url, headers=headers, content=audio_data)
        response.raise_for_status()

        data = response.json()
        text = data["results"]["channels"][0]["alternatives"][0]["transcript"]
        result = text.strip()

    log.info(f"Deepgram STT result: '{result}'")
    return result
