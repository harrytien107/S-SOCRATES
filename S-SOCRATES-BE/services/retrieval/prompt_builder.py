from __future__ import annotations


def _trim_text(value: str, max_chars: int) -> str:
    normalized = (value or "").strip()
    if len(normalized) <= max_chars:
        return normalized
    return normalized[: max_chars - 3].rstrip() + "..."


def build_rag_prompt(
    *,
    system_prompt: str,
    history_context: str,
    retrieved_chunks: list[dict],
    user_message: str,
) -> str:
    context_lines = []
    for idx, item in enumerate(retrieved_chunks[:3], start=1):
        source = item.get("source", "unknown")
        chunk_type = item.get("type", "knowledge")
        score = item.get("score", 0.0)
        text = _trim_text(item.get("text", ""), max_chars=650)
        context_lines.append(
            f"[Nguon {idx} | type={chunk_type} | source={source} | score={score:.3f}]\n{text}"
        )

    retrieved_context = "\n\n".join(context_lines) if context_lines else "Khong co tri thuc bo sung."
    history_block = _trim_text(history_context or "Chua co lich su hoi thoai.", max_chars=1200)

    return f"""{system_prompt}

{history_block}

Tri thuc lien quan:
{retrieved_context}

Cau hoi hien tai:
{user_message}

Yeu cau tra loi:
- Uu tien cao nhat tri thuc tu uth.txt va cac chunk knowledge goc cua truong.
- Chi dung qa_presets.json nhu tai lieu tham khao bo sung, khong de no ghi de thong tin trong uth.txt.
- Neu uth.txt va qa_presets co ve mau thuan, hay theo uth.txt.
- Neu tri thuc khong du, tra loi than trong va khong che tao su that.
- Giu giong dieu S-SOCRATES phu hop cho talkshow UTH.
"""
