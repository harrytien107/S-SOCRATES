import os
import json
import re
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeoutError
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from urllib import request

from dotenv import load_dotenv
from llama_index.core import SimpleDirectoryReader, VectorStoreIndex
from llama_index.core.settings import Settings
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from llama_index.llms.ollama import Ollama
import requests

from utils.logger import log

BASE_DIR = Path(__file__).resolve().parent.parent
ENV_PATH = BASE_DIR / ".env"
load_dotenv(dotenv_path=ENV_PATH, override=True)
KNOWLEDGE_DIR = BASE_DIR / "knowledge"
PROMPT_PATH = KNOWLEDGE_DIR / "uth.txt"


def _read_bool_env(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


OPENROUTER_API_BASE = os.getenv("OPENROUTER_API_BASE", "https://openrouter.ai/api/v1").strip()
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "").strip()
OPENROUTER_TIMEOUT_S = float(os.getenv("OPENROUTER_TIMEOUT_S", "20"))
OPENROUTER_TEMPERATURE = float(os.getenv("OPENROUTER_TEMPERATURE", "0.3"))
OPENROUTER_MAX_TOKENS = int(os.getenv("OPENROUTER_MAX_TOKENS", "300"))
OPENROUTER_FALLBACK_LOCAL_ON_TIMEOUT = _read_bool_env(
    "OPENROUTER_FALLBACK_LOCAL_ON_TIMEOUT", False
)
OPENROUTER_FALLBACK_LOCAL_ON_QUOTA = _read_bool_env(
    "OPENROUTER_FALLBACK_LOCAL_ON_QUOTA", False
)
OPENROUTER_USE_RETRIEVAL = _read_bool_env("OPENROUTER_USE_RETRIEVAL", False)
OPENROUTER_HTTP_REFERER = os.getenv("OPENROUTER_HTTP_REFERER", "").strip()
OPENROUTER_APP_NAME = os.getenv("OPENROUTER_APP_NAME", "S-SOCRATES").strip()
_cloud_timeout_executor = ThreadPoolExecutor(max_workers=2)
STRICT_PROMPT_MODE = _read_bool_env("STRICT_PROMPT_MODE", True)
STRICT_MAX_SENTENCES = int(os.getenv("STRICT_MAX_SENTENCES", "3"))
STRICT_MAX_WORDS = int(os.getenv("STRICT_MAX_WORDS", "60"))
STRICT_FORCE_POLITE_PREFIX = _read_bool_env("STRICT_FORCE_POLITE_PREFIX", True)

STRICT_CLOUD_SUFFIX = """
YEU CAU BAT BUOC BAM PROMPT:
- Tuân thủ tuyệt đối PERSONA + OUTPUT RULES trong SYSTEM_PROMPT.
- Luôn xưng 'em', xưng hô lễ phép với 'Giáo sư' hoặc 'Tiến sĩ'.
- Không trả lời kiểu "không có dữ liệu" cho các chủ đề kiến thức phổ thông.
- Không dùng "..." hoặc "…" trong câu trả lời; nếu cần ngắt nhịp thì dùng dấu phẩy.
"""


def _http_ready(url: str, timeout: float) -> bool:
    try:
        req = request.Request(url, method="GET")
        with request.urlopen(req, timeout=timeout) as resp:
            return 200 <= resp.status < 500
    except Exception:
        return False


def _wait_until_ready(checker, timeout_s: float, interval_s: float = 0.5) -> bool:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if checker():
            return True
        time.sleep(interval_s)
    return checker()


def _normalize_whitespace(text: str) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def _normalize_pause_punctuation(text: str) -> str:
    cleaned = (text or "").replace("…", "...")
    # Convert repeated dots to a spoken pause that TTS won't read as "ba cham".
    cleaned = re.sub(r"(?:\s*\.\s*){2,}", ", ", cleaned)
    cleaned = re.sub(r"\s+([,.;:!?])", r"\1", cleaned)
    cleaned = re.sub(r"([,;:!?])(?=\S)", r"\1 ", cleaned)
    return _normalize_whitespace(cleaned)


