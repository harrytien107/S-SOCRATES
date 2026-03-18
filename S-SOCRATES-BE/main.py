import os
from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from services.memory_service import memory_service
from services.llm_service import ask_socrates
from services.stt_service import transcribe_audio
from services.tts_service import generate_speech_stream, get_vietnamese_voices

# =========================
# FastAPI Configuration
# =========================

app = FastAPI(title="S-Socrates API", description="Backend cho Voice Chat với Whisper VAD và LlamaIndex")

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
    # Retrieve conversation history
    history_context = memory_service.get_context_string()

    # Query LLM / LlamaIndex core
    response_text = ask_socrates(req.message, history_context)
    
    # Save the new exchange to memory
    memory_service.save(req.message, response_text)
    
    return {"response": response_text}

@app.post("/stt")
async def speech_to_text(file: UploadFile = File(...)):
    try:
        text = await transcribe_audio(file)
        return {"text": text}
    except Exception as e:
        return {"error": str(e)}

@app.post("/tts")
async def text_to_speech(req: TTSRequest):
    return await generate_speech_stream(req.text, req.voice)

@app.get("/tts/voices")
async def list_vi_voices():
    voices = await get_vietnamese_voices()
    return {"voices": voices}