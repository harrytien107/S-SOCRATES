# S-SOCRATES: Hệ Thống AI Phản Biện
## Nền tảng AI đối thoại giọng nói cho kịch bản phản biện/talkshow

---

## 📋 Tổng Quan Dự Án

**S-SOCRATES** là nền tảng điều phối robot AI tương tác giọng nói cho các buổi phản biện hoặc talkshow. Hệ thống gồm 3 thành phần chính:

1. **Giao Diện Điều Phối** (Web): Giao diện web để quản lý transcript, tạo response, điều khiển mic robot từ xa
2. **Backend** (FastAPI): Xử lý AI, STT, TTS, quản lý trạng thái, **GỬI LỆNH TRỰC TIẾP TỚI ROBOT**
3. **Ứng Dụng Robot** (Flutter HTTP Server): Ghi âm, phát TTS, hiển thị cảm xúc, nhận lệnh từ backend

⚠️ **Điểm Chính**: Ứng Dụng Robot là một **HTTP Server** (port 9000), Backend gửi lệnh trực tiếp qua HTTP POST.

---

## 🏗️ Kiến Trúc Hệ Thống

### Sơ Đồ Tổng Quan

```
                      ┌──────────────────────────────────────────────────────┐
                      │         GIAO DIỆN ĐIỀU PHỐI(Trình Duyệt Web)         │
                      │  ┌────────────────────────────────────────────────┐  │
                      │  │ Bố cục 3 cột:                                  │  │
                      │  │ 1. Câu Hỏi Sẵn | 2. Nhập Từ Khách | 3. Phản Hồi│  │
                      │  └────────────────────────────────────────────────┘  │
                      └─────────────────────────────┬────────────────────────┘
                                                    │
                                  ┌─────────────────┴─────────────────┐
                                  │                                   │
                                  │ WebSocket: ws://backend:8000/ws/  │
                                  │ operator (Broadcast: dữ liệu)     │
                                  │                                   │
                                  │ HTTP Poll: GET /latest-transcript │
                                  │ (Định kỳ, xóa tự động)            │
                                  │                                   │
                                  ▼                                   ▼
                      ┌───────────────────────┐            ┌─────────────────────┐
                      │  BACKEND (FastAPI)    │            │  DỊCH VỤ BÊN NGOÀI  │
                      │  (S-SOCRATES-BE)      │            │                     │
                      │                       │            │ • Deepgram (STT)    │
                      │ Trạng Thái Chung:     │            │ • Google Cloud TTS  │
                      │ • transcript_mới      │            │ • Ollama (LLM)      │
                      │ • robot_command_mới   │            │ • Gemini (LLM)      │
                      │ • robot_mic_status    │            │                     │
                      │ • GLOBAL_AUDIO_CONFIG │            └─────────────────────┘
                      │                       │
                      │ Dịch Vụ:              │
                      │ • STT (Deepgram)      │
                      │ • TTS (Google Cloud)  │
                      │ • LLM (Ollama/Gemini) │
                      │ • Quản Lý Kết Nối     │
                      │                       │
                      │ Chìa Khóa:            │
                      │ dispatch_robot_       │
                      │ request() GỬI trực    │
                      │ tiếp đến Robot        │
                      │ (KHÔNG POLL)          │
                      └───────────┬───────────┘
                                  │
               ┌──────────────────┴──────────────────┐
               │                                     │
               │ HTTP POST Trực tiếp:                │
               │ • POST :9000/mic {action}           │
               │ • POST :9000/command {text, cảm xúc}│
               │                                     │
               ▼                                     ▼
┌─────────────────────────────┐             ┌─────────────────┐
│ ROBOT HTTP SERVER           │             │ (Backend dùng   │
│ (Flutter, port 9000)        │             │ dispatch_robot_ │
│                             │             │ request() để    │
│ Endpoints:                  │             │ POST trực tiếp) │
│ • POST /mic {action}        │             └─────────────────┘
│ • POST /command {text,...}  │
│ • GET /status               │
│ • GET /health               │
│                             │
│ Gửi lại đến backend:        │
│ • POST /process-audio (STT) │
│ • POST /robot/mic-sync      │
│ • POST /robot/log           │
└─────────────────────────────┘
```

