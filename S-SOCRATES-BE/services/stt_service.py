import os
import shutil
import time

from fastapi import UploadFile
from faster_whisper import WhisperModel

# =========================
# Init Whisper STT Component
# =========================

def init_stt_model():
    # Sử dụng Whisper bản 'base' chạy trên CPU để tối ưu RAM (compute_type='int8')
    print("Initializing Whisper Model...")
    return WhisperModel("base", device="cpu", compute_type="int8")

_stt_model = init_stt_model()

# Đảm bảo thư mục voice luôn tồn tại
VOICE_DIR = "voice"
os.makedirs(VOICE_DIR, exist_ok=True)

async def transcribe_audio(file: UploadFile) -> str:
    # Đặt tên file kèm thời gian để tránh trùng lặp và lưu trữ
    timestamp = int(time.time() * 1000)
    file_path = os.path.join(VOICE_DIR, f"voice_{timestamp}.m4a")
    
    try:
        # Lưu thẳng file vào thư mục voice thay vì làm file tạm
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        # Gọi model Whisper để dịch file tiếng Việt
        segments, info = _stt_model.transcribe(file_path, beam_size=5, language="vi")
        text = "".join([segment.text for segment in segments])
        return text.strip()
    except Exception as e:
        raise e
    finally:
        # Xóa file sau khi dịch xong để không bừa bộn ổ cứng
        if os.path.exists(file_path):
            os.remove(file_path)

