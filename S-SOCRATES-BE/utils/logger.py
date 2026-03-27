import logging
import sys

def setup_logger():
    # Cấu hình logging chuyên nghiệp hiển thị dưới terminal
    logger = logging.getLogger("SSocratesApp")
    logger.setLevel(logging.DEBUG)
    
    # Ngăn log nhảy lên root logger gây tình trạng in ra 2 lần
    logger.propagate = False
    
    # Xoá các handler cũ nếu có
    if logger.hasHandlers():
        logger.handlers.clear()
        
    # Tạo console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.DEBUG)
    
    # Định dạng chuỗi log
    formatter = logging.Formatter(
        '[%(asctime)s] %(levelname)-8s | %(filename)s:%(lineno)-3d | %(message)s',
        datefmt='%d-%m-%Y %H:%M:%S'
    )
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    
    # =======================================================
    # TẮT LOG RÁC TỪ CÁC THƯ VIỆN BÊN THỨ 3 (HuggingFace, HTTP...)
    # =======================================================
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("sentence_transformers").setLevel(logging.WARNING)
    # Tắt log rác chung từ Root để tránh bị in HTTP Request
    logging.getLogger().setLevel(logging.WARNING)
    
    # MỞ LẠI LOG CHO TƯƠNG TÁC API FastAPI (Cái này giúp bạn thấy khi Flutter gọi Backend)
    logging.getLogger("uvicorn.access").setLevel(logging.INFO)
    
    return logger

log = setup_logger()