import json
import shutil
import time
from pathlib import Path

from utils.logger import log


BASE_DIR = Path(__file__).resolve().parent.parent
DEFAULT_MEMORY_PATH = BASE_DIR / "memory.json"
DEFAULT_CONTEXT_TURNS = 4
DEFAULT_CONTEXT_CHARS = 1200
DEFAULT_RECONSTRUCTION_TURNS = 3
DEFAULT_RECONSTRUCTION_CHARS = 900


def _trim_text(value: str, max_chars: int) -> str:
    normalized = (value or "").strip()
    if len(normalized) <= max_chars:
        return normalized
    return normalized[: max_chars - 3].rstrip() + "..."


class MemoryService:
    def __init__(self, filepath: str | Path = DEFAULT_MEMORY_PATH):
        self.filepath = Path(filepath)
        self.history = self.load()

    def load(self) -> list[dict]:
        if not self.filepath.exists():
            return []

        try:
            with self.filepath.open("r", encoding="utf-8") as file:
                return json.load(file)
        except Exception as exc:
            backup_path = self.filepath.with_suffix(self.filepath.suffix + ".backup")
            shutil.copy2(self.filepath, backup_path)
            log.error("Failed to parse memory file %s: %s", self.filepath, exc)
            log.warning("Created memory backup at %s", backup_path)
            return []

    def save(self, user_msg: str, ai_msg: str) -> None:
        self.history.append(
            {
                "timestamp": time.time(),
                "user": user_msg,
                "ai": ai_msg,
            }
        )

        with self.filepath.open("w", encoding="utf-8") as file:
            json.dump(self.history, file, ensure_ascii=False, indent=4)

    def _select_recent_history(self, max_turns: int) -> list[dict]:
        if not self.history:
            return []
        return self.history[-max_turns:]

    def get_context_string(
        self,
        max_turns: int = DEFAULT_CONTEXT_TURNS,
        max_chars: int = DEFAULT_CONTEXT_CHARS,
    ) -> str:
        selected_history = self._select_recent_history(max_turns=max_turns)
        if not selected_history:
            return ""

        context_lines = ["Lich su tro chuyen truoc day:"]
        for turn in selected_history:
            user_text = _trim_text(turn.get("user", ""), max_chars=240)
            ai_text = _trim_text(turn.get("ai", ""), max_chars=320)
            context_lines.append(f"User: {user_text}")
            context_lines.append(f"AI: {ai_text}")
            context_lines.append("")

        return _trim_text("\n".join(context_lines).strip(), max_chars=max_chars)

    def build_reconstruction_prompt(
        self,
        max_turns: int = DEFAULT_RECONSTRUCTION_TURNS,
        max_chars: int = DEFAULT_RECONSTRUCTION_CHARS,
    ) -> str:
        selected_history = self._select_recent_history(max_turns=max_turns)
        if not selected_history:
            return ""

        context_lines = [
            "TOM TAT NGU CANH PHIEN HOI THOAI GAN DAY DE TAI TAO BO NHO NGU CANH:"
        ]
        for turn in selected_history:
            context_lines.append(f"User: {_trim_text(turn.get('user', ''), max_chars=180)}")
            context_lines.append(f"Assistant: {_trim_text(turn.get('ai', ''), max_chars=220)}")
        return _trim_text("\n".join(context_lines), max_chars=max_chars)


memory_service = MemoryService()
