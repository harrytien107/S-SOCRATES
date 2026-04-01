import time
import json
import base64
from fastapi import FastAPI, UploadFile, File, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
import os
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
from dotenv import load_dotenv
load_dotenv()  # Phải load TRƯỚC khi import services (vì llm_service đọc env lúc khởi tạo)

from services.stt_service import process_stt_request
from services.chat_orchestrator import process_chat_message
from services.tts_service import process_tts_request, CHIRP3_HD_VOICES
from services.semantic_router import semantic_router
from services.llm_service import ask_socrates, switch_gemini_model, AVAILABLE_GEMINI_MODELS
from services.memory_service import memory_service
from services.streaming_stt_service import StreamingSTTSession
from services.streaming_tts_service import synthesize_sentence, split_into_sentences
from services.llm_streaming_service import stream_gemini_sentences

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
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception:
                pass

ws_manager = ConnectionManager()       # Operator Web UI
robot_ws_manager = ConnectionManager()  # Robot Flutter App

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
    gemini_model: str = "models/gemini-2.5-flash"

# =========================
# Global Runtime State
# =========================
_latest_robot_command = None
_latest_transcript = None

# Tích lũy transcript từ STT streaming (Deepgram real-time)
_full_transcript: list[dict] = []  # [{"text": "...", "speaker": 0}, ...]
_streaming_active = False  # Đang stream STT hay không

