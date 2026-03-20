from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
from llama_index.llms.ollama import Ollama
from llama_index.core.settings import Settings
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from huggingface_hub import snapshot_download

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
# Init Service Components
# =========================

def init_query_engine():
    # Load Local LLM
    llm = Ollama(
        model="qwen2:1.5b",
        request_timeout=120.0
    )

    # Local Embedding
    try:
        # Trích xuất thẳng đường dẫn thư mục bộ nhớ để chặn 100% truy vấn mạng
        model_path = snapshot_download("sentence-transformers/all-MiniLM-L6-v2", local_files_only=True)
        embed_model = HuggingFaceEmbedding(model_name=model_path)
    except Exception:
        print("Đang tải model Embedding lần đầu (Chỉ một lần duy nhất)...")
        model_path = snapshot_download("sentence-transformers/all-MiniLM-L6-v2", local_files_only=False)
        embed_model = HuggingFaceEmbedding(model_name=model_path)

    Settings.llm = llm
    Settings.embed_model = embed_model

    # Load documents from knowledge folder
    documents = SimpleDirectoryReader("knowledge").load_data()
    index = VectorStoreIndex.from_documents(documents)
    
    return index.as_query_engine()

# Global query engine instance
_query_engine = init_query_engine()

def ask_socrates(user_message: str, history_context: str = "") -> str:
    prompt = f"""{SYSTEM_PROMPT}

{history_context}
Câu hỏi hiện tại:
{user_message}
"""
    response = _query_engine.query(prompt)
    return str(response)