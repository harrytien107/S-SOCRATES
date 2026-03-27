import time
from services.memory_service import memory_service
from services.llm_service import ask_socrates
from services.semantic_router import semantic_router
from utils.logger import log

def process_chat_message(message: str) -> str:
    log.info(f"\n[BẮT ĐẦU] Nhận yêu cầu Chat: '{message}'")
    start_time = time.time()
    
    # Retrieve conversation history
    history_context = memory_service.get_context_string()

    # 1. So khớp câu hỏi với bộ qa_presets.json thông qua Semantic Router
    semantic_router.reload_presets()
    preset_answer = semantic_router.get_best_match(message)
    
    if preset_answer:
        llm_time = (time.time() - start_time) * 1000
        log.info(f"👉 Đã bắt trúng kịch bản! Dùng đáp án mẫu. (Thời gian match Vector: {llm_time:.0f}ms)")
        response_text = preset_answer
    else:
        # 2. Nếu không khớp, truy vấn LLM / LlamaIndex core
        log.info("👉 Truyền câu nói vào LLM S-Socrates (Qwen2) kèm lịch sử...")
        llm_start = time.time()
        response_text = ask_socrates(message, history_context)
        llm_time = (time.time() - llm_start) * 1000
        log.info(f"👉 Kết quả LLM trả về: '{response_text}' (Thời gian suy nghĩ: {llm_time:.0f}ms)")
    
    # Save the new exchange to memory
    memory_service.save(message, response_text)
    
    total_time = (time.time() - start_time) * 1000
    log.info(f"[HOÀN THÀNH] Hoạt động Core/Chat xử lý xong. (Tổng tốn: {total_time:.0f}ms)\n")
    return response_text
