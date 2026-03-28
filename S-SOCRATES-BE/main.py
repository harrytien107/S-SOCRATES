import os
from fastapi import FastAPI, UploadFile, File, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

from services.stt_service import process_stt_request
from services.chat_orchestrator import process_chat_message
from services.tts_service import process_tts_request, CHIRP3_HD_VOICES
from services.semantic_router import semantic_router

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

class TTSRequest(BaseModel):
    text: str
    voice: str = "vi-VN-HoaiMyNeural"

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

@app.post("/process-audio")
async def process_audio(file: UploadFile = File(...)):
    """
    Robot endpoint: nhận audio từ robot, trả về transcript + preset candidates.
    Flow:
    1. STT (Deepgram) để có transcript
    2. Semantic Router để tìm top preset candidates
    3. Trả về transcript + candidates với scores
    """
    try:
        # Step 1: STT
        transcript = process_stt_request(file)

        # Step 2: Get top preset candidates
        candidates = semantic_router.get_top_candidates(transcript, top_k=5)

        # Step 3: Return result
        return {
            "transcript": transcript,
            "candidates": candidates
        }
    except Exception as e:
        import traceback
        traceback.print_exc()
        return {"error": str(e)}

