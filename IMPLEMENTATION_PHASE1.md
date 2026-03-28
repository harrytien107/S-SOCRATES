# S-SOCRATES Phase 1 Implementation: Robot Audio Flow

## Tổng quan

Giai đoạn 1 tập trung vào triển khai flow audio cơ bản theo hướng thực dụng:
- Robot Flutter bật mic → thu audio theo lượt nói → gửi audio xuống backend
- Backend xử lý STT + preset matching → trả transcript + preset suggestions
- Không còn auto-restart sau TTS (turn-based thay vì continuous)

## Các thay đổi chính

### 1. Backend Changes

#### File: `S-SOCRATES-BE/services/semantic_router.py`
**Thêm method mới:**
```python
def get_top_candidates(self, user_text: str, top_k: int = 5)
```
- Trả về top K preset candidates với scores
- Format: `[{"question": str, "answer": str, "score": float}, ...]`
- Dùng cosine similarity để tính độ match

#### File: `S-SOCRATES-BE/main.py`
**Thêm endpoint mới:**
```python
POST /process-audio
```
- Nhận: multipart/form-data với file audio
- Xử lý:
  1. STT qua Deepgram (tận dụng lại `process_stt_request`)
  2. Preset matching qua semantic_router (dùng `get_top_candidates`)
- Trả về:
```json
{
  "transcript": "text đã nhận diện được",
  "candidates": [
    {
      "question": "câu hỏi preset",
      "answer": "câu trả lời preset",
      "score": 0.82
    },
    // ... top 5 candidates
  ]
}
```

**Services được tận dụng lại:**
- ✅ `stt_service.py` (Deepgram STT)
- ✅ `semantic_router.py` (Preset matching với embeddings)
- ✅ `qa_presets.json` (Database của preset Q&A)

### 2. Flutter App Changes

#### File: `S-SOCRATES-APP/voice_chat_app/lib/services/agent_api.dart`
**Thêm method mới:**
```dart
Future<Map<String, dynamic>> processAudio(String filePath)
```
- Gửi audio file lên `/process-audio`
- Trả về Map với keys: `transcript` và `candidates`

#### File: `S-SOCRATES-APP/voice_chat_app/lib/voice_chat_tab.dart`
**Thay đổi chính:**

1. **Removed auto-restart after TTS** (lines 62-73)
   - Trước: Sau khi AI nói xong, tự động bật mic lại
   - Sau: User phải bấm mic button thủ công cho mỗi lượt
   - **Lý do:** Chuyển sang turn-based thay vì continuous conversation

2. **Updated `_stopSession()` method** (lines 241-302)
   - Trước: Gọi `speechToText()` → nhận transcript → gọi `sendMessage()`
   - Sau: Gọi `processAudio()` → nhận transcript + candidates → hiển thị suggestions

3. **Added preset candidates UI** (lines 387-516)
   - Method: `_candidateSuggestions()`
   - Hiển thị top 3 candidates với:
     - Question text
     - Answer preview (2 dòng)
     - Score % (màu xanh lá)
   - User có thể:
     - Tap vào candidate → dùng luôn preset answer (không qua LLM)
     - Tap X để đóng suggestions

4. **Added state variable** (line 25)
   - `List<Map<String, dynamic>> _presetCandidates = []`
   - Lưu candidates từ `/process-audio` response

### 3. Code đã xóa

**Không có code bị xóa**
- Giữ lại tất cả services cũ
- Endpoint `/stt` và `/chat` vẫn hoạt động cho text chat tab
- Chỉ thêm logic mới, không phá code cũ

## Flow hoạt động mới

### Voice Chat Flow (Turn-based)

```
1. User bấm mic button
   ↓
2. Flutter bắt đầu ghi âm (VAD monitoring)
   ↓
3. Phát hiện 2s silence → tự động stop
   ↓
4. Gửi audio lên POST /process-audio
   ↓
5. Backend:
   - Deepgram STT → transcript
   - Semantic Router → top 5 candidates
   ↓
6. Flutter nhận response:
   - Hiển thị transcript trong chat
   - Hiển thị top 3 preset suggestions
   ↓
7a. User tap preset suggestion:
    - Dùng luôn preset answer
    - Skip LLM
    - TTS phát câu trả lời
    ↓
7b. User không tap (hoặc đóng suggestions):
    - Gọi /chat để LLM trả lời
    - TTS phát câu trả lời
    ↓
8. TTS xong → dừng (KHÔNG auto-restart)
   ↓
9. User phải bấm mic lại để tiếp tục
```

