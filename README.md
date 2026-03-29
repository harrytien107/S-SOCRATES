# S-SOCRATES

S-SOCRATES là hệ thống AI hội thoại tiếng Việt cho kịch bản phản biện/talkshow, gồm:
- **Operator Console (Web)** để điều phối nội dung và cảm xúc robot.
- **Robot App (Flutter)** để tương tác giọng nói trên sân khấu.
- **Backend (FastAPI)** để xử lý STT, điều phối phản hồi AI, và TTS.

## Kiến trúc tổng quan

```text
Operator UI (Web) ───────────────┐
                                 │
Robot App (Flutter) ───────┐     │
                           ├──> FastAPI Backend (S-SOCRATES-BE)
                           │        ├─ STT (Deepgram)
                           │        ├─ Semantic Router / LLM
                           │        └─ TTS
                           │
                           └<── Polling command/status
```

## Thành phần dự án

- `S-SOCRATES-BE/`: Backend FastAPI, nghiệp vụ AI, STT/TTS.
- `S-SOCRATES-APP/voice_chat_app/`: Ứng dụng Flutter (robot + giao diện chat).
- `operator-ui/`: Console web cho operator.

## Yêu cầu hệ thống

- Python `>= 3.10`
- Flutter SDK `>= 3.x`
- Ollama (nếu dùng local LLM)

## Quick Start (3 terminal)

### 1) Ollama

```powershell
ollama pull qwen2:1.5b
ollama serve
```

### 2) Backend

```powershell
cd S-SOCRATES-BE
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000 --host 0.0.0.0 --no-access-log
```

### 3) Flutter App

```powershell
cd S-SOCRATES-APP\voice_chat_app
flutter pub get
flutter run -d windows # hoặc flutter run -d chrome hoặc flutter run -d <device_id>
```

## Operator Console

Mở file `operator-ui/index.html` bằng web server tĩnh (hoặc Live Server), sau đó cấu hình `API BASE URL` trỏ tới backend.

Các chức năng chính:
- Nhận transcript và gợi ý phản hồi.
- Generate AI response.
- Chọn emotion và gửi lệnh cho robot.
- Điều phối trạng thái `no_voice`, `speaking`, `challenge`, ...

## Lưu ý vận hành

- Nếu backend bận xử lý AI, polling có thể chậm tạm thời.
- Robot app đã có ngưỡng chống false disconnect (không báo mất kết nối quá sớm).
- Khi STT rỗng, hệ thống tự đưa robot sang trạng thái `no_voice`.

## Tài liệu chi tiết

- Backend: `S-SOCRATES-BE/README.md`
- Flutter App: `S-SOCRATES-APP/README.md`

## Bảo mật

- Không commit key/credential vào repo.
- Nếu từng lộ key service account, cần rotate key ngay.
