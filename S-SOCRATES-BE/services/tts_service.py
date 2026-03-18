import io
import edge_tts
from fastapi.responses import StreamingResponse

# =========================
# Text-To-Speech Service
# =========================

async def generate_speech_stream(text: str, voice: str = "vi-VN-HoaiMyNeural") -> StreamingResponse:
    communicate = edge_tts.Communicate(text, voice)
    buffer = io.BytesIO()
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            buffer.write(chunk["data"])
    
    # Đưa con trỏ buffer về vị trí 0 để fastapi có thể đọc file ra
    buffer.seek(0)
    
    return StreamingResponse(
        buffer,
        media_type="audio/mpeg",
        headers={"Content-Disposition": "inline"},
    )

async def get_vietnamese_voices() -> list:
    voices = await edge_tts.list_voices()
    return [v for v in voices if v["Locale"].startswith("vi")]
