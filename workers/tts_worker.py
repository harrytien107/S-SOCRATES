import os
import asyncio
import edge_tts
from PyQt6.QtCore import QThread, pyqtSignal
from utils.logger import log

class TTSWorker(QThread):
    progress_signal = pyqtSignal(str)
    play_audio_signal = pyqtSignal(str)
    finished_signal = pyqtSignal()
    
    def __init__(self, text_to_speak):
        super().__init__()
        self.text_to_speak = text_to_speak
        
    def run(self):
        try:
            log.info("Chạy quy trình TTS (Admin Manual)...")
            self.progress_signal.emit("🔊 Đang nạp tiếng nói (TTS) từ đáp án mẫu...")
            tts_file = os.path.abspath("temp_admin_reply.mp3") 
            
            async def generate_speech():
                communicate = edge_tts.Communicate(self.text_to_speak, "vi-VN-HoaiMyNeural")
                await communicate.save(tts_file)
                
            asyncio.run(generate_speech())
            
            log.info("Phát tín hiệu Play Audio về giao diện Admin UI.")
            self.play_audio_signal.emit(tts_file)
            self.finished_signal.emit()
            
        except Exception as e:
            log.error(f"Lỗi TTS văng ra ở quá trình Admin: {e}")
            self.progress_signal.emit(f"⚠️ Lỗi tạo âm thanh: {e}")
            self.finished_signal.emit()
