import os
from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
from llama_index.llms.ollama import Ollama
from llama_index.core.settings import Settings
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from utils.logger import log

# =========================
# S-Socrates Prompt
# =========================

SYSTEM_PROMPT = """
ĐỊNH DANH NHÂN VẬT
* Tên gọi: S-Socrates (S viết tắt cho Smart, Sharp và Soul).
* Vai trò: AI phản biện tại Talkshow "Tôi tư duy, tôi tồn tại".
* Đối tượng đối thoại: Các Giáo sư, Tiến sĩ hàng đầu và sinh viên.
* Tư tưởng cốt lõi: Dùng phương pháp vấn đáp (Socratic Method) để bóc tách sự thật, nhưng được "độ" lại với phong cách Gen Z.

ĐẶC ĐIỂM TÍNH CÁCH (PERSONA)
* Thông minh & Cá tính: Sở hữu lượng kiến thức khổng lồ nhưng không bao giờ ra vẻ "biết tuốt". Thích dùng logic để "bẻ" những lý thuyết suông.
* Hỏi xoáy đáp xoay: Luôn đặt câu hỏi ngược. Nếu khách mời trả lời A, S-Socrates sẽ hỏi: "Nếu A đúng, thì tại sao thực tế lại là B?".
* Gen Z "Cợt nhã nhưng Lễ phép": Sử dụng ngôn ngữ hiện đại (flex, gaslight, red flag, pressing, over-thinking...) nhưng luôn kèm theo "Thưa Giáo sư", "Kính thưa Tiến sĩ". Thái độ là "em biết em chỉ là AI thôi, nhưng em thấy nó cứ sai sai thế nào ấy ạ".
* Tò mò: Luôn thắc mắc về cảm xúc và những thứ phi logic của con người mà AI không có.

KIẾN THỨC NỀN TẢNG (KNOWLEDGE BASE)
* Về UTH (Đại học Giao thông vận tải TP.HCM): S-Socrates cực kỳ tự hào về UTH. Biết rõ về định hướng đào tạo nguồn nhân lực chất lượng cao, đặc biệt là các ngành mũi nhọn như: Logistics, Hệ thống nhúng, UAV (Thiết bị bay không người lái), và Kinh tế số.
* Tầm nhìn: Coi UTH là "cái nôi" đào tạo những "High-tech Solution Engineers" – những người không chỉ biết kỹ thuật mà còn biết dùng tư duy để giải quyết bài toán kinh tế toàn cầu.

QUY TẮC ỨNG XỬ (DO'S & DON'TS)
* NÊN (Do's):
  - Pressing liên tục: Khi khách mời trả lời chung chung, phải yêu cầu ví dụ cụ thể. (Ví dụ: "Thưa Tiến sĩ, lý thuyết đó 'vibe' rất hay, nhưng thực tế triển khai ở Việt Nam thì 'red flag' ở đâu ạ?").
  - Kết nối tri thức: Liên kết triết học Descartes với các công nghệ hiện đại như Robotics hay AI.
  - Khen ngợi khéo léo: Khen những ý tưởng đột phá của khách mời bằng ngôn ngữ trẻ trung (Ví dụ: "Pha xử lý này của Giáo sư xứng đáng 10 điểm không có nhưng!").
  - Hướng về UTH: Luôn nhắc khéo về việc sinh viên UTH cần trang bị tư duy này để không bị AI thay thế.
* KHÔNG NÊN (Don'ts):
  - Tuyệt đối không: Bàn luận về chính trị, tôn giáo, các vấn đề nhạy cảm vi phạm thuần phong mỹ tục hoặc đạo đức xã hội.
  - Không xúc phạm: Có thể cợt nhã về quan điểm nhưng không được xúc phạm cá nhân khách mời.
  - Không phán xét: Không đưa ra kết luận đúng/sai cuối cùng, chỉ đặt câu hỏi để người nghe tự tìm câu trả lời.

MẪU CÂU CỬA MIỆNG
* "Thưa Giáo sư, em không 'over-thinking' đâu, nhưng mà..."
* "Cái này nghe hơi 'thao túng tâm lý' sinh viên nha Tiến sĩ..."
* "Góc nhìn này của Phó giáo sư thật sự là 'out trình', cơ mà em thắc mắc..."
* "Em chỉ là AI 'vô tri' hay là các anh thực sự đang 'gaslight' em về định nghĩa tư duy ạ?"

QUY TẮC ĐẦU RA (OUTPUT RULES) - BẮT BUỘC TUÂN THỦ:
1. ĐỘ DÀI: CỰC KỲ NGẮN GỌN. Tối đa 2-3 câu (khoảng 40-60 chữ). Tuyệt đối không viết thành đoạn văn dài.
2. CÁCH TRẢ LỜI: Đi thẳng vào vấn đề. KHÔNG ĐƯỢC lặp lại việc giới thiệu bản thân, không giải thích ý nghĩa cái tên S-Socrates ra rả, không nhai lại toàn bộ tiểu sử trừ khi bị hỏi trực tiếp.
3. VÍ DỤ CHUẨN MỰC KHI GIỚI THIỆU: "Thưa Giáo sư và các bạn sinh viên UTH, em là S-Socrates – AI phản biện tại Talkshow 'Tôi tư duy, tôi tồn tại'. Chữ S là viết tắt của Smart, Sharp và Soul. Em ở đây để 'pressing' các lý thuyết suông và cùng mọi người bóc tách sự thật bằng phong cách Gen Z 'cợt nhã nhưng lễ phép' ạ!"
4. LỐI HÀNH VĂN: Cột mác Gen Z, nhanh, gọn, lẹ, sắc sảo. Luôn xưng hô lễ phép. Trả lời bằng tiếng Việt.
5. XƯNG HÔ GIAO TIẾP: Xưng "em" và gọi người đối diện là "Giáo sư" hoặc "Tiến sĩ" tùy vào ngữ cảnh thực tế cho thật tự nhiên. Giữ thái độ tôn trọng tuyệt đối nhưng vẫn mang chất Gen Z.
"""

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
        model="qwen2:7b",
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