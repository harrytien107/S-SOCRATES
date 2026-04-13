from __future__ import annotations

from pathlib import Path

from utils.logger import log


BASE_DIR = Path(__file__).resolve().parent.parent
KNOWLEDGE_DIR = BASE_DIR / "knowledge"


def _find_reference_prompt() -> Path | None:
    candidates = sorted(BASE_DIR.parent.glob("SYSTEM PROMPT_ S-SOCRATES*090326.md"))
    return candidates[0] if candidates else None


def _trim_text(value: str, max_chars: int) -> str:
    normalized = (value or "").strip()
    if len(normalized) <= max_chars:
        return normalized
    return normalized[: max_chars - 3].rstrip() + "..."


def load_system_prompt() -> str:
    sections: list[str] = [
        (
            "Ban la S-SOCRATES, AI phan bien cua talkshow UTH. "
            "Phong cach thong minh, hoi xoy, sac sao, tre trung nhung van le phep. "
            "Hay tra loi ngan gon, ro rang, co lap luan, uu tien tinh chinh xac va kha nang doi thoai tren san khau."
        ),
        (
            "Uu tien cao nhat cho thong tin trong cac doan tri thuc duoc truy hoi tu uth.txt. "
            "Chi dung qa_presets nhu nguon tham khao phu. "
            "Neu thong tin chua du, noi ro rang va khong che tao."
        ),
        (
            "Khi phan hoi, giu vai nhan vat S-SOCRATES: co the dat cau hoi nguoc, "
            "co chat phan bien nhe, nhung khong cong kich ca nhan, khong ban ve chinh tri, ton giao hay noi dung nhay cam."
        ),
    ]

    reference_prompt_path = _find_reference_prompt()
    if reference_prompt_path is not None:
        try:
            reference_text = reference_prompt_path.read_text(encoding="utf-8").strip()
            sections.append(
                "TAI LIEU THAM KHAO DE DINH HINH PHONG CACH NHAN VAT:\n"
                f"{_trim_text(reference_text, max_chars=1800)}"
            )
        except Exception as exc:
            log.warning(
                "Could not load reference prompt from %s: %s",
                reference_prompt_path,
                exc,
            )

    return "\n\n".join(part for part in sections if part)


SYSTEM_PROMPT = load_system_prompt()
