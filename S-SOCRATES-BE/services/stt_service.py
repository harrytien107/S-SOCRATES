import os
import time
import shutil
import httpx
from fastapi import UploadFile
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


def transcribe_file(wav_path: str, model: str = "nova-2", language: str = "vi") -> str:
    """
    Đọc file WAV từ disk, gửi lên Deepgram REST API, trả về transcript.
    model: Deepgram model (nova-2, nova-2-general, whisper-large, ...)
    language: Mã ngôn ngữ (vi, en, ja, ...)
    """
    api_key = get_deepgram_api_key()

    url = f"{DEEPGRAM_API_URL}?model={model}&language={language}&smart_format=true"
    headers = {
        "Authorization": f"Token {api_key}",
    }
    
    log.info(f"Gửi file audio tới Deepgram API: {wav_path} (model={model}, lang={language})")

    with open(wav_path, "rb") as audio_file:
        audio_data = audio_file.read()

    with httpx.Client(timeout=120.0) as client:
        response = client.post(url, headers=headers, content=audio_data)
        response.raise_for_status()

        data = response.json()
        text = data["results"]["channels"][0]["alternatives"][0]["transcript"]
        result = text.strip()

    log.info(f"Deepgram STT result: '{result}'")
    return result

def process_stt_request(file: UploadFile, model: str = "nova-2", language: str = "vi") -> str:
    log.info(f"--- Đã nhận file Upload '{file.filename}' từ Flutter (STT: {model}/{language}) ---")
    stt_start = time.time()
    temp_path = f"temp_{file.filename}"
    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        text = transcribe_file(temp_path, model=model, language=language)
        
        stt_time = (time.time() - stt_start) * 1000
        log.info(f"STT Pipeline dịch xong. Thời gian trễ xử lý: {stt_time:.0f}ms")
        return text
    finally:
        # Luôn dọn rác ổ cứng sau khi dịch xong
        if os.path.exists(temp_path):
            os.remove(temp_path)