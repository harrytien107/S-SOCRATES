import json

class MemoryService:
    def __init__(self, filepath="memory.json"):
        self.filepath = filepath
        self.history = self.load()

    def load(self):
        try:
            with open(self.filepath, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []

    def save(self, user_msg: str, ai_msg: str):
        self.history.append({
            "user": user_msg,
            "ai": ai_msg
        })
        # Keep only the last 10 exchanges to prevent context bloat
        if len(self.history) > 10:
            self.history = self.history[-10:]
            
        with open(self.filepath, "w", encoding="utf-8") as f:
            json.dump(self.history, f, ensure_ascii=False, indent=2)

    def get_context_string(self) -> str:
        if not self.history:
            return ""
        context = "Lịch sử trò chuyện trước đó:\n"
        for idx, turn in enumerate(self.history[-5:]): # Only inject last 5 turns into prompt for speed
            context += f"User: {turn['user']}\nAI: {turn['ai']}\n\n"
        return context

memory_service = MemoryService()