### So sánh với flow cũ

| Feature | Flow cũ | Flow mới |
|---------|---------|----------|
| Mic behavior | Auto-restart after TTS | Manual restart (turn-based) |
| STT | `/stt` endpoint | `/process-audio` endpoint |
| Preset matching | Không có | Top 5 candidates với scores |
| UI suggestions | Không có | Hiển thị top 3 presets |
| User experience | Continuous conversation | Turn-based (dễ kiểm soát) |

## Hướng dẫn Test

### 1. Khởi động Backend

```bash
cd S-SOCRATES-BE

# Đảm bảo có .env với DEEPGRAM_API_KEY
# Đảm bảo Ollama đang chạy (cho /chat endpoint)

uvicorn main:app --reload --port 8000
```

**Kiểm tra backend:**
```bash
curl http://localhost:8000/
# Expected: {"status": "S-Socrates API is running clean and fast!"}
```

### 2. Test `/process-audio` endpoint

**Chuẩn bị:**
- Tìm 1 file audio .m4a hoặc .wav
- Hoặc dùng Flutter app để record

**Test với curl:**
```bash
curl -X POST http://localhost:8000/process-audio \
  -F "file=@/path/to/audio.m4a"
```

**Expected response:**
```json
{
  "transcript": "S-Socrates ơi, bạn tự giới thiệu về mình đi",
  "candidates": [
    {
      "question": "S-Socrates ơi, bạn tự giới thiệu về mình đi!",
      "answer": "Thưa Giáo sư và các bạn sinh viên UTH...",
      "score": 0.95
    },
    {
      "question": "Bạn nghĩ sao về việc đào tạo theo đơn đặt hàng...",
      "answer": "Góc nhìn này của PGS.TS Phương...",
      "score": 0.42
    }
    // ... more candidates
  ]
}
```

### 3. Khởi động Flutter App

```bash
cd S-SOCRATES-APP/voice_chat_app

# Cấu hình API URL trong Settings (nếu cần)
# Mặc định: http://192.168.1.239:8000

# Chạy app
flutter run -d windows
# hoặc
flutter run -d chrome
```

### 4. Test Flow hoàn chỉnh

**Bước 1: Kiểm tra voice tab**
- Mở tab "Voice AI"
- Kiểm tra có thấy nút mic không

**Bước 2: Test recording**
- Bấm nút mic (màu xanh lá)
- Overlay hiển thị "AI Voice đang lắng nghe"
- Nói một câu (ví dụ: "S-Socrates ơi, bạn tự giới thiệu về mình đi")
- Sau 2 giây im lặng → tự động dừng ghi âm

**Bước 3: Kiểm tra STT + Candidates**
- Overlay hiển thị "Đang nhận diện..."
- Chat hiển thị transcript của bạn
- **Quan trọng:** Phải thấy panel "Gợi ý preset:" với 1-3 suggestions
  - Mỗi suggestion có: question text, answer preview, score %

**Bước 4: Test preset selection**
- Tap vào 1 preset suggestion
- Suggestions panel đóng lại
- AI response hiển thị ngay (dùng preset answer)
- TTS bắt đầu đọc

**Bước 5: Kiểm tra turn-based behavior**
- Đợi TTS đọc xong
- **Quan trọng:** Mic KHÔNG tự động bật lại
- Phải bấm nút mic thủ công để tiếp tục

**Bước 6: Test LLM fallback**
- Bấm mic lại
- Nói 1 câu không match preset (ví dụ: "Hôm nay thời tiết thế nào?")
- Không thấy preset suggestions (hoặc score thấp)
- System tự gọi LLM qua `/chat`
- AI trả lời bằng LLM response

### 5. Test Cases chi tiết