### Mẫu Giao Tiếp

**Giao Diện ← → Backend (WebSocket)**
```
kết nối: ws://backend:8000/ws/operator
  ├─ Nhận: {type: "transcript", data: {transcript, candidates}}
  ├─ Nhận: {type: "mic_status", status: "idle|listening|..."}
  ├─ Nhận: {type: "log", message: "..."}
  └─ Gửi: heartbeat (định kỳ)
```

**Giao Diện ← Backend (HTTP Poll - Chỉ Giao Diện)**
```
GET /latest-transcript (poll định kỳ)
  ├─ Lần 1: {transcript, candidates}
  └─ Lần 2+: null (xóa tự động)
```

**Giao Diện → Backend → Robot (HTTP Trực Tiếp)**
```
POST /send-to-robot {text, emotion}
  ├─ Backend lưu vào _latest_robot_command
  └─ Backend POST trực tiếp tới ROBOT_CONTROL_URL:/command

POST /robot/mic-control {action: "start|stop|cancel"}
  └─ Backend POST trực tiếp tới ROBOT_CONTROL_URL:/mic
```

**Robot HTTP Server ← Backend (Lệnh Trực Tiếp)**
```
Robot chạy HTTP server nghe trên :9000
  ├─ POST /mic {action}  ← nhận điều khiển mic từ backend
  ├─ POST /command {text, emotion}  ← nhận phản hồi từ backend
  ├─ GET /status  ← trả về trạng thái
  └─ GET /health  ← kiểm tra sức khỏe

Robot đồng bộ trạng thái lại:
  ├─ POST /robot/mic-sync {status}  ← tới backend
  └─ POST /robot/log {message}  ← tới backend (broadcast)
```

---

## 📡 Endpoints API

### Cơ Bản
| Endpoint | Phương Thức | Đầu Vào | Đầu Ra | Ghi Chú |
|----------|------------|---------|--------|--------|
| `/` | GET | - | `{status: "ok"}` | Kiểm tra sức khỏe |
| `/qa-presets` | GET | - | `{presets: [...]}` | Tải từ qa_presets.json |
| `/process-audio` | POST | File WAV | `{transcript, candidates}` | STT qua Deepgram |
| `/operator-decision` | POST | `{mode, transcript}` | `{text, emotion}` | Tạo phản hồi AI |
| `/send-to-robot` | POST | `{text, emotion}` | Trạng thái | Gửi lệnh đến robot |

### Cấu Hình
| Endpoint | Phương Thức | Đầu Vào | Đầu Ra |
|----------|------------|---------|--------|
| `/configs` | GET | - | Cấu hình + tùy chọn |
| `/configs` | POST | `AudioConfigRequest` | Cấu hình cập nhật |
| `/tts/voices` | GET | - | `{voices: [...]}` |

### Điều Khiển Mic
| Endpoint | Phương Thức | Đầu Vào | Đầu Ra | Cách Dùng |
|----------|------------|---------|--------|----------|
| `/robot/mic-control` | POST | `{action: "start\|stop\|cancel"}` | Trạng thái | Giao Diện → Backend → Robot |
| `/robot/mic-status` | GET | - | `{mic_status: "..."}` | ⚠️ **KHÔNG DÙNG/LỖI MŨI** |
| `/robot/mic-done` | POST | - | Trạng thái | Robot → Backend (không dùng) |
| `/robot/mic-sync` | POST | `{status: "..."}` | Trạng thái | Robot → Backend (đồng bộ) |
| `/robot/log` | POST | `{message: "..."}` | Trạng thái | Robot → Backend (broadcast) |

### WebSocket
| Endpoint | Loại | Tin Nhắn |
|----------|------|---------|
| `/ws/operator` | WS | `{type: "transcript"\|"mic_status"\|"log", ...}` |

### Tiện Ích
| Endpoint | Phương Thức | Mục Đích |
|----------|------------|---------|
| `/latest-transcript` | GET | Lấy transcript mới nhất (xóa tự động) |
| `/stt` | POST | STT trực tiếp (thay thế) |
| `/tts` | POST | TTS trực tiếp |
| `/operator` | GET | Các file tĩnh (mount) |

