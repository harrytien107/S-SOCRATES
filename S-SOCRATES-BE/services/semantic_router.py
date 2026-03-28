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
            
    def get_top_matches(self, user_text: str, top_k: int = 3):
        if not self.model or not self.preset_qs or len(self.preset_vectors) == 0:
            return []
            
        # Vectorize input
        user_vector = self.model.encode([user_text])[0]
        
        # Calculate Cosine Similarity
        dots = np.dot(self.preset_vectors, user_vector)
        norms_presets = np.linalg.norm(self.preset_vectors, axis=1)
        norm_user = np.linalg.norm(user_vector)
        
        if norm_user == 0:
            return []
            
        similarities = dots / (norms_presets * norm_user)
        
        # Get top K
        top_indices = np.argsort(similarities)[::-1][:top_k]
        
        results = []
        for idx in top_indices:
            results.append({
                "question": self.preset_qs[idx],
                "answer": self.preset_as[idx],
                "score": float(similarities[idx])
            })
        return results

    def get_best_match(self, user_text: str, threshold: float = 0.75):
        # ... (existing code or simplified)
        matches = self.get_top_matches(user_text, top_k=1)
        if matches and matches[0]["score"] >= threshold:
            return matches[0]["answer"]
        return None

semantic_router = SemanticRouter()