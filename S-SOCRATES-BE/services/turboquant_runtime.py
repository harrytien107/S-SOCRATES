from __future__ import annotations

import os
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from urllib import request

from dotenv import load_dotenv

from services.prompt_config import BASE_DIR
from utils.logger import log


ENV_PATH = BASE_DIR / ".env"
load_dotenv(dotenv_path=ENV_PATH, override=False)


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


@dataclass(frozen=True)
class TurboQuantConfig:
    autostart: bool
    timeout_s: float
    host: str
    port: int
    model_name: str
    gguf_path: str
    server_bin: str
    cache_type: str
    ngl: int
    ctx: int
    max_tokens: int
    reasoning_budget: int

    @property
    def health_url(self) -> str:
        return f"http://{self.host}:{self.port}/health"

    @property
    def api_base(self) -> str:
        return f"http://{self.host}:{self.port}/v1"


def load_turboquant_config() -> TurboQuantConfig:
    def _env(*names: str, default: str = "") -> str:
        for name in names:
            value = os.getenv(name)
            if value is not None and value.strip() != "":
                return value.strip()
        return default

    return TurboQuantConfig(
        autostart=_read_bool_env("LOCAL_LLM_AUTOSTART", True),
        port=int(_env("LOCAL_LLM_PORT", default="8011")),
        timeout_s=float(_env("LOCAL_TIMEOUT_S", default="300")),
        host=_env("LOCAL_HOST", default="127.0.0.1"),
        model_name=_env("LOCAL_MODEL_NAME"),
        gguf_path=_env("LOCAL_GGUF_PATH"),
        server_bin=_env("LOCAL_SERVER_BIN"),
        cache_type=_env("LOCAL_CACHE_TYPE", default="turbo2"),
        ngl=int(_env("LOCAL_NGL", default="99")),
        ctx=int(_env("LOCAL_CTX", default="8192")),
        max_tokens=int(_env("LOCAL_MAX_TOKENS", default="256")),
        reasoning_budget=int(_env("LOCAL_REASONING_BUDGET", default="0")),
    )