---

## 🧩 Phân Tích Modules

### 1️⃣ Giao Diện Điều Phối (`operator-ui/`)

**Công Nghệ**: HTML5 + CSS3 + JavaScript Vanilla

**Các File**:
- `index.html` - Bố cục 3 cột
  - Cột 1: Câu Hỏi Sẵn (tải từ `/qa-presets`)
  - Cột 2: Transcript Deepgram + Chat Thủ Công (box 12rem cố định)
  - Cột 3: Xem Trước Kịch Bản + Chọn Cảm Xúc + Điều Khiển Mic
- `style.css` - Giao diện tối, màu cyan, responsive, modal
- `script.js` - Logic client (~800 dòng)

**Các Hàm Chính**:
```javascript
connectWebSocket()         // ws://backend/ws/operator
loadPresetQuestions()      // GET /qa-presets
useAI()                    // POST /operator-decision (Ollama)
useGemini()                // POST /operator-decision (Gemini)
sendToRobot()              // POST /send-to-robot
startRobotMic()            // POST /robot/mic-control action=start
stopRobotMic()             // POST /robot/mic-control action=stop
toggleTranscriptModal()    // Hiển/ẩn modal mở rộng transcript
toggleManualModal()        // Hiển/ẩn modal mở rộng chat thủ công
clearInputBoxes()          // Xóa tất cả input
```

**Biến Trạng Thái**:
```javascript
currentData              // {transcript, candidates}
selectedEmotion         // "idle", "speaking", "error"
selectedAiInputSource   // "deepgram" hoặc "manual"
hasReceivedDeepgramData // Flag cho logic cảnh báo
```

**Luồng WebSocket**:
```
1. Kết nối tới /ws/operator
2. Nhận: {type: "transcript", data: {...}}
3. Cập nhật UI, tự động chuyển AI input nếu cần
4. Người dùng bấm "AI (Ollama)", "AI (Gemini)", hoặc chọn preset
5. Người dùng bấm "GỬI ĐẾN ROBOT"
6. Nhận: {type: "mic_status", status: "..."}
```

---

### 2️⃣ Backend (`S-SOCRATES-BE/`)

**Công Nghệ**: FastAPI + Python 3.10+

**Các File**:
- `main.py` - Tất cả endpoints (400+ dòng)
- `services/stt_service.py` - Chuyển giọng thành văn bản (Deepgram)
- `services/tts_service.py` - Chuyển văn bản thành giọng (Google Cloud)
- `services/llm_service.py` - LLM Ollama (local) + Gemini (cloud)
- `knowledge/uth.txt` - System prompt
- `qa_presets.json` - Cơ sở dữ liệu Q&A
- `requirements.txt` - Phụ thuộc

**Trạng Thái Chung**:
```python
_latest_transcript = {         # Transcript hiện tại từ STT
    "transcript": "...",
    "candidates": [...]        # Mảng preset Q&A
}

_latest_robot_command = {      # Lệnh hiện tại cho robot
    "text": "...",
    "emotion": "speaking|idle|error",
    "timestamp": 1234567890    # nanoseconds
}

_robot_mic_status = "idle"     # idle|listening|processing|canceled

GLOBAL_AUDIO_CONFIG = {
    "tts_voice": "Aoede",
    "tts_speed": 1.0,
    "stt_model": "nova-2",
    "stt_language": "vi",
    "gemini_model": "models/gemini-2.0-flash",
}

ROBOT_CONTROL_URL = "http://192.168.1.6:9000"  # URL robot từ .env
```

**Dịch Vụ**:

**Dịch Vụ STT** (Deepgram):
```python
transcribe_file(wav_path, model="nova-2", language="vi")
  ├─ POST tới Deepgram REST API
  ├─ Phân tích response
  └─ Trả về transcript (hoặc fallback nếu rỗng)

Mô hình: nova-2, nova-2-general, whisper-large
Ngôn ngữ: vi, en, ja, zh
Fallback: "Không nhận được voice. Vui lòng nói lại."
```

