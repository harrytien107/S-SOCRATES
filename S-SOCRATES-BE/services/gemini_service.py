from __future__ import annotations

import os

from dotenv import load_dotenv

from services.prompt_config import BASE_DIR
from utils.logger import log


ENV_PATH = BASE_DIR / ".env"
load_dotenv(dotenv_path=ENV_PATH, override=True)

AVAILABLE_GEMINI_MODELS = [
    "models/gemini-3.1-pro-preview",
    "models/gemini-3-flash-preview",
    "models/gemini-2.5-pro",
    "models/gemini-2.5-flash",
    "models/gemini-2.0-flash",
]


class GeminiService:
    def __init__(self) -> None:
        self._llm = None
        self._current_model: str | None = None

    @property
    def current_model(self) -> str | None:
        return self._current_model

    def initialize(self, model_name: str = "models/gemini-2.5-flash") -> None:
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            log.warning("GEMINI_API_KEY not found in .env. Gemini engine disabled.")
            self._llm = None
            self._current_model = None
            return

        try:
            from llama_index.llms.gemini import Gemini

            self._llm = Gemini(model=model_name, api_key=api_key)
            self._current_model = model_name
            log.info("Gemini LLM (%s) initialized.", model_name)
        except Exception as exc:
            log.error("Failed to initialize Gemini engine: %s", exc)
            self._llm = None
            self._current_model = None

    def switch_model(self, model_name: str) -> None:
        if model_name == self._current_model:
            return
        log.info("Switching Gemini model: %s -> %s", self._current_model, model_name)
        self.initialize(model_name)

    def generate(self, prompt: str) -> str:
        if self._llm is None:
            raise RuntimeError(
                "Gemini engine is not available. "
                "Please verify GEMINI_API_KEY and the selected Gemini model."
            )

        log.info("Routing to Gemini (Cloud) [%s]...", self._current_model)
        try:
            response = self._llm.complete(prompt)
        except Exception as exc:
            error_type = exc.__class__.__name__
            error_text = str(exc)
            if error_type == "ResourceExhausted" or "RESOURCE_EXHAUSTED" in error_text:
                raise RuntimeError(
                    "Gemini quota exceeded for the current API key/project. "
                    "Please wait and retry, or switch to the local model."
                ) from exc
            raise RuntimeError(f"Gemini request failed: {error_text}") from exc

        return str(getattr(response, "text", response))


gemini_service = GeminiService()
gemini_service.initialize()
