# S-SOCRATES Frontend (Flutter App)

Đây là Giao diện Người dùng Khách (Client) của hệ thống S-Socrates. Ứng dụng cung cấp 2 phương thức giao tiếp Text-Chat và Voice-Chat thông minh với thiết kế hiện đại, mượt mà và trực quan.

## ✨ Tính năng chính

- **Voice Activity Detection (VAD):** Hệ thống thông minh tự nhận biết khi bạn ngưng nói (2 giây im lặng) để lập tức thu âm file và gửi thẳng lên Backend phân tích. Bạn không cần phải bấm dừng mic thủ công.
- **Microphone Glow Animation:** Vòng tròn sóng âm ánh sáng tương tác thời gian thực khi thu âm để báo hiệu đang lắng nghe.
- **Auto-Play Edge TTS:** Cảm biến âm thanh nhận câu trả lời dạng chữ từ AI và sử dụng Edge-TTS (FastAPI Backend) để phát trực tiếp âm thanh ra loa.
- **Web & Desktop Ready:** Ứng dụng code bằng Flutter 3, build hoàn hảo dưới dạng file `.exe` cho máy ảo/máy tính bàn Windows hoặc chạy qua trình duyệt Chrome/Edge.

---

## 💻 Hướng dẫn chạy môi trường (Running the App)

### Yêu cầu
- Đã cài hoàn tất Flutter SDK (khuyên dùng bản `stable`).
- Kiểm tra hệ điều hành bằng lệnh: `flutter doctor`

### Các bước chạy

1. Đi vào thư mục chứa code UI:
   ```powershell
   cd voice_chat_app
   ```
2. Cài đặt các thư viện mới (UI, record audio, path_provider, http...):
   ```powershell
   flutter pub get
   ```
3. Chạy App (Chọn 1 trong 2):
   - **Chạy bằng Windows Desktop (Khuyên dùng)**: Mượt, không bị dính bảo mật Microphone của trình duyệt Web.
     ```powershell
     flutter run -d windows
     ```
   - **Chạy bằng Trình duyệt Web (Browser)**: Nhanh, nhẹ nhàng nếu không muốn gen file `.exe`.
     ```powershell
     flutter run -d chrome
     ```

## 🌐 Liên kết Backend
Frontend này giao tiếp toàn diện thông qua 3 endpoint chính được mở tại `http://localhost:8000`:
- `/chat`: Gửi text và nhận LLM response.
- `/stt`: Gửi file `.m4a` thu âm và nhận văn bản Text.
- `/tts`: Gửi văn bản Text và nhận Streaming Audio (MP3).

Đảm bảo **S-SOCRATES-BE** đang hoạt động trước khi gửi câu lệnh để ứng dụng không gặp lỗi *Timeout / CORS Exception*.