import time
import os
from services.memory_service import memory_service
from services.llm_service import ask_socrates
from services.semantic_router import semantic_router
from utils.logger import log

SUPPORTED_MODEL_CHOICES = {"ollama", "openrouter"}
OPENROUTER_STRICT_CONTEXT_PROFILE = {
    "seed_turns": 0,
    "recent_turns": 4,
    "max_turn_chars": 180,
    "max_total_chars": 900,
    "include_ai": False,
}
OPENROUTER_USE_SEMANTIC_PRESET = os.getenv("OPENROUTER_USE_SEMANTIC_PRESET", "0").strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
}


def process_chat_message(message: str, model_choice: str = "ollama") -> str:
    normalized_message = (message or "").strip()
    if not normalized_message:
        return ""

    if model_choice not in SUPPORTED_MODEL_CHOICES:
        raise ValueError(
            f"Unsupported model_choice '{model_choice}'. Expected one of: ollama, openrouter."
        )

    log.info("[CHAT] Processing request with model_choice=%s", model_choice)
    start_time = time.time()
    
    # Retrieve conversation history (compact for cloud model to reduce latency)
    if model_choice == "openrouter":
        history_context = memory_service.get_context_string(**OPENROUTER_STRICT_CONTEXT_PROFILE)
    else:
        history_context = memory_service.get_context_string()

    # 1. So khớp câu hỏi với bộ qa_presets.json thông qua Semantic Router
    semantic_router.reload_presets()
    preset_answer = None
    if model_choice != "openrouter" or OPENROUTER_USE_SEMANTIC_PRESET:
        preset_answer = semantic_router.get_best_match(normalized_message)
    
    if preset_answer:
        response_text = preset_answer
        llm_time = (time.time() - start_time) * 1000
        log.info(
            "[CHAT] Preset match resolved in %.0fms.",
            llm_time,
        )
    else:
        # 2. Nếu không khớp, truy vấn LLM / LlamaIndex core
        log.info("[CHAT] Routing to LLM with history context...")
        llm_start = time.time()
        response_text = ask_socrates(
            normalized_message,
            history_context,
            model_choice=model_choice,
        )
        llm_time = (time.time() - llm_start) * 1000
        log.info("[CHAT] LLM response generated in %.0fms.", llm_time)
    
    # Save the new exchange to memory
    memory_service.save(normalized_message, response_text)
    
    total_time = (time.time() - start_time) * 1000
    log.info("[CHAT] Request complete in %.0fms.", total_time)
    return response_text
