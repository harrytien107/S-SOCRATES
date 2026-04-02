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

Tạo file `.env` từ mẫu:

```powershell
copy .env.example .env
```

## Chạy backend

```powershell
uvicorn main:app --reload --port 8000 --host 0.0.0.0 --no-access-log
```

Docs: `http://localhost:8000/docs`

## Endpoint quan trọng

- `POST /stt`: chuyển audio -> text.
- `POST /tts`: chuyển text -> audio.
- `POST /process-audio`: pipeline voice end-to-end cho robot.
- `POST /send-to-robot`: operator gửi lệnh (text + emotion).
- `GET /configs`: lấy cấu hình audio, Gemini, robot control URL, và local LLM status.
- `GET /latest-transcript`: operator polling transcript mới nhất.
- `WS /ws/operator`: đẩy transcript/mic status/log realtime cho operator UI.

## Lưu ý trạng thái robot

- `speaking`, `challenge`: yêu cầu có text.
- `no_voice`: dùng khi STT rỗng hoặc không nhận được voice.
- `error`: dùng cho lỗi/kết nối.

## Biến môi trường

Tùy cấu hình service, bạn có thể cần:
- `DEEPGRAM_API_KEY`
- `GEMINI_API_KEY`
- `ROBOT_CONTROL_URL`

## Local LLM

Backend local hiện hỗ trợ 2 lựa chọn qua `.env`:
- `LOCAL_LLM_BACKEND=ollama`
- `LOCAL_LLM_BACKEND=turboquant`

Luồng hiện tại:
- Backend vẫn giữ Gemini như trước.
- Khi `req.mode == "ai"`, backend sẽ route sang local backend được chọn.
- Nếu `LOCAL_LLM_AUTOSTART=1`, backend sẽ thử tự khởi động local engine khi app start.

Ví dụ Ollama:

```env
LOCAL_LLM_BACKEND=ollama
LOCAL_LLM_AUTOSTART=1
LOCAL_LLM_HOST=127.0.0.1
LOCAL_LLM_PORT=11434
OLLAMA_CMD=ollama
OLLAMA_MODEL_NAME=qwen2:1.5b
```

Ví dụ TurboQuant:

```env
LOCAL_LLM_BACKEND=turboquant
LOCAL_LLM_AUTOSTART=1
LOCAL_LLM_HOST=127.0.0.1
LOCAL_LLM_PORT=8011
LOCAL_LLM_MODEL_NAME=Qwen3.5-4b-finetuned-opinion.Q4_K_M.gguf
LOCAL_LLM_GGUF_PATH=D:\models\Qwen3.5-4b-finetuned-opinion.Q4_K_M.gguf
TURBOQUANT_SERVER_BIN=D:\llama-cpp-turboquant-cuda\build-win-cuda\bin\Release\llama-server.exe
TURBOQUANT_CACHE_TYPE=turbo2
TURBOQUANT_NGL=99
TURBOQUANT_CTX=8192
```

## Windows TurboQuant

PR #5 đã được merge chọn lọc kèm script hỗ trợ Windows:
- `scripts/setup_turboquant_windows.ps1`
- `scripts/start_turboquant_windows.ps1`

Ví dụ setup:

```powershell
cd S-SOCRATES-BE
powershell -ExecutionPolicy Bypass -File .\scripts\setup_turboquant_windows.ps1 `
  -ModelPath "D:\models\Qwen3.5-4b-finetuned-opinion.Q4_K_M.gguf"
```

Ví dụ chạy riêng `llama-server`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_turboquant_windows.ps1
```

## Troubleshooting

- Timeout khi polling: kiểm tra backend có đang xử lý request nặng.
- Không có transcript: kiểm tra audio format, key STT, và log backend.
- Không phát tiếng: kiểm tra TTS service và đường trả audio.
- Local backend không lên: kiểm tra `LOCAL_LLM_BACKEND`, port, binary/path model GGUF, và log startup của FastAPI.