def _truncate_sentences(text: str, max_sentences: int) -> str:
    if max_sentences <= 0:
        return text
    segments = [s.strip() for s in re.split(r"(?<=[.!?…])\s+", text) if s.strip()]
    if len(segments) <= max_sentences:
        return " ".join(segments)
    return " ".join(segments[:max_sentences])


def _truncate_words(text: str, max_words: int) -> str:
    if max_words <= 0:
        return text
    words = text.split()
    if len(words) <= max_words:
        return text
    shortened = " ".join(words[:max_words]).rstrip(" ,;:")
    if shortened and shortened[-1] not in ".!?":
        shortened += "."
    return shortened


def _enforce_socrates_style(text: str) -> str:
    cleaned = _normalize_whitespace(text)
    cleaned = cleaned.replace("S-Socrates:", "").strip()
    cleaned = _normalize_pause_punctuation(cleaned)

    if not cleaned:
        return "Thưa Giáo sư, em xin lỗi, em chưa xử lý được câu hỏi này ạ."

    if STRICT_PROMPT_MODE:
        cleaned = _truncate_sentences(cleaned, max(1, STRICT_MAX_SENTENCES))
        cleaned = _truncate_words(cleaned, max(20, STRICT_MAX_WORDS))

    if STRICT_FORCE_POLITE_PREFIX and not re.match(r"^(thưa|kính thưa|thua|kinh thua)\s", cleaned, re.IGNORECASE):
        cleaned = f"Thưa Giáo sư, {cleaned}"

    cleaned = cleaned.strip()
    if cleaned and cleaned[-1] not in ".!?":
        cleaned += "."
    return cleaned


def _extract_response_text(response_obj) -> str:
    if response_obj is None:
        return ""
    text_attr = getattr(response_obj, "text", None)
    if text_attr is not None:
        return str(text_attr)
    return str(response_obj)


try:
    SYSTEM_PROMPT = PROMPT_PATH.read_text(encoding="utf-8").strip()
except Exception as exc:
    print(f"⚠️ Không thể tải cấu hình system prompt từ {PROMPT_PATH}: {exc}")
    SYSTEM_PROMPT = "Bạn là S-SOCRATES, một AI phản biện."


@dataclass(frozen=True)
class LocalLLMConfig:
    backend: str
    autostart: bool
    timeout_s: float
    host: str
    port: int
    model_name: str
    gguf_path: str
    ollama_cmd: str
    ollama_model_name: str
    turboquant_server_bin: str
    turboquant_cache_type: str
    turboquant_ngl: int
    turboquant_ctx: int

    @property
    def health_url(self) -> str:
        if self.backend == "ollama":
            return f"http://{self.host}:{self.port}/api/tags"
        return f"http://{self.host}:{self.port}/health"

    @property
    def api_base(self) -> str:
        if self.backend == "ollama":
            return f"http://{self.host}:{self.port}"
        return f"http://{self.host}:{self.port}/v1"


def _load_local_config() -> LocalLLMConfig:
    backend = os.getenv("LOCAL_LLM_BACKEND", "ollama").strip().lower()
    if backend not in {"ollama", "turboquant"}:
        raise ValueError(
            "LOCAL_LLM_BACKEND phải là 'ollama' hoặc 'turboquant'."
        )

    default_port = 11434 if backend == "ollama" else 8011
    return LocalLLMConfig(
        backend=backend,
        autostart=_read_bool_env("LOCAL_LLM_AUTOSTART", True),
        timeout_s=float(os.getenv("LOCAL_LLM_TIMEOUT_S", "120")),
        host=os.getenv("LOCAL_LLM_HOST", "127.0.0.1"),
        port=int(os.getenv("LOCAL_LLM_PORT", str(default_port))),
        model_name=os.getenv(
            "LOCAL_LLM_MODEL_NAME",
            os.getenv("OLLAMA_MODEL_NAME", "qwen2:7b"),
        ),
        gguf_path=os.getenv("LOCAL_LLM_GGUF_PATH", "").strip(),
        ollama_cmd=os.getenv("OLLAMA_CMD", "ollama").strip(),
        ollama_model_name=os.getenv("OLLAMA_MODEL_NAME", "qwen2:7b").strip(),
        turboquant_server_bin=os.getenv("TURBOQUANT_SERVER_BIN", "").strip(),
        turboquant_cache_type=os.getenv("TURBOQUANT_CACHE_TYPE", "turbo2").strip(),
        turboquant_ngl=int(os.getenv("TURBOQUANT_NGL", "99")),
        turboquant_ctx=int(os.getenv("TURBOQUANT_CTX", "8192")),
    )


