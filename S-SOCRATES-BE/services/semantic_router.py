import json
import os
import numpy as np
from utils.logger import log

PRESETS_FILE = "qa_presets.json"

class SemanticRouter:
    def __init__(self):
        try:
            from sentence_transformers import SentenceTransformer
            from huggingface_hub import snapshot_download
            
            try:
                # Đảm bảo Offline Native chống crash do mất mạng
                model_path = snapshot_download("sentence-transformers/all-MiniLM-L6-v2", local_files_only=True)
            except Exception:
                model_path = snapshot_download("sentence-transformers/all-MiniLM-L6-v2", local_files_only=False)
                
            self.model = SentenceTransformer(model_path)
            log.debug("Đã load SentenceTransformer cho QoS Semantic Router (Giao thức Offline Native).")
        except ImportError:
            self.model = None
            log.warning("Không tải được SentenceTransformer cho Semantic Router.")
            
        self.preset_qs = []
        self.preset_as = []
        self.preset_vectors = []
        self.reload_presets()
        
    def reload_presets(self):
        if not os.path.exists(PRESETS_FILE):
            self.preset_qs = []
            self.preset_as = []
            self.preset_vectors = []
            return
            
        try:
            with open(PRESETS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                
            new_qs = [item['question'] for item in data]
            # Nếu bộ câu hỏi mới khác bộ hiện tại thì vectorize lại để tối ưu
            if new_qs != self.preset_qs:
                self.preset_qs = new_qs
                self.preset_as = [item['answer'] for item in data]
                if self.model and self.preset_qs:
                    self.preset_vectors = self.model.encode(self.preset_qs)
                    log.info(f"Đã Vector hóa {len(self.preset_qs)} câu hỏi mẫu.")
        except Exception as e:
            log.error(f"Lỗi load presets router: {e}")
            
    def get_best_match(self, user_text: str, threshold: float = 0.75):
        if not self.model or not self.preset_qs or len(self.preset_vectors) == 0:
            return None

        # Vectorize input
        user_vector = self.model.encode([user_text])[0]

        # Calculate Cosine Similarity
        # Dot product / (norm(a) * norm(b))
        dots = np.dot(self.preset_vectors, user_vector)
        norms_presets = np.linalg.norm(self.preset_vectors, axis=1)
        norm_user = np.linalg.norm(user_vector)

        # Chống chia cho 0
        if norm_user == 0:
            return None

        similarities = dots / (norms_presets * norm_user)

        best_idx = np.argmax(similarities)
        best_score = similarities[best_idx]

        log.debug(f"Độ Semantic Match cao nhất: {best_score:.3f} (Câu: '{self.preset_qs[best_idx]}')")

        if best_score >= threshold:
            log.info(f"KHỚP VỚI CÂU MẪU (Độ chính xác: {best_score:.2f}) -> Bỏ qua AI, báo đáp án cứng!")
            return self.preset_as[best_idx]

        return None

    def get_top_candidates(self, user_text: str, top_k: int = 5):
        """
        Trả về top K preset candidates với scores.
        Returns: List[dict] với format {"question": str, "answer": str, "score": float}
        """
        if not self.model or not self.preset_qs or len(self.preset_vectors) == 0:
            return []

        # Vectorize input
        user_vector = self.model.encode([user_text])[0]

        # Calculate Cosine Similarity
        dots = np.dot(self.preset_vectors, user_vector)
        norms_presets = np.linalg.norm(self.preset_vectors, axis=1)
        norm_user = np.linalg.norm(user_vector)

        # Chống chia cho 0
        if norm_user == 0:
            return []

        similarities = dots / (norms_presets * norm_user)

        # Lấy top K indices theo score cao nhất
        top_indices = np.argsort(similarities)[::-1][:top_k]

        candidates = []
        for idx in top_indices:
            candidates.append({
                "question": self.preset_qs[idx],
                "answer": self.preset_as[idx],
                "score": float(similarities[idx])
            })

        log.info(f"Tìm được {len(candidates)} preset candidates (top score: {candidates[0]['score']:.2f})")
        return candidates

semantic_router = SemanticRouter()