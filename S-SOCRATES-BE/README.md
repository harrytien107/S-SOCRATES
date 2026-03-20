# S-SOCRATES Backend (Python)

Đây là thành phần Cốt lõi của hệ thống S-Socrates. Nó tiếp nhận các yêu cầu từ Flutter App, sử dụng AI (Whisper, Ollama Qwen2:1.5b, Edge-TTS) để nhận diện, suy luận, phản biện và trả về âm thanh.

## 🏗️ Cấu trúc dự án (Clean Architecture)

```text
S-SOCRATES-BE/
│
├── main.py                    # Router chính kết nối API (FastAPI)
├── requirements.txt           # Danh sách thư viện Python
├── memory.json                # Lưu trữ bối cảnh trò chuyện (Auto-generated)
│
├── knowledge/                 # Thư mục chứa tài liệu Text dùng cho RAG 
│   └── uth.txt                # Thông tin ĐH Giao thông vận tải
│
├── voice/                     # Thư mục lưu audio người dùng (Auto-generated)
│
└── services/                  # Business Logic Layer
    ├── llm_service.py         # Liên kết Ollama LlamaIndex để suy nghĩ
    ├── memory_service.py      # Lưu và chèn lịch sử 5 lệnh gần nhất vào AI
    ├── stt_service.py         # Faster-Whisper: Chuyển giọng nói tiếng Việt thành Text
    └── tts_service.py         # Edge-TTS: Chuyển văn bản thành âm thanh MP3
```

## 🛠️ Hướng dẫn cài đặt Backend

1. **Khởi động Ollama (Bắt buộc chạy trước)**
   ```powershell
   ollama pull qwen2:1.5b
   ollama serve
   ```

2. **Cài đặt thư viện Python**
   Mở terminal trong thư mục `S-SOCRATES-BE` và chạy:
   ```powershell
   python -m venv .venv
   .\.venv\Scripts\activate
   pip install -r requirements.txt
   ```

3. **Chạy Server**
   ```powershell
   uvicorn main:app --reload --port 8000
   ```
   Server sẽ mở ở cổng 8000. Bạn có thể xem tài liệu API tại: `http://localhost:8000/docs`

## 📡 Các API chính

- `POST /chat`: Gửi câu hỏi văn bản lên, nhận câu trả lời AI (tích hợp nhớ bối cảnh `memory.json`).
- `POST /stt`: Nhận file âm thanh `.m4a` (thông qua form upload), dùng Whisper trả về dạng Text. Lệnh này cũng sẽ lưu tạm file ở thư mục `voice/` và xóa sạch sau khi làm xong để tối ưu dung lượng.
- `POST /tts`: Tự động convert văn bản AI thành file âm thanh (MP3 Stream) để loa máy tính có thể đọc ngay lập tức.