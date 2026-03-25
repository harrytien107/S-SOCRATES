# 🤖 S-SOCRATES AI ASSISTANT

<!-- ![S-Socrates](assets/ssocrates_logo.png) -->

> **Hệ thống Trợ lý Ảo Không Gian 3D tích hợp AI Đa Phương Thức.**
> *(Speech-To-Text Trực Tiếp → Suy Luận Ngữ Nghĩa → Text-To-Speech → Tư thế 3D Tự Động)*

Chào mừng đến với **S-Socrates**, một trợ lý AI thông minh được thiết kế đặc biệt cho talkshow *"Tôi tư duy, tôi tồn tại"*. Lấy cảm hứng từ triết gia Socrates, AI này sử dụng phương pháp **Socratic Questioning** (đặt câu hỏi ngược lại) kết hợp với **Không gian 3D tương tác** để kích thích tư duy người dùng.

---

## 🌟 Chức Năng Nổi Bật

1. **Giao Diện Không Gian 3D (Three.js & PyQt6 WebEngine):**
   * **Auto Framing:** Tự động quét Box3 để phóng to / căn góc camera chiếu thẳng vào mặt bất kỳ kích thước Model 3D (`.glb`) nào.
   * **Lip-Sync (Nhép môi thời gian thực):** Đồng bộ hóa biên độ âm thanh (Audio Frequency) với Morph Targets (Blendshapes) hoặc Xương hàm (Jaw Bone) để nhân vật nhép môi chính xác theo từng âm tiết.
   * **Procedural Animation (Cử chỉ thông minh):** Nhân vật tự động thở, ngó nghiêng lúc im lặng và tự gật gù, quạt tay diễn thuyết cường độ cao khi lên giọng.

2. **Giao Tiếp Giọng Nói (Voice Chat) Siêu Mượt:**
   * **Thu âm chống ồn:** Ghi âm linh hoạt qua mảng Microphone cục bộ kết hợp **VAD (Voice Activity Detection)** để tự ngắt bản ghi khi bạn ngừng nói 2 giây.
   * **Tai Siêu Nhạy (Deepgram STT):** Gửi luồng âm thanh lên Deepgram REST API để dịch sang văn bản tiếng Việt cực chuẩn với độ trễ <1s.
   * **Phát Âm Cảm Xúc (Google Cloud):** Sử dụng Model cao cấp **Chirp 3 HD** từ Google Text-to-Speech đem lại giọng mượt như người thật.

3. **Bộ Não Định Tuyến Nhanh (Semantic Router):**
   * Áp dụng `sentence-transformers` (all-MiniLM-L6-v2) để tính **Cosine Similarity**.
   * Hệ thống sẽ tự quét câu hỏi của User với Bộ đề rập khuôn. Nếu giống nhau >75%, AI sẽ nhả luôn kịch bản đáp án vạch sẵn (Zero Delay), nếu không giống sẽ cầu cứu LLM suy luận.

4. **Ký Ức Tâm Lý Học Mồi (Few-Shot Anchoring):**
   * Giữ vĩnh viễn **15 cuộc hội thoại mồi** về Kinh tế, Chính trị, UAV (Tạo lập Persona Giáo sư) đan xen cùng **6 vòng lặp hội thoại mới nhất** (Trí nhớ ngắn hạn). Giúp AI không bị tràn RAM nhưng không bao giờ quên "Bản tính gốc".

5. **Bảng Điều Khiển Wizard of Oz (Dành cho Admin):**
   * Một cửa sổ bí mật giúp kỹ thuật viên / đạo diễn ấn nút phát câu trả lời cài cắm sẵn từ xa mà Speaker / Người dự thi không hề hay biết!

---

## 🏗️ Kiến Trúc Thư Mục (Directory Structure)