**Dịch Vụ TTS** (Google Cloud):
```python
generate_speech_file(text, output_path, voice="Aoede", speaking_rate=1.0)
  ├─ Gọi Google Cloud TTS Chirp 3 HD
  ├─ Tạo MP3
  └─ Lưu vào disk

Giọng nói: Aoede, Kore, Leda, Zephyr, Puck, Charon, Fenrir, Orus
Tốc độ: 0.25x đến 2.0x
```

**Dịch Vụ LLM**:
```python
ask_socrates(question, model_choice="ollama"|"gemini")
  ├─ Tải knowledge từ knowledge/uth.txt
  ├─ Sử dụng LlamaIndex với vector index chung
  ├─ Truy vấn Ollama HOẶC Gemini
  └─ Trả về response

Ollama: qwen2:1.5b (local, offline)
Gemini: gemini-2.0-flash (mặc định), mô hình khác có sẵn
```

**ConnectionManager** (WebSocket):
```python
class ConnectionManager:
    active_connections: list[WebSocket]
    async def connect(ws)       # Thêm vào danh sách
    async def disconnect(ws)    # Xóa khỏi danh sách
    async def broadcast(msg)    # Gửi đến tất cả operator
```

**Model Request**:
```python
class DecisionRequest:
    mode: str              # "preset", "ai", "gemini"
    selected_answer: str   # Cho preset mode
    transcript: str        # Văn bản câu hỏi

class RobotCommand:
    text: str
    emotion: str

class AudioConfigRequest:
    tts_voice: str
    tts_speed: float
    stt_model: str
    stt_language: str
    gemini_model: str
    robot_control_url: str
```

**Mẫu Endpoint**:
```python
# Ví dụ: Gửi lệnh tới robot
@app.post("/send-to-robot")
async def send_to_robot(req: RobotCommand):
    global _latest_robot_command
    
    # Lưu trong trạng thái chung
    _latest_robot_command = {
        "text": req.text,
        "emotion": req.emotion,
        "timestamp": time.time_ns()
    }
    
    # Chuyển tiếp tới robot device
    try:
        robot_response = await dispatch_robot_request(
            "/command",
            {"text": req.text, "emotion": req.emotion}
        )
    except Exception as e:
        return {"error": f"Không thể kết nối robot: {e}"}
    
    # Broadcast tới operator console
    await ws_manager.broadcast({
        "type": "mic_status",
        "status": _robot_mic_status
    })
    
    return {
        "status": "Lệnh đã gửi",
        "command": _latest_robot_command,
        "robot_response": robot_response
    }
```

---

### 3️⃣ Ứng Dụng Robot (`S-SOCRATES-APP/voice_chat_app/`)

**Công Nghệ**: Flutter 3.x + Dart

**Cấu Trúc**:
```
lib/
├── main.dart            # Entry point + theme
├── services/
│   ├── robot_control_server.dart  # HTTP server (port 9000) nhận lệnh
│   ├── agent_api.dart             # Client gọi backend
│   ├── tts_service.dart           # Phát TTS
│   └── api_config.dart            # Cấu hình URL backend
├── controllers/         # Business logic
└── stage/
    └── robot_stage_screen.dart # UI chính
```

**Trách Nhiệm Chính**:
- 🔌 **HTTP Server** trên port `9000` (qua `RobotControlServer`)
  - Nghe `POST /mic {action}` từ backend → xử lý mic
  - Nghe `POST /command {text, emotion}` từ backend → phát TTS/hiển cảm xúc
  - Phục vụ `GET /status` và `GET /health` để truy vấn trạng thái
  - ⚠️ **KHÔNG POLL** - backend gửi lệnh trực tiếp tới server này
  
- 🎤 **Ghi Âm/Phát Âm Thanh**
  - Khi nhận mic action = "listening", bắt đầu ghi âm
  - Khi hoàn tất, upload WAV tới `POST /process-audio` (backend)
  
- 🌐 **Giao Tiếp Backend** (client side)
  - `POST /process-audio` (upload audio cho STT)
  - `POST /robot/mic-sync` (báo cáo thay đổi mic)
  - `POST /robot/log` (gửi logs → backend broadcast cho operator)
  
- 🔊 **Phát TTS**
  - Nhận response từ `/command` POST
  - Chuyển text→voice qua Google Cloud TTS (backend)
  - Phát audio trên loa