class TurboQuantRuntime:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._llm = None
        self._managed_process: Optional[subprocess.Popen] = None
        self._managed_command = None
        self._stdout_handle = None
        self._stderr_handle = None
        self._last_warm_context: str | None = None
        self._context_warmed = False
        self._logs_dir = BASE_DIR / "logs"
        self._stdout_log_path = self._logs_dir / "turboquant.stdout.log"
        self._stderr_log_path = self._logs_dir / "turboquant.stderr.log"
        self._status = {
            "phase": "stopped",
            "detail": "TurboQuant runtime is stopped.",
            "updated_at": time.time(),
            "last_warm_ms": None,
            "last_generate_ms": None,
            "last_error": None,
        }

    def _set_status(self, phase: str, detail: str, **extra) -> None:
        self._status.update(
            {
                "phase": phase,
                "detail": detail,
                "updated_at": time.time(),
            }
        )
        self._status.update(extra)

    def _build_client(self, config: TurboQuantConfig):
        try:
            from llama_index.llms.openai_like import OpenAILike
        except ImportError as exc:
            raise RuntimeError(
                "Missing package llama-index-llms-openai-like. "
                "Please run `pip install -r requirements.txt`."
            ) from exc

        temperature = float(os.getenv("LOCAL_LLM_TEMPERATURE", "0.35"))
        frequency_penalty = float(os.getenv("LOCAL_LLM_FREQUENCY_PENALTY", "0.2"))
        presence_penalty = float(os.getenv("LOCAL_LLM_PRESENCE_PENALTY", "0.15"))
        top_p = float(os.getenv("LOCAL_LLM_TOP_P", "0.9"))

        stop_sequences = [
            "\nNgười hỏi:",
            "\nUser:",
            "\nS-Socrates:",
            "\nS-SOCRATES:",
            "\n---",
            "\n\n##",
            "<|eot_id|>",
            "<|end_of_text|>",
        ]

        additional_kwargs: dict = {
            "stop": stop_sequences,
            "frequency_penalty": frequency_penalty,
            "presence_penalty": presence_penalty,
            "top_p": top_p,
        }

        min_p_env = os.getenv("LOCAL_LLM_MIN_P", "").strip()
        if min_p_env:
            try:
                additional_kwargs["extra_body"] = {"min_p": float(min_p_env)}
            except ValueError:
                pass

        return OpenAILike(
            model=config.model_name,
            api_base=config.api_base,
            api_key="not-needed",
            context_window=config.ctx,
            is_chat_model=True,
            is_function_calling_model=False,
            timeout=config.timeout_s,
            max_tokens=config.max_tokens,
            temperature=temperature,
            additional_kwargs=additional_kwargs,
        )

    def _start_process(self, config: TurboQuantConfig) -> subprocess.Popen:
        if not config.server_bin:
            raise RuntimeError("TURBOQUANT_SERVER_BIN is not configured.")
        if not config.gguf_path:
            raise RuntimeError("LOCAL_LLM_GGUF_PATH is not configured.")
        if not Path(config.server_bin).exists():
            raise RuntimeError(f"Could not find llama-server binary at {config.server_bin}")
        if not Path(config.gguf_path).exists():
            raise RuntimeError(f"Could not find GGUF model at {config.gguf_path}")

        cmd = [
            config.server_bin,
            "--host",
            config.host,
            "--port",
            str(config.port),
            "-m",
            config.gguf_path,
            "-ngl",
            str(config.ngl),
            "-c",
            str(config.ctx),
            "--flash-attn",
            "on",
            "--cache-type-k",
            config.cache_type,
            "--cache-type-v",
            config.cache_type,
            "--reasoning-budget",
            str(config.reasoning_budget),
            "--jinja",
        ]
        log.info("Starting TurboQuant runtime at %s using model %s", config.api_base, config.gguf_path)
        self._logs_dir.mkdir(parents=True, exist_ok=True)
        self._stdout_handle = self._stdout_log_path.open("a", encoding="utf-8")
        self._stderr_handle = self._stderr_log_path.open("a", encoding="utf-8")
        self._stdout_handle.write(f"\n===== START {time.strftime('%Y-%m-%d %H:%M:%S')} =====\n")
        self._stderr_handle.write(f"\n===== START {time.strftime('%Y-%m-%d %H:%M:%S')} =====\n")
        self._stdout_handle.flush()
        self._stderr_handle.flush()
        return subprocess.Popen(
            cmd,
            stdout=self._stdout_handle,
            stderr=self._stderr_handle,
            cwd=str(BASE_DIR),
        )

    def initialize(self, force_restart: bool = False) -> None:
        config = load_turboquant_config()
        with self._lock:
            if force_restart:
                self.shutdown()
            elif self._llm is not None:
                return

            self._set_status("starting", "TurboQuant runtime is starting...")
            if _http_ready(config.health_url, timeout=min(config.timeout_s, 5.0)):
                log.info("Reusing existing TurboQuant runtime at %s", config.api_base)
                self._llm = self._build_client(config)
                phase = "ready" if self._context_warmed else "cold"
                detail = (
                    "TurboQuant runtime is ready."
                    if self._context_warmed
                    else "TurboQuant runtime is online, but previous-session context has not been loaded yet."
                )
                self._set_status(phase, detail, last_error=None)
                return

            if not config.autostart:
                self._set_status(
                    "error",
                    "TurboQuant runtime is not ready and LOCAL_LLM_AUTOSTART=0.",
                    last_error="LOCAL_LLM_AUTOSTART=0",
                )
                raise RuntimeError(
                    f"TurboQuant runtime is not ready at {config.api_base} and LOCAL_LLM_AUTOSTART=0."
                )

            self.shutdown()
            process = self._start_process(config)
            self._managed_process = process
            self._managed_command = process.args

            ready = _wait_until_ready(
                lambda: _http_ready(config.health_url, timeout=min(config.timeout_s, 5.0)),
                timeout_s=min(max(config.timeout_s, 30.0), 180.0),
            )
            if not ready:
                self.shutdown()
                self._set_status(
                    "error",
                    f"TurboQuant runtime is not ready at {config.api_base}.",
                    last_error="runtime_not_ready",
                )
                raise RuntimeError(
                    f"TurboQuant runtime is not ready at {config.api_base}."
                )

            self._llm = self._build_client(config)
            phase = "ready" if self._context_warmed else "cold"
            detail = (
                "TurboQuant runtime is ready."
                if self._context_warmed
                else "TurboQuant runtime is online, but previous-session context has not been loaded yet."
            )
            self._set_status(phase, detail, last_error=None)
            log.info(
                "TurboQuant runtime ready: host=%s port=%s model=%s ctx=%s cache=%s",
                config.host,
                config.port,
                config.model_name,
                config.ctx,
                config.cache_type,
            )

    def shutdown(self) -> None:
        with self._lock:
            process = self._managed_process
            command = self._managed_command
            self._llm = None
            self._managed_process = None
            self._managed_command = None
            self._last_warm_context = None
            self._context_warmed = False
            self._set_status(
                "stopped",
                "TurboQuant runtime is stopped.",
                last_warm_ms=None,
                last_generate_ms=None,
            )

            if process is None:
                return

            log.info("Stopping app-managed TurboQuant runtime")
            try:
                process.terminate()
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                log.warning("TurboQuant runtime did not stop in time, killing it.")
                process.kill()
                process.wait(timeout=5)
            except Exception as exc:
                log.error("Failed to stop TurboQuant runtime (%s): %s", command, exc)
            finally:
                if self._stdout_handle is not None:
                    self._stdout_handle.close()
                    self._stdout_handle = None
                if self._stderr_handle is not None:
                    self._stderr_handle.close()
                    self._stderr_handle = None

    def get_status(self) -> dict:
        config = load_turboquant_config()
        with self._lock:
            ready = _http_ready(config.health_url, timeout=min(config.timeout_s, 5.0))
            phase = self._status["phase"]
            detail = self._status["detail"]
            if not ready and phase not in {"starting", "warming", "generating", "error", "stopped"}:
                phase = "offline"
                detail = "TurboQuant runtime is offline."
            return {
                "backend": "turboquant",
                "host": config.host,
                "port": config.port,
                "api_base": config.api_base,
                "model_name": config.model_name,
                "gguf_path": config.gguf_path or None,
                "autostart": config.autostart,
                "ready": ready,
                "managed_by_app": self._managed_process is not None,
                "ctx": config.ctx,
                "cache_type": config.cache_type,
                "max_tokens": config.max_tokens,
                "reasoning_budget": config.reasoning_budget,
                "phase": phase,
                "detail": detail,
                "context_warmed": self._context_warmed,
                "updated_at": self._status["updated_at"],
                "last_warm_ms": self._status["last_warm_ms"],
                "last_generate_ms": self._status["last_generate_ms"],
                "last_error": self._status["last_error"],
                "stdout_log_path": str(self._stdout_log_path),
                "stderr_log_path": str(self._stderr_log_path),
            }

    def warm_context(self, context_text: str) -> None:
        normalized = (context_text or "").strip()
        if not normalized:
            return

        with self._lock:
            if self._llm is None:
                self.initialize()
            assert self._llm is not None

            if normalized == self._last_warm_context:
                if self._context_warmed:
                    self._set_status("ready", "TurboQuant has already restored the previous-session context.", last_error=None)
                return

            warm_prompt = (
                "Hay doc va ghi nho ngu canh hoi thoai sau de phuc vu cac luot hoi tiep theo.\n"
                "Khong can tra loi dai, chi can xac nhan da nap ngu canh.\n\n"
                f"{normalized}"
            )
            self._set_status("warming", "TurboQuant is restoring previous-session context...", last_error=None)
            warm_start = time.time()
            try:
                self._llm.complete(warm_prompt)
                self._last_warm_context = normalized
                self._context_warmed = True
                warm_ms = (time.time() - warm_start) * 1000
                self._set_status(
                    "ready",
                    "TurboQuant has restored context and is ready to answer.",
                    last_warm_ms=round(warm_ms, 2),
                    last_error=None,
                )
                log.info("TurboQuant runtime warmed with persistent conversation context.")
            except Exception as exc:
                self._set_status(
                    "error",
                    "TurboQuant failed to restore context.",
                    last_error=str(exc),
                )
                raise RuntimeError(f"TurboQuant context warmup failed: {exc}") from exc

    def generate(self, prompt: str) -> str:
        normalized_prompt = (prompt or "").strip()
        if not normalized_prompt:
            return ""

        config = load_turboquant_config()
        with self._lock:
            if self._llm is None:
                self.initialize()
            assert self._llm is not None

            log.info("Routing to TurboQuant local runtime (complete)...")
            self._set_status("generating", "TurboQuant is generating a response...", last_error=None)
            generate_start = time.time()
            try:
                response = self._llm.complete(normalized_prompt)
            except Exception as exc:
                self._set_status(
                    "error",
                    "TurboQuant inference failed.",
                    last_error=str(exc),
                )
                log.error(
                    "TurboQuant request failed after timeout=%ss. Check logs: stdout=%s stderr=%s",
                    config.timeout_s,
                    self._stdout_log_path,
                    self._stderr_log_path,
                )
                raise RuntimeError(f"TurboQuant local model request failed: {exc}") from exc
            generate_ms = (time.time() - generate_start) * 1000
            ready_detail = (
                "TurboQuant is ready and context has been restored."
                if self._context_warmed
                else "TurboQuant is ready."
            )
            self._set_status(
                "ready",
                ready_detail,
                last_generate_ms=round(generate_ms, 2),
                last_error=None,
            )

        return _clean_llm_output(str(getattr(response, "text", response)))

    def generate_chat(self, messages: list[dict]) -> str:
        """Generate a response using the chat API.

        `messages` is a list of {"role": "system"|"user"|"assistant", "content": str}.
        The runtime converts them to llama-index ChatMessage and calls `llm.chat(...)`.
        """
        if not messages:
            return ""

        try:
            from llama_index.core.base.llms.types import ChatMessage, MessageRole
        except ImportError:
            from llama_index.core.llms import ChatMessage, MessageRole

        role_map = {
            "system": MessageRole.SYSTEM,
            "user": MessageRole.USER,
            "assistant": MessageRole.ASSISTANT,
        }

        chat_messages = []
        for m in messages:
            role = role_map.get(str(m.get("role", "user")).lower(), MessageRole.USER)
            content = str(m.get("content", "")).strip()
            if not content:
                continue
            chat_messages.append(ChatMessage(role=role, content=content))

        if not chat_messages:
            return ""

        config = load_turboquant_config()
        with self._lock:
            if self._llm is None:
                self.initialize()
            assert self._llm is not None

            log.info(
                "Routing to TurboQuant local runtime (chat, %d messages)...",
                len(chat_messages),
            )
            self._set_status("generating", "TurboQuant is generating a response...", last_error=None)
            generate_start = time.time()
            try:
                response = self._llm.chat(chat_messages)
            except Exception as exc:
                self._set_status(
                    "error",
                    "TurboQuant inference failed.",
                    last_error=str(exc),
                )
                log.error(
                    "TurboQuant chat request failed after timeout=%ss. Check logs: stdout=%s stderr=%s",
                    config.timeout_s,
                    self._stdout_log_path,
                    self._stderr_log_path,
                )
                raise RuntimeError(f"TurboQuant local chat request failed: {exc}") from exc
            generate_ms = (time.time() - generate_start) * 1000
            ready_detail = (
                "TurboQuant is ready and context has been restored."
                if self._context_warmed
                else "TurboQuant is ready."
            )
            self._set_status(
                "ready",
                ready_detail,
                last_generate_ms=round(generate_ms, 2),
                last_error=None,
            )

        msg = getattr(response, "message", None)
        text = getattr(msg, "content", None) if msg is not None else None
        if text is None:
            text = str(response)
        return _clean_llm_output(str(text))


