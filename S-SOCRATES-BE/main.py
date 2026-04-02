import time
import json
import asyncio
import httpx
from fastapi import FastAPI, UploadFile, File, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool
from fastapi.staticfiles import StaticFiles
import os
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

load_dotenv()

from services.stt_service import process_stt_request
from services.tts_service import process_tts_request, CHIRP3_HD_VOICES
from services.llm_service import (
    ask_socrates,
    switch_gemini_model,
    AVAILABLE_GEMINI_MODELS,
    get_local_backend_status,
    initialize_local_backend,
    shutdown_local_backend,
)
from utils.logger import log

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

# Thống nhất thư mục Operator-UI để Serve Frontend qua FastAPI
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ui_dir = os.path.join(BASE_DIR, "operator-ui")
if os.path.exists(ui_dir):
    app.mount("/operator", StaticFiles(directory=ui_dir, html=True), name="operator")


class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        stale_connections = []
        for connection in list(self.active_connections):
            try:
                await asyncio.wait_for(connection.send_json(message), timeout=0.5)
            except Exception:
                stale_connections.append(connection)
        for connection in stale_connections:
            self.disconnect(connection)


ws_manager = ConnectionManager()

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
    emotion: str  # "neutral", "speaking", "no_voice", "error"

class AudioConfigRequest(BaseModel):
    tts_voice: str = "Aoede"
    tts_speed: float = 1.0
    stt_model: str = "nova-2"
    stt_language: str = "vi"
    gemini_model: str = "models/gemini-2.0-flash"
    robot_control_url: str | None = None


class RobotSyncRequest(BaseModel):
    status: str

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
ROBOT_CONTROL_URL = os.getenv("ROBOT_CONTROL_URL", "http://192.168.1.6:9000").rstrip("/")


@app.on_event("startup")
async def startup_local_llm():
    try:
        await run_in_threadpool(initialize_local_backend)
    except Exception as e:
        log.warning(f"⚠️ Local LLM backend startup skipped: {e}")


@app.on_event("shutdown")
async def shutdown_local_llm():
    await run_in_threadpool(shutdown_local_backend)


@app.on_event("startup")
async def startup_local_llm():
    try:
        initialize_local_backend()
    except Exception as e:
        log.warning(f"⚠️ Local LLM backend startup skipped: {e}")


@app.on_event("shutdown")
async def shutdown_local_llm():
    shutdown_local_backend()

# Remote Mic Control – Cột đèn giao thông giữa Operator và App
# idle = ngủ, listening = đang thu âm, processing = đang xử lý STT
_robot_mic_status = "idle"

QA_PRESETS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qa_presets.json")


