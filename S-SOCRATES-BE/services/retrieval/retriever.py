from __future__ import annotations

import json
import threading
from pathlib import Path

from services.retrieval.chunker import chunk_text
from services.retrieval.embedder import embedding_service
from services.retrieval.quantized_store import QuantizedVectorStore
from utils.logger import log


BASE_DIR = Path(__file__).resolve().parent.parent.parent
DATA_DIR = BASE_DIR / "data"
KNOWLEDGE_DIR = BASE_DIR / "knowledge"
QA_PRESETS_PATH = BASE_DIR / "qa_presets.json"
VECTOR_PATH = DATA_DIR / "rag_vectors_uint8.npz"
META_PATH = DATA_DIR / "rag_meta.json"


def _source_priority_bonus(item: dict) -> float:
    source = (item.get("source") or "").lower()
    chunk_type = (item.get("type") or "").lower()

    if source == "uth.txt":
        return 0.18
    if chunk_type == "knowledge":
        return 0.05
    if chunk_type == "preset":
        return -0.04
    return 0.0


def _load_qa_presets() -> list[dict]:
    if not QA_PRESETS_PATH.exists():
        return []
    try:
        return json.loads(QA_PRESETS_PATH.read_text(encoding="utf-8"))
    except Exception as exc:
        log.warning("Failed to load QA presets for retrieval: %s", exc)
        return []


def build_corpus(chunk_size: int = 700, overlap: int = 120) -> list[dict]:
    corpus: list[dict] = []

    for path in sorted(KNOWLEDGE_DIR.glob("*.txt")):
        text = path.read_text(encoding="utf-8")
        for idx, chunk in enumerate(chunk_text(text, chunk_size=chunk_size, overlap=overlap)):
            corpus.append(
                {
                    "id": f"{path.stem}-chunk-{idx}",
                    "source": path.name,
                    "type": "knowledge",
                    "text": chunk,
                }
            )

    for idx, item in enumerate(_load_qa_presets()):
        question = (item.get("question") or "").strip()
        answer = (item.get("answer") or "").strip()
        if not question or not answer:
            continue
        corpus.append(
            {
                "id": f"qa-preset-{idx}",
                "source": "qa_presets.json",
                "type": "preset",
                "text": f"Cau hoi mau: {question}\nTra loi mau: {answer}",
            }
        )

    return corpus


def build_quantized_store() -> QuantizedVectorStore:
    corpus = build_corpus()
    if not corpus:
        raise RuntimeError("No retrieval corpus found in knowledge/ or qa_presets.json")
    vectors = embedding_service.encode([item["text"] for item in corpus])
    store = QuantizedVectorStore.from_float_vectors(vectors, corpus)
    store.save(VECTOR_PATH, META_PATH)
    log.info(
        "Quantized retrieval store built: chunks=%s dims=%s path=%s",
        len(corpus),
        vectors.shape[1],
        VECTOR_PATH,
    )
    return store


class QuantizedRetriever:
    def __init__(self):
        self._lock = threading.RLock()
        self._store: QuantizedVectorStore | None = None

    def initialize(self, force_rebuild: bool = False) -> None:
        with self._lock:
            if force_rebuild or not VECTOR_PATH.exists() or not META_PATH.exists():
                self._store = build_quantized_store()
                return
            if self._store is None:
                self._store = QuantizedVectorStore.load(VECTOR_PATH, META_PATH)
                log.info(
                    "Quantized retrieval store loaded: vectors=%s path=%s",
                    len(self._store.metadata),
                    VECTOR_PATH,
                )

    def search(self, query: str, top_k: int = 4, rerank_k: int = 12) -> list[dict]:
        normalized = (query or "").strip()
        if not normalized:
            return []
        with self._lock:
            if self._store is None:
                self.initialize()
            assert self._store is not None
            query_vec = embedding_service.encode([normalized])[0]
            raw_results = self._store.search(
                query_vec,
                top_k=max(top_k * 3, top_k + 4),
                rerank_k=max(rerank_k, top_k * 4),
            )
            for item in raw_results:
                item["base_score"] = float(item.get("score", 0.0))
                item["score"] = item["base_score"] + _source_priority_bonus(item)
            raw_results.sort(key=lambda item: item["score"], reverse=True)
            return raw_results[:top_k]

    def stats(self) -> dict:
        with self._lock:
            if self._store is None:
                self.initialize()
            assert self._store is not None
            vector_count = len(self._store.metadata)
            dim = int(self._store.vectors_uint8.shape[1])
            compressed_bytes = int(self._store.vectors_uint8.nbytes)
            float32_bytes = vector_count * dim * 4
            memory_saved_ratio = 0.0
            if float32_bytes > 0:
                memory_saved_ratio = 1.0 - (compressed_bytes / float32_bytes)
            return {
                "vector_count": vector_count,
                "dimension": dim,
                "compressed_bytes": compressed_bytes,
                "float32_bytes": float32_bytes,
                "memory_saved_ratio": memory_saved_ratio,
                "vector_path": str(VECTOR_PATH),
                "meta_path": str(META_PATH),
            }


retriever = QuantizedRetriever()