_TRAILING_CUT_MARKERS = (
    "\nNgười hỏi:",
    "\nNguoi hoi:",
    "\nUser:",
    "\nUSER:",
    "\nS-Socrates:",
    "\nS-SOCRATES:",
    "\n---",
    "\n##",
)


def _clean_llm_output(text: str) -> str:
    """Strip any hallucinated follow-up turns and collapse repetitive sentences."""
    if not text:
        return ""

    cleaned = text.strip()

    for marker in _TRAILING_CUT_MARKERS:
        idx = cleaned.find(marker)
        if idx > 0:
            cleaned = cleaned[:idx].rstrip()

    for prefix in ("S-Socrates:", "S-SOCRATES:", "S-socrates:"):
        if cleaned.lower().startswith(prefix.lower()):
            cleaned = cleaned[len(prefix):].lstrip()

    if cleaned.startswith('"') and cleaned.endswith('"') and cleaned.count('"') == 2:
        cleaned = cleaned[1:-1].strip()

    sentences: list[str] = []
    seen_normalized: set[str] = set()
    buf = ""
    for char in cleaned:
        buf += char
        if char in ".!?":
            sentence = buf.strip()
            norm = "".join(ch.lower() for ch in sentence if ch.isalnum())
            if sentence and norm and norm not in seen_normalized:
                sentences.append(sentence)
                seen_normalized.add(norm)
            buf = ""
    tail = buf.strip()
    if tail:
        norm = "".join(ch.lower() for ch in tail if ch.isalnum())
        if norm and norm not in seen_normalized:
            sentences.append(tail)

    return " ".join(sentences).strip() or cleaned


turboquant_runtime = TurboQuantRuntime()
