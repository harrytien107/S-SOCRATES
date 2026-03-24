import os
import time
import tempfile
import wave
import numpy as np
import sounddevice as sd

from utils.logger import log

from services.stt_service import transcribe_file
from services.llm_service import ask_socrates
from services.memory_service import memory_service
from services.tts_service import generate_speech_file

from PyQt6.QtCore import QThread, pyqtSignal

class AIVoiceWorker(QThread):
    progress_signal = pyqtSignal(str)
    finished_signal = pyqtSignal(str)
    play_audio_signal = pyqtSignal(str)
    
    def __init__(self):
        super().__init__()
        self.is_recording = True
        
    def stop_recording(self):
        self.is_recording = False
        log.info("Lệnh yêu cầu cắt ghi âm SỚM được kích hoạt.")
        
    def run(self):
        try:
            log.info("Bắt đầu luồng xử lý AI Voice Worker...")
            start_time = time.time()
            
            # --- 1. RECORD LOCAL AUDIO ---
            fs = 16000
            duration = 30.0
            SILENCE_DURATION = 1.0  # Chờ 1 giây im lặng để nộp
            
            log.info(f"Yêu cầu micrphone. Bắt đầu thu âm ({duration} giây tối đa)...")
            
            audio_data = []
            
            def audio_callback(indata, frames, time_info, status):
                if self.is_recording:
                    audio_data.append(indata.copy())
                    
            with sd.InputStream(samplerate=fs, channels=1, dtype='int16', callback=audio_callback):
                rec_start = time.time()
                has_spoken = False
                silence_start = None
                
                while self.is_recording and (time.time() - rec_start) < duration:
                    time.sleep(0.1)
                    
                    if len(audio_data) > 0:
                        # Phân tích âm lượng của đoạn 1/10 giây gần nhất
                        recent = audio_data[-1]
                        vol = np.max(np.abs(recent))
                        
                        # vol trên 1500 (khoảng 5% peak) là có tiếng nói
                        if vol > 1500:
                            has_spoken = True
                            silence_start = None
                        # vol dưới 800 là môi trường im lặng
                        elif has_spoken and vol < 800:
                            if silence_start is None:
                                silence_start = time.time()
                            elif time.time() - silence_start > SILENCE_DURATION:
                                log.info("Phát hiện kết thúc câu nói (im lặng 1s). Tự động cắt ghi âm!")
                                self.is_recording = False
                                break
                                
            log.debug("Đã thu âm xong. Giải phóng microphone.")
            
            if len(audio_data) > 0:
                myrecording = np.concatenate(audio_data, axis=0)
            else:
                myrecording = np.zeros((0, 1), dtype='int16')
            
            temp_wav = tempfile.mktemp(suffix=".wav")
            with wave.open(temp_wav, 'wb') as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(fs)
                wf.writeframes(myrecording.tobytes())
            log.debug(f"Đã lưu cache audio tạm thời tại {temp_wav}")
                
            # --- 2. THỰC THI STT (Deepgram REST API) ---
            log.info("Khởi chạy Deepgram STT...")
            stt_start = time.time()
            text = transcribe_file(temp_wav)
            
            if os.path.exists(temp_wav):
                os.remove(temp_wav)
                
            stt_time = (time.time() - stt_start) * 1000
            log.info(f"Kết quả Deepgram: '{text}' (thời gian: {stt_time:.0f}ms)")
            
            if not text:
                log.warning("Audio trống hoặc Deepgram không nhận dạng được.")
                self.progress_signal.emit("❌ Không nghe rõ âm thanh, hãy bấm nói lại lần nữa nhé!")
                self.finished_signal.emit("")
                return
                
            self.progress_signal.emit(f"🧑 Bạn: {text}")
            
            # --- 3. THỰC THI SEMANTIC ROUTER HOẶC LLM (Qwen2) ---
            from services.semantic_router import semantic_router
            
            log.info("Kiểm tra sự trùng khớp với bộ script Câu hỏi mẫu (Semantic Router)...")
            semantic_router.reload_presets() # Load data mới nhỡ Admin thêm
            
            llm_start = time.time()
            preset_answer = semantic_router.get_best_match(text, threshold=0.75)
            
            if preset_answer:
                response = preset_answer
                llm_time = (time.time() - llm_start) * 1000
                log.info(f"Đã bắt trúng kịch bản! Dùng đáp án mẫu. (Thời gian match Vector: {llm_time:.0f}ms)")
            else:
                log.info("Truyền câu nói vào LLM S-Socrates (Qwen2) kèm lịch sử...")
                
                # Load memory history
                history = memory_service.get_context_string()
                
                # Gọi LLM
                response = ask_socrates(text, history)
                
                llm_time = (time.time() - llm_start) * 1000
                log.info(f"Kết quả LLM: '{response}' (Thời gian chạy Qwen2: {llm_time:.0f}ms)")
                
            # Lưu đoạn hội thoại vào memory
            memory_service.save(text, response)
            
            # --- 4. THỰC THI TTS (Google Chirp 3 HD) ---
            log.info("Chạy quy trình TTS (Google Cloud Chirp 3 HD)...")
            tts_start = time.time()
            
            tts_file = os.path.abspath("voice/temp_reply.mp3")
            generate_speech_file(response, tts_file)
            
            tts_time = (time.time() - tts_start) * 1000
            log.info(f"TTS Engine đã ghi file thành công tại {tts_file} (thời gian: {tts_time:.0f}ms)")
            
            total_time = (time.time() - start_time) * 1000
            log.info(f"Hoạt động Core xử lý xong. Tổng thời gian tốn {total_time:.0f}ms")
            
            self.progress_signal.emit(f"🤖 S-Socrates: {response}\n")
            
            # --- 5. BÁO HIỆU UI PHÁT ÂM THANH ---
            log.debug("Phát tín hiệu Play Audio về giao diện chính UI.")
            self.play_audio_signal.emit(tts_file)
            
            self.finished_signal.emit("")
            
        except Exception as e:
            log.error("Lỗi nghiêm trọng trong quá trình AI Worker chạy!", exc_info=True)
            self.progress_signal.emit("⚠️ Lỗi hệ thống, vui lòng xem Terminal.")
            self.finished_signal.emit("")
