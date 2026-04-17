# S-SOCRATES

S-SOCRATES là hệ thống robot talkshow AI của UTH, được xây dựng để vận hành theo hai hướng:

  - `Hội thảo / demo`: ưu tiên `Gemini API`
  - `TTTN / LVTN`: ưu tiên `Local AI + TurboQuant`

Toàn bộ hệ thống gồm 3 thành phần:

  - `operator-ui`: giao diện điều phối trên web
  - `S-SOCRATES-BE`: backend FastAPI xử lý STT, RAG, AI và kết nối robot
  - `S-SOCRATES-APP/voice_chat_app`: ứng dụng robot Flutter

## Kiến trúc tổng quát

```text
Robot / Operator
    ↓
Backend
    ↓
RAG + Memory
    ↓
Gemini API hoặc TurboQuant Local AI
    ↓
Operator / Robot
```

## Trạng thái hiện tại

Dự án hiện đã tách rõ thành 3 chế độ backend:

  - `DEPLOYMENT_MODE=api`
  - `DEPLOYMENT_MODE=local`
  - `DEPLOYMENT_MODE=hybrid`

Ý nghĩa:

  - `api`: chỉ dùng Gemini
  - `local`: chỉ dùng TurboQuant local
  - `hybrid`: bật cả hai để dev và so sánh

## Luồng xử lý chính

### Voice từ robot

```text
Robot record
 -> Backend nhận audio
 -> Deepgram STT
 -> transcript đưa lên Operator
 -> Operator chọn AI
 -> Backend lấy RAG context
 -> Gemini hoặc TurboQuant trả lời
 -> kết quả gửi lại robot/operator
```

### Text từ operator

```text
Operator nhập câu hỏi
 -> Backend
 -> RAG + memory
 -> Gemini hoặc TurboQuant
 -> hiển thị response
```

## Cấu hình trước khi chạy nằm ở `S-SOCRATES-BE`. Bạn cần chuẩn bị:

  - Python 3.11
  - Cài tool build nếu muốn chạy local AI (xem phần TurboQuant)
  - API key cho Gemini, Deepgram, Google Cloud (cho retrieval)
  - Model GGUF nếu dùng local AI
  - Cấu hình robot control URL nếu cần

### `.env` file

Backend đọc cấu hình từ `S-SOCRATES-BE/.env`.

```powershell
GEMINI_API_KEY=my_gemini_api_key
GOOGLE_APPLICATION_CREDENTIALS=path_to_google_credentials.json
DEEPGRAM_API_KEY=my_deepgram_api_key
ROBOT_CONTROL_URL=http://IP:9000

# Local AI mode for the thesis: TurboQuant local runtime
LOCAL_LLM_BACKEND=turboquant
LOCAL_LLM_AUTOSTART=1
LOCAL_LLM_HOST=127.0.0.1
LOCAL_LLM_PORT=8011
LOCAL_LLM_TIMEOUT_S=300
LOCAL_LLM_MAX_TOKENS=256
LOCAL_LLM_MODEL_NAME=NameModel.gguf
LOCAL_LLM_GGUF_PATH=path\to\NameModel.gguf

# TurboQuant mode
# Build llama-server with the provided setup script, then point this variable to it.
TURBOQUANT_SERVER_BIN=path\to\S-SOCRATES\turboquant-workspace\llama-cpp-turboquant-cuda\build-win-cuda\bin\llama-server.exe
TURBOQUANT_CACHE_TYPE=turbo2
TURBOQUANT_NGL=99
TURBOQUANT_CTX=4096
TURBOQUANT_REASONING_BUDGET=0

# Backend deployment split:
# - api: only Gemini API pipeline
# - local: only TurboQuant local pipeline
# - hybrid: both are available
DEPLOYMENT_MODE=api
```

### `setup_turboquant_windows.ps1`

