import logging
import sys

def setup_logger():
    # Cấu hình logging chuyên nghiệp hiển thị dưới terminal
    logger = logging.getLogger("SSocratesApp")
    logger.setLevel(logging.DEBUG)
    
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
    return logger

log = setup_logger()