# =========================
# Shared Retrieval Components
# =========================

_embed_model = HuggingFaceEmbedding(
    model_name="sentence-transformers/all-MiniLM-L6-v2"
)
Settings.embed_model = _embed_model
_documents = SimpleDirectoryReader(str(KNOWLEDGE_DIR)).load_data()
_index = VectorStoreIndex.from_documents(_documents)


# =========================
# Local Engine Runtime State
# =========================

_runtime_lock = threading.RLock()
_local_query_engine = None
_local_backend_name = None
_managed_local_process: Optional[subprocess.Popen] = None
_managed_local_backend: Optional[str] = None
_managed_local_command = None


def _build_local_query_engine(config: LocalLLMConfig):
    if config.backend == "ollama":
        llm = Ollama(
            model=config.ollama_model_name,
            request_timeout=config.timeout_s,
            base_url=config.api_base,
        )
        return _index.as_query_engine(llm=llm)

    try:
        from llama_index.llms.openai_like import OpenAILike
    except ImportError as exc:
        raise RuntimeError(
            "Thiếu package llama-index-llms-openai-like. "
            "Hãy chạy `pip install -r requirements.txt`."
        ) from exc

    llm = OpenAILike(
        model=config.model_name,
        api_base=config.api_base,
        api_key="not-needed",
        context_window=config.turboquant_ctx,
        is_chat_model=True,
        is_function_calling_model=False,
        timeout=config.timeout_s,
        max_tokens=1024,
        temperature=0.2,
    )
    return _index.as_query_engine(llm=llm)


def _start_ollama_process(config: LocalLLMConfig) -> subprocess.Popen:
    cmd = [config.ollama_cmd, "serve"]
    log.info(
        "🚀 Starting Ollama local backend at %s using model %s",
        config.api_base,
        config.ollama_model_name,
    )
    return subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd=str(BASE_DIR),
    )


def _start_turboquant_process(config: LocalLLMConfig) -> subprocess.Popen:
    if not config.turboquant_server_bin:
        raise RuntimeError("TURBOQUANT_SERVER_BIN chưa được cấu hình.")
    if not config.gguf_path:
        raise RuntimeError("LOCAL_LLM_GGUF_PATH chưa được cấu hình cho turboquant.")
    if not Path(config.turboquant_server_bin).exists():
        raise RuntimeError(
            f"Không tìm thấy binary llama-server tại {config.turboquant_server_bin}"
        )
    if not Path(config.gguf_path).exists():
        raise RuntimeError(f"Không tìm thấy model GGUF tại {config.gguf_path}")

    cmd = [
        config.turboquant_server_bin,
        "--host",
        config.host,
        "--port",
        str(config.port),
        "-m",
        config.gguf_path,
        "-ngl",
        str(config.turboquant_ngl),
        "-c",
        str(config.turboquant_ctx),
        "--flash-attn",
        "on",
        "--cache-type-k",
        config.turboquant_cache_type,
        "--cache-type-v",
        config.turboquant_cache_type,
        "--jinja",
    ]
    log.info(
        "🚀 Starting TurboQuant local backend at %s using model %s",
        config.api_base,
        config.gguf_path,
    )
    return subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd=str(BASE_DIR),
    )


