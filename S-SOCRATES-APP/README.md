# S-SOCRATES App (Flutter)

Ứng dụng Flutter cho trải nghiệm người dùng/robot stage:
- Voice chat (ghi âm, gửi STT, nhận phản hồi)
- Hiển thị trạng thái robot theo emotion
- Polling command từ backend

## Cấu trúc chính

```text
S-SOCRATES-APP/voice_chat_app/
├── lib/
│   ├── main.dart
│   ├── stage/
│   ├── controllers/
│   ├── services/
│   └── widgets/
├── pubspec.yaml
└── test/
```

## Yêu cầu

- Flutter SDK `>= 3.x`
- Thiết bị/chế độ chạy: Windows hoặc Chrome (tùy nhu cầu)

## Chạy ứng dụng

```powershell
cd S-SOCRATES-APP\voice_chat_app
flutter pub get
flutter run -d windows
```

Hoặc chạy web:

```powershell
flutter run -d chrome
```

Hoặc chạy trên thiết bị Android/iOS (cần cấu hình thêm):

```powershell
flutter run -d <device_id>
```

## Kết nối backend

App sử dụng base URL cấu hình trong settings và gọi các endpoint backend như:
- `/latest-command`
- `/process-audio`
- `/stt`, `/tts`, `/chat` (tùy flow)

Đảm bảo backend đang chạy trước khi test.

## Luồng quan trọng

- Robot polling command theo chu kỳ.
- Có ngưỡng tránh báo mất kết nối giả khi backend bận.
- Khi STT trả rỗng, app chuyển sang trạng thái `noVoice` (khuôn mặt thất vọng).

## Troubleshooting

- Không thu âm được: kiểm tra permission micro.
- Timeout polling: kiểm tra IP backend và mạng LAN.
- Không có audio phát ra: kiểm tra response TTS và thiết bị âm thanh.
