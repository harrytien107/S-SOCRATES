import asyncio
import json
import os
import time
from pathlib import Path

from dotenv import load_dotenv
from fastapi import (
    BackgroundTasks,
    FastAPI,
    File,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from services.chat_orchestrator import process_chat_message
from services.gemini_service import gemini_service
from services.llm_service import (
    AVAILABLE_GEMINI_MODELS,
    get_local_backend_status,
    initialize_local_backend,
    shutdown_local_backend,
    switch_gemini_model,
    warm_local_context,
)
from services.memory_service import memory_service
from services.retrieval.retriever import retriever
from services.stt_service import process_stt_request
from services.tts_service import CHIRP3_HD_VOICES, process_tts_request
from utils.logger import log

ENV_PATH = Path(__file__).resolve().parent / ".env"
load_dotenv(dotenv_path=ENV_PATH, override=True)

api_key = os.getenv("DEEPGRAM_API_KEY")
if not api_key:
    print("❌ DEEPGRAM_API_KEY is MISSING in environment variables!")
    exit(1)
else:
    print(f"✅ DEEPGRAM_API_KEY loaded: {api_key[:4]}...")

api_key = os.getenv("GEMINI_API_KEY")
if not api_key:
    print("❌ GEMINI_API_KEY is MISSING in environment variables!")
    exit(1)
else:
    print(f"✅ GEMINI_API_KEY loaded: {api_key[:4]}...")

DEPLOYMENT_MODE = os.getenv("DEPLOYMENT_MODE", "hybrid").strip().lower()
if DEPLOYMENT_MODE not in {"hybrid", "api", "local"}:
    DEPLOYMENT_MODE = "hybrid"


app = FastAPI(
    title="S-Socrates API",
    description="Backend cho S-SOCRATES: Deepgram STT, Quantized RAG, Gemini cloud, TurboQuant local runtime, va robot control.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

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


class RobotConnectionManager:
    def __init__(self):
        self.active_connection: WebSocket | None = None
        self._lock = asyncio.Lock()
        self.last_seen_ns = 0

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        old_connection: WebSocket | None
        async with self._lock:
            old_connection = self.active_connection
            self.active_connection = websocket
            self.last_seen_ns = time.time_ns()

        if old_connection and old_connection is not websocket:
            try:
                await old_connection.close(code=1000, reason="Replaced by a newer robot connection")
            except Exception:
                pass

    def disconnect(self, websocket: WebSocket):
        if self.active_connection is websocket:
            self.active_connection = None

    def is_connected(self) -> bool:
        return self.active_connection is not None

    def touch(self):
        self.last_seen_ns = time.time_ns()

    async def send_json(self, message: dict, timeout_seconds: float = 1.5):
        connection = self.active_connection
        if connection is None:
            raise RuntimeError("Robot app is not connected via WebSocket.")

        try:
            await asyncio.wait_for(connection.send_json(message), timeout=timeout_seconds)
            self.last_seen_ns = time.time_ns()
        except Exception as exc:
            self.disconnect(connection)
            raise RuntimeError(f"Robot WebSocket send failed: {exc}") from exc


ws_manager = ConnectionManager()
robot_ws_manager = RobotConnectionManager()
_local_runtime_warm_task: asyncio.Task | None = None


class ChatRequest(BaseModel):
    message: str


class DecisionRequest(BaseModel):
    mode: str
    selected_answer: str | None = None
    transcript: str | None = None


class TTSRequest(BaseModel):
    text: str
    voice: str = "vi-VN-HoaiMyNeural"


class RobotCommand(BaseModel):
    text: str = ""
    emotion: str


class AudioConfigRequest(BaseModel):
    tts_voice: str = "Aoede"
    tts_speed: float = 1.0
    stt_model: str = "nova-2"
    stt_language: str = "vi"
    gemini_model: str = "models/gemini-2.5-flash"


class RobotSyncRequest(BaseModel):
    status: str


class MicControlRequest(BaseModel):
    action: str


class LogRequest(BaseModel):
    message: str


_latest_robot_command = None
_latest_transcript = None

GLOBAL_AUDIO_CONFIG = {
    "tts_voice": "Aoede",
    "tts_speed": 1.0,
    "stt_model": "nova-2",
    "stt_language": "vi",
    "gemini_model": "models/gemini-2.5-flash",
}
_robot_mic_status = "idle"
SETTINGS_PATH = Path(__file__).resolve().parent / "operator_settings.json"

QA_PRESETS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qa_presets.json")


def load_operator_settings_from_disk():
    if not SETTINGS_PATH.exists():
        return None

    try:
        with open(SETTINGS_PATH, "r", encoding="utf-8") as file:
            payload = json.load(file)
    except Exception as exc:
        log.warning("Could not load operator settings: %s", exc)
        return None

    if not isinstance(payload, dict):
        return None

    return payload


def supports_local_ai() -> bool:
    return DEPLOYMENT_MODE in {"hybrid", "local"}


def supports_api_ai() -> bool:
    return DEPLOYMENT_MODE in {"hybrid", "api"}


def _apply_audio_config(config: dict) -> None:
    """Normalize + update GLOBAL_AUDIO_CONFIG in place from a dict payload."""
    if not isinstance(config, dict):
        return

    GLOBAL_AUDIO_CONFIG["tts_voice"] = config.get("tts_voice", GLOBAL_AUDIO_CONFIG["tts_voice"])
    try:
        tts_speed = float(config.get("tts_speed", GLOBAL_AUDIO_CONFIG["tts_speed"]))
    except (TypeError, ValueError):
        tts_speed = GLOBAL_AUDIO_CONFIG["tts_speed"]
    GLOBAL_AUDIO_CONFIG["tts_speed"] = max(0.25, min(2.0, tts_speed))
    GLOBAL_AUDIO_CONFIG["stt_model"] = config.get("stt_model", GLOBAL_AUDIO_CONFIG["stt_model"])
    GLOBAL_AUDIO_CONFIG["stt_language"] = config.get("stt_language", GLOBAL_AUDIO_CONFIG["stt_language"])
    GLOBAL_AUDIO_CONFIG["gemini_model"] = config.get("gemini_model", GLOBAL_AUDIO_CONFIG["gemini_model"])


def _activate_audio_config(*, source: str) -> None:
    """Propagate GLOBAL_AUDIO_CONFIG to the downstream services (Gemini, ...).

    Called both on boot (after loading operator_settings.json) and on every
    `/configs` POST so the running backend actually mirrors the saved state
    without requiring a manual "Save & Connect" click from the operator UI.
    """
    gemini_model = GLOBAL_AUDIO_CONFIG.get("gemini_model")
    if supports_api_ai() and gemini_model:
        try:
            switch_gemini_model(gemini_model)
            log.info(
                "[settings:%s] Gemini active model = %s",
                source,
                gemini_service.current_model or gemini_model,
            )
        except Exception as exc:
            log.warning("[settings:%s] Could not apply Gemini model %s: %s", source, gemini_model, exc)

    log.info(
        "[settings:%s] Audio config active: voice=%s speed=%sx stt=%s/%s gemini=%s",
        source,
        GLOBAL_AUDIO_CONFIG["tts_voice"],
        GLOBAL_AUDIO_CONFIG["tts_speed"],
        GLOBAL_AUDIO_CONFIG["stt_model"],
        GLOBAL_AUDIO_CONFIG["stt_language"],
        GLOBAL_AUDIO_CONFIG["gemini_model"],
    )


def apply_operator_settings(payload: dict, *, source: str = "disk") -> None:
    if not isinstance(payload, dict):
        return
    config = payload.get("config")
    _apply_audio_config(config if isinstance(config, dict) else {})
    _activate_audio_config(source=source)


def save_operator_settings_to_disk():
    payload = {
        "config": GLOBAL_AUDIO_CONFIG,
    }

    try:
        with open(SETTINGS_PATH, "w", encoding="utf-8") as file:
            json.dump(payload, file, ensure_ascii=False, indent=2)
    except Exception as exc:
        log.warning("Could not save operator settings: %s", exc)


persisted_settings = load_operator_settings_from_disk()
if persisted_settings:
    apply_operator_settings(persisted_settings, source="boot")
else:
    log.info("[settings:boot] No operator_settings.json found - using built-in defaults.")


def build_local_runtime_payload() -> dict:
    if supports_local_ai():
        return get_local_backend_status()
    return {
        "ready": False,
        "phase": "disabled",
        "detail": "Local AI is disabled in this deployment mode.",
    }


@app.on_event("startup")
async def startup_local_llm():
    global _local_runtime_warm_task
    try:
        await run_in_threadpool(retriever.initialize)
    except Exception as e:
        log.warning(f"Quantized retrieval startup skipped: {e}")
    if supports_local_ai():
        try:
            await run_in_threadpool(initialize_local_backend)
        except Exception as e:
            log.warning(f"Local LLM backend startup skipped: {e}")
        warm_context = memory_service.build_reconstruction_prompt()
        if warm_context:
            _local_runtime_warm_task = asyncio.create_task(background_warm_local_runtime(warm_context))
    else:
        log.info("Local AI startup skipped because DEPLOYMENT_MODE=%s", DEPLOYMENT_MODE)


@app.on_event("shutdown")
async def shutdown_local_llm():
    global _local_runtime_warm_task
    if _local_runtime_warm_task is not None:
        _local_runtime_warm_task.cancel()
        _local_runtime_warm_task = None
    if supports_local_ai():
        await run_in_threadpool(shutdown_local_backend)


async def background_warm_local_runtime(warm_context: str):
    if not supports_local_ai():
        return
    try:
        await run_in_threadpool(warm_local_context, warm_context)
        await ws_manager.broadcast(
            {
                "type": "local_runtime_status",
                "data": await run_in_threadpool(build_local_runtime_payload),
            }
        )
    except Exception as exc:
        log.warning("Background local runtime warmup skipped: %s", exc)


def load_qa_presets():
    with open(QA_PRESETS_PATH, "r", encoding="utf-8") as file:
        return json.load(file)


@app.get("/")
async def root():
    return {"status": "S-Socrates API is running clean and fast!"}


@app.post("/stt")
async def speech_to_text(file: UploadFile = File(...)):
    try:
        text = process_stt_request(
            file,
            model=GLOBAL_AUDIO_CONFIG["stt_model"],
            language=GLOBAL_AUDIO_CONFIG["stt_language"],
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
        return process_tts_request(
            req.text,
            voice,
            background_tasks,
            speaking_rate=speed,
        )
    except Exception as e:
        import traceback

        traceback.print_exc()
        return {"error": str(e)}


@app.get("/tts/voices")
async def list_vi_voices():
    voices = [{"Name": v, "Locale": "vi-VN"} for v in CHIRP3_HD_VOICES]
    return {"voices": voices}


@app.get("/configs")
async def get_configs():
    local_runtime = await run_in_threadpool(build_local_runtime_payload)
    retrieval_stats = await run_in_threadpool(retriever.stats)
    supported_modes = []
    if supports_local_ai():
        supported_modes.append({"code": "local", "label": "TurboQuant Local Model"})
    if supports_api_ai():
        supported_modes.append({"code": "gemini", "label": "Gemini API"})
    return {
        "config": GLOBAL_AUDIO_CONFIG,
        "deployment_mode": DEPLOYMENT_MODE,
        "robot_ws_connected": robot_ws_manager.is_connected(),
        "local_runtime": local_runtime,
        "local_llm": local_runtime,
        "retrieval": retrieval_stats,
        "supported_model_modes": supported_modes,
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


@app.get("/local-runtime/status")
async def get_local_runtime_status():
    return {"local_runtime": await run_in_threadpool(build_local_runtime_payload)}


@app.post("/configs")
async def update_configs(req: AudioConfigRequest):
    _apply_audio_config(req.model_dump())
    _activate_audio_config(source="post")
    save_operator_settings_to_disk()
    return {"status": "Config updated", "config": GLOBAL_AUDIO_CONFIG}


@app.post("/retrieval/rebuild")
async def rebuild_retrieval_index():
    await run_in_threadpool(retriever.initialize, True)
    stats = await run_in_threadpool(retriever.stats)
    return {"status": "Quantized retrieval index rebuilt", "retrieval": stats}


async def dispatch_robot_request(path: str, payload: dict | None = None):
    payload = payload or {}

    if path == "/mic":
        action = str(payload.get("action", "")).strip().lower()
        status_map = {
            "start": "listening",
            "stop": "processing",
            "cancel": "canceled",
        }
        status = status_map.get(action)
        if not status:
            raise ValueError("Invalid mic action for robot dispatch.")

        message = {
            "type": "mic_status",
            "status": status,
            "timestamp": time.time_ns(),
        }
    elif path == "/command":
        message = {
            "type": "command",
            "text": str(payload.get("text", "")).strip(),
            "emotion": str(payload.get("emotion", "neutral")).strip().lower(),
            "timestamp": time.time_ns(),
        }
    else:
        raise ValueError(f"Unsupported robot dispatch path: {path}")

    await robot_ws_manager.send_json(message)
    return {
        "status": "ok",
        "transport": "websocket",
        "message": message,
    }


@app.post("/robot/mic-control")
async def mic_control(req: MicControlRequest):
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
        return {"error": f"Failed to dispatch mic action over WebSocket: {e}"}

    await ws_manager.broadcast({"type": "mic_status", "status": _robot_mic_status})
    return {
        "status": f"Robot mic {req.action}",
        "mic_status": _robot_mic_status,
        "robot_response": robot_response,
    }


@app.get("/robot/mic-status")
async def get_mic_status():
    return {"mic_status": _robot_mic_status}


@app.post("/robot/mic-done")
async def mic_done():
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


@app.post("/robot/log")
async def receive_robot_log(req: LogRequest):
    await ws_manager.broadcast({"type": "log", "message": req.message})
    return {"status": "Log broadcasted"}


@app.websocket("/ws/operator")
async def websocket_operator(websocket: WebSocket):
    await ws_manager.connect(websocket)
    try:
        await websocket.send_json({"type": "mic_status", "status": _robot_mic_status})
        await websocket.send_json(
            {
                "type": "local_runtime_status",
                "data": await run_in_threadpool(build_local_runtime_payload),
            }
        )
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


@app.websocket("/ws/robot")
async def websocket_robot(websocket: WebSocket):
    global _robot_mic_status

    await robot_ws_manager.connect(websocket)
    await ws_manager.broadcast({"type": "robot_connection", "status": "connected"})
    try:
        await websocket.send_json(
            {
                "type": "mic_status",
                "status": _robot_mic_status,
                "timestamp": time.time_ns(),
            }
        )

        while True:
            payload = await websocket.receive_json()
            if not isinstance(payload, dict):
                continue

            robot_ws_manager.touch()
            msg_type = str(payload.get("type", "")).strip().lower()

            if msg_type == "manual_mic":
                action = str(payload.get("action", "")).strip().lower()
                if action == "start":
                    _robot_mic_status = "listening"
                elif action == "stop":
                    _robot_mic_status = "processing"
                elif action == "cancel":
                    _robot_mic_status = "canceled"
                await ws_manager.broadcast({"type": "mic_status", "status": _robot_mic_status})

            elif msg_type == "mic_done":
                _robot_mic_status = "idle"
                await ws_manager.broadcast({"type": "mic_status", "status": _robot_mic_status})

            elif msg_type == "mic_sync":
                status = str(payload.get("status", "")).strip().lower()
                if status:
                    _robot_mic_status = status
                    await ws_manager.broadcast({"type": "mic_status", "status": _robot_mic_status})

            elif msg_type == "log":
                message = str(payload.get("message", "")).strip()
                if message:
                    await ws_manager.broadcast({"type": "log", "message": message})

            elif msg_type == "ping":
                await websocket.send_json({"type": "pong", "timestamp": time.time_ns()})

    except WebSocketDisconnect:
        pass
    except Exception as exc:
        log.warning("Robot websocket closed with error: %s", exc)
    finally:
        robot_ws_manager.disconnect(websocket)
        await ws_manager.broadcast({"type": "robot_connection", "status": "disconnected"})


@app.post("/process-audio")
async def process_audio(file: UploadFile = File(...)):
    global _latest_transcript, _latest_robot_command
    try:
        presets = load_qa_presets()
        transcript = process_stt_request(
            file,
            model=GLOBAL_AUDIO_CONFIG["stt_model"],
            language=GLOBAL_AUDIO_CONFIG["stt_language"],
        )
        if transcript.strip() == "":
            _latest_transcript = {
                "transcript": "Không nhận được voice. Vui lòng nói lại.",
                "candidates": presets,
            }
            _latest_robot_command = {
                "text": "Không nhận được voice. Vui lòng nói lại.",
                "emotion": "no_voice",
                "timestamp": time.time_ns(),
            }
            await ws_manager.broadcast({"type": "transcript", "data": _latest_transcript})
            return _latest_transcript

        _latest_transcript = {
            "transcript": transcript,
            "candidates": presets,
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
        res = _latest_transcript
        _latest_transcript = None
        return res
    return None


@app.post("/operator-decision")
async def operator_decision(req: DecisionRequest):
    request_start = time.time()
    text = ""
    emotion = "neutral"

    try:
        await ws_manager.broadcast(
            {
                "type": "local_runtime_status",
                "data": await run_in_threadpool(build_local_runtime_payload),
            }
        )
        if req.mode == "preset":
            text = req.selected_answer or ""
            emotion = "speaking"
        elif req.mode == "ai":
            if not supports_local_ai():
                return {"error": "Local AI is disabled in this deployment mode."}
            text = await run_in_threadpool(
                process_chat_message,
                req.transcript or "",
                "local",
            )
            emotion = "speaking"
        elif req.mode == "gemini":
            if not supports_api_ai():
                return {"error": "API AI is disabled in this deployment mode."}
            text = await run_in_threadpool(
                process_chat_message,
                req.transcript or "",
                "gemini",
            )
            emotion = "speaking"
        else:
            return {"error": "Invalid mode"}
    except Exception as e:
        log.error("operator_decision failed for mode=%s: %s", req.mode, e)
        await ws_manager.broadcast(
            {
                "type": "local_runtime_status",
                "data": await run_in_threadpool(build_local_runtime_payload),
            }
        )
        return {"error": str(e)}

    total_ms = (time.time() - request_start) * 1000
    log.info(
        "operator_decision completed: mode=%s response_chars=%s latency_ms=%.0f",
        req.mode,
        len(text),
        total_ms,
    )
    await ws_manager.broadcast(
        {
            "type": "local_runtime_status",
            "data": await run_in_threadpool(build_local_runtime_payload),
        }
    )

    return {
        "text": text,
        "emotion": emotion,
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
        "timestamp": time.time_ns(),
    }
    try:
        robot_response = await dispatch_robot_request(
            "/command",
            {"text": text, "emotion": req.emotion},
        )
    except Exception as e:
        return {"error": f"Failed to dispatch command over WebSocket: {e}"}

    return {
        "status": "Command sent directly to robot",
        "command": _latest_robot_command,
        "robot_response": robot_response,
    }
