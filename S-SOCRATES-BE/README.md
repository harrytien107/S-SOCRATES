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
- `GEMINI_API_KEY`

### Local LLM: chọn `ollama` hoặc `turboquant`

Backend local chỉ có 2 lựa chọn qua `.env`:

- `LOCAL_LLM_BACKEND=ollama`
- `LOCAL_LLM_BACKEND=turboquant`

Khi backend FastAPI khởi động:

- app sẽ kiểm tra local engine đã sẵn sàng chưa
- nếu chưa sẵn sàng và `LOCAL_LLM_AUTOSTART=1`, app sẽ tự khởi động engine local đã chọn
- khi backend tắt, app chỉ dừng process local mà chính app đã start
- app không kill service ngoài hệ thống, nhờ đó an toàn hơn khi máy còn tiến trình khác

### Ví dụ cấu hình Ollama

```env
LOCAL_LLM_BACKEND=ollama
LOCAL_LLM_AUTOSTART=1
LOCAL_LLM_HOST=127.0.0.1
LOCAL_LLM_PORT=11434
LOCAL_LLM_TIMEOUT_S=120
OLLAMA_CMD=ollama
OLLAMA_MODEL_NAME=qwen2:7b
```

### Ví dụ cấu hình TurboQuant

```env
LOCAL_LLM_BACKEND=turboquant
LOCAL_LLM_AUTOSTART=1
LOCAL_LLM_HOST=127.0.0.1
LOCAL_LLM_PORT=8011
LOCAL_LLM_TIMEOUT_S=120
LOCAL_LLM_MODEL_NAME=Qwen3.5-4b-finetuned-opinion.Q4_K_M.gguf
LOCAL_LLM_GGUF_PATH=/home/your-user/models/Qwen3.5-4b-finetuned-opinion.Q4_K_M.gguf
TURBOQUANT_SERVER_BIN=/home/your-user/llama-cpp-turboquant-cuda/build-cuda-kv/bin/llama-server
TURBOQUANT_CACHE_TYPE=turbo2
TURBOQUANT_NGL=99
TURBOQUANT_CTX=8192
```

Lưu ý:

- Gemini giữ nguyên luồng cũ và không phụ thuộc local backend.
- `model_choice="ollama"` trong code hiện tại vẫn được giữ nguyên để tương thích API, nhưng thực tế nó sẽ route sang local backend đã chọn trong `.env`.
- Với TurboQuant, backend không tải lại model; nó dùng trực tiếp file GGUF đã có sẵn tại `LOCAL_LLM_GGUF_PATH`.

## Windows: setup TurboQuant tự động

Nếu máy Windows chưa có TurboQuant, bạn có thể dùng script PowerShell để:

- kiểm tra và cài dependency còn thiếu bằng `winget`
- cài Python venv cho backend
- clone repo TurboQuant
- build `llama-server.exe` bằng CUDA
- ghi lại các biến `.env` cần thiết để backend tự autostart local engine

Ví dụ:

```powershell
cd S-SOCRATES-BE
powershell -ExecutionPolicy Bypass -File .\scripts\setup_turboquant_windows.ps1 `
  -ModelPath "D:\models\Qwen3.5-4b-finetuned-opinion.Q4_K_M.gguf"
```

Script mặc định dùng:

- repo: `spiritbuun/llama-cpp-turboquant-cuda`
- branch: `feature/turboquant-kv-cache`
- cache type: `turbo2`

Nếu muốn test riêng `llama-server` trước khi chạy FastAPI:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start_turboquant_windows.ps1
```

Sau đó mới chạy backend:

```powershell
.\.venv\Scripts\activate
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## Troubleshooting

- Timeout khi polling: kiểm tra backend có đang xử lý request nặng.
- Không có transcript: kiểm tra audio format, key STT, và log backend.
- Không phát tiếng: kiểm tra TTS service và đường trả audio.
- Local backend không lên: kiểm tra `LOCAL_LLM_BACKEND`, port, binary/path model GGUF, và log startup của FastAPI.
- Build TurboQuant trên Windows lỗi: kiểm tra CUDA Toolkit, Visual Studio Build Tools C++, và thử chạy lại `setup_turboquant_windows.ps1 -ForceReconfigure`.
