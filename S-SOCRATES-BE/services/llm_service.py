import os
from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
from llama_index.llms.ollama import Ollama
from llama_index.core.settings import Settings
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from utils.logger import log

# =========================
# S-Socrates Prompt
# =========================

import os

_prompt_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "knowledge", "uth.txt")
try:
    with open(_prompt_path, "r", encoding="utf-8") as _f:
        SYSTEM_PROMPT = _f.read().strip()
except Exception as e:
    print(f"⚠️ Không thể tải cấu hình system prompt từ {_prompt_path}: {e}")
    SYSTEM_PROMPT = "Bạn là S-SOCRATES, một AI phản biện."

# =========================
# Init Service Components
# =========================

# Shared embedding model (dùng chung cho cả 2 engine)
_embed_model = HuggingFaceEmbedding(
    model_name="sentence-transformers/all-MiniLM-L6-v2"
)

# Shared vector index (cả Ollama và Gemini đều đọc chung kho tri thức)
Settings.embed_model = _embed_model
_documents = SimpleDirectoryReader("knowledge").load_data()
_index = VectorStoreIndex.from_documents(_documents)


# --- Engine 1: Ollama (Local) ---
def _init_ollama_engine():
    llm = Ollama(
        model="qwen2:1.5b",
        request_timeout=120.0
    )
    return _index.as_query_engine(llm=llm)

_ollama_engine = _init_ollama_engine()
log.info("✅ Ollama Query Engine (Qwen2:7b) initialized.")


# --- Engine 2: Gemini (Cloud) - Dynamic Model ---
_gemini_engine = None
_current_gemini_model = None

AVAILABLE_GEMINI_MODELS = [
    "models/gemini-2.0-flash",
    "models/gemini-2.0-flash-lite",
    "models/gemini-1.5-flash",
    "models/gemini-1.5-pro",
]

def _init_gemini_engine(model_name: str = "models/gemini-2.0-flash"):
    global _gemini_engine, _current_gemini_model
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        log.warning("⚠️ GEMINI_API_KEY not found in .env. Gemini engine disabled.")
        return

    try:
        from llama_index.llms.gemini import Gemini
        llm = Gemini(
            model=model_name,
            api_key=api_key,
        )
        _gemini_engine = _index.as_query_engine(llm=llm)
        _current_gemini_model = model_name
        log.info(f"✅ Gemini Query Engine ({model_name}) initialized.")
    except Exception as e:
        log.error(f"❌ Failed to initialize Gemini engine: {e}")
        _gemini_engine = None

_init_gemini_engine()


def switch_gemini_model(model_name: str):
    """Hot-swap Gemini model tại runtime. Gọi từ API /configs."""
    global _current_gemini_model
    if model_name == _current_gemini_model:
        return  # Không cần khởi tạo lại nếu cùng model
    log.info(f"🔄 Switching Gemini model: {_current_gemini_model} → {model_name}")
    _init_gemini_engine(model_name)


# =========================
# Public API
# =========================

def ask_socrates(user_message: str, history_context: str = "", model_choice: str = "ollama") -> str:
    """
    Hỏi S-Socrates. 
    model_choice: "ollama" (default, local) hoặc "gemini" (cloud).
    Cả hai đều đọc chung kho tri thức knowledge/.
    """
    prompt = f"""{SYSTEM_PROMPT}

{history_context}
Câu hỏi hiện tại:
{user_message}
"""
    
    if model_choice == "gemini":
        if _gemini_engine is None:
            log.error("Gemini engine is not available. Falling back to Ollama.")
            response = _ollama_engine.query(prompt)
        else:
            log.info(f"🧠 Routing to Gemini (Cloud) [{_current_gemini_model}]...")
            response = _gemini_engine.query(prompt)
    else:
        log.info("🧠 Routing to Ollama (Local)...")
        response = _ollama_engine.query(prompt)
    
    return str(response)