Backend có script `.\S-SOCRATES-BE\scripts\setup_turboquant_windows.ps1` để build và chạy TurboQuant server trên Windows. Chạy script này một lần để chuẩn bị môi trường local AI.

```powershell
param(
    ...
    [string]$SoftwareRoot = "path\to\" # Thay bằng đường dẫn bạn muốn cài phần mềm,
    ...
)
```

1. Cài tool build nếu máy chưa có:
    - Git
    - CMake
    - Ninja
    - Python 3.11
    - Visual Studio Build Tools
    - Có thể cả CUDA nếu bạn không bật -SkipCudaInstall
2. Clone source TurboQuant runtime
    - Repository llama-cpp-turboquant-cuda
    - Mặc định vào thư mục: `path\to\S-SOCRATES\turboquant-workspace\llama-cpp-turboquant-cuda`
3. Build ra `llama-server.exe`
    - Đây là local server để backend gọi suy luận
4. Tạo/cập nhật .venv cho backend
    - Rồi `pip install -r requirements.txt`
5. Cập nhật file `.env`

### `rebuild_retrieval_windows.ps1`

Nếu bạn chỉnh sửa tri thức trong `S-SOCRATES-BE/knowledge/`, hãy chạy script này để rebuild retrieval index:

```powershell
cd S-SOCRATES-BE
powershell -ExecutionPolicy Bypass -File .\scripts\rebuild_retrieval_windows.ps1
```

```powershell
param(
    [string]$BackendRoot = "",
    [string]$PythonExe = "path\to" # Thay bằng đường dẫn đến python.exe của bạn, ví dụ: .venv\Scripts\python.exe
)
```

### `start_backend_windows.ps1`

Script này khởi động backend trên Windows. Nó sẽ đọc cấu hình từ `.env` và khởi động FastAPI server, đồng thời nếu `LOCAL_LLM_AUTOSTART=1` thì cũng sẽ tự động khởi động TurboQuant local server.

```powershell
cd S-SOCRATES-BE
powershell -ExecutionPolicy Bypass -File .\scripts\start_backend_windows.ps1
```

```powershell
param(
    [string]$BackendRoot = "",
    [string]$PythonExe = "path\to", # Thay bằng đường dẫn đến python.exe của bạn, ví dụ: .venv\Scripts\python.exe
    [string]$ListenHost = "0.0.0.0", # Mặc định lắng nghe trên tất cả IP, bạn có thể đổi thành "
    [int]$Port = 8000, # Cổng mặc định
    [switch]$NoReload
)
```

### `start_turboquant_server_windows.ps1`

Nếu bạn muốn tự khởi động TurboQuant server riêng biệt (thay vì để backend tự start), có thể dùng script này:

```powershell
cd S-SOCRATES-BE
powershell -ExecutionPolicy Bypass -File .\scripts\start_turboquant_server_windows.ps1
```

## Cách chạy nhanh

### 1\. Chạy backend

```powershell
cd S-SOCRATES-BE
powershell -ExecutionPolicy Bypass -File .\scripts\start_backend_windows.ps1
```

### 2\. Mở operator UI

```text
http://localhost:8000/operator/
```

### 3\. Chạy robot app

```powershell
cd S-SOCRATES-APP\voice_chat_app
flutter run
```

## Ghi chú vận hành

  - Nếu sửa tri thức trong `S-SOCRATES-BE/knowledge/`, hãy rebuild retrieval.
  - Nếu đổi model local GGUF, hãy sửa `.env` rồi restart backend.
  - Nếu chạy `DEPLOYMENT_MODE=api`, backend sẽ không khởi động TurboQuant.
  - Nếu chạy `DEPLOYMENT_MODE=local`, operator sẽ chỉ dùng local AI.

## Tài liệu liên quan

  - Tổng hợp backend: [README.md](.\S-SOCRATES\S-SOCRATES-BE\README.md)
  - Tổng hợp frontend: [README.md](.\S-SOCRATES-APP\voice_chat_app\README.md)