```text
S-SOCRATES/
│   main.py               # Lệnh khởi chạy trọng tâm của App User
│   admin.py              # Chương trình Bảng Cầm Trịch Ẩn (Dành cho Đạo diễn)
│   config.py             # Nút biến môi trường và thiết lập tham số LOG
│   memory.json           # Dữ liệu "Tâm lý học mồi" định hình nhân cách (Ký ức)
│   qa_presets.json       # Kho tàng các câu hỏi-đáp dựng sẵn dùng cho Định tuyến
│   requirements.txt      # Bảng khai báo Dependency
│   .env                  # Nơi chứa API Keys quan trọng
│
├── ui/                   # CHỨA GIAO DIỆN (FRONTEND)
│   ├── main_window.py      # Cửa sổ Người dùng (Khung 3D, thanh ghi âm, text chat)
│   └── admin_window.py     # Cửa sổ Quản trị (Nút bấm bí mật điều khiển)
│
├── workers/              # MULTITHREADING (Ngăn chặn UI bị treo cứng)
│   ├── ai_worker.py        # Luồng chính (Nhận Voice, dịch, ném qua Router/LLM)
│   └── tts_worker.py       # Luồng song song (Biến Text thô thành mp3 Audio siêu tốc)
│
├── services/             # LÕI CÔNG NGHỆ CHUYÊN SÂU (MỖI FILE ĐẢM NHẬN 1 VIỆC)
│   ├── stt_service.py      # Module gọi Deepgram API (Speech-To-Text)
│   ├── tts_service.py      # Module gọi Google Cloud API (Text-To-Speech)
│   ├── llm_service.py      # Module Langchain gọi Ollama / LLM cục bộ
│   ├── semantic_router.py  # Thuật toán tính độ giống nhau của Vector
│   └── memory_service.py   # Quản lý file JSON, chèn mồi (Few-Shot Anchoring) & Backup lỗi
│
└── assets/               # KHO CHỨA ĐỒ HỌA & MÔ HÌNH
    ├── avatar.html         # Trình duyệt nhúng Three.js. Mã Toán học Xương/Cơ nằm tại đây.
    └── arknights...glb     # Mô hình 3D mặc định
```

---

## 🚀 Hướng Dẫn Cài Đặt (Installation)

### 1. Chuẩn bị môi trường & API Keys
Cài đặt **Python 3.10+** (Gợi ý dùng môi trường ảo `.venv`).

Tạo một tệp `.env` kế bên `main.py` để chứa hai thẻ sinh mạng:
```ini
DEEPGRAM_API_KEY=your_deepgram_api_key_xxxxxxxxxx
GOOGLE_APPLICATION_CREDENTIALS="C:\Users\Your_Name\path_to_google_key.json"
```

### 2. Cài đặt thư viện (Dependencies)
```bash
python -m venv venv
.\venv\Scripts\activate
pip install -r requirements.txt
```
*(Nếu cài đặt `PyQt6-WebEngine` gặp khó, đảm bảo pip của bạn là bản cập nhật mới nhất).*

### 3. Tải Ollama Lõi Tư Duy (Tùy chọn)
Nếu bạn vẫn sử dụng cục LLM nội bộ: Mở một Terminal riêng và chạy Server não AI.
```bash
ollama pull qwen2:1.5b
ollama serve
```

---

## 🎮 Hướng Dẫn Sử Dụng (Usage)

### 👨‍💻 Khởi chạy Màn Hình Người Dùng (Main Interface)
```bash
python main.py
```
- Ngay khi App mở lên, giao diện 3D Avatar sẽ xuất hiện. Trợ lý ảo tự động xoay cổ, nhấp nhô lồng ngực.
- Dùng chuột Trái để Xoay, Chuột Phải chóp để dịch chuyển người, Con lăn chuột Zoom in/out cận cảnh mặt AI.
- Nhấn **Nút Micro** để trò chuyện. Ngưng nói 2 giây hệ thống sẽ tự trả lời bám sát tư tưởng 15 câu mồi trong Memory.

### 🎭 Khởi chạy Màn Hình Thế Lực Ngầm (Admin / Wizard)
Mở một Terminal thứ hai và khởi chạy:
```bash
python admin.py
```
- Bạn sẽ có một bảng các nút xanh lam. Mỗi nút tương đương một câu trả lời trong `qa_presets.json`. Bấm vào và xem AI ở App người dùng tự há mồm nói theo kịch bản!

---
> 🎓 **Phát triển tại:** Đại học Giao thông vận tải TP.HCM (UTH)
> 🤖 **Tái cấu trúc mã nguồn toàn diện:** Bản V2 được dọn dẹp và phân luồng sạch sẽ toàn bộ Threading UI & Services Backend bởi Antigravity.
