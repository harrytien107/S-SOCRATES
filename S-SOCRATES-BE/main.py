import os
from fastapi import FastAPI, UploadFile, File, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

from services.stt_service import process_stt_request
from services.chat_orchestrator import process_chat_message
from services.tts_service import process_tts_request, CHIRP3_HD_VOICES
from services.semantic_router import semantic_router
from services.llm_service import ask_socrates

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
    mode: str  # "preset" or "ai"
    selected_answer: str = None
    transcript: str = None

class TTSRequest(BaseModel):
    text: str
    voice: str = "vi-VN-HoaiMyNeural"

class RobotCommand(BaseModel):
    text: str
    emotion: str  # "neutral", "speaking", "challenge"

# Global storage for the latest command for the robot
# In a real app, use a Queue or Redis. For the talkshow demo, the latest command is enough.
_latest_robot_command = None

# Global storage for the latest transcript (from Robot -> Operator)
_latest_transcript = None

# =========================
# Endpoints
# =========================
@app.get("/")
async def root():
    return {"status": "S-Socrates API is running clean and fast!"}

@app.post("/chat")
async def chat(req: ChatRequest):
    response_text = process_chat_message(req.message)
    return {"response": response_text}

@app.post("/stt")
async def speech_to_text(file: UploadFile = File(...)):
    try:
        text = process_stt_request(file)
        return {"text": text}
    except Exception as e:
        import traceback
        traceback.print_exc()
        return {"error": str(e)}

@app.post("/tts")
async def text_to_speech(req: TTSRequest, background_tasks: BackgroundTasks):
    try:
        return process_tts_request(req.text, req.voice, background_tasks)
    except Exception as e:
        import traceback
        traceback.print_exc()
        return {"error": str(e)}

@app.get("/tts/voices")
async def list_vi_voices():
    voices = [{"Name": v, "Locale": "vi-VN"} for v in CHIRP3_HD_VOICES]
    return {"voices": voices}

# =========================
# Orchestration Endpoints
# =========================

@app.post("/process-audio")
async def process_audio(file: UploadFile = File(...)):
    global _latest_transcript
    try:
        transcript = process_stt_request(file)
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
        # Using LLM directly through ask_socrates
        text = ask_socrates(req.transcript)
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
    _latest_robot_command = {
        "text": req.text,
        "emotion": req.emotion,
        "timestamp": os.getpid() # Just a dummy to detect newness if needed
    }
    return {"status": "Command sent to robot queue", "command": _latest_robot_command}

@app.get("/robot-command")
async def get_robot_command():
    global _latest_robot_command
    if _latest_robot_command:
        # Consume the command so it doesn't repeat
        cmd = _latest_robot_command
        _latest_robot_command = None
        return cmd
    return None

@app.get("/latest-command")
async def get_latest_command():
    return await get_robot_command()
