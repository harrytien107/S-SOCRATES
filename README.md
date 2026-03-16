## Cách chạy S-Socrates (Web + Backend)

### Sau khi đã cài xong tất cả — chỉ cần chạy 3 lệnh

Mở **3 cửa sổ PowerShell** và chạy lần lượt (giữ mỗi cửa sổ mở):

**Cửa sổ 1 — Ollama:**
```powershell
ollama serve
```

**Cửa sổ 2 — Backend:**
```powershell
cd d:\tailieuhoctap\S-Socrates\S-SOCRATES-BE
.\.venv\Scripts\activate
uvicorn main:app --reload --port 8000
```

**Cửa sổ 3 — Frontend web:**
```powershell
cd d:\tailieuhoctap\S-Socrates\S-SOCRATES-APP\voice_chat_app
flutter run -d chrome
```
*(hoặc `flutter run -d edge` nếu dùng Edge)*

Sau khi cả 3 đang chạy, mở trình duyệt tại URL mà Flutter in ra và bắt đầu chat với S-Socrates.

---

### 1. Chuẩn bị môi trường

- **Yêu cầu chung**
  - Windows 10/11
  - Đã cài:
    - **Python** (>= 3.10)
    - **Flutter SDK** (channel `stable`, Dart 3.11.x)
    - **Ollama** (client `ollama` chạy được trong PowerShell)

Kiểm tra nhanh:

```powershell
python --version
flutter --version
ollama --version
```

### 2. Khởi động Ollama + model Qwen2

Mở **một** cửa sổ PowerShell mới và chạy:

```powershell
ollama serve
```

Giữ cửa sổ này luôn mở (Ollama server chạy nền).

Mở **cửa sổ PowerShell khác** để tải model (chỉ cần lần đầu):

```powershell
ollama pull qwen2:7b
```

### 3. Chạy backend FastAPI (S-SOCRATES-BE)

Mở **cửa sổ PowerShell mới**:

```powershell
cd d:\tailieuhoctap\S-Socrates\S-SOCRATES-BE

# Nếu chưa có virtualenv, tạo mới:
python -m venv .venv

# Kích hoạt virtualenv
.\.venv\Scripts\activate

# Cài các thư viện cần thiết (chỉ cần lần đầu)
pip install fastapi uvicorn
pip install llama-index
pip install llama-index-llms-ollama
pip install llama-index-embeddings-huggingface
pip install sentence-transformers
```

Sau khi cài xong, chạy server:

```powershell
uvicorn main:app --reload --port 8000
```

Giữ cửa sổ này mở. Backend sẽ chạy ở `http://localhost:8000` với endpoint `POST /chat`.

### 4. Chạy Flutter web app (S-SOCRATES-APP)

Mở **cửa sổ PowerShell khác**:

```powershell
cd d:\tailieuhoctap\S-Socrates\S-SOCRATES-APP\voice_chat_app

# Lấy dependencies Flutter
flutter pub get

# Chạy app ở chế độ web
flutter run -d chrome
# hoặc (nếu dùng Edge)
flutter run -d edge
```

Flutter sẽ build và tự mở trình duyệt tới một URL dạng `http://localhost:xxxxx` hiển thị UI chat S‑Socrates.

### 5. (Tuỳ chọn) Build bản web tĩnh

Nếu muốn build bản web tĩnh để deploy lên hosting:

```powershell
cd d:\tailieuhoctap\S-Socrates\S-SOCRATES-APP\voice_chat_app
flutter build web
```

Kết quả nằm ở thư mục:

```text
build/web
```

Bạn có thể dùng bất kỳ HTTP server tĩnh nào để serve thư mục này (ví dụ `python -m http.server`) và trỏ frontend về đúng backend (theo mặc định, backend là `http://localhost:8000`).

### 6. Kiểm tra end-to-end

1. Đảm bảo **3 thứ đang chạy**:
   - `ollama serve`
   - `uvicorn main:app --reload --port 8000`
   - `flutter run -d chrome` (hoặc Edge)
2. Mở UI web trên trình duyệt.
3. Gửi câu hỏi thử, ví dụ:  
   `Anh/chị phân tích giúp em về ngành Logistics ở UTH?`
4. Kiểm tra:
   - Backend log có request mới.
   - Ollama sinh trả lời.
   - Flutter hiển thị phản hồi của S‑Socrates.

