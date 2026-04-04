import json
import shutil
from pathlib import Path

from utils.logger import log


BASE_DIR = Path(__file__).resolve().parent.parent
DEFAULT_MEMORY_PATH = BASE_DIR / "memory.json"


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
        self.history.append({"user": user_msg, "ai": ai_msg})

        with self.filepath.open("w", encoding="utf-8") as file:
            json.dump(self.history, file, ensure_ascii=False, indent=4)

    def get_context_string(self) -> str:
        if not self.history:
            return ""

        if len(self.history) <= 21:
            selected_history = self.history
        else:
            selected_history = self.history[:15] + self.history[-6:]

        context_lines = ["Lich su tro chuyen truoc day:"]
        for turn in selected_history:
            user_text = turn.get("user", "")
            ai_text = turn.get("ai", "")
            context_lines.append(f"User: {user_text}")
            context_lines.append(f"AI: {ai_text}")
            context_lines.append("")

        return "\n".join(context_lines).strip()


memory_service = MemoryService()