def _start_local_process(config: LocalLLMConfig) -> subprocess.Popen:
    if config.backend == "ollama":
        return _start_ollama_process(config)
    return _start_turboquant_process(config)


def _is_backend_ready(config: LocalLLMConfig) -> bool:
    return _http_ready(config.health_url, timeout=min(config.timeout_s, 5.0))


def shutdown_local_backend() -> None:
    global _local_query_engine, _local_backend_name
    global _managed_local_process, _managed_local_backend, _managed_local_command

    with _runtime_lock:
        process = _managed_local_process
        backend = _managed_local_backend
        command = _managed_local_command

        _local_query_engine = None
        _local_backend_name = None
        _managed_local_process = None
        _managed_local_backend = None
        _managed_local_command = None

        if process is None:
            return

        log.info("🧹 Stopping app-managed local backend %s", backend)
        try:
            process.terminate()
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            log.warning("⚠️ Local backend did not stop in time, killing it.")
            process.kill()
            process.wait(timeout=5)
        except Exception as exc:
            log.error("❌ Failed to stop local backend %s (%s): %s", backend, command, exc)


def initialize_local_backend(force_restart: bool = False) -> None:
    global _local_query_engine, _local_backend_name
    global _managed_local_process, _managed_local_backend, _managed_local_command

    config = _load_local_config()
    with _runtime_lock:
        if force_restart:
            shutdown_local_backend()
        elif (
            _local_query_engine is not None
            and _local_backend_name == config.backend
        ):
            return
        elif _managed_local_process is not None and _managed_local_backend != config.backend:
            shutdown_local_backend()

        if _is_backend_ready(config):
            log.info(
                "✅ Reusing existing %s local backend at %s (model=%s)",
                config.backend,
                config.api_base,
                config.model_name if config.backend == "turboquant" else config.ollama_model_name,
            )
            _local_query_engine = _build_local_query_engine(config)
            _local_backend_name = config.backend
            return

        if not config.autostart:
            raise RuntimeError(
                f"Local backend '{config.backend}' chưa sẵn sàng tại {config.api_base} "
                "và LOCAL_LLM_AUTOSTART=0."
            )

        shutdown_local_backend()
        process = _start_local_process(config)
        _managed_local_process = process
        _managed_local_backend = config.backend
        _managed_local_command = process.args

        ready = _wait_until_ready(
            lambda: _is_backend_ready(config),
            timeout_s=min(max(config.timeout_s, 30.0), 180.0),
        )
        if not ready:
            shutdown_local_backend()
            raise RuntimeError(
                f"Local backend '{config.backend}' không sẵn sàng tại {config.api_base}."
            )

        _local_query_engine = _build_local_query_engine(config)
        _local_backend_name = config.backend
        log.info(
            "✅ Local backend ready: backend=%s host=%s port=%s model=%s gguf=%s",
            config.backend,
            config.host,
            config.port,
            config.model_name if config.backend == "turboquant" else config.ollama_model_name,
            config.gguf_path or "-",
        )


def _get_local_query_engine():
    with _runtime_lock:
        if _local_query_engine is None:
            initialize_local_backend()
        return _local_query_engine


def get_local_backend_status() -> dict:
    config = _load_local_config()
    with _runtime_lock:
        return {
            "backend": config.backend,
            "host": config.host,
            "port": config.port,
            "api_base": config.api_base,
            "model_name": config.model_name if config.backend == "turboquant" else config.ollama_model_name,
            "gguf_path": config.gguf_path or None,
            "autostart": config.autostart,
            "ready": _is_backend_ready(config),
            "managed_by_app": _managed_local_process is not None,
        }


# =========================
# OpenRouter (Cloud) - Dynamic Model
# =========================

_openrouter_query_engine = None
_current_openrouter_model = None