**Giao Tiếp** (Robot App là SERVER, KHÔNG phải client):
```
Backend POST tới Robot:9000/mic {action}  ← Robot nhận lệnh mic
Backend POST tới Robot:9000/command {text, emotion}  ← Robot nhận response

Robot App POST tới Backend:/process-audio  ← Upload audio cho STT
Robot App POST tới Backend:/robot/mic-sync  ← Báo mic status
Robot App POST tới Backend:/robot/log  ← Gửi logs
```

**KHÔNG POLL** - Backend gửi lệnh qua HTTP POST trực tiếp tới robot app server.

---

## 🔐 Mô Hình Dữ Liệu

### Preset Q&A (`qa_presets.json`)
```json
{
  "presets": [
    {
      "id": "preset_1",
      "question": "S-Socrates là gì?",
      "answer": "S-Socrates là hệ thống AI...",
      "emotion": "speaking",
      "category": "introduction"
    }
  ]
}
```

### System Prompt (`knowledge/uth.txt`)
Chứa system prompt được tải bởi LLM service khi khởi động. Dùng chung cho Ollama và Gemini.

### Trạng Thái In-Memory (Python globals)
```python
_latest_transcript = {...}        # Transcript hiện tại
_latest_robot_command = {...}     # Lệnh hiện tại cho robot
_robot_mic_status = "idle"        # Trạng thái mic hiện tại
GLOBAL_AUDIO_CONFIG = {...}       # Cấu hình TTS/STT
```

---

## 🚀 Thiết Lập Phát Triển

### Yêu Cầu
- Python 3.10+
- Ollama (cho LLM local)
- Flutter SDK
- API keys (Deepgram, Gemini, Google Cloud TTS)

### Cài Đặt

```powershell
# Terminal 1: Chạy Ollama
ollama pull qwen2:1.5b
ollama serve

# Terminal 2: Backend
cd S-SOCRATES-BE
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt

# Tạo .env
# DEEPGRAM_API_KEY=key_của_bạn
# GEMINI_API_KEY=key_của_bạn
# GOOGLE_APPLICATION_CREDENTIALS=/đường/dẫn/google-key.json
# ROBOT_CONTROL_URL=http://192.168.1.6:9000

uvicorn main:app --reload --port 8000 --host 0.0.0.0

# Terminal 3: Giao Diện Điều Phối
# Mở http://localhost:8000/operator trong trình duyệt

# Terminal 4: Ứng Dụng Robot
cd S-SOCRATES-APP/voice_chat_app
flutter pub get
flutter run -d windows  # hoặc chrome, android, etc.
```

### Biến Môi Trường

Tạo `.env` trong `S-SOCRATES-BE/`:
```bash
# STT
DEEPGRAM_API_KEY=<key_của_bạn>

# TTS
GOOGLE_APPLICATION_CREDENTIALS=/đường/dẫn/tuyệt/đối/google-key.json

# LLM Cloud
GEMINI_API_KEY=<key_của_bạn>

# Robot
ROBOT_CONTROL_URL=http://192.168.1.6:9000

# Logging
LOG_LEVEL=INFO
```

---

## 🔧 Stack Công Nghệ

| Thành Phần | Công Nghệ | Mục Đích |
|-----------|-----------|---------|
| **Giao Diện** | HTML5 + CSS3 + JS | Console web |
| **Robot App** | Flutter + Dart | Giao diện phần cứng |
| **API** | FastAPI + Python 3.10+ | Điều phối |
| **STT** | Deepgram REST API | Giọng → Văn bản |
| **TTS** | Google Cloud Chirp 3 HD | Văn bản → Giọng |
| **LLM Local** | Ollama (Qwen2:1.5b) | Tạo offline |
| **LLM Cloud** | Google Gemini API | Tạo nâng cao |
| **Knowledge** | LlamaIndex + HuggingFace | Lấy vector |
| **Real-time** | WebSocket (asyncio) | Broadcast operator |
| **Config** | JSON files | Preset Q&A, trạng thái |

---

## 🎯 Tính Năng Hiện Tại

