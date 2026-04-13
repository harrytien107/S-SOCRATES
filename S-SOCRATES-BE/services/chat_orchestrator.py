import time

from services.llm_service import SYSTEM_PROMPT, generate_answer, warm_local_context
from services.memory_service import memory_service
from services.retrieval.prompt_builder import build_rag_prompt
from services.retrieval.retriever import retriever
from utils.logger import log


SUPPORTED_MODEL_CHOICES = {"local", "turboquant", "gemini"}


def process_chat_message(message: str, model_choice: str = "local") -> str:
    normalized_message = (message or "").strip()
    if not normalized_message:
        return ""

    if model_choice not in SUPPORTED_MODEL_CHOICES:
        raise ValueError(
            f"Unsupported model_choice '{model_choice}'. "
            "Expected one of: local, turboquant, gemini."
        )

    log.info("[CHAT] Processing request with model_choice=%s", model_choice)
    start_time = time.time()

    history_context = memory_service.get_context_string()
    if model_choice in {"local", "turboquant"}:
        warm_context = memory_service.build_reconstruction_prompt()
        if warm_context:
            warm_start = time.time()
            warm_local_context(warm_context)
            warm_ms = (time.time() - warm_start) * 1000
            log.info("[CHAT] Warmed TurboQuant context in %.0fms.", warm_ms)

    retrieval_start = time.time()
    retrieved_chunks = retriever.search(normalized_message, top_k=4, rerank_k=12)
    retrieval_ms = (time.time() - retrieval_start) * 1000
    retrieval_stats = retriever.stats()
    retrieved_sources = [item.get("source", "unknown") for item in retrieved_chunks]
    log.info(
        "[CHAT] Retrieved %s quantized context chunks in %.0fms.",
        len(retrieved_chunks),
        retrieval_ms,
    )

    prompt = build_rag_prompt(
        system_prompt=SYSTEM_PROMPT,
        history_context=history_context,
        retrieved_chunks=retrieved_chunks,
        user_message=normalized_message,
    )
    log.info(
        "[CHAT] Context metrics: prompt_length=%s history_length=%s retrieval_memory_saved=%.2f%% sources=%s",
        len(prompt),
        len(history_context),
        retrieval_stats["memory_saved_ratio"] * 100,
        retrieved_sources,
    )

    llm_start = time.time()
    response_text = generate_answer(prompt, model_choice=model_choice)
    llm_ms = (time.time() - llm_start) * 1000
    log.info(
        "[CHAT] LLM response generated via %s in %.0fms.",
        model_choice,
        llm_ms,
    )

    memory_service.save(normalized_message, response_text)

    total_ms = (time.time() - start_time) * 1000
    log.info("[CHAT] Request complete in %.0fms.", total_ms)
    return response_text
