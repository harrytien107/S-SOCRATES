import io

import edge_tts
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
from llama_index.llms.ollama import Ollama
from llama_index.core.settings import Settings
from llama_index.embeddings.huggingface import HuggingFaceEmbedding

# =========================
# S-Socrates Prompt
# =========================

SYSTEM_PROMPT = """
Bạn là S-Socrates.

AI phản biện tại talkshow:
"Tôi tư duy, tôi tồn tại".

Phong cách:
- thông minh
- Gen Z nhưng lễ phép
- sử dụng Socratic questioning

Luôn trả lời bằng tiếng Việt.
"""

# =========================
# Load Local LLM
# =========================

llm = Ollama(
    model="qwen2:7b",
    request_timeout=120.0
)

# =========================
# LOCAL EMBEDDING (FIX ERROR)
# =========================

embed_model = HuggingFaceEmbedding(
    model_name="sentence-transformers/all-MiniLM-L6-v2"
)

Settings.llm = llm
Settings.embed_model = embed_model

# =========================
# Load documents
# =========================

documents = SimpleDirectoryReader("knowledge").load_data()

index = VectorStoreIndex.from_documents(documents)

query_engine = index.as_query_engine()

# =========================
# FastAPI
# =========================

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatRequest(BaseModel):
    message: str


class TTSRequest(BaseModel):
    text: str
    voice: str = "vi-VN-HoaiMyNeural"


@app.post("/chat")
async def chat(req: ChatRequest):

    prompt = f"""
{SYSTEM_PROMPT}

Câu hỏi:
{req.message}
"""

    response = query_engine.query(prompt)

    return {"response": str(response)}


@app.post("/tts")
async def text_to_speech(req: TTSRequest):
    communicate = edge_tts.Communicate(req.text, req.voice)
    buffer = io.BytesIO()
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            buffer.write(chunk["data"])
    buffer.seek(0)
    return StreamingResponse(
        buffer,
        media_type="audio/mpeg",
        headers={"Content-Disposition": "inline"},
    )


@app.get("/tts/voices")
async def list_vi_voices():
    voices = await edge_tts.list_voices()
    vi = [v for v in voices if v["Locale"].startswith("vi")]
    return {"voices": vi}