| Tính Năng | Trạng Thái | Ghi Chú |
|----------|-----------|--------|
| Đầu vào giọng nói (STT) | ✅ Hoạt động | Deepgram, nhiều mô hình |
| Tạo phản hồi AI (Ollama) | ✅ Hoạt động | Local, offline |
| Tạo phản hồi AI (Gemini) | ✅ Hoạt động | Cloud, có thể thay đổi động |
| Chuyển văn bản thành giọng | ✅ Hoạt động | 8 giọng nói, điều chỉnh tốc độ |
| Console operator | ✅ Hoạt động | 3 cột, responsive |
| Điều khiển mic | ✅ Hoạt động | HTTP trực tiếp |
| Preset Q&A | ✅ Hoạt động | JSON-based |
| Transcript real-time | ✅ Hoạt động | WebSocket + polling |
| Trạng thái cảm xúc | ✅ Hoạt động | idle, speaking, error |
| System logs | ✅ Hoạt động | Broadcast qua WebSocket |
| Mở rộng transcript | ✅ Hoạt động | 12rem cố định + modal |
| Nút xóa xem trước | ✅ Hoạt động | Xóa tất cả input |

---

## 🛑 Hạn Chế & Nâng Cấp Tương Lai

### Hạn Chế Hiện Tại
1. **Trạng Thái**: Globals in-memory (mất khi restart)
2. **Một Robot**: Một robot mỗi session
3. **Không Lưu**: Transcripts không lưu DB
4. **Endpoints Không Dùng**: `/robot/mic-status` (mã chết), `/robot/mic-done` (không dùng)
5. **Dịch Vụ Không Dùng**: `chat_orchestrator`, `semantic_router`, `memory_service` có nhưng không dùng

### Nâng Cấp Tương Lai
- [ ] PostgreSQL cho persistence
- [ ] Hỗ trợ multi-robot
- [ ] Advanced intent routing (semantic_router)
- [ ] Lưu trữ conversation memory
- [ ] Subtitle phụ đề live
- [ ] Dashboard analytics
- [ ] UI operator mobile
- [ ] Fine-tune LLM custom
- [ ] Mức độ cảm xúc (không chỉ 3 trạng thái)

---

## 📊 Hiệu Năng

| Hoạt Động | Thời Gian | Bottleneck |
|----------|-----------|-----------|
| STT (Deepgram) | 2-5s | Network |
| Local LLM (Ollama) | 5-15s | Inference |
| Cloud LLM (Gemini) | 3-8s | Network + API |
| TTS (Google Cloud) | 2-4s | Network + synthesis |
| WebSocket broadcast | <100ms | I/O |

**Mẹo Tối Ưu**:
- `nova-2` STT nhanh, `whisper-large` chính xác
- `gemini-2.0-flash` nhanh nhất, `1.5-pro` mạnh nhất
- Điều chỉnh tốc độ TTS nếu cần (mặc định 1.0x)
- Kiểm soát resource Ollama trên device robot

---

## 💬 Quy Trình Ví Dụ

### Quy Trình 1: Operator gửi phản hồi tới robot
```
1. Operator bấm "AI (Ollama)" hoặc chọn preset
2. Operator bấm "GỬI ĐẾN ROBOT"
3. Giao Diện POST tới /send-to-robot {text, emotion}
4. Backend lưu lệnh trong _latest_robot_command
5. Backend POST trực tiếp tới Robot:9000/command
6. Robot app nhận POST /command, chiết xuất {text, emotion}
7. Robot app chuyển text→speech qua TTS
8. Robot app phát audio trên loa
9. Robot app cập nhật hiển thị cảm xúc/text
10. Robot app POST /robot/mic-sync báo trạng thái lại
```

### Quy Trình 2: Operator điều khiển mic robot
```
1. Operator bấm nút "BẬT MIC ROBOT"
2. Giao Diện POST tới /robot/mic-control {action: "start"}
3. Backend lưu _robot_mic_status = "listening"
4. Backend POST trực tiếp tới Robot:9000/mic {action: "start"}  ← TRỰC TIẾP
5. Robot app HTTP server nhận POST /mic
6. Robot app gọi handler onMicAction("start")
7. Robot app bắt đầu ghi âm từ microphone
8. (Sau) Operator bấm "TẮT MIC ROBOT"
9. Giao Diện POST tới /robot/mic-control {action: "stop"}
10. Backend POST tới Robot:9000/mic {action: "stop"}  ← TRỰC TIẾP
11. Robot app nhận lệnh dừng ghi âm
12. Robot app upload WAV tới POST /process-audio
13. Backend xử lý STT (Deepgram)
14. Backend broadcast transcript qua WebSocket cho operator
```

