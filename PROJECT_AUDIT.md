# S-SOCRATES Project Audit

> Ngày audit: 2026-04-23
> Scope: `D:\tailieuhoctap\S-Socrates\` (BE + APP + Operator UI)
> Mục tiêu: liệt kê thẳng thắn những gì đã xong, còn thiếu, và gợi ý tiếp theo để chuẩn bị talkshow.

---

## 1. Đã hoàn thành (không cần đụng)

- [x] Core pipeline: **Deepgram STT → RAG → LLM (Gemini/TurboQuant) → TTS → Flutter app + Operator UI**
- [x] TurboQuant local chạy `Meta-Llama-3.1-8B-Instruct-Q5_K_M.gguf` với:
  - Sampling đã fine-tune (`temperature=0.35`, `top_p=0.9`, `min_p=0.05` qua `extra_body`, `freq/presence penalty`)
  - Stop sequences Llama-3 (`<|eot_id|>`, `<|end_of_text|>`)
  - `_clean_llm_output` post-processor dedupe + cắt hallucinated follow-up turns
- [x] **Speculative decoding** với `Llama-3.2-1B-Instruct-Q4_K_M` (toggle qua `LOCAL_LLM_DRAFT_GGUF_PATH` - 8GB VRAM bật, 5GB VRAM để trống)
- [x] RAG quantized vector store, knowledge base gọn (chỉ `uth.txt` - factual, persona/rules đã tách sang `prompt_config.py`)
- [x] Operator UI: load saved settings khi boot và **tự apply không cần nhấn "Save & Connect"** (fix `_apply_audio_config` + `_activate_audio_config`)
- [x] **Conversation Summarization**: `summarizer_service.py` rolling summary, fold old turns khi > `KEEP_RECENT(4) + BATCH(6)` lượt, prefer Gemini Flash fallback local LLM, chạy background thread không block chat
- [x] `ROBOT_CONTROL_URL` đã dẹp sạch khỏi `.env`, `main.py`, UI, docs
- [x] WebSocket `/ws/operator` + `/ws/robot` với broadcast, reconnect, status monitoring
- [x] `.gitignore` đã bọc `memory.json`, `memory_summary.json`, `operator_settings.json`, `.env`, `Chathistory/`, `*.code-workspace`, `S-SOCRATES-BE/logs/`
- [x] Gemini giờ dùng `build_api_chat_messages` + `gemini_service.generate_chat()` (bỏ legacy single-string prompt)
- [x] Empty-response guard: log warning + fallback message `"Em cần thầy/cô nhắc lại câu hỏi giúp em, sóng em đang hơi lag."` khi local/Gemini trả rỗng sau post-processing
- [x] **Operator UI: "Reset Conversation"** button trong panel `Session Memory` (column 3) + checkbox chọn "wipe summary luôn hay không" + confirm dialog
- [x] **Operator UI: rolling summary panel** readonly, auto-poll 15s, hiển thị `turns · chars · updated_at`, có nút `↻ REFRESH` manual
- [x] **Log rotation**: `utils/logger.py` dùng `RotatingFileHandler` 10MB × 5 files, log file ghi vào `S-SOCRATES-BE/logs/app.log` (gitignored). Override qua env `LOG_DIR`, `LOG_FILE_MAX_BYTES`, `LOG_FILE_BACKUP_COUNT`
- [x] **Health endpoint `GET /healthz`**: trả `{gemini, turboquant, retrieval, robot_ws}` + block `details{}` kèm `deployment_mode`, `phase`, `vector_count`, `last_seen_ago_ms`. HTTP 200 nếu healthy, 503 nếu có thành phần bắt buộc down (bắt buộc phụ thuộc `DEPLOYMENT_MODE`)

---

## 2. Cần làm trước talkshow (P0)

- [ ] **End-to-end test pipeline với model + prompt mới**
  Chạy 5 câu mẫu verify không regression:
  - `"Tự giới thiệu về bản thân đi"` (không được lặp, không giả lập multi-turn)
  - `"Sinh viên UTH cần gì để không bị AI thay thế?"` (pressing đúng vibe)
  - `"Giải phương trình x² + 2x - 3 = 0"` (lái về talkshow)
  - `"AI ngu vãi, viết dở ẹc"` (giữ thái độ, xin feedback)
  - Câu hỏi dài → câu tiếp theo → câu tiếp theo (test summarization sau 10+ lượt)

- [ ] **Failover Gemini → local khi quota cạn**
  Scenario: Gemini 429 giữa talkshow. Verify `deployment_mode=hybrid` auto-switch, không để robot im.
  File cần check: `services/gemini_service.py` raise `RuntimeError` → `chat_orchestrator` có catch và retry local không?

- [ ] **Fallback message khi LLM fail/timeout**
  Hiện tại LLM fail → UI/robot có thể bị silent. Thêm 1 câu đỡ cố định:
  > `"Em cần giáo sư nhắc lại ạ, line em đang lag xíu."`
  Chỗ nên thêm: `try/except` trong `process_local_chat_message` và `process_api_chat_message`, trả câu fallback thay vì throw lên WebSocket.

---

## 3. Nên làm sớm (P1)

- [ ] **Pre-talkshow smoke test script** `scripts/smoke.py`
  Một lệnh verify trong 30 giây:
  - [ ] Deepgram API key hợp lệ (gọi 1 request ngắn)
  - [ ] Gemini API key + model có response
  - [ ] TurboQuant warmup OK
  - [ ] `/chat` trả text không rỗng
  - [ ] Retrieval search("UTH") có ≥1 chunk
  - [ ] WebSocket robot accept connect
  Mỗi bước in `[OK]` / `[FAIL]` màu. Hôm sự kiện chạy cái này xong mới mở được talkshow.

- [x] ~~**Operator UI: nút "Reset Conversation"**~~ — done. Panel `Session Memory` có button + checkbox "wipe summary luôn" + confirm dialog.
- [x] ~~**Operator UI: panel hiển thị rolling summary**~~ — done. Readonly panel auto-poll 15s, meta hiển thị `turns · chars · updated_at`.
- [x] ~~**Log rotation**~~ — done. `RotatingFileHandler` 10MB × 5 → `S-SOCRATES-BE/logs/app.log`.

---

## 4. Chất lượng đời sống (P2)

- [x] ~~**Health endpoint `/healthz`**~~ — done. `GET /healthz` → `{gemini, turboquant, retrieval, robot_ws, deployment_mode, details, status}`; 200 OK / 503 degraded.

- [ ] **Rate limit / debounce WebSocket**
  Nếu Operator spam mic button, flood server. Throttle 200ms client-side hoặc server-side.

- [ ] **TTS audio cache**
  Nếu AI hay chào cùng câu mở đầu, cache MP3 theo SHA1(text+voice+speed) trong `data/tts_cache/`. Giảm latency + đỡ tốn Google TTS quota.

- [ ] **Unit tests cơ bản (5 tests đủ dùng)**
  - `_clean_llm_output` với input multi-turn hallucinate
  - `_parse_history_turns` với format chuẩn và edge case
  - `summarizer_service.maybe_update_async` trigger condition (đủ/chưa đủ turns)
  - `retriever.search` trả đúng `top_k`
  - `_apply_audio_config` không crash khi payload thiếu field

---

## 5. Nice-to-have (P3, làm khi rảnh)

- [ ] **Port streaming STT/TTS từ `S-SOCRATES-dev`** (optional co-exist mode)
  User đã defer. Nếu muốn cut latency **~4s → ~1.5s** đây là bước lớn nhất.

- [ ] **Hybrid search BM25 + semantic**
  User đã defer. Đúng là chưa cần với knowledge nhỏ hiện tại. Mở rộng corpus > 50 docs thì mới bật.

- [ ] **Prompt A/B testing**
  Lưu `prompt_version` vào `memory.json` mỗi turn → so sánh chất lượng phản biện giữa các version prompt.

- [ ] **Export conversation log MD/PDF**
  `GET /memory/export?format=md` → sinh viên xem lại sau talkshow được.

---

## 6. Nợ kỹ thuật (đã xử lý)

Tất cả các món dưới đã được đóng trong các đợt cleanup gần đây:

| Trạng thái | Vấn đề cũ | Cách fix |
|---|---|---|
| ✅ Done | `Chathistory/` untracked | Thêm pattern `Chathistory/` vào `.gitignore` |
| ✅ Done | `S-Socrates.code-workspace` untracked | Thêm pattern `*.code-workspace` vào `.gitignore` |
| ✅ Done | `memory.json` vẫn tracked | `git rm --cached S-SOCRATES-BE/memory.json` |
| ✅ Done | `memory.json.backup` ở working tree | Xoá file |
| ✅ Done | Gemini còn dùng `build_api_rag_prompt` legacy | `gemini_service.generate_chat()` mới + `process_api_chat_message` đổi sang `build_api_chat_messages` |
| ✅ Done | `process_local_chat_message` im lặng khi LLM trả rỗng | Log warning + fallback `EMPTY_RESPONSE_FALLBACK` cho cả local + Gemini path |

---

## 7. Ý tưởng "sharp" cho talkshow (optional, cho vui)

- [ ] **Pressing timer**: đếm im lặng sau pressing, nếu > 8s AI tự chêm: `"Thầy đang over-think đúng không ạ?"` → tăng dramatic
- [ ] **Audience question routing**: operator gõ câu hỏi khán giả, push với flag `source=audience` → few-shot riêng "phản biện khán giả"
- [ ] **Mood meter**: operator tag `[cool]/[spicy]/[serious]` → chỉnh `temperature` runtime (0.25 / 0.5 / 0.35)
- [ ] **Stage LED sync**: robot blink LED khi `mic_status=listening` hoặc đang phát TTS → ăn rơ stage, không cần chạm tay

---

## 8. Đề xuất thứ tự triển khai

Nếu chỉ có ngân sách ~4 giờ trước talkshow:

1. ~~Nút Reset Conversation trong Operator UI (P1)~~ — ✅ done
2. ~~Log rotation (P1)~~ — ✅ done
3. ~~Cleanup kỹ thuật (mục 6)~~ — ✅ done
4. ~~Operator UI summary panel (P1)~~ — ✅ done
5. Smoke test script (P1) — **30 phút**, cứu nguy rủi ro live lớn nhất
6. Fallback message khi LLM fail (P0) — đã có cho Gemini/local; còn cần cho WebSocket bên Flutter app (cảnh báo "line lag" trên robot UI)
7. End-to-end test 5 câu mẫu (P0) — **30 phút**
8. Failover Gemini → local khi quota cạn (P0) — **15 phút**, thêm `try/except` trong `process_api_chat_message`

**Còn lại ~1.5 giờ** cho các P0 quan trọng. Pipeline đủ "production-ready" sau đó.

---

## 9. Checklist ngay trước khi lên sân khấu

- [ ] Chạy `scripts/smoke.py` → tất cả `[OK]`
- [ ] Kiểm tra `/configs` đúng `gemini_model` muốn dùng
- [ ] Memory reset (`DELETE /memory?keep_summary=false`)
- [ ] Operator UI kết nối được robot (xanh)
- [ ] Test 1 câu thật với mic → nghe được TTS từ robot
- [ ] GPU VRAM còn đủ (`nvidia-smi` - nếu > 7GB used thì tắt speculative)
- [ ] Battery laptop > 50% hoặc cắm điện
- [ ] Deepgram / Gemini quota còn

---

_Audit này là snapshot ngày **2026-04-23**. Cập nhật lại sau mỗi lần hoàn thành 1 tick hoặc phát hiện issue mới._
