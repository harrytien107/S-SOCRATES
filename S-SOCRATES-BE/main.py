import time
from fastapi import FastAPI, UploadFile, File, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
from dotenv import load_dotenv

from services.stt_service import process_stt_request
from services.chat_orchestrator import process_chat_message
from services.tts_service import process_tts_request, CHIRP3_HD_VOICES
from services.semantic_router import semantic_router
from services.llm_service import ask_socrates, switch_gemini_model, AVAILABLE_GEMINI_MODELS

# =========================
# FastAPI Configuration
# =========================
app = FastAPI(title="S-Socrates API", description="Backend cho Voice Chat với Whisper VAD và LlamaIndex")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

load_dotenv()

# =========================
# Input Models
# =========================
class ChatRequest(BaseModel):
    message: str

class DecisionRequest(BaseModel):
    mode: str  # "preset", "ai" (Ollama), or "gemini"
    selected_answer: str = None
    transcript: str = None

class TTSRequest(BaseModel):
    text: str
    voice: str = "vi-VN-HoaiMyNeural"

class RobotCommand(BaseModel):
    text: str = ""
    emotion: str  # "neutral", "speaking", "challenge"

class AudioConfigRequest(BaseModel):
    tts_voice: str = "Aoede"
    tts_speed: float = 1.0
    stt_model: str = "nova-2"
    stt_language: str = "vi"
    gemini_model: str = "models/gemini-2.0-flash"

# =========================
# Global Runtime State
# =========================
_latest_robot_command = None
_latest_transcript = None

# Operator có thể chỉnh trực tiếp từ Web UI
GLOBAL_AUDIO_CONFIG = {
    "tts_voice": "Aoede",
    "tts_speed": 1.0,
    "stt_model": "nova-2",
    "stt_language": "vi",
    "gemini_model": "models/gemini-2.0-flash",
}

# Remote Mic Control – Cột đèn giao thông giữa Operator và App
# idle = ngủ, listening = đang thu âm, processing = đang xử lý STT
_robot_mic_status = "idle"

# =========================
# Endpoints
# =========================
@app.get("/")
async def root():
    return {"status": "S-Socrates API is running clean and fast!"}

@app.post("/stt")
async def speech_to_text(file: UploadFile = File(...)):
    try:
        text = process_stt_request(
            file,
            model=GLOBAL_AUDIO_CONFIG["stt_model"],
            language=GLOBAL_AUDIO_CONFIG["stt_language"]
        )
        return {"text": text}
    except Exception as e:
        import traceback
        traceback.print_exc()
        return {"error": str(e)}

@app.post("/tts")
async def text_to_speech(req: TTSRequest, background_tasks: BackgroundTasks):
    try:
        voice = GLOBAL_AUDIO_CONFIG["tts_voice"]
        speed = GLOBAL_AUDIO_CONFIG["tts_speed"]
        return process_tts_request(req.text, voice, background_tasks, speaking_rate=speed)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return {"error": str(e)}

@app.get("/tts/voices")
async def list_vi_voices():
    voices = [{"Name": v, "Locale": "vi-VN"} for v in CHIRP3_HD_VOICES]
    return {"voices": voices}

# =========================
# Audio Config Endpoints
# =========================

@app.get("/configs")
async def get_configs():
    return {
        "config": GLOBAL_AUDIO_CONFIG,
        "available_voices": CHIRP3_HD_VOICES,
        "available_stt_models": ["nova-2", "nova-2-general", "whisper-large"],
        "available_stt_languages": [
            {"code": "vi", "label": "Tiếng Việt"},
            {"code": "en", "label": "English"},
            {"code": "ja", "label": "日本語"},
            {"code": "zh", "label": "中文"},
        ],
        "available_gemini_models": AVAILABLE_GEMINI_MODELS,
    }

@app.post("/configs")
async def update_configs(req: AudioConfigRequest):
    GLOBAL_AUDIO_CONFIG["tts_voice"] = req.tts_voice
    GLOBAL_AUDIO_CONFIG["tts_speed"] = max(0.25, min(2.0, req.tts_speed))
    GLOBAL_AUDIO_CONFIG["stt_model"] = req.stt_model
    GLOBAL_AUDIO_CONFIG["stt_language"] = req.stt_language
    GLOBAL_AUDIO_CONFIG["gemini_model"] = req.gemini_model
    
    # Hot-swap Gemini model nếu thay đổi
    switch_gemini_model(req.gemini_model)
    
    return {"status": "Config updated", "config": GLOBAL_AUDIO_CONFIG}

