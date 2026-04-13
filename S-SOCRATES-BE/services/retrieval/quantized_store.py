from __future__ import annotations

import json
from pathlib import Path

import numpy as np


class QuantizedVectorStore:
    def __init__(
        self,
        vectors_uint8: np.ndarray,
        mins: np.ndarray,
        scales: np.ndarray,
        metadata: list[dict],
    ):
        self.vectors_uint8 = vectors_uint8.astype(np.uint8, copy=False)
        self.mins = mins.astype(np.float32, copy=False)
        self.scales = scales.astype(np.float32, copy=False)
        self.metadata = metadata

    @classmethod
    def from_float_vectors(cls, vectors: np.ndarray, metadata: list[dict]):
        if vectors.ndim != 2 or len(vectors) == 0:
            raise ValueError("vectors must be a non-empty 2D array")
        mins = vectors.min(axis=0)
        maxs = vectors.max(axis=0)
        ranges = maxs - mins
        ranges[ranges < 1e-8] = 1e-8
        scales = ranges / 255.0
        quantized = np.clip(
            np.round((vectors - mins) / scales),
            0,
            255,
        ).astype(np.uint8)
        return cls(quantized, mins, scales, metadata)

    def quantize_query(self, query: np.ndarray) -> np.ndarray:
        return np.clip(
            np.round((query - self.mins) / self.scales),
            0,
            255,
        ).astype(np.uint8)

    def dequantize(self, indices: np.ndarray | None = None) -> np.ndarray:
        vectors = self.vectors_uint8 if indices is None else self.vectors_uint8[indices]
        restored = vectors.astype(np.float32) * self.scales + self.mins
        norms = np.linalg.norm(restored, axis=1, keepdims=True) + 1e-8
        return restored / norms

    def search(self, query: np.ndarray, top_k: int = 4, rerank_k: int = 12) -> list[dict]:
        if self.vectors_uint8.size == 0:
            return []

        query = query.astype(np.float32, copy=False).reshape(1, -1)
        q_uint8 = self.quantize_query(query)
        diff = self.vectors_uint8.astype(np.int16) - q_uint8.astype(np.int16)
        approx_scores = -np.sum(diff * diff, axis=1)

        rerank_k = max(top_k, min(rerank_k, len(approx_scores)))
        candidate_ids = np.argpartition(-approx_scores, rerank_k - 1)[:rerank_k]
        candidate_vectors = self.dequantize(candidate_ids)

        q_norm = query / (np.linalg.norm(query, axis=1, keepdims=True) + 1e-8)
        final_scores = candidate_vectors @ q_norm[0]
        ordered = np.argsort(-final_scores)[:top_k]

        results: list[dict] = []
        for idx in ordered:
            meta_index = int(candidate_ids[idx])
            item = dict(self.metadata[meta_index])
            item["score"] = float(final_scores[idx])
            results.append(item)
        return results

    def save(self, vector_path: str | Path, meta_path: str | Path) -> None:
        vector_path = Path(vector_path)
        meta_path = Path(meta_path)
        vector_path.parent.mkdir(parents=True, exist_ok=True)
        meta_path.parent.mkdir(parents=True, exist_ok=True)

        np.savez_compressed(
            vector_path,
            vectors_uint8=self.vectors_uint8,
            mins=self.mins,
            scales=self.scales,
        )
        meta_path.write_text(
            json.dumps(self.metadata, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    @classmethod
    def load(cls, vector_path: str | Path, meta_path: str | Path):
        vector_path = Path(vector_path)
        meta_path = Path(meta_path)
        payload = np.load(vector_path)
        metadata = json.loads(meta_path.read_text(encoding="utf-8"))
        return cls(
            vectors_uint8=payload["vectors_uint8"],
            mins=payload["mins"],
            scales=payload["scales"],
            metadata=metadata,
        )

