# S-SOCRATES Backend (FastAPI)

Backend chịu trách nhiệm xử lý voice/text request, điều phối AI response, quản lý RAG + memory, và trả command cho robot app/operator UI.

## Tech stack

- FastAPI + Uvicorn
- Deepgram STT
- Quantized RAG retrieval
- Gemini cloud API
- TurboQuant local runtime
- Persistent conversation memory
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
│   ├── gemini_service.py
│   ├── turboquant_runtime.py
│   ├── prompt_config.py
│   ├── memory_service.py
│   ├── chat_orchestrator.py
│   └── retrieval/
│       ├── retriever.py
│       ├── quantized_store.py
│       ├── embedder.py
│       ├── chunker.py
│       └── prompt_builder.py
├── scripts/
│   ├── build_quantized_index.py
│   ├── setup_turboquant_windows.ps1
│   └── start_turboquant_windows.ps1
├── data/
│   ├── rag_meta.json
│   └── rag_vectors_uint8.npz
└── utils/
    └── logger.py
```

## Endpoint quan trọng

- `POST /stt`: chuyển audio -> text.
- `POST /tts`: chuyển text -> audio.
- `POST /process-audio`: pipeline voice end-to-end cho robot.
- `POST /send-to-robot`: operator gửi lệnh (text + emotion).
- `GET /configs`: lấy cấu hình audio, Gemini, robot control URL, local runtime status, và retrieval stats.
- `POST /retrieval/rebuild`: rebuild lại quantized retrieval index khi đổi `knowledge/` hoặc `qa_presets.json`.
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

Nhánh AI hiện tại chỉ có 2 loại:
- `Gemini API` cho cloud mode
- `TurboQuant local runtime` cho local mode

Luồng hiện tại:
- Backend giữ Gemini như cloud mode.
- Khi `req.mode == "ai"`, backend route sang `TurboQuant local runtime`.
- Nếu `LOCAL_LLM_AUTOSTART=1`, backend sẽ thử tự khởi động local engine khi app start.
- Persistent memory được lưu lại để rebuild working context sau restart và warm lại context cho TurboQuant local runtime.

## Quantized RAG

- `knowledge/uth.txt` là nguồn tri thức ưu tiên cao nhất.
- `qa_presets.json` chỉ đóng vai trò nguồn tham khảo phụ.
- Quantized retrieval index được lưu ở `data/`.
- Khi thay đổi `knowledge/` hoặc `qa_presets.json`, hãy rebuild index bằng một trong hai cách:

```powershell
cd S-SOCRATES-BE
.\.venv\Scripts\python.exe scripts\build_quantized_index.py
```

hoặc gọi:

```http
POST /retrieval/rebuild
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

- Timeout khi polling/WebSocket: kiểm tra backend có đang xử lý request nặng.
- Không có transcript: kiểm tra audio format, key STT, và log backend.
- Không phát tiếng: kiểm tra TTS service và đường trả audio.
- TurboQuant local backend không lên: kiểm tra port, binary/path model GGUF, và log startup của FastAPI.
- Sau khi sửa `knowledge/uth.txt` hoặc `qa_presets.json` mà AI vẫn trả dữ liệu cũ: rebuild quantized retrieval index.
