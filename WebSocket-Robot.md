# Khai Tử Polling cho Robot Flutter bằng WebSocket

Mục tiêu của chặng này là giúp Robot chấm dứt việc phải dùng "vòng lặp hỏi mỏi mồm" (Polling Request) lên máy chủ, chuyển sang sử dụng "Đường hầm kết nối ngầm" WebSocket y hệt như Màn Hình Web. Điều này sẽ giúp App trên Android tiết kiệm tối đa RAM/Pin và tốc độ phản xạ lệnh gần như là 0ms.

## 🛠️ Trọng Tâm Triển Khai

### 1. Phía Máy Chủ (Python `main.py`)
Ta sẽ xây một "Đường hầm số 2" chuyên dùng để "nhồi" lệnh cho App Robot. Độc lập hoàn toàn với cổng `/ws/operator` của Đạo diễn.
- **[NEW] Endpoint `/ws/robot`:** Tạo trạm thu/phát WebSocket riêng chặn ở FastAPI.
- **[MODIFY] Gửi Lệnh:** Khi Web Operator nhấn nút (hay gọi API `/send-to-robot` / `/operator/mic-control`), thay vì chỉ cập nhật biến cục bộ và bắt Robot tự mò lên xem, Máy Chủ sẽ lập tức dùng cổng `/ws/robot` để "Quăng thẳng" gói lệnh `(mic_status=listening)` hoặc lệnh `(text="Chào bạn", emotion="speaking")` xuống tận tay App Flutter.

### 2. Phía Môi Trường App Flutter
Cập nhật công cụ phá núi mở đường hầm.
- **[MODIFY] `pubspec.yaml`:** Cài đặt package tiêu chuẩn `web_socket_channel`. (Đây là lõi mạng nền tảng để Android mở TCP Socket hai chiều).

### 3. Phía Code Logic Robot (`robot_controller.dart`)
Đập đi rào lại toàn bộ nền tảng vận hành mạng nội bộ của con Robot:
- **[DELETE] 2 bộ máy Polling:** Xóa sổ vĩnh viễn 2 hàm chạy bằng Timer là `_pollMicStatus()` và `_pollCommands()`.
- **[NEW] `connectWebSocket()`:** Viết ra dòng code thiết lập kết nối (ví dụ `ws://<IP>:8000/ws/robot`).
- Lắng nghe trực tiếp: Khi ống nước đẩy xuống cục JSON:
    - Nếu tin nhắn có `type: "mic_status"`: Kích hoạt ngay hàm Bật/Tắt Mic.
    - Nếu tin nhắn có `type: "command"`: Kích hoạt ngay hàm TTS (nói chuyện & chỉnh cảm xúc AI).
- **[NEW] Tự Thức Tỉnh (Auto-Reconnect):** Điện thoại sụp mạng, đứt Wifi? Không sao! Cơ chế *Auto-reconnect* sẽ tự liên tục dò tìm Wifi để nối lại ống nước mỗi 3 giây. Trạng thái kết nối vẫn được giữ nguyên để Màn Hình 3D của Robot không bị Panic hay kẹt cứng.

> [!CAUTION]
> Hệ thống Flutter vốn có luồng Event Loop và Asynchronous (bất đồng bộ) tách biệt. Cần xử lý tỉ mỉ để quá trình Lắng Nghe WebSocket không bị đụng độ với quá trình Thu Âm (Microphone Stream) hiện tại. Bằng cách vẫn tái sử dụng hoàn toàn hàm `startRecordingAudio()` và `stopRecordingAndProcess()` đang chạy mượt hiện hữu. 

---
## Yêu Cầu Phê Duyệt
Toàn bộ logic "Gửi Request đấm Server mỗi giây" đang là trái tim cũ của hệ thống Robot giờ sẽ đem đi mổ xẻ thay thế toàn diện.
Nếu bạn đồng ý hãy nhấn duyệt để tôi bắt đầu tháo khớp nối ở FastAPI và đào hầm sang Flutter nhé!
