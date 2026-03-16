from llama_index.llms.ollama import Ollama
from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
from llama_index.core.settings import Settings
from llama_index.embeddings.huggingface import HuggingFaceEmbedding

from services.memory_service import history, save_memory


SYSTEM_PROMPT = """
Bạn là S-Socrates.
Luôn trả lời ngắn gọn và đặt câu hỏi phản biện.
"""

llm = Ollama(model="qwen2:7b")

embed_model = HuggingFaceEmbedding(
    model_name="sentence-transformers/all-MiniLM-L6-v2"
)

Settings.llm = llm
Settings.embed_model = embed_model

documents = SimpleDirectoryReader("knowledge").load_data()

index = VectorStoreIndex.from_documents(documents)

query_engine = index.as_query_engine()


def ask_llm(message):

    prompt = f"""
{SYSTEM_PROMPT}

Conversation history:
{history}

User:
{message}
"""

    response = query_engine.query(prompt)

    save_memory(message, str(response))

    return str(response)