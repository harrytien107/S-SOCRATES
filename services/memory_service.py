import json
import os
import shutil

class MemoryService:
    def __init__(self, filepath="memory.json"):
        self.filepath = filepath
        self.history = self.load()

    def load(self):
        if not os.path.exists(self.filepath):
            return []
        try:
            with open(self.filepath, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            # Nếu User tự viết JSON bị sai dấu phẩy, không được XÓA file của họ!
            # Quăng file lỗi sang một bản backup để họ xem lại
            backup_path = self.filepath + ".backup"
            shutil.copy2(self.filepath, backup_path)
            print(f"[MEMORY_SERVICE] LỖI CÚ PHÁP TRONG memory.json: {e}")
            print(f"[MEMORY_SERVICE] Đã tạo bản sao lưu tại {backup_path}")
            return []

    def save(self, user_msg: str, ai_msg: str):
        self.history.append({
            "user": user_msg,
            "ai": ai_msg
        })
        
        # Không tự động xóa data của User trong file JSON nữa
        # Cứ lưu vô hạn để làm bằng chứng/nhật ký nguyên bản
        with open(self.filepath, "w", encoding="utf-8") as f:
            json.dump(self.history, f, ensure_ascii=False, indent=4)

    def get_context_string(self) -> str:
        if not self.history:
            return ""
        context = "Lịch sử trò chuyện trước đó:\n"
        
        # CHIẾN THUẬT RẤT HAY CỦA USER: "Tâm lý học mồi" (Few-Shot Anchoring)
        # Giữ vĩnh viễn 15 câu mẫu đầu tiên để AI học cách nói chuyện và lập trường
        # + Cộng thêm 6 câu trò chuyện thật mới nhất để tạo mạch ngữ cảnh
        
        if len(self.history) <= 21:
            selected_history = self.history
        else:
            # 15 cái mẫu giả đầu tiên + 6 cái thật mới mẻ nhất (Bỏ phần giữa đi)
            selected_history = self.history[:15] + self.history[-6:]
        
        for turn in selected_history:
            # Xử lý an toàn nhỡ User tự gõ sai Key
            u = turn.get("user", "")
            a = turn.get("ai", "")
            context += f"User: {u}\nAI: {a}\n\n"
        return context

memory_service = MemoryService()