# Operator có thể chỉnh trực tiếp từ Web UI
GLOBAL_AUDIO_CONFIG = {
    "tts_voice": "Aoede",
    "tts_speed": 1.0,
    "stt_model": "nova-2",
    "stt_language": "vi",
    "gemini_model": "models/gemini-2.5-flash",
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
    elif req.action == "stop":
        _robot_mic_status = "processing"
    elif req.action == "cancel":
        _robot_mic_status = "canceled"
    else:
        return {"error": "Invalid action. Use 'start', 'stop', or 'cancel'."}
        
    # Phát qua WebSocket để Operator UI + Robot đều cập nhật ngay lập tức
    mic_msg = {"type": "mic_status", "status": _robot_mic_status}
    await ws_manager.broadcast(mic_msg)
    await robot_ws_manager.broadcast(mic_msg)
    return {"status": f"Robot mic {req.action}", "mic_status": _robot_mic_status}

@app.get("/robot/mic-status")
async def get_mic_status():
    """App điện thoại poll mỗi 1 giây để biết Đạo diễn muốn nó làm gì."""
    return {"mic_status": _robot_mic_status}

@app.post("/robot/mic-done")
async def mic_done():
    """App gọi sau khi đã upload xong audio, báo hiệu hoàn tất chu kỳ."""
    global _robot_mic_status
    _robot_mic_status = "idle"
    idle_msg = {"type": "mic_status", "status": _robot_mic_status}
    await ws_manager.broadcast(idle_msg)
    await robot_ws_manager.broadcast(idle_msg)
    return {"status": "Mic cycle complete", "mic_status": _robot_mic_status}

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
        # Gửi ngay trạng thái hiện tại khi mới kết nối
        await websocket.send_json({"type": "mic_status", "status": _robot_mic_status})
        if _latest_transcript:
            await websocket.send_json({"type": "transcript", "data": _latest_transcript})
            
        while True:
            # Chờ nhận lệnh nếu UI muốn gửi qua WS, tạm thời chỉ listen để giữ connection
            data = await websocket.receive_text()
    except WebSocketDisconnect:
        ws_manager.disconnect(websocket)


# =========================
# WebSocket — Robot Flutter App
# =========================
@app.websocket("/ws/robot")
async def websocket_robot(websocket: WebSocket):
    await robot_ws_manager.connect(websocket)
    global _robot_mic_status
    print("🤖 Robot WebSocket connected!")
    try:
        # Đồng bộ ngay trạng thái hiện tại khi Robot vừa kết nối
        await websocket.send_json({"type": "mic_status", "status": _robot_mic_status})
        if _latest_robot_command:
            await websocket.send_json({"type": "command", **_latest_robot_command})

        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type", "")

            if msg_type == "mic_done":
                # Robot báo đã upload xong audio
                _robot_mic_status = "idle"
                idle_msg = {"type": "mic_status", "status": "idle"}
                await ws_manager.broadcast(idle_msg)
                await robot_ws_manager.broadcast(idle_msg)

            elif msg_type == "manual_mic":
                # Robot báo người dùng chạm Orb thủ công bật/tắt mic
                action = data.get("action", "")
                if action == "start":
                    _robot_mic_status = "listening"
                elif action == "stop":
                    _robot_mic_status = "processing"
                mic_msg = {"type": "mic_status", "status": _robot_mic_status}
                await ws_manager.broadcast(mic_msg)

            elif msg_type == "log":
                # Robot gửi log — chuyển tiếp cho Operator UI
                log_msg = {"type": "log", "message": data.get("message", "")}
                await ws_manager.broadcast(log_msg)

    except WebSocketDisconnect:
        robot_ws_manager.disconnect(websocket)
        print("🤖 Robot WebSocket disconnected.")

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
        await ws_manager.broadcast({"type": "transcript", "data": _latest_transcript})
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

    # Lấy lịch sử hội thoại để AI nhớ ngữ cảnh
    history_context = memory_service.get_context_string()

    if req.mode == "preset":
        text = req.selected_answer
        emotion = "speaking"
    elif req.mode == "ai":
        # Using Ollama (Local LLM) through ask_socrates
        text = ask_socrates(req.transcript, history_context, model_choice="ollama")
        emotion = "challenge"
    elif req.mode == "gemini":
        # Using Gemini (Cloud LLM) through ask_socrates
        text = ask_socrates(req.transcript, history_context, model_choice="gemini")
        emotion = "challenge"
    else:
        return {"error": "Invalid mode"}

    # Lưu lại cuộc hội thoại vào memory
    memory_service.save(req.transcript, text)

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
    # Đẩy lệnh trực tiếp xuống Robot qua WebSocket — 0ms delay
    await robot_ws_manager.broadcast({"type": "command", **_latest_robot_command})
    return {"status": "Command sent to robot queue", "command": _latest_robot_command}

@app.get("/robot-command")
async def get_robot_command():
    # Frontend deduplicates via timestamp, do not destroy the command.
    return _latest_robot_command


# =========================
# WebSocket — Deepgram STT Streaming
# =========================
@app.websocket("/ws/audio-stream")
async def ws_audio_stream(websocket: WebSocket):
    """Nhận audio chunks từ Browser Operator → forward tới Deepgram → trả text real-time."""
    global _full_transcript, _streaming_active, _latest_transcript
    await websocket.accept()
    print("🎙️ Audio streaming session started!")

    _full_transcript = []
    _streaming_active = True

    async def on_interim(text):
        """Deepgram đang phân tích — text tạm."""
        await ws_manager.broadcast({"type": "stt_interim", "text": text})

    async def on_final(text, speaker):
        """Deepgram chốt 1 câu — lưu và broadcast."""
        global _latest_transcript
        _full_transcript.append({"text": text, "speaker": speaker})

        # Broadcast transcript final cho Operator UI
        await ws_manager.broadcast({
            "type": "stt_final",
            "text": text,
            "speaker": speaker,
            "total_sentences": len(_full_transcript)
        })

        # Chạy semantic router để gợi ý câu trả lời
        try:
            candidates = semantic_router.get_top_matches(text)
            _latest_transcript = {"transcript": text, "candidates": candidates}
            await ws_manager.broadcast({"type": "transcript", "data": _latest_transcript})
        except Exception as e:
            print(f"Semantic router error: {e}")

    async def on_error(err):
        await ws_manager.broadcast({"type": "stt_error", "error": err})

    session = StreamingSTTSession(
        on_interim=on_interim,
        on_final=on_final,
        on_error=on_error,
        model=GLOBAL_AUDIO_CONFIG["stt_model"],
        language=GLOBAL_AUDIO_CONFIG["stt_language"],
    )

    try:
        await session.start()

        while True:
            data = await websocket.receive()
            if "bytes" in data:
                await session.send_audio(data["bytes"])
            elif "text" in data:
                msg = json.loads(data["text"])
                if msg.get("action") == "stop":
                    break

    except WebSocketDisconnect:
        print("🎙️ Audio streaming disconnected.")
    except Exception as e:
        print(f"🎙️ Audio streaming error: {e}")
    finally:
        await session.stop()
        _streaming_active = False
        print(f"🎙️ Streaming ended. Total sentences: {len(_full_transcript)}")


@app.get("/streaming/transcript")
async def get_full_streaming_transcript():
    """Lấy toàn bộ transcript tích lũy từ streaming session."""
    full_text = " ".join(entry["text"] for entry in _full_transcript)
    return {
        "full_text": full_text,
        "sentences": _full_transcript,
        "total": len(_full_transcript),
        "active": _streaming_active,
    }


# =========================
# Streaming TTS — Sentence Chunking
# =========================

class StreamDecisionRequest(BaseModel):
    transcript: str
    mode: str = "gemini"  # "gemini" hoặc "ollama"

@app.post("/operator-decision/stream")
async def operator_decision_stream(req: StreamDecisionRequest):
    """
    AI Trực Tiếp: Gemini stream → cắt câu → TTS từng câu → push audio chunks xuống Robot.
    Robot nói câu đầu tiên chỉ trong ~1 giây.
    """
    global _latest_robot_command
    history_context = memory_service.get_context_string()

    from services.llm_service import SYSTEM_PROMPT
    prompt = f"""{SYSTEM_PROMPT}

{history_context}
Câu hỏi hiện tại:
{req.transcript}
"""

    full_response = ""
    chunk_index = 0
    model_name = GLOBAL_AUDIO_CONFIG["gemini_model"]

    try:
        async for sentence in stream_gemini_sentences(prompt, model_name):
            full_response += sentence + " "

            # Dịch câu này sang audio ngay lập tức
            audio_bytes = await synthesize_sentence(
                sentence,
                voice=GLOBAL_AUDIO_CONFIG["tts_voice"],
                speed=GLOBAL_AUDIO_CONFIG["tts_speed"],
            )

            # Đẩy audio chunk xuống Robot qua WebSocket
            await robot_ws_manager.broadcast({
                "type": "tts_chunk",
                "audio": base64.b64encode(audio_bytes).decode(),
                "text": sentence,
                "emotion": "challenge",
                "index": chunk_index,
            })

            # Cập nhật Operator UI
            await ws_manager.broadcast({
                "type": "stream_progress",
                "text": sentence,
                "index": chunk_index,
            })

            chunk_index += 1

        # Kết thúc streaming
        await robot_ws_manager.broadcast({"type": "tts_done"})

        full_text = full_response.strip()

        # Lưu memory
        memory_service.save(req.transcript, full_text)

        # Cập nhật latest command
        _latest_robot_command = {
            "text": full_text,
            "emotion": "challenge",
            "timestamp": time.time_ns()
        }

        return {"text": full_text, "emotion": "challenge", "chunks": chunk_index}

    except Exception as e:
        await robot_ws_manager.broadcast({"type": "tts_done"})
        return {"error": str(e)}


@app.post("/operator-decision/stream-tts")
async def operator_decision_stream_tts(req: RobotCommand):
    """
    AI Duyệt Trước: Operator đã duyệt text → cắt câu → TTS từng câu → push xuống Robot.
    Dùng khi Operator muốn kiểm tra nội dung trước khi cho Robot nói.
    """
    global _latest_robot_command
    text = (req.text or "").strip()
    if not text:
        return {"error": "Text is required"}

    sentences = split_into_sentences(text)
    chunk_index = 0

    for sentence in sentences:
        audio_bytes = await synthesize_sentence(
            sentence,
            voice=GLOBAL_AUDIO_CONFIG["tts_voice"],
            speed=GLOBAL_AUDIO_CONFIG["tts_speed"],
        )

        await robot_ws_manager.broadcast({
            "type": "tts_chunk",
            "audio": base64.b64encode(audio_bytes).decode(),
            "text": sentence,
            "emotion": req.emotion,
            "index": chunk_index,
        })

        await ws_manager.broadcast({
            "type": "stream_progress",
            "text": sentence,
            "index": chunk_index,
        })

        chunk_index += 1

    await robot_ws_manager.broadcast({"type": "tts_done"})

    _latest_robot_command = {
        "text": text,
        "emotion": req.emotion,
        "timestamp": time.time_ns()
    }

    return {"text": text, "emotion": req.emotion, "chunks": chunk_index}
