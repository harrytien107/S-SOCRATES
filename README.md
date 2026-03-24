# S-Socrates AI – Chiến Thần Phản Biện UTH

Chào mừng đến với **S-Socrates**, một trợ lý AI thông minh được thiết kế đặc biệt cho talkshow *"Tôi tư duy, tôi tồn tại"*. Lấy cảm hứng từ triết gia Socrates, AI này không chỉ trả lời câu hỏi mà còn sử dụng phương pháp **Socratic Questioning** (đặt câu hỏi ngược lại) để kích thích tư duy người dùng.

## 🌟 Chức năng nổi bật

- 🎙️ **Giao tiếp bằng giọng nói (Voice Chat):** Tích hợp Whisper AI để nhận diện tiếng Việt cực chuẩn và Edge-TTS để trả lời bằng giọng nói tự nhiên.
- 🛑 **Tự động bắt nhịp (VAD):** Hệ thống tự động nhận diện khoảng lặng (silence) để biết khi nào bạn đã nói xong và lập tức phản hồi mà không cần chạm tay.
- 🧠 **Trí nhớ ngữ cảnh (Memory Context):** S-Socrates có thể nhớ lại các diễn biến trước đó trong cuộc trò chuyện để đưa ra câu trả lời liền mạch, logic.
- 📚 **Kiến thức RAG (Retrieval-Augmented Generation):** AI có khả năng nhúng kiến thức từ tài liệu (ví dụ: về trường ĐH Giao thông vận tải TP.HCM - UTH) để cung cấp thông tin chính xác.
- 🖥️ **Giao diện đa nền tảng:** Hỗ trợ chạy mượt mà trên **Windows Desktop** và **Web Browser** thông qua Flutter.
- ⚡ **Local LLM & Offline Ready:** Sử dụng Ollama (Qwen2 1.5b) chạy trực tiếp trên máy, bảo mật 100% dữ liệu.

---

## 🏗️ Kiến trúc Hệ thống (System Architecture)

```text
S-SOCRATES-Vo (Desktop App - All in Python)
     │
     ├─ [STT Service] Deepgram REST API (Nhận diện giọng nói)
     ├─ [Memory Service] Lưu trữ ngữ cảnh hội thoại
     ├─ [LLM & RAG Service] LlamaIndex + Ollama (Xử lý tư duy)
     └─ [TTS Service] Google Cloud Chirp 3 HD (Phát sinh âm thanh)
```

---

## 🚀 Hướng dẫn Cài đặt & Khởi chạy

Để chạy toàn bộ hệ thống, bạn cần 2 Terminal riêng biệt: (1) Ollama, (2) Python Desktop App.

### Yêu cầu hệ thống (Prerequisites)
- **Python** (>= 3.10)
- **Ollama** (Client `ollama` cài đặt trên máy)
- Tài khoản và API Keys cho **Deepgram** (STT) và **Google Cloud** (TTS)

---

### Bước 1: Khởi động Lõi Trí tuệ (Ollama)

Mở **Terminal 1**:
```powershell
# Tải model Qwen2 bản nhẹ (chỉ cần chạy lần đầu, tốn ~1GB RAM)
ollama pull qwen2:1.5b

# Khởi động server Ollama
ollama serve
```
*(Giữ Terminal này luôn mở để AI có "não" suy nghĩ).*

---

### Bước 2: Cài đặt biến môi trường (API Keys)

Tạo một file `.env` trong thư mục gốc của dự án `S-SOCRATES-Vo` (bạn có thể copy từ file `.env.example`) và điền thông tin:

```env
DEEPGRAM_API_KEY=your_deepgram_api_key_here
GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/your/google-credentials.json
```

---

### Bước 3: Khởi động Ứng dụng Desktop (PyQt6)

Mở **Terminal 2**:
```powershell
# Cài đặt môi trường ảo (Khuyên dùng)
python -m venv .venv
.\.venv\Scripts\activate

# Cài đặt các thư viện (Chỉ lần đầu)
pip install -r requirements.txt

# Khởi chạy giao diện Desktop
python main.py
```
*(Giao diện S-Socrates Desktop App sẽ hiện lên)*

---

## 🎯 Cách sử dụng

1. **Text Chat (Tab Tin nhắn):** Bạn chỉ cần nhập văn bản vào và ấn gửi. S-Socrates sẽ trả lời cực kỳ sắc bén và hơi có chút "gen Z".
2. **Voice Chat (Tab Giọng nói):** 
   - Ấn vào biểu tượng Micro để gọi S-Socrates. 
   - Khi vòng sáng hiện lên *"AI Voice đang lắng nghe"*, bạn hãy đưa ra câu hỏi.
   - Khi bạn ngừng nói **2 giây**, hệ thống tự hiểu bạn đã nói xong (VAD) và sẽ tự nhận diện giọng nói -> Xử lý AI -> Phát âm thanh trả lời ra Loa.
   - Cuộc gọi diễn ra liên tục, Rảnh tay hoàn toàn!

---

**🎓 Phát triển tại: Đại học Giao thông vận tải TP.HCM (UTH)**  
👤 *Hệ thống đang được phát triển hỗ trợ cho dự án Talkshow Phản biện.*