DEFAULT_OPENROUTER_MODELS = [
    "google/gemini-2.0-flash-001",
    "google/gemini-2.5-flash-preview",
    "openai/gpt-4o-mini",
    "deepseek/deepseek-chat-v3-0324:free",
    "meta-llama/llama-3.1-8b-instruct:free",
]


def _load_openrouter_models() -> list[str]:
    raw = os.getenv("OPENROUTER_MODELS", "").strip()
    if raw:
        parsed = [item.strip() for item in raw.split(",") if item.strip()]
        if parsed:
            return parsed
    return DEFAULT_OPENROUTER_MODELS


AVAILABLE_OPENROUTER_MODELS = _load_openrouter_models()


def _openrouter_headers() -> dict:
    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
    }
    if OPENROUTER_HTTP_REFERER:
        headers["HTTP-Referer"] = OPENROUTER_HTTP_REFERER
    if OPENROUTER_APP_NAME:
        headers["X-Title"] = OPENROUTER_APP_NAME
    return headers


def _build_openrouter_query_engine(model_name: str):
    from llama_index.llms.openai_like import OpenAILike

    llm = OpenAILike(
        model=model_name,
        api_base=OPENROUTER_API_BASE,
        api_key=OPENROUTER_API_KEY,
        is_chat_model=True,
        is_function_calling_model=False,
        timeout=OPENROUTER_TIMEOUT_S,
        max_tokens=OPENROUTER_MAX_TOKENS,
        temperature=OPENROUTER_TEMPERATURE,
    )
    return _index.as_query_engine(llm=llm)


def _init_openrouter_model(model_name: str | None = None):
    global _openrouter_query_engine, _current_openrouter_model

    target_model = model_name or (AVAILABLE_OPENROUTER_MODELS[0] if AVAILABLE_OPENROUTER_MODELS else "")
    _current_openrouter_model = target_model

    if not OPENROUTER_API_KEY:
        _openrouter_query_engine = None
        log.warning("⚠️ OPENROUTER_API_KEY not found in .env. OpenRouter cloud mode disabled.")
        return

    try:
        if OPENROUTER_USE_RETRIEVAL:
            _openrouter_query_engine = _build_openrouter_query_engine(target_model)
        else:
            _openrouter_query_engine = None
        log.info(
            "✅ OpenRouter initialized (%s). retrieval=%s",
            target_model,
            OPENROUTER_USE_RETRIEVAL,
        )
    except Exception as exc:
        log.error("❌ Failed to initialize OpenRouter engine: %s", exc)
        _openrouter_query_engine = None


_init_openrouter_model()


def switch_openrouter_model(model_name: str):
    global _current_openrouter_model
    if model_name == _current_openrouter_model:
        return
    log.info("🔄 Switching OpenRouter model: %s → %s", _current_openrouter_model, model_name)
    _init_openrouter_model(model_name)


def _openrouter_complete_text(prompt: str) -> str:
    if not OPENROUTER_API_KEY:
        raise RuntimeError("OPENROUTER_API_KEY is not configured.")
    if not _current_openrouter_model:
        raise RuntimeError("No OpenRouter model configured.")

    url = f"{OPENROUTER_API_BASE.rstrip('/')}/chat/completions"
    payload = {
        "model": _current_openrouter_model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": OPENROUTER_TEMPERATURE,
        "max_tokens": OPENROUTER_MAX_TOKENS,
    }

    timeout = OPENROUTER_TIMEOUT_S if OPENROUTER_TIMEOUT_S > 0 else None
    resp = requests.post(
        url,
        headers=_openrouter_headers(),
        json=payload,
        timeout=timeout,
    )

    if resp.status_code >= 400:
        detail = resp.text
        try:
            body = resp.json()
            detail = body.get("error", {}).get("message") or body.get("message") or detail
        except Exception:
            pass
        if resp.status_code == 429:
            raise RuntimeError(f"OPENROUTER_QUOTA_EXCEEDED: {detail}")
        raise RuntimeError(f"OpenRouter HTTP {resp.status_code}: {detail}")

    data = resp.json()
    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError("OpenRouter response has no choices.")

    content = ((choices[0] or {}).get("message") or {}).get("content", "")
    if not content:
        raise RuntimeError("OpenRouter response content is empty.")
    return str(content)


def _query_openrouter_with_timeout(prompt: str):
    if OPENROUTER_USE_RETRIEVAL:
        if _openrouter_query_engine is None:
            raise RuntimeError("OpenRouter retrieval engine is not initialized")
        query_fn = _openrouter_query_engine.query
    else:
        query_fn = _openrouter_complete_text

    if OPENROUTER_TIMEOUT_S <= 0:
        return query_fn(prompt)

    future = _cloud_timeout_executor.submit(query_fn, prompt)
    try:
        return future.result(timeout=OPENROUTER_TIMEOUT_S)
    except FuturesTimeoutError as exc:
        future.cancel()
        if OPENROUTER_FALLBACK_LOCAL_ON_TIMEOUT:
            log.warning(
                "⏱️ OpenRouter timeout after %.1fs, fallback to local backend.",
                OPENROUTER_TIMEOUT_S,
            )
            return _get_local_query_engine().query(prompt)
        raise RuntimeError(
            f"OpenRouter timed out after {OPENROUTER_TIMEOUT_S:.1f}s."
        ) from exc


# =========================
# Public API
# =========================

def ask_socrates(user_message: str, history_context: str = "", model_choice: str = "ollama") -> str:
    if model_choice not in {"ollama", "openrouter"}:
        raise ValueError(
            f"Unsupported model_choice '{model_choice}'. Expected one of: ollama, openrouter."
        )

    base_prompt = f"""{SYSTEM_PROMPT}

{history_context}
Câu hỏi hiện tại:
{user_message}
"""

    cloud_mode = model_choice == "openrouter"

    if cloud_mode:
        prompt = (
            base_prompt
            + "\n"
            + STRICT_CLOUD_SUFFIX
        )
    else:
        prompt = base_prompt

    if cloud_mode:
        if not OPENROUTER_API_KEY:
            raise RuntimeError(
                "OpenRouter API key is missing. Please set OPENROUTER_API_KEY in .env."
            )
        if not _current_openrouter_model:
            _init_openrouter_model()

        log.info("🧠 Routing to OpenRouter (Cloud) [%s]...", _current_openrouter_model)
        try:
            response = _query_openrouter_with_timeout(prompt)
        except Exception as exc:
            error_text = str(exc)
            lower_error = error_text.lower()
            quota_like = (
                "openrouter_quota_exceeded" in lower_error
                or "429" in lower_error
                or "quota" in lower_error
                or "rate limit" in lower_error
            )
            if quota_like:
                if OPENROUTER_FALLBACK_LOCAL_ON_QUOTA:
                    log.warning(
                        "OpenRouter quota exhausted, falling back to local backend while keeping strict output formatting."
                    )
                    try:
                        response = _get_local_query_engine().query(base_prompt)
                    except Exception as local_exc:
                        raise RuntimeError(
                            f"OpenRouter quota exceeded and local fallback failed: {local_exc}"
                        ) from local_exc
                    return _enforce_socrates_style(_extract_response_text(response))

                raise RuntimeError(
                    "OpenRouter quota/rate limit exceeded for current API key. "
                    "Please retry later, switch model, or use AI mode (local backend)."
                ) from exc

            raise RuntimeError(f"OpenRouter request failed: {error_text}") from exc
    else:
        local_status = get_local_backend_status()
        log.info(
            "🧠 Routing to local backend (%s) at %s...",
            local_status["backend"],
            local_status["api_base"],
        )
        try:
            response = _get_local_query_engine().query(prompt)
        except Exception as exc:
            raise RuntimeError(f"Local model request failed: {exc}") from exc

    return _enforce_socrates_style(_extract_response_text(response))