def load_qa_presets():
    with open(QA_PRESETS_PATH, "r", encoding="utf-8") as file:
        return json.load(file)

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
    local_backend = await run_in_threadpool(get_local_backend_status)
    return {
        "config": GLOBAL_AUDIO_CONFIG,
        "robot_control_url": ROBOT_CONTROL_URL,
        "local_llm": local_backend,
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
    global ROBOT_CONTROL_URL
    GLOBAL_AUDIO_CONFIG["tts_voice"] = req.tts_voice
    GLOBAL_AUDIO_CONFIG["tts_speed"] = max(0.25, min(2.0, req.tts_speed))
    GLOBAL_AUDIO_CONFIG["stt_model"] = req.stt_model
    GLOBAL_AUDIO_CONFIG["stt_language"] = req.stt_language
    GLOBAL_AUDIO_CONFIG["gemini_model"] = req.gemini_model
    if req.robot_control_url:
        ROBOT_CONTROL_URL = req.robot_control_url.rstrip("/")
    
    # Hot-swap Gemini model nếu thay đổi
    switch_gemini_model(req.gemini_model)
    
    return {"status": "Config updated", "config": GLOBAL_AUDIO_CONFIG}

# =========================
# Remote Mic Control Endpoints
# =========================

class MicControlRequest(BaseModel):
    action: str  # "start" hoặc "stop"


async def dispatch_robot_request(path: str, payload: dict | None = None):
    url = f"{ROBOT_CONTROL_URL}{path}"
    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await client.post(url, json=payload or {})
        response.raise_for_status()
        if not response.content:
            return {"status": "ok"}
        return response.json()

@app.post("/robot/mic-control")
async def mic_control(req: MicControlRequest):
    """Đạo diễn (Operator) bấm nút BẬT/TẮT Mic Robot từ xa."""
    global _robot_mic_status
    if req.action == "start":
        _robot_mic_status = "listening"
    elif req.action == "stop":
        _robot_mic_status = "processing"
    elif req.action == "cancel":
        _robot_mic_status = "canceled"
    else:
        return {"error": "Invalid action. Use 'start', 'stop', or 'cancel'."}

    try:
        robot_response = await dispatch_robot_request("/mic", {"action": req.action})
    except Exception as e:
        return {"error": f"Failed to reach robot at {ROBOT_CONTROL_URL}: {e}"}

    await ws_manager.broadcast({"type": "mic_status", "status": _robot_mic_status})
    return {
        "status": f"Robot mic {req.action}",
        "mic_status": _robot_mic_status,
        "robot_response": robot_response,
    }

@app.get("/robot/mic-status")
async def get_mic_status():
    """App điện thoại poll mỗi 1 giây để biết Đạo diễn muốn nó làm gì."""
    return {"mic_status": _robot_mic_status}

@app.post("/robot/mic-done")
async def mic_done():
    """App gọi sau khi đã upload xong audio, báo hiệu hoàn tất chu kỳ."""
    global _robot_mic_status
    _robot_mic_status = "idle"
    await ws_manager.broadcast({"type": "mic_status", "status": _robot_mic_status})
    return {"status": "Mic cycle complete", "mic_status": _robot_mic_status}


@app.post("/robot/mic-sync")
async def robot_mic_sync(req: RobotSyncRequest):
    global _robot_mic_status
    _robot_mic_status = req.status
    await ws_manager.broadcast({"type": "mic_status", "status": _robot_mic_status})
    return {"status": "Robot mic synced", "mic_status": _robot_mic_status}


class LogRequest(BaseModel):
    message: str


@app.post("/robot/log")
async def receive_robot_log(req: LogRequest):
    await ws_manager.broadcast({"type": "log", "message": req.message})
    return {"status": "Log broadcasted"}


@app.websocket("/ws/operator")
async def websocket_operator(websocket: WebSocket):
    await ws_manager.connect(websocket)
    try:
        await websocket.send_json({"type": "mic_status", "status": _robot_mic_status})
        if _latest_transcript:
            await websocket.send_json({"type": "transcript", "data": _latest_transcript})

        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        ws_manager.disconnect(websocket)

# =========================
# Orchestration Endpoints
# =========================

@app.post("/process-audio")
async def process_audio(file: UploadFile = File(...)):
    global _latest_transcript, _latest_robot_command
    try:
        presets = load_qa_presets()
        transcript = process_stt_request(
            file,
            model=GLOBAL_AUDIO_CONFIG["stt_model"],
            language=GLOBAL_AUDIO_CONFIG["stt_language"]
        )
        if transcript.strip() == "":
            _latest_transcript = {
                "transcript": "Không nhận được voice. Vui lòng nói lại.",
                "candidates": presets
            }
            _latest_robot_command = {
                "text": "Không nhận được voice. Vui lòng nói lại.",
                "emotion": "no_voice",
                "timestamp": time.time_ns()
            }
            await ws_manager.broadcast({"type": "transcript", "data": _latest_transcript})
            return _latest_transcript
        _latest_transcript = {
            "transcript": transcript,
            "candidates": presets
        }
        await ws_manager.broadcast({"type": "transcript", "data": _latest_transcript})
        return _latest_transcript
    except Exception as e:
        return {"error": str(e)}


@app.get("/qa-presets")
async def get_qa_presets():
    try:
        return {"presets": load_qa_presets()}
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
        # Using selected local LLM backend (Ollama or TurboQuant) through ask_socrates
        text = ask_socrates(req.transcript, model_choice="ollama")
        emotion = "speaking"
    elif req.mode == "gemini":
        # Using Gemini (Cloud LLM) through ask_socrates
        text = ask_socrates(req.transcript, model_choice="gemini")
        emotion = "speaking"
    else:
        return {"error": "Invalid mode"}

    return {
        "text": text,
        "emotion": emotion
    }

@app.post("/send-to-robot")
async def send_to_robot(req: RobotCommand):
    global _latest_robot_command
    text = (req.text or "").strip()
    if req.emotion == "speaking" and not text:
        return {"error": "Text is required for speaking emotion"}

    _latest_robot_command = {
        "text": text,
        "emotion": req.emotion,
        "timestamp": time.time_ns()
    }
    try:
        robot_response = await dispatch_robot_request(
            "/command",
            {"text": text, "emotion": req.emotion},
        )
    except Exception as e:
        return {"error": f"Failed to reach robot at {ROBOT_CONTROL_URL}: {e}"}

    return {
        "status": "Command sent directly to robot",
        "command": _latest_robot_command,
        "robot_response": robot_response,
    }