# =========================
# Remote Mic Control Endpoints
# =========================

class MicControlRequest(BaseModel):
    action: str  # "start" hoặc "stop"

@app.post("/operator/mic-control")
async def mic_control(req: MicControlRequest):
    """Đạo diễn (Operator) bấm nút BẬT/TẮT Mic Robot từ xa."""
    global _robot_mic_status
    if req.action == "start":
        _robot_mic_status = "listening"
        return {"status": "Robot mic activated", "mic_status": _robot_mic_status}
    elif req.action == "stop":
        _robot_mic_status = "processing"
        return {"status": "Robot mic stopped, waiting for audio upload", "mic_status": _robot_mic_status}
    elif req.action == "cancel":
        _robot_mic_status = "canceled"
        return {"status": "Robot mic canceled, throwing away audio", "mic_status": _robot_mic_status}
    else:
        return {"error": "Invalid action. Use 'start', 'stop', or 'cancel'."}

@app.get("/robot/mic-status")
async def get_mic_status():
    """App điện thoại poll mỗi 1 giây để biết Đạo diễn muốn nó làm gì."""
    return {"mic_status": _robot_mic_status}

@app.post("/robot/mic-done")
async def mic_done():
    """App gọi sau khi đã upload xong audio, báo hiệu hoàn tất chu kỳ."""
    global _robot_mic_status
    _robot_mic_status = "idle"
    return {"status": "Mic cycle complete", "mic_status": _robot_mic_status}

# =========================
# Orchestration Endpoints
# =========================

@app.post("/process-audio")
async def process_audio(file: UploadFile = File(...)):
    global _latest_transcript, _latest_robot_command
    try:
        transcript = process_stt_request(
            file,
            model=GLOBAL_AUDIO_CONFIG["stt_model"],
            language=GLOBAL_AUDIO_CONFIG["stt_language"]
        )
        if transcript.strip() == "":
            _latest_transcript = {
                "transcript": "Không nhận được voice. Vui lòng nói lại.",
                "candidates": []
            }
            _latest_robot_command = {
                "text": "Không nhận được voice. Vui lòng nói lại.",
                "emotion": "no_voice",
                "timestamp": time.time_ns()
            }
            return _latest_transcript
        candidates = semantic_router.get_top_matches(transcript)
        _latest_transcript = {
            "transcript": transcript,
            "candidates": candidates
        }
        return _latest_transcript
    except Exception as e:
        return {"error": str(e)}
        
@app.get("/latest-transcript")
async def get_latest_transcript():
    global _latest_transcript
    if _latest_transcript:
        # Operator UI polls this. Only return once, then clear, so UI doesn't re-process duplicate
        res = _latest_transcript
        _latest_transcript = None
        return res
    return None

@app.post("/operator-decision")
async def operator_decision(req: DecisionRequest):
    text = ""
    emotion = "neutral"

    if req.mode == "preset":
        text = req.selected_answer
        emotion = "speaking"
    elif req.mode == "ai":
        # Using Ollama (Local LLM) through ask_socrates
        text = ask_socrates(req.transcript, model_choice="ollama")
        emotion = "challenge"
    elif req.mode == "gemini":
        # Using Gemini (Cloud LLM) through ask_socrates
        text = ask_socrates(req.transcript, model_choice="gemini")
        emotion = "challenge"
    else:
        return {"error": "Invalid mode"}

    # Heuristic for emotion
    if "phản biện" in text.lower() or "nhưng" in text.lower() or "thế nào" in text.lower():
        emotion = "challenge"

    return {
        "text": text,
        "emotion": emotion
    }

@app.post("/send-to-robot")
async def send_to_robot(req: RobotCommand):
    global _latest_robot_command
    text = (req.text or "").strip()
    if req.emotion in {"speaking", "challenge"} and not text:
        return {"error": "Text is required for speaking/challenge emotion"}

    _latest_robot_command = {
        "text": text,
        "emotion": req.emotion,
        "timestamp": time.time_ns()
    }
    return {"status": "Command sent to robot queue", "command": _latest_robot_command}

@app.get("/robot-command")
async def get_robot_command():
    # Frontend deduplicates via timestamp, do not destroy the command.
    return _latest_robot_command
