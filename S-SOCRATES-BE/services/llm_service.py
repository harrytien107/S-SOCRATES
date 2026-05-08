from services.gemini_service import AVAILABLE_GEMINI_MODELS, gemini_service
from services.local_baseline_runtime import local_baseline_runtime
from services.turboquant_runtime import turboquant_runtime


def initialize_local_backend(force_restart: bool = False) -> None:
    turboquant_runtime.initialize(force_restart=force_restart)


def shutdown_local_backend() -> None:
    turboquant_runtime.shutdown()


def get_local_backend_status() -> dict:
    return turboquant_runtime.get_status()


def warm_local_context(context_text: str) -> None:
    turboquant_runtime.warm_context(context_text)


def initialize_local_baseline_backend(force_restart: bool = False) -> None:
    local_baseline_runtime.initialize(force_restart=force_restart)


def shutdown_local_baseline_backend() -> None:
    local_baseline_runtime.shutdown()


def get_local_baseline_backend_status() -> dict:
    return local_baseline_runtime.get_status()


def switch_gemini_model(model_name: str) -> None:
    gemini_service.switch_model(model_name)


def generate_local_answer(prompt: str) -> str:
    return turboquant_runtime.generate(prompt)


def generate_local_chat_answer(messages: list[dict]) -> str:
    return turboquant_runtime.generate_chat(messages)


def generate_local_baseline_chat_answer(messages: list[dict]) -> str:
    return local_baseline_runtime.generate_chat(messages)


def generate_api_answer(prompt: str) -> str:
    return gemini_service.generate(prompt)


def generate_answer(prompt: str, model_choice: str = "local") -> str:
    if model_choice == "gemini":
        return generate_api_answer(prompt)
    if model_choice in {"local", "turboquant"}:
        return generate_local_answer(prompt)
    if model_choice in {"local_baseline", "baseline"}:
        # Legacy function takes a plain prompt string, but our baseline path now
        # uses chat-message flow in chat_orchestrator. Keep explicit error here.
        raise ValueError("Use generate_local_baseline_chat_answer() for baseline mode.")
    raise ValueError(f"Unsupported model_choice '{model_choice}'")
