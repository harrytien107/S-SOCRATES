import time

from services.llm_service import ask_socrates
from services.memory_service import memory_service
from utils.logger import log


SUPPORTED_MODEL_CHOICES = {"ollama", "gemini"}


def process_chat_message(message: str, model_choice: str = "ollama") -> str:
    normalized_message = (message or "").strip()
    if not normalized_message:
        return ""

    if model_choice not in SUPPORTED_MODEL_CHOICES:
        raise ValueError(
            f"Unsupported model_choice '{model_choice}'. "
            "Expected one of: ollama, gemini."
        )

    log.info("[CHAT] Processing request with model_choice=%s", model_choice)
    start_time = time.time()

    history_context = memory_service.get_context_string()
    llm_start = time.time()
    response_text = ask_socrates(
        normalized_message,
        history_context=history_context,
        model_choice=model_choice,
    )
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
