import time

from services.llm_service import (
    generate_api_chat_answer,
    generate_local_chat_answer,
    warm_local_context,
)
from services.memory_service import memory_service
from services.prompt_config import (
    API_SYSTEM_PROMPT,
    FEW_SHOT_TURNS,
    LOCAL_SYSTEM_PROMPT,
)
from services.retrieval.prompt_builder import (
    build_api_chat_messages,
    build_local_chat_messages,
)
from services.retrieval.retriever import retriever
from utils.logger import log


SUPPORTED_MODEL_CHOICES = {"local", "turboquant", "gemini"}

EMPTY_RESPONSE_FALLBACK = (
    "Em cần thầy/cô nhắc lại câu hỏi giúp em, sóng em đang hơi lag."
)


def _log_context_metrics(
    *,
    prompt: str,
    history_context: str,
    retrieved_chunks: list[dict],
    retrieval_ms: float,
) -> None:
    retrieval_stats = retriever.stats()
    retrieved_sources = [item.get("source", "unknown") for item in retrieved_chunks]
    log.info(
        "[CHAT] Retrieved %s quantized context chunks in %.0fms.",
        len(retrieved_chunks),
        retrieval_ms,
    )
    log.info(
        "[CHAT] Context metrics: prompt_length=%s history_length=%s retrieval_memory_saved=%.2f%% sources=%s",
        len(prompt),
        len(history_context),
        retrieval_stats["memory_saved_ratio"] * 100,
        retrieved_sources,
    )


def process_local_chat_message(message: str) -> str:
    normalized_message = (message or "").strip()
    if not normalized_message:
        return ""

    start_time = time.time()
    log.info("[CHAT] Processing LOCAL request")

    history_context = memory_service.get_context_string()
    memory_summary = memory_service.get_summary_text()
    warm_context = memory_service.build_reconstruction_prompt()
    if warm_context:
        warm_start = time.time()
        warm_local_context(warm_context)
        warm_ms = (time.time() - warm_start) * 1000
        log.info("[CHAT] Warmed TurboQuant context in %.0fms.", warm_ms)

    retrieval_start = time.time()
    retrieved_chunks = retriever.search(normalized_message, top_k=2, rerank_k=6)
    retrieval_ms = (time.time() - retrieval_start) * 1000

    chat_messages = build_local_chat_messages(
        system_prompt=LOCAL_SYSTEM_PROMPT,
        few_shot_turns=FEW_SHOT_TURNS,
        history_context=history_context,
        retrieved_chunks=retrieved_chunks,
        user_message=normalized_message,
        memory_summary=memory_summary,
    )
    total_prompt_len = sum(len(m.get("content", "")) for m in chat_messages)
    _log_context_metrics(
        prompt="[chat_messages:%d turns, %d chars]" % (len(chat_messages), total_prompt_len),
        history_context=history_context,
        retrieved_chunks=retrieved_chunks,
        retrieval_ms=retrieval_ms,
    )

    llm_start = time.time()
    response_text = generate_local_chat_answer(chat_messages)
    llm_ms = (time.time() - llm_start) * 1000
    log.info(
        "[CHAT] LLM response generated via local chat in %.0fms (len=%d).",
        llm_ms,
        len(response_text or ""),
    )

    if not response_text or not response_text.strip():
        log.warning(
            "[CHAT] Local LLM returned empty output after post-processing. "
            "user_len=%d history_len=%d retrieved=%d -> using fallback message.",
            len(normalized_message),
            len(history_context),
            len(retrieved_chunks),
        )
        response_text = EMPTY_RESPONSE_FALLBACK

    memory_service.save(normalized_message, response_text)

    total_ms = (time.time() - start_time) * 1000
    log.info("[CHAT] Local request complete in %.0fms.", total_ms)
    return response_text


def process_api_chat_message(message: str) -> str:
    normalized_message = (message or "").strip()
    if not normalized_message:
        return ""

    start_time = time.time()
    log.info("[CHAT] Processing API request")

    history_context = memory_service.get_api_context_string(max_turns=6, max_chars=1200)
    memory_summary = memory_service.get_summary_text()

    retrieval_start = time.time()
    retrieved_chunks = retriever.search(normalized_message, top_k=3, rerank_k=7)
    retrieval_ms = (time.time() - retrieval_start) * 1000

    chat_messages = build_api_chat_messages(
        system_prompt=API_SYSTEM_PROMPT,
        few_shot_turns=FEW_SHOT_TURNS,
        history_context=history_context,
        retrieved_chunks=retrieved_chunks,
        user_message=normalized_message,
        memory_summary=memory_summary,
    )
    total_prompt_len = sum(len(m.get("content", "")) for m in chat_messages)
    _log_context_metrics(
        prompt="[chat_messages:%d turns, %d chars]" % (len(chat_messages), total_prompt_len),
        history_context=history_context,
        retrieved_chunks=retrieved_chunks,
        retrieval_ms=retrieval_ms,
    )

    llm_start = time.time()
    response_text = generate_api_chat_answer(chat_messages)
    llm_ms = (time.time() - llm_start) * 1000
    log.info(
        "[CHAT] LLM response generated via gemini chat in %.0fms (len=%d).",
        llm_ms,
        len(response_text or ""),
    )

    if not response_text or not response_text.strip():
        log.warning(
            "[CHAT] Gemini returned empty output. "
            "user_len=%d history_len=%d retrieved=%d -> using fallback message.",
            len(normalized_message),
            len(history_context),
            len(retrieved_chunks),
        )
        response_text = EMPTY_RESPONSE_FALLBACK

    memory_service.save(normalized_message, response_text)

    total_ms = (time.time() - start_time) * 1000
    log.info("[CHAT] API request complete in %.0fms.", total_ms)
    return response_text


def process_chat_message(message: str, model_choice: str = "local") -> str:
    if model_choice not in SUPPORTED_MODEL_CHOICES:
        raise ValueError(
            f"Unsupported model_choice '{model_choice}'. "
            "Expected one of: local, turboquant, gemini."
        )

    if model_choice == "gemini":
        return process_api_chat_message(message)

    return process_local_chat_message(message)
