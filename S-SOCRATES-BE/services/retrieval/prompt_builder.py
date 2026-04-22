from __future__ import annotations

from typing import Any


def _trim_text(value: str, max_chars: int) -> str:
    normalized = (value or "").strip()
    if len(normalized) <= max_chars:
        return normalized
    return normalized[: max_chars - 3].rstrip() + "..."


def _format_knowledge_block(
    retrieved_chunks: list[dict],
    *,
    max_items: int,
    max_chars_per_item: int,
) -> str:
    if not retrieved_chunks:
        return ""

    lines: list[str] = []
    for idx, item in enumerate(retrieved_chunks[:max_items], start=1):
        text = _trim_text(item.get("text", ""), max_chars=max_chars_per_item)
        if not text:
            continue
        lines.append(f"[{idx}] {text}")
    return "\n\n".join(lines)


def _parse_history_turns(history_context: str) -> list[tuple[str, str]]:
    """Parse a plain-text history block into (user, assistant) pairs.

    Accepts the format produced by memory_service.get_context_string / get_api_context_string.
    Lines starting with "User:" and "AI:" / "Assistant:" are grouped by order.
    """
    if not history_context:
        return []

    pairs: list[tuple[str, str]] = []
    current_user: str | None = None
    current_ai_parts: list[str] = []

    def _flush() -> None:
        nonlocal current_user, current_ai_parts
        if current_user is not None:
            ai_text = "\n".join(current_ai_parts).strip()
            pairs.append((current_user, ai_text))
        current_user = None
        current_ai_parts = []

    for raw_line in history_context.splitlines():
        line = raw_line.strip()
        if not line or line.lower().startswith(("lich su", "recent conversation")):
            continue

        lower = line.lower()
        if lower.startswith("user:"):
            _flush()
            current_user = line.split(":", 1)[1].strip()
        elif lower.startswith(("ai:", "assistant:")):
            current_ai_parts.append(line.split(":", 1)[1].strip())
        else:
            if current_user is not None and not current_ai_parts:
                current_user = f"{current_user} {line}".strip()
            elif current_ai_parts:
                current_ai_parts[-1] = f"{current_ai_parts[-1]} {line}".strip()

    _flush()
    return [(u, a) for u, a in pairs if u and a]


def build_local_chat_messages(
    *,
    system_prompt: str,
    few_shot_turns: list[tuple[str, str]],
    history_context: str,
    retrieved_chunks: list[dict],
    user_message: str,
) -> list[dict[str, Any]]:
    """Build an OpenAI-chat-style message list for the local LLM.

    Returns a list of {"role": ..., "content": ...} dicts so the caller can convert
    to llama-index ChatMessage without importing it here.
    """
    knowledge_block = _format_knowledge_block(
        retrieved_chunks,
        max_items=2,
        max_chars_per_item=450,
    )

    system_content = system_prompt.strip()
    if knowledge_block:
        system_content = (
            system_content
            + "\n\nTRI THỨC NỀN (nội bộ - chỉ dùng để trả lời, không trích nguyên văn):\n"
            + knowledge_block
        )

    messages: list[dict[str, Any]] = [{"role": "system", "content": system_content}]

    for user_text, assistant_text in few_shot_turns:
        messages.append({"role": "user", "content": user_text.strip()})
        messages.append({"role": "assistant", "content": assistant_text.strip()})

    for user_text, assistant_text in _parse_history_turns(history_context):
        messages.append({"role": "user", "content": _trim_text(user_text, max_chars=220)})
        messages.append({"role": "assistant", "content": _trim_text(assistant_text, max_chars=300)})

    messages.append({"role": "user", "content": _trim_text(user_message, max_chars=500)})
    return messages


def build_api_chat_messages(
    *,
    system_prompt: str,
    few_shot_turns: list[tuple[str, str]],
    history_context: str,
    retrieved_chunks: list[dict],
    user_message: str,
) -> list[dict[str, Any]]:
    knowledge_block = _format_knowledge_block(
        retrieved_chunks,
        max_items=3,
        max_chars_per_item=650,
    )

    system_content = system_prompt.strip()
    if knowledge_block:
        system_content = (
            system_content
            + "\n\nTRI THỨC NỀN (nội bộ - chỉ dùng để trả lời, không trích nguyên văn):\n"
            + knowledge_block
        )

    messages: list[dict[str, Any]] = [{"role": "system", "content": system_content}]

    for user_text, assistant_text in few_shot_turns[:2]:
        messages.append({"role": "user", "content": user_text.strip()})
        messages.append({"role": "assistant", "content": assistant_text.strip()})

    for user_text, assistant_text in _parse_history_turns(history_context):
        messages.append({"role": "user", "content": _trim_text(user_text, max_chars=260)})
        messages.append({"role": "assistant", "content": _trim_text(assistant_text, max_chars=400)})

    messages.append({"role": "user", "content": _trim_text(user_message, max_chars=700)})
    return messages


def build_local_rag_prompt(
    *,
    system_prompt: str,
    history_context: str,
    retrieved_chunks: list[dict],
    user_message: str,
) -> str:
    """Legacy single-prompt builder. Kept for backwards compatibility only."""
    knowledge_block = _format_knowledge_block(
        retrieved_chunks,
        max_items=2,
        max_chars_per_item=500,
    ) or "(Không có tri thức bổ sung.)"
    history_block = _trim_text(history_context, max_chars=500) or "(Chưa có lịch sử.)"
    user_block = _trim_text(user_message, max_chars=400)
    return (
        f"{system_prompt}\n\n"
        f"TRI THỨC NỀN:\n{knowledge_block}\n\n"
        f"LỊCH SỬ:\n{history_block}\n\n"
        f"USER: {user_block}\nS-SOCRATES:"
    )


def build_api_rag_prompt(
    *,
    system_prompt: str,
    history_context: str,
    retrieved_chunks: list[dict],
    user_message: str,
) -> str:
    """Legacy single-prompt builder for Gemini API path (still uses single prompt string)."""
    knowledge_block = _format_knowledge_block(
        retrieved_chunks,
        max_items=3,
        max_chars_per_item=700,
    ) or "(Không có tri thức bổ sung.)"
    history_block = _trim_text(history_context, max_chars=1200) or "(Chưa có lịch sử.)"
    user_block = _trim_text(user_message, max_chars=600)
    return (
        f"{system_prompt}\n\n"
        f"TRI THỨC NỀN:\n{knowledge_block}\n\n"
        f"LỊCH SỬ GẦN NHẤT:\n{history_block}\n\n"
        f"Câu hỏi hiện tại: {user_block}\n\n"
        f"S-Socrates trả lời (3-5 câu, có ít nhất 1 câu pressing):"
    )