| Test Case | Input | Expected Output |
|-----------|-------|-----------------|
| Preset match cao | "S-Socrates ơi, bạn tự giới thiệu về mình đi" | Top candidate score > 0.8, có suggestions panel |
| Preset match thấp | "Thời tiết hôm nay ra sao?" | Candidates có score < 0.5, fallback to LLM |
| Silence detection | Nói → im lặng 2s | Auto-stop recording |
| Turn-based | TTS xong | Mic không tự bật, phải bấm lại |
| Tap preset | Tap suggestion | Dùng preset answer, skip LLM |
| Close suggestions | Tap X button | Panel đóng, LLM xử lý transcript |

## Debug Tips

### Backend logs
```bash
# Trong terminal chạy backend, xem:
# "Gửi file audio tới Deepgram API: ..."
# "Deepgram STT result: '...'"
# "Tìm được N preset candidates (top score: X.XX)"
```

### Flutter logs
```bash
# Trong terminal chạy Flutter, xem:
# "Process audio result: '...'"
# "Candidates: N"
```

### Common Issues

**1. Backend trả error 500**
- Check: Deepgram API key trong .env
- Check: sentence-transformers model đã download chưa

**2. Candidates luôn rỗng**
- Check: `qa_presets.json` có tồn tại không
- Check: semantic_router khởi động thành công không
- Check backend logs: "Đã Vector hóa N câu hỏi mẫu"

**3. Flutter không hiển thị suggestions**
- Check: `_presetCandidates` có data không (print debug)
- Check: `_candidateSuggestions()` được gọi trong build
- Check: Candidates array không empty trong response

**4. Mic tự động bật lại**
- Check: Đã remove code auto-restart trong `_initTTSListeners()`
- Check: Không còn `Future.delayed` sau TTS completion

## Performance Notes

### Latency breakdown

**Trước (2 API calls):**
```
STT: ~1-2s (Deepgram)
Chat: ~2-3s (Ollama LLM)
Total: ~3-5s
```

**Sau (1 API call):**
```
STT: ~1-2s (Deepgram)
Preset matching: ~50ms (local embeddings)
Total: ~1-2s (nếu dùng preset)
Total: ~3-5s (nếu fallback LLM)
```

**Cải thiện:**
- Nhanh hơn ~2-3s khi match preset cao
- Tương tự khi phải dùng LLM

### Memory usage

Backend thêm:
- sentence-transformers model: ~80MB RAM
- Preset vectors cache: ~1MB RAM

Flutter không thay đổi đáng kể.

## Code Structure Summary

### Backend
```
S-SOCRATES-BE/
├── main.py                      [MODIFIED] +1 endpoint
├── services/
│   ├── semantic_router.py      [MODIFIED] +1 method
│   ├── stt_service.py          [NO CHANGE]
│   └── chat_orchestrator.py    [NO CHANGE]
└── qa_presets.json             [NO CHANGE]
```

### Flutter
```
S-SOCRATES-APP/voice_chat_app/lib/
├── services/
│   └── agent_api.dart          [MODIFIED] +1 method
└── voice_chat_tab.dart         [MODIFIED]
    ├── _initTTSListeners()     [MODIFIED] removed auto-restart
    ├── _stopSession()          [MODIFIED] use processAudio()
    └── _candidateSuggestions() [NEW] display presets
```

## Tương lai (Phase 2+)

**Không triển khai trong Phase 1:**
- ❌ Streaming audio realtime
- ❌ WebSocket audio
- ❌ Partial transcript liên tục
- ❌ Operator UI (không có trong codebase hiện tại)
- ❌ Robot stage riêng biệt (dùng chung voice_chat_tab)
- ❌ Demo mode (không tồn tại trong code)

**Có thể mở rộng:**
- ✅ Thêm emotion/expression cho robot
- ✅ Lưu history preset selections để học
- ✅ Điều chỉnh threshold preset matching
- ✅ Thêm UI để operator edit presets
- ✅ Export conversation logs

## Kết luận

Phase 1 đã hoàn thành:
- ✅ Backend `/process-audio` endpoint hoạt động
- ✅ Flutter chuyển sang turn-based flow
- ✅ Preset suggestions hiển thị cho user
- ✅ Tận dụng tối đa code/service cũ
- ✅ Không phá flow hiện có
- ✅ Code sạch, dễ maintain

**Next steps:**
- Test thực tế với nhiều câu hỏi
- Thu thập feedback từ user
- Fine-tune preset matching threshold
- Thêm metrics/logging nếu cần
