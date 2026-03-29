# S-SOCRATES Backend (FastAPI)

Backend chịu trách nhiệm xử lý voice/text request, điều phối AI response, và trả command cho robot app/operator UI.

## Tech stack

- FastAPI + Uvicorn
- Deepgram STT
- Semantic Router + LLM service
- TTS service

## Cấu trúc chính

```text
S-SOCRATES-BE/
├── main.py
├── requirements.txt
├── qa_presets.json
├── knowledge/
│   └── uth.txt
├── services/
│   ├── stt_service.py
│   ├── tts_service.py
│   ├── llm_service.py
│   ├── semantic_router.py
│   ├── memory_service.py
│   └── chat_orchestrator.py
└── utils/
    └── logger.py
```

## Cài đặt

```powershell
cd S-SOCRATES-BE
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
```

## Chạy backend

```powershell
uvicorn main:app --reload --port 8000 --host 0.0.0.0 --no-access-log
```

Docs: `http://localhost:8000/docs`

## Endpoint quan trọng

- `POST /chat`: xử lý chat text.
- `POST /stt`: chuyển audio -> text.
- `POST /tts`: chuyển text -> audio.
- `POST /process-audio`: pipeline voice end-to-end cho robot.
- `POST /send-to-robot`: operator gửi lệnh (text + emotion).
- `GET /latest-command`: robot polling command mới nhất.
- `GET /latest-transcript`: operator polling transcript mới nhất.

## Lưu ý trạng thái robot

- `speaking`, `challenge`: yêu cầu có text.
- `no_voice`: dùng khi STT rỗng hoặc không nhận được voice.
- `error`: dùng cho lỗi/kết nối.

## Biến môi trường

Tùy cấu hình service, bạn có thể cần:
- `DEEPGRAM_API_KEY`
- Các biến liên quan TTS/LLM (nếu áp dụng theo môi trường của bạn)

## Troubleshooting

- Timeout khi polling: kiểm tra backend có đang xử lý request nặng.
- Không có transcript: kiểm tra audio format, key STT, và log backend.
- Không phát tiếng: kiểm tra TTS service và đường trả audio.
