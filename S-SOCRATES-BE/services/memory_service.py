import json
import shutil
from pathlib import Path

from utils.logger import log

BASE_DIR = Path(__file__).resolve().parent.parent
DEFAULT_MEMORY_PATH = BASE_DIR / "memory.json"

class MemoryService:
    def __init__(self, filepath=DEFAULT_MEMORY_PATH):
        path = Path(filepath)
        if not path.is_absolute():
            path = BASE_DIR / path
        self.filepath = path
        self.history = self.load()

    def load(self):
        if not self.filepath.exists():
            return []
        try:
            with self.filepath.open("r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            # Nếu User tự viết JSON bị sai dấu phẩy, không được XÓA file của họ!
            # Quăng file lỗi sang một bản backup để họ xem lại
            backup_path = self.filepath.with_name(f"{self.filepath.name}.backup")
            created_backup = False
            try:
                shutil.copy2(self.filepath, backup_path)
                created_backup = True
            except Exception as backup_error:
                log.warning("Không thể tạo bản sao lưu memory.json: %s", backup_error)
            log.error("LỖI CÚ PHÁP TRONG memory.json: %s", e)
            if created_backup:
                log.warning("Đã tạo bản sao lưu tại %s", backup_path)
            return []

    def save(self, user_msg: str, ai_msg: str):
        self.history.append({
            "user": user_msg,
            "ai": ai_msg
        })
        
        # Không tự động xóa data của User trong file JSON nữa
        # Cứ lưu vô hạn để làm bằng chứng/nhật ký nguyên bản
        self.filepath.parent.mkdir(parents=True, exist_ok=True)
        with self.filepath.open("w", encoding="utf-8") as f:
            json.dump(self.history, f, ensure_ascii=False, indent=4)

    @staticmethod
    def _truncate_text(text: str, max_chars: int | None) -> str:
        if max_chars is None or max_chars <= 0:
            return text
        if len(text) <= max_chars:
            return text
        return text[: max_chars - 1].rstrip() + "..."

    def get_context_string(
        self,
        seed_turns: int = 15,
        recent_turns: int = 6,
        max_turn_chars: int | None = None,
        max_total_chars: int | None = None,
        include_ai: bool = True,
    ) -> str:
        if not self.history:
            return ""
        context = "Lịch sử trò chuyện trước đó:\n"
        
        # CHIẾN THUẬT RẤT HAY CỦA USER: "Tâm lý học mồi" (Few-Shot Anchoring)
        # Giữ vĩnh viễn 15 câu mẫu đầu tiên để AI học cách nói chuyện và lập trường
        # + Cộng thêm 6 câu trò chuyện thật mới nhất để tạo mạch ngữ cảnh
        
        seed_turns = max(0, int(seed_turns))
        recent_turns = max(0, int(recent_turns))
        target_turn_count = seed_turns + recent_turns

        if target_turn_count <= 0:
            return ""

        if len(self.history) <= target_turn_count:
            selected_history = self.history
        else:
            selected_history = []
            if seed_turns:
                selected_history.extend(self.history[:seed_turns])
            if recent_turns:
                selected_history.extend(self.history[-recent_turns:])

        emitted_chars = 0
        
        for turn in selected_history:
            # Xử lý an toàn nhỡ User tự gõ sai Key
            u = self._truncate_text(turn.get("user", ""), max_turn_chars)
            a = self._truncate_text(turn.get("ai", ""), max_turn_chars)
            if include_ai:
                chunk = f"User: {u}\nAI: {a}\n\n"
            else:
                chunk = f"User: {u}\n\n"

            if max_total_chars and max_total_chars > 0:
                next_size = emitted_chars + len(chunk)
                if next_size > max_total_chars:
                    remaining = max_total_chars - emitted_chars
                    if remaining <= 0:
                        break
                    context += chunk[:remaining]
                    break

            context += chunk
            emitted_chars += len(chunk)
        return context

memory_service = MemoryService()