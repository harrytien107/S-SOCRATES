import os
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from urllib import request

from dotenv import load_dotenv
from llama_index.core import SimpleDirectoryReader, VectorStoreIndex
from llama_index.core.settings import Settings
from llama_index.embeddings.huggingface import HuggingFaceEmbedding
from llama_index.llms.ollama import Ollama

from utils.logger import log

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent
KNOWLEDGE_DIR = BASE_DIR / "knowledge"
PROMPT_PATH = KNOWLEDGE_DIR / "uth.txt"


def _read_bool_env(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


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

    @property
    def active_model_name(self) -> str:
        if self.backend == "ollama":
            return self.ollama_model_name
        return self.model_name


def _load_local_config() -> LocalLLMConfig:
    backend = os.getenv("LOCAL_LLM_BACKEND", "ollama").strip().lower()
    if backend not in {"ollama", "turboquant"}:
        raise ValueError("LOCAL_LLM_BACKEND phải là 'ollama' hoặc 'turboquant'.")

    default_port = 11434 if backend == "ollama" else 8011
    default_model = "qwen2:1.5b"
    return LocalLLMConfig(
        backend=backend,
        autostart=_read_bool_env("LOCAL_LLM_AUTOSTART", True),
        timeout_s=float(os.getenv("LOCAL_LLM_TIMEOUT_S", "120")),
        host=os.getenv("LOCAL_LLM_HOST", "127.0.0.1"),
        port=int(os.getenv("LOCAL_LLM_PORT", str(default_port))),
        model_name=os.getenv(
            "LOCAL_LLM_MODEL_NAME",
            os.getenv("OLLAMA_MODEL_NAME", default_model),
        ).strip(),
        gguf_path=os.getenv("LOCAL_LLM_GGUF_PATH", "").strip(),
        ollama_cmd=os.getenv("OLLAMA_CMD", "ollama").strip(),
        ollama_model_name=os.getenv("OLLAMA_MODEL_NAME", default_model).strip(),
        turboquant_server_bin=os.getenv("TURBOQUANT_SERVER_BIN", "").strip(),
        turboquant_cache_type=os.getenv("TURBOQUANT_CACHE_TYPE", "turbo2").strip(),
        turboquant_ngl=int(os.getenv("TURBOQUANT_NGL", "99")),
        turboquant_ctx=int(os.getenv("TURBOQUANT_CTX", "8192")),
    )


_embed_model = HuggingFaceEmbedding(
    model_name="sentence-transformers/all-MiniLM-L6-v2"
)
Settings.embed_model = _embed_model
_documents = SimpleDirectoryReader(str(KNOWLEDGE_DIR)).load_data()
_index = VectorStoreIndex.from_documents(_documents)


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
            log.error(
                "❌ Failed to stop local backend %s (%s): %s",
                backend,
                command,
                exc,
            )


def initialize_local_backend(force_restart: bool = False) -> None:
    global _local_query_engine, _local_backend_name
    global _managed_local_process, _managed_local_backend, _managed_local_command

    config = _load_local_config()
    with _runtime_lock:
        if force_restart:
            shutdown_local_backend()
        elif _local_query_engine is not None and _local_backend_name == config.backend:
            return
        elif (
            _managed_local_process is not None
            and _managed_local_backend != config.backend
        ):
            shutdown_local_backend()

        if _is_backend_ready(config):
            log.info(
                "✅ Reusing existing %s local backend at %s (model=%s)",
                config.backend,
                config.api_base,
                config.active_model_name,
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
            config.active_model_name,
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
            "model_name": config.active_model_name,
            "gguf_path": config.gguf_path or None,
            "autostart": config.autostart,
            "ready": _is_backend_ready(config),
            "managed_by_app": _managed_local_process is not None,
        }

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
# Gemini (Cloud) - Dynamic Model
# =========================

_gemini_engine = None
_current_gemini_model = None

AVAILABLE_GEMINI_MODELS = [
    "models/gemini-2.0-flash",
    "models/gemini-2.0-flash-lite",
    "models/gemini-1.5-flash",
    "models/gemini-1.5-pro",
]


def _init_gemini_engine(model_name: str = "models/gemini-2.0-flash"):
    global _gemini_engine, _current_gemini_model
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        log.warning("⚠️ GEMINI_API_KEY not found in .env. Gemini engine disabled.")
        return

    try:
        from llama_index.llms.gemini import Gemini

        llm = Gemini(
            model=model_name,
            api_key=api_key,
        )
        _gemini_engine = _index.as_query_engine(llm=llm)
        _current_gemini_model = model_name
        log.info(f"✅ Gemini Query Engine ({model_name}) initialized.")
    except Exception as exc:
        log.error(f"❌ Failed to initialize Gemini engine: {exc}")
        _gemini_engine = None


_init_gemini_engine()


def switch_gemini_model(model_name: str):
    global _current_gemini_model
    if model_name == _current_gemini_model:
        return
    log.info(f"🔄 Switching Gemini model: {_current_gemini_model} → {model_name}")
    _init_gemini_engine(model_name)


def ask_socrates(
    user_message: str,
    history_context: str = "",
    model_choice: str = "ollama",
) -> str:
    prompt = f"""{SYSTEM_PROMPT}

{history_context}
Câu hỏi hiện tại:
{user_message}
"""

    if model_choice == "gemini":
        if _gemini_engine is None:
            log.error("Gemini engine is not available. Falling back to local backend.")
            response = _get_local_query_engine().query(prompt)
        else:
            log.info(f"🧠 Routing to Gemini (Cloud) [{_current_gemini_model}]...")
            response = _gemini_engine.query(prompt)
    else:
        config = _load_local_config()
        log.info(
            "🧠 Routing to local backend (%s) at %s...",
            config.backend,
            config.api_base,
        )
        response = _get_local_query_engine().query(prompt)

    return str(response)
