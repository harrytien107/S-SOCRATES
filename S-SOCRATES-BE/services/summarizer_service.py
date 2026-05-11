"""Conversation summarization service.

Maintains a rolling summary of older chat turns in `memory_summary.json` so
S-Socrates can still "remember" past context even when recent raw history is
trimmed or cleared. Triggered asynchronously from `memory_service.save()`.

Flow:
    raw history (memory.json, full)
          |
          +--> last KEEP_RECENT_TURNS stays as raw context for the prompt
          |
          +--> everything older is gradually summarized into a single short
               Vietnamese paragraph stored in memory_summary.json

If the Gemini API is configured, summarization prefers Gemini Flash (cheap,
fast). Otherwise it falls back to the local TurboQuant runtime, but with a
tight token budget so it does not compete much with live chat replies.
"""

from __future__ import annotations

import json
import os
import threading
import time
from pathlib import Path
from typing import Any, Optional

from dotenv import load_dotenv

from services.prompt_config import BASE_DIR
from utils.logger import log


ENV_PATH = BASE_DIR / ".env"
load_dotenv(dotenv_path=ENV_PATH, override=True)


DEFAULT_SUMMARY_PATH = Path(__file__).resolve().parent.parent / "memory_summary.json"


def _read_bool_env(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _read_int_env(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


SUMMARY_ENABLED = _read_bool_env("MEMORY_SUMMARY_ENABLED", True)
# Always keep the last N turns raw (never summarized) so the prompt has recent context.
KEEP_RECENT_TURNS = _read_int_env("MEMORY_SUMMARY_KEEP_RECENT", 4)
# Summarize as soon as this many turns are waiting beyond the "keep recent" window.
SUMMARY_BATCH = _read_int_env("MEMORY_SUMMARY_BATCH", 6)
# Target length for the rolling summary (characters).
SUMMARY_MAX_CHARS = _read_int_env("MEMORY_SUMMARY_MAX_CHARS", 600)


_SUMMARY_PROMPT_TEMPLATE = """Bạn là bộ tóm tắt hội thoại cho S-Socrates (AI phản biện của talkshow UTH).
Nhiệm vụ: gộp TÓM TẮT HIỆN TẠI với các LƯỢT MỚI bên dưới thành MỘT đoạn tiếng Việt có dấu, 3-5 câu, tối đa {max_chars} ký tự.

YÊU CẦU:
- Giữ lại chủ đề chính, tên riêng, các câu hỏi nổi bật mà người dùng đã nêu.
- Không thêm câu hỏi mới, không thêm nhận xét, không dùng bullet.
- Không xưng "em/thầy", viết ở ngôi thứ ba ngắn gọn (ví dụ: "Người dùng hỏi về ...", "S-Socrates phản biện rằng ...").
- Chỉ output đoạn tóm tắt, KHÔNG thêm tiêu đề hay tiền tố.

TÓM TẮT HIỆN TẠI (có thể rỗng):
{old_summary}

CÁC LƯỢT MỚI CẦN GỘP:
{new_turns}

TÓM TẮT MỚI:"""


def _format_turns(turns: list[dict]) -> str:
    lines: list[str] = []
    for idx, turn in enumerate(turns, start=1):
        user_text = (turn.get("user") or "").strip()
        ai_text = (turn.get("ai") or "").strip()
        if not user_text and not ai_text:
            continue
        lines.append(f"[{idx}] User: {user_text}")
        if ai_text:
            lines.append(f"    S-Socrates: {ai_text}")
    return "\n".join(lines)


def _trim(text: str, max_chars: int) -> str:
    normalized = (text or "").strip()
    if len(normalized) <= max_chars:
        return normalized
    return normalized[: max_chars - 3].rstrip() + "..."


class SummarizerService:
    """Async-friendly rolling conversation summarizer."""

    def __init__(self, filepath: str | Path = DEFAULT_SUMMARY_PATH) -> None:
        self.filepath = Path(filepath)
        self._lock = threading.Lock()
        self._job_lock = threading.Lock()
        self._running_job: Optional[threading.Thread] = None
        self._summary: str = ""
        self._summarized_up_to: int = 0
        self._updated_at: Optional[float] = None
        self._load()

    def _load(self) -> None:
        if not self.filepath.exists():
            return
        try:
            with self.filepath.open("r", encoding="utf-8") as fh:
                payload = json.load(fh)
            self._summary = str(payload.get("summary") or "").strip()
            self._summarized_up_to = int(payload.get("summarized_up_to", 0))
            self._updated_at = payload.get("updated_at")
        except Exception as exc:
            log.warning("Failed to load %s: %s", self.filepath, exc)

    def _save(self) -> None:
        payload = {
            "summary": self._summary,
            "summarized_up_to": self._summarized_up_to,
            "updated_at": self._updated_at,
        }
        try:
            with self.filepath.open("w", encoding="utf-8") as fh:
                json.dump(payload, fh, ensure_ascii=False, indent=2)
        except Exception as exc:
            log.warning("Failed to write %s: %s", self.filepath, exc)

    def get_summary_text(self) -> str:
        with self._lock:
            return self._summary

    def get_status(self) -> dict[str, Any]:
        with self._lock:
            return {
                "enabled": SUMMARY_ENABLED,
                "summary": self._summary,
                "summary_length": len(self._summary),
                "summarized_up_to": self._summarized_up_to,
                "updated_at": self._updated_at,
                "batch": SUMMARY_BATCH,
                "keep_recent": KEEP_RECENT_TURNS,
                "max_chars": SUMMARY_MAX_CHARS,
                "path": str(self.filepath),
            }

    def clear(self) -> None:
        with self._lock:
            self._summary = ""
            self._summarized_up_to = 0
            self._updated_at = time.time()
            self._save()
        log.info("Conversation summary cleared.")

    def maybe_update_async(self, history: list[dict]) -> None:
        """Trigger a background summarization pass if thresholds are reached.

        Returns immediately so the caller (chat pipeline) is not blocked.
        """
        if not SUMMARY_ENABLED:
            return

        with self._lock:
            pending = max(0, len(history) - self._summarized_up_to - KEEP_RECENT_TURNS)
            if pending < SUMMARY_BATCH:
                return

            # Snapshot the turns we plan to fold into the summary.
            end_index = len(history) - KEEP_RECENT_TURNS
            new_turns = list(history[self._summarized_up_to:end_index])
            old_summary = self._summary
            old_up_to = self._summarized_up_to

        if not new_turns:
            return

        if not self._job_lock.acquire(blocking=False):
            # Another summarization is already running; skip this tick.
            return

        def _worker() -> None:
            try:
                new_summary = self._call_summarizer(old_summary, new_turns)
                if not new_summary:
                    log.info("Summarizer returned empty text; keeping previous summary.")
                    return
                with self._lock:
                    self._summary = _trim(new_summary, SUMMARY_MAX_CHARS)
                    self._summarized_up_to = old_up_to + len(new_turns)
                    self._updated_at = time.time()
                    self._save()
                log.info(
                    "Rolling summary updated: folded %d turns (up to index=%d, len=%d).",
                    len(new_turns),
                    self._summarized_up_to,
                    len(self._summary),
                )
            except Exception as exc:
                log.warning("Summarization failed: %s", exc)
            finally:
                self._job_lock.release()

        thread = threading.Thread(target=_worker, name="summarizer", daemon=True)
        self._running_job = thread
        thread.start()

    def _call_summarizer(self, old_summary: str, new_turns: list[dict]) -> str:
        new_turns_block = _format_turns(new_turns)
        if not new_turns_block:
            return old_summary

        prompt = _SUMMARY_PROMPT_TEMPLATE.format(
            max_chars=SUMMARY_MAX_CHARS,
            old_summary=old_summary.strip() or "(chưa có)",
            new_turns=new_turns_block,
        )

        # Prefer Gemini Flash when available: cheaper & faster, doesn't compete
        # with the local LLM that may be serving a live chat turn.
        text = self._try_gemini(prompt)
        if text:
            return text

        # Fallback: local TurboQuant runtime with a very short budget.
        return self._try_local(prompt)

    def _try_gemini(self, prompt: str) -> str:
        try:
            from services.gemini_service import gemini_service  # lazy to avoid cycles
        except Exception as exc:
            log.debug("Gemini not importable for summarization: %s", exc)
            return ""

        if getattr(gemini_service, "_llm", None) is None:
            return ""

        try:
            log.info("Summarizing via Gemini [%s]...", gemini_service.current_model)
            response = gemini_service._llm.complete(prompt)
            return str(getattr(response, "text", response) or "").strip()
        except Exception as exc:
            log.warning("Gemini summarizer call failed: %s", exc)
            return ""

    def _try_local(self, prompt: str) -> str:
        try:
            from llama_index.core.base.llms.types import ChatMessage, MessageRole
        except ImportError:
            try:
                from llama_index.core.llms import ChatMessage, MessageRole  # type: ignore
            except Exception as exc:
                log.warning("Cannot import llama-index ChatMessage: %s", exc)
                return ""

        try:
            from services.turboquant_runtime import turboquant_runtime
        except Exception as exc:
            log.debug("TurboQuant not importable for summarization: %s", exc)
            return ""

        if getattr(turboquant_runtime, "_llm", None) is None:
            return ""

        try:
            log.info("Summarizing via local TurboQuant fallback...")
            messages = [
                ChatMessage(
                    role=MessageRole.SYSTEM,
                    content="Bạn là bộ tóm tắt hội thoại tiếng Việt ngắn gọn, trung thực.",
                ),
                ChatMessage(role=MessageRole.USER, content=prompt),
            ]
            response = turboquant_runtime._llm.chat(messages)
            msg = getattr(response, "message", None)
            text = getattr(msg, "content", None) if msg is not None else None
            if text is None:
                text = str(response)
            return str(text).strip()
        except Exception as exc:
            log.warning("Local summarizer call failed: %s", exc)
            return ""


summarizer_service = SummarizerService()
