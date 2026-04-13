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
load_dotenv(dotenv_path=ENV_PATH, override=True)


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
    return TurboQuantConfig(
        autostart=_read_bool_env("LOCAL_LLM_AUTOSTART", True),
        timeout_s=float(os.getenv("LOCAL_LLM_TIMEOUT_S", "120")),
        host=os.getenv("LOCAL_LLM_HOST", "127.0.0.1"),
        port=int(os.getenv("LOCAL_LLM_PORT", "8011")),
        model_name=os.getenv("LOCAL_LLM_MODEL_NAME", "").strip(),
        gguf_path=os.getenv("LOCAL_LLM_GGUF_PATH", "").strip(),
        server_bin=os.getenv("TURBOQUANT_SERVER_BIN", "").strip(),
        cache_type=os.getenv("TURBOQUANT_CACHE_TYPE", "turbo2").strip(),
        ngl=int(os.getenv("TURBOQUANT_NGL", "99")),
        ctx=int(os.getenv("TURBOQUANT_CTX", "8192")),
        max_tokens=int(os.getenv("LOCAL_LLM_MAX_TOKENS", "256")),
        reasoning_budget=int(os.getenv("TURBOQUANT_REASONING_BUDGET", "0")),
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

        return OpenAILike(
            model=config.model_name,
            api_base=config.api_base,
            api_key="not-needed",
            context_window=config.ctx,
            is_chat_model=True,
            is_function_calling_model=False,
            timeout=config.timeout_s,
            max_tokens=config.max_tokens,
            temperature=0.2,
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

            log.info("Routing to TurboQuant local runtime...")
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

        return str(getattr(response, "text", response))


turboquant_runtime = TurboQuantRuntime()
