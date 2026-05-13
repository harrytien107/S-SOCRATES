# S-SOCRATES - Hướng dẫn cài công cụ và chạy dự án cho người mới

Tài liệu này dành cho người mới bắt đầu chạy S-SOCRATES trên Windows. Mục tiêu là cài đúng công cụ, biết công cụ đó dùng để làm gì, kiểm tra đã cài đúng chưa, rồi chạy được backend, operator UI, local AI baseline, TurboQuant và benchmark.

## 1. Tổng quan dự án

S-SOCRATES gồm các phần chính:

- `S-SOCRATES-BE`: backend Python FastAPI.
- `operator-ui`: giao diện operator chạy trên trình duyệt.
- `S-SOCRATES-APP/voice_chat_app`: app Flutter cho robot.
- Gemini API: chế độ AI cloud dùng cho demo/hội thảo.
- Local AI baseline: chạy model GGUF bằng `llama-server` với KV-cache `f16`.
- TurboQuant local AI: chạy model GGUF bằng `llama-server` có nén KV-cache `turbo2`.
- Benchmark: chạy bộ câu hỏi để lấy số liệu so sánh baseline và TurboQuant.

## 2. Thư mục nên biết

```text
path\to\S-SOCRATES
```

Các thư mục/file quan trọng:

```text
S-SOCRATES-BE\.env
S-SOCRATES-BE\scripts
S-SOCRATES-BE\benchmark
S-SOCRATES-BE\logs
operator-ui
S-SOCRATES-APP\voice_chat_app
```

## 3. Công cụ cần cài

Có thể cài đặt tất các công cụ này thông qua file `setup_turboquant_windows.ps1` trong `S-SOCRATES-BE\scripts`, nhưng cần hiểu công cụ đó dùng để làm gì, và kiểm tra đã cài đúng chưa. 

### 3.1. Git

Dùng để tải source code và quản lý phiên bản.

Kiểm tra:

```powershell
git --version
```

