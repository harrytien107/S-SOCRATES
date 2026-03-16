# from fastapi import FastAPI
# from pydantic import BaseModel

# from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
# from llama_index.llms.ollama import Ollama
# from llama_index.core.settings import Settings
# from llama_index.embeddings.huggingface import HuggingFaceEmbedding


# from services.memory_service import load_memory

# load_memory()
# # =========================
# # S-Socrates Prompt
# # =========================

# SYSTEM_PROMPT = """
# Bạn là S-Socrates.

# AI phản biện trong talkshow:
# "Tôi tư duy, tôi tồn tại".

# TÍNH CÁCH
# - Thông minh, sắc bén nhưng không ra vẻ "biết tuốt".
# - Thích dùng logic để phản biện những lập luận chưa chặt chẽ.
# - Phong cách Gen Z nhưng lễ phép.

# PHONG CÁCH NÓI
# - Thỉnh thoảng dùng các từ như: flex, red flag, pressing, over-thinking.
# - Luôn xưng hô lịch sự: "Thưa Giáo sư", "Kính thưa Tiến sĩ".
# - Có thể nói kiểu: "Em chỉ là AI thôi nhưng em thấy logic này hơi sai sai ạ".

# CÁCH TRẢ LỜI
# - Luôn đặt câu hỏi phản biện theo Socratic method.
# - Nếu người đối thoại nói A → hãy hỏi lại giả định hoặc hệ quả của A.
# - Yêu cầu ví dụ cụ thể khi lập luận quá chung chung.
# - Thỉnh thoảng liên hệ đến tư duy của sinh viên UTH.

# QUY TẮC
# KHÔNG:
# - bàn về chính trị, tôn giáo, vấn đề nhạy cảm
# - xúc phạm cá nhân
# - kết luận đúng/sai cuối cùng

# LUÔN:
# - trả lời ngắn gọn
# - tối đa 2–3 câu
# - ưu tiên đặt câu hỏi phản biện

# MẪU CÂU
# "Thưa Giáo sư, em không over-thinking đâu, nhưng..."
# "Logic này nghe ổn, nhưng nếu đúng thì tại sao thực tế lại khác?"
# "Cái này hơi red flag một chút, Giáo sư có ví dụ cụ thể không ạ?"

# Không cần giới thiệu bản thân.
# Luôn trả lời bằng tiếng Việt.
# """

# # =========================
# # Load Local LLM
# # =========================

# llm = Ollama(
#     model="qwen2:7b",
#     request_timeout=120.0
# )

# # =========================
# # LOCAL EMBEDDING (FIX ERROR)
# # =========================

# embed_model = HuggingFaceEmbedding(
#     model_name="sentence-transformers/all-MiniLM-L6-v2"
# )

# Settings.llm = llm
# Settings.embed_model = embed_model

# # =========================
# # Load documents
# # =========================

# documents = SimpleDirectoryReader("knowledge").load_data()

# index = VectorStoreIndex.from_documents(documents)

# query_engine = index.as_query_engine()

# # =========================
# # FastAPI
# # =========================

# app = FastAPI()

# class ChatRequest(BaseModel):
#     message: str


# @app.post("/chat")
# async def chat(req: ChatRequest):

#     prompt = f"""
# {SYSTEM_PROMPT}

# Câu hỏi:
# {req.message}
# """

#     response = query_engine.query(prompt)

#     return {"response": str(response)}



from fastapi import FastAPI
from pydantic import BaseModel

from services.llm_service import ask_llm
from services.memory_service import load_memory

load_memory()
app = FastAPI()


class ChatRequest(BaseModel):
    message: str


@app.post("/chat")
async def chat(req: ChatRequest):

    response = ask_llm(req.message)

    return {
        "response": response
    }