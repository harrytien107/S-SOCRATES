import logging
import os
import sys
from logging.handlers import RotatingFileHandler
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent.parent
DEFAULT_LOG_DIR = BASE_DIR / "logs"

# 10 MB per file, keep 5 backups (~50 MB max). Safe for multi-hour talkshow demos.
LOG_FILE_MAX_BYTES = int(os.getenv("LOG_FILE_MAX_BYTES", str(10 * 1024 * 1024)))
LOG_FILE_BACKUP_COUNT = int(os.getenv("LOG_FILE_BACKUP_COUNT", "5"))
LOG_FILE_NAME = os.getenv("LOG_FILE_NAME", "app.log")


def setup_logger():
    logger = logging.getLogger("SSocratesApp")
    logger.setLevel(logging.DEBUG)
    logger.propagate = False

    if logger.hasHandlers():
        logger.handlers.clear()

    formatter = logging.Formatter(
        '[%(asctime)s] %(levelname)-8s | %(filename)s:%(lineno)-3d | %(message)s',
        datefmt='%d-%m-%Y %H:%M:%S'
    )

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.DEBUG)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    log_dir = Path(os.getenv("LOG_DIR", str(DEFAULT_LOG_DIR)))
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        file_handler = RotatingFileHandler(
            filename=log_dir / LOG_FILE_NAME,
            maxBytes=LOG_FILE_MAX_BYTES,
            backupCount=LOG_FILE_BACKUP_COUNT,
            encoding="utf-8",
        )
        file_handler.setLevel(logging.INFO)
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
    except Exception as exc:
        logger.warning("Rotating file log disabled (%s): %s", log_dir, exc)

    # =======================================================
    # TẮT LOG RÁC TỪ CÁC THƯ VIỆN BÊN THỨ 3 (HuggingFace, HTTP...)
    # =======================================================
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("sentence_transformers").setLevel(logging.WARNING)
    logging.getLogger().setLevel(logging.WARNING)

    # MỞ LẠI LOG CHO TƯƠNG TÁC API FastAPI (Cái này giúp bạn thấy khi Flutter gọi Backend)
    logging.getLogger("uvicorn.access").setLevel(logging.INFO)

    return logger


log = setup_logger()