### Quy Trình 3: Robot báo trạng thái lại backend
```
1. Robot app trạng thái microphone thay đổi
2. Robot app POST /robot/mic-sync {status: "idle"}
3. Backend cập nhật _robot_mic_status = "idle"
4. Backend broadcast qua WebSocket cho operator
5. Giao Diện nhận cập nhật mic_status real-time
```

---

## 📁 Cấu Trúc File

```
S-SOCRATES/
├── README.md
├── operator-ui/
│   ├── index.html
│   ├── style.css
│   ├── script.js
│   └── assets/
│
├── S-SOCRATES-BE/
│   ├── main.py
│   ├── requirements.txt
│   ├── qa_presets.json
│   ├── memory.json
│   ├── knowledge/
│   │   └── uth.txt
│   ├── services/
│   │   ├── stt_service.py
│   │   ├── tts_service.py
│   │   ├── llm_service.py
│   │   └── ...
│   └── utils/
│       └── logger.py
│
└── S-SOCRATES-APP/
    └── voice_chat_app/
        ├── pubspec.yaml
        ├── lib/
        ├── android/
        ├── ios/
        ├── windows/
        └── test/
```

---

## 🐛 Khắc Phục Sự Cố

### Backend không khởi động
```bash
# Kiểm tra port 8000
netstat -ano | findstr :8000

# Kiểm tra phiên bản Python (phải 3.10+)
python --version

# Kiểm tra .env tồn tại
type .env
```

### Giao Diện không kết nối
- Kiểm tra backend chạy trên :8000
- Mở console trình duyệt (F12) kiểm tra lỗi WebSocket
- Xác minh ROBOT_CONTROL_URL trong .env (backend cần kết nối tới robot)
- Thử trực tiếp: http://localhost:8000/operator

### Robot app không nhận lệnh
- Đảm bảo robot app chạy (HTTP server port 9000 hoạt động)
- Kiểm tra ROBOT_CONTROL_URL trong .env backend khớp robot IP:9000
- Xác minh robot app có `RobotControlServer` khởi động trong `main.dart`
- Kiểm tra firewall cho phép backend → robot network
- Thử curl trực tiếp: `curl http://ROBOT_IP:9000/health`

### Deepgram STT trả về rỗng
- Xác minh file WAV hợp lệ (không bị hỏng)
- Kiểm tra DEEPGRAM_API_KEY trong .env đúng
- Thử mô hình khác (nova-2-general, whisper-large)
- Xác minh mã ngôn ngữ đúng (vi, en, etc.)

### Gemini LLM không phản hồi
- Kiểm tra GEMINI_API_KEY trong .env hợp lệ và không bị thu hồi
- Xác minh tên mô hình qua `/configs` endpoint
- Đảm bảo `knowledge/uth.txt` không rỗng
- Kiểm tra quota API không vượt
- Thử thay đổi mô hình qua `/configs` endpoint

---

## 📞 Hỗ Trợ

**Tài Liệu API**:
- Swagger UI: http://localhost:8000/docs
- OpenAPI JSON: http://localhost:8000/openapi.json

**Debug**:
```python
# Trong main.py
import logging
logging.basicConfig(level=logging.DEBUG)
```

**Kiểm Tra Sức Khỏe**:
```bash
curl http://localhost:8000/
curl http://localhost:8000/qa-presets
curl http://localhost:8000/configs
```

---

## 📄 Ghi Công

**Dự Án**: S-SOCRATES AI Debate System  
**Tổ Chức**: Trường Đại Học Giao Thông Vận Tải TP.HCM (UTH)  
**Mục Đích**: Giáo Dục & Nghiên Cứu

---

**Cập Nhật Lần Cuối**: 2026-04-02  
**Trạng Thái**: Sẵn Sàng Sản Xuất  
**Phiên Bản**: 1.0
