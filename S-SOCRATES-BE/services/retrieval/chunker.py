from __future__ import annotations


def chunk_text(text: str, chunk_size: int = 700, overlap: int = 120) -> list[str]:
    normalized = " ".join((text or "").split())
    if not normalized:
        return []

    if chunk_size <= overlap:
        raise ValueError("chunk_size must be larger than overlap")

    chunks: list[str] = []
    start = 0
    step = chunk_size - overlap
    while start < len(normalized):
        end = min(len(normalized), start + chunk_size)
        chunk = normalized[start:end].strip()
        if chunk:
            chunks.append(chunk)
        start += step
    return chunks

