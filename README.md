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
Flutter App (S-SOCRATES-APP)
     │
     │ 1. API: Voice/Text Request  
     │ 2. API: Audio Stream Response
     ▼
FastAPI Backend (S-SOCRATES-BE)
     │
     ├─ [STT Service] Faster-Whisper (Nhận diện giọng nói)
     ├─ [Memory Service] Lưu trữ ngữ cảnh hội thoại
     ├─ [LLM & RAG Service] LlamaIndex + Ollama (Xử lý tư duy)
     └─ [TTS Service] Edge-TTS (Phát sinh âm thanh phản hồi)
```

---

## 🚀 Hướng dẫn Cài đặt & Khởi chạy

Để chạy toàn bộ hệ thống, bạn cần 3 Terminal riêng biệt: (1) Ollama, (2) Backend, (3) Frontend.

### Yêu cầu hệ thống (Prerequisites)
- **Python** (>= 3.10)
- **Flutter SDK** (>= 3.x.x)
- **Ollama** (Client `ollama` cài đặt trên máy)

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

### Bước 2: Khởi động Backend (Python FastAPI)

Mở **Terminal 2**:
```powershell
# Chuyển vào thư mục Backend
cd S-SOCRATES-BE

# Cài đặt môi trường ảo (Tuỳ chọn)
python -m venv .venv
.\.venv\Scripts\activate

# Cài đặt các thư viện (Chỉ lần đầu)
pip install -r requirements.txt

# Khởi động Backend Server
uvicorn main:app --reload --port 8000
```
Backend sẽ khởi chạy tại: `http://localhost:8000`. Khi bạn thấy log báo *"Application startup complete"* là thành công.

---

### Bước 3: Khởi động Giao diện Cửa sổ (Flutter App)

Mở **Terminal 3**:
```powershell
# Chuyển vào thư mục Flutter App
cd S-SOCRATES-APP\voice_chat_app

# Lấy các thư viện UI (Chỉ lần đầu)
flutter pub get

# Chạy App với giao diện Desktop Windows
flutter run -d windows
```
*(Hoặc nếu bạn muốn thử nghiệm giao diện Web: `flutter run -d chrome`)*

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