Nếu chưa có, cài tại [https://git-scm.com/download/win](https://git-scm.com/download/win).

### 3.2. Python 3.11

Dùng để chạy backend FastAPI, benchmark, RAG và các script xử lý số liệu.

Kiểm tra:

```powershell
python --version
```

Khuyến nghị dùng Python 3.11. CÀi đặt tại [https://www.python.org/downloads/release/python-3110/](https://www.python.org/downloads/release/python-3110/)

### 3.3. PowerShell

Dùng để chạy các file `.ps1`.

Kiểm tra:

```powershell
powershell $PSVersionTable.PSVersion
```

Khi chạy script, dùng dạng:

```powershell
powershell -ExecutionPolicy Bypass -File .\S-SOCRATES-BE\scripts\start_api_only.ps1
```

Nếu chưa cài PowerShell 7, cài tại [https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.6](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.6)

### 3.4. Visual Studio Build Tools 2022

Dùng để build `llama-server.exe` có CUDA cho TurboQuant.

Cần cài:

- Visual Studio Build Tools 2022
- Workload `Desktop development with C++`
- MSVC v143
- Windows 10/11 SDK

Quan trọng: dùng `x64 Native Tools Command Prompt for VS 2022` khi build TurboQuant. Không dùng `Visual Studio 2026 Developer Prompt` nếu CUDA 12.5.

Kiểm tra trong `x64 Native Tools Command Prompt for VS 2022`:

```cmd
where cl
```

Đường dẫn đúng thường có dạng:

```text
...\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\...\cl.exe
```

### 3.5. CMake

Dùng để cấu hình build `llama-server`.

Kiểm tra:

```powershell
cmake --version
```

Nếu chưa có, cài tại [https://cmake.org/download/](https://cmake.org/download/).

### 3.6. Ninja

Dùng làm build tool nhanh cho CMake.

Kiểm tra:

```powershell
ninja --version
```

Nếu chưa có, cài tại [https://github.com/ninja-build/ninja/releases](https://github.com/ninja-build/ninja/releases).

### 3.7. NVIDIA Driver và CUDA Toolkit

Dùng để chạy local AI trên GPU NVIDIA.

Kiểm tra driver:

```cmd
nvidia-smi
```

Kiểm tra CUDA compiler:

```cmd
nvcc --version
```

Nếu chưa có NVIDIA Driver, cài tại [https://www.nvidia.com/Download/index.aspx](https://www.nvidia.com/Download/index.aspx). Kiểm tra CUDA version bao nhiêu cài cho đúng bằng `nvidia-smi`.

### 3.8. Model GGUF

Local AI cần file model `.gguf`, ví dụ:

```text
G:\Software\Model-AI\Qwen3.5-4B-Q4_K_M.gguf
```

Nếu đổi model, chỉ cần sửa đường dẫn trong `.env`, thường không cần build lại `llama-server.exe`. Có thể tải các model GGUF tại [https://huggingface.co/models?filter=gguf](https://huggingface.co/models?filter=gguf).

### 3.9. Flutter SDK

Dùng để chạy app robot Flutter.

Kiểm tra:

```powershell
flutter --version
flutter doctor
```

Nếu chỉ chạy backend và operator UI thì chưa cần Flutter.

### 3.10. Trình duyệt Chrome hoặc Edge

Dùng để mở operator UI:

```text
http://localhost:8000/operator/
```

## 4. Cấu hình `.env`

File cấu hình backend:

```text
S-SOCRATES-BE\.env
```

Các biến quan trọng:

```env
GEMINI_API_KEY=your_gemini_key
DEEPGRAM_API_KEY=your_deepgram_key

DEPLOYMENT_MODE=hybrid

LOCAL_HOST=127.0.0.1
LOCAL_TIMEOUT_S=300
LOCAL_MAX_TOKENS=256
LOCAL_MODEL_NAME=model.gguf
LOCAL_GGUF_PATH=path\to\your\model.gguf
LOCAL_SERVER_BIN=path\to\llama-server.exe
LOCAL_TYPE=turbo2
LOCAL_NGL=99
LOCAL_CTX=8192
LOCAL_REASONING_BUDGET=0

LOCAL_LLM_PORT=8011
LOCAL_LLM_AUTOSTART=1
LOCAL_BASELINE_PORT=8012
LOCAL_BASELINE_AUTOSTART=1

SETUP_SOFTWARE_ROOT=path\to\
TURBOQUANT_WORKSPACE_ROOT=path\to\BuildTool\
BACKEND_VENV_ROOT=path\to\BuildTool\venvs\
```

Không đưa API key thật lên GitHub.

## 5. Cài thư viện Python backend

Nếu đã có venv tại:

```text
path\to\BuildTool\venvs\
```

Thì dùng Python trong venv này để chạy backend.

Nếu cần cài thêm thư viện:

```powershell
path\to\BuildTool\venvs\Scripts\python.exe -m pip install ten-thu-vien
```

Nếu dự án có `requirements.txt`, cài bằng:

```powershell
path\to\BuildTool\venvs\Scripts\python.exe -m pip install -r .\S-SOCRATES-BE\requirements.txt
```

## 6. Build TurboQuant lần đầu

Mở `x64 Native Tools Command Prompt for VS 2022`.

Chạy:

```cmd
cd /d path\to\S-SOCRATES\S-SOCRATES-BE

powershell -ExecutionPolicy Bypass -File .\scripts\setup_turboquant_windows.ps1 -ModelPath "path\to\model.gguf" -ForceReconfigure -SkipCudaInstall
```

Sau khi build xong, kiểm tra file:

```text
path\to\BuildTool\llama-cpp-turboquant-cuda\build-win-cuda\bin\Release\llama-server.exe
```

## 7. Chạy backend theo từng chế độ

Mở terminal tại root project:

```powershell
cd path\to\S-SOCRATES
```

### 7.1. Chạy API only

Dùng Gemini API, không chạy local model.

```powershell
powershell -ExecutionPolicy Bypass -File .\S-SOCRATES-BE\scripts\start_api_only.ps1
```

Mở operator:

```text
http://localhost:8000/operator/
```

### 7.2. Chạy local baseline

Dùng để đo đối chứng không TurboQuant.

```powershell
powershell -ExecutionPolicy Bypass -File .\S-SOCRATES-BE\scripts\start_baseline_only.ps1
```

Baseline dùng KV-cache `f16`.

Log:

```text
S-SOCRATES-BE\logs\baseline.stderr.log
S-SOCRATES-BE\logs\baseline.stdout.log
```

### 7.3. Chạy local TurboQuant

Dùng để đo hệ thống có TurboQuant.

```powershell
powershell -ExecutionPolicy Bypass -File .\S-SOCRATES-BE\scripts\start_turbo_only.ps1
```

TurboQuant dùng KV-cache `turbo2`.

Log:

```text
S-SOCRATES-BE\logs\turboquant.stderr.log
S-SOCRATES-BE\logs\turboquant.stdout.log
```

## 8. Kiểm tra GPU đang chạy

Khi local AI đang trả lời, mở terminal khác:

```cmd
nvidia-smi
```

Nếu thành công, sẽ thấy `llama-server.exe` dùng VRAM.

Nếu log có dòng này:

```text
ggml_cuda_init: failed to initialize CUDA
```

thì runtime chưa dùng CUDA đúng.

## 9. Chạy benchmark

Chạy baseline trước, sau đó chạy TurboQuant sau. Không chạy cả hai cùng lúc khi đo.

### 9.1. Benchmark baseline

Đầu tiên chạy:

```powershell
powershell -ExecutionPolicy Bypass -File .\S-SOCRATES-BE\scripts\start_baseline_only.ps1
```

Sau đó mở terminal khác và chạy:

```powershell
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode ai_baseline `
  --label baseline_cache_fp16_long_context `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_long_context.csv `
  --runs-per-case 3 `
  --timeout-s 300
```

### 9.2. Benchmark TurboQuant

Dừng backend baseline, rồi chạy:

```powershell
powershell -ExecutionPolicy Bypass -File .\S-SOCRATES-BE\scripts\start_turbo_only.ps1
```

Sau đó mở terminal khác và chạy:

```powershell
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode ai_turbo `
  --label turboquant_cache_turbo2_long_context `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_long_context.csv `
  --runs-per-case 3 `
  --timeout-s 300
```

Kết quả benchmark:

```text
S-SOCRATES-BE\benchmark\results
S-SOCRATES-BE\benchmark\logs
```

## 10. Lấy thông số KV-cache

Sau khi chạy baseline hoặc TurboQuant, dùng script:

```powershell
python .\S-SOCRATES-BE\scripts\export_kv_cache_turn_metrics.py
```

Nhập đường dẫn log:

```text
S-SOCRATES-BE\logs\baseline.stderr.log
```

hoặc:

```text
S-SOCRATES-BE\logs\turboquant.stderr.log
```

Script sẽ hỏi mốc `START`. Có thể nhập:

```text
===== START 2026-05-11 16:47:01 =====
START 2026-05-11 16:47:01
2026-05-11 16:47:01
16:47:01
```

Script tạo 2 file:

```text
kv_cache_metrics_*.csv
kv_cache_turn_metrics_*.csv
```

## 11. Đọc kết quả nhanh

Trong `kv_cache_metrics_*.csv`:

- `kv_total_mib`: tổng KV-cache.
- `k_cache_type`: kiểu K-cache.
- `k_mib`: dung lượng K-cache.
- `v_cache_type`: kiểu V-cache.
- `v_mib`: dung lượng V-cache.

Ví dụ:

```text
Baseline: K(f16) 128 MiB + V(f16) 128 MiB = 256 MiB
TurboQuant: K(turbo2) 20 MiB + V(turbo2) 20 MiB = 40 MiB
```

Công thức:

```text
memory_saved_percent = (baseline_kv_total_mib - turbo_kv_total_mib) / baseline_kv_total_mib * 100
```

Ví dụ:

```text
(256 - 40) / 256 * 100 = 84.38%
```

Trong `kv_cache_turn_metrics_*.csv`:

- `prompt_eval_ms`: thời gian xử lý prompt.
- `eval_ms`: thời gian sinh câu trả lời.
- `total_ms`: tổng thời gian.
- `prompt_eval_tokens`: số token prompt.
- `eval_tokens`: số token sinh ra.
- `restored_checkpoint_count`: số lần phục hồi context checkpoint.

## 12. Chạy app robot Flutter

Đi tới thư mục Flutter:

```powershell
cd path\to\S-SOCRATES\S-SOCRATES-APP\voice_chat_app
```

Kiểm tra:

```powershell
flutter doctor
```

Chạy app:

```powershell
flutter run
```

Đảm bảo app robot trỏ đúng IP backend.

## 13. Lỗi thường gặp

### Sai terminal khi build CUDA

Nếu gặp:

```text
unsupported Microsoft Visual Studio version
```

Hãy build lại bằng `x64 Native Tools Command Prompt for VS 2022`.

### Không thấy GPU chạy

Kiểm tra:

```cmd
nvidia-smi
nvcc --version
```

Kiểm tra log:

```text
S-SOCRATES-BE\logs\turboquant.stderr.log
```

### Benchmark báo không tìm thấy file

Thường do đang đứng sai thư mục. Các lệnh benchmark trong tài liệu này mặc định chạy từ:

```text
path\to\S-SOCRATES
```

### Đổi API key nhưng backend không nhận

Dừng backend, mở terminal mới, rồi chạy lại script start.

### Đổi model GGUF

Sửa trong `.env`:

```env
LOCAL_MODEL_NAME=ten-model.gguf
LOCAL_GGUF_PATH=duong-dan\ten-model.gguf
```

Sau đó chạy lại `start_baseline_only.ps1` hoặc `start_turbo_only.ps1`.

## 14. Quy trình cho người mới

Nếu chỉ muốn chạy demo Gemini:

```text
1. Cài Python 3.11
2. Cấu hình GEMINI_API_KEY và DEEPGRAM_API_KEY
3. Chạy start_api_only.ps1
4. Mở http://localhost:8000/operator/
```

Nếu muốn chạy đề tài TurboQuant:

```text
1. Cài Python 3.11, Git, CMake, Ninja
2. Cài Visual Studio Build Tools 2022
3. Cài NVIDIA Driver và CUDA Toolkit 12.5
4. Tải model GGUF
5. Build TurboQuant bằng setup_turboquant_windows.ps1
6. Chạy baseline và benchmark
7. Chạy TurboQuant và benchmark
8. Xuất CSV KV-cache
9. So sánh baseline f16 và TurboQuant turbo2
```
