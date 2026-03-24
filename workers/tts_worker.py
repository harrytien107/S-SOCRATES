import os
from PyQt6.QtCore import QThread, pyqtSignal
from utils.logger import log
from services.tts_service import generate_speech_file


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
            self.progress_signal.emit("🔊 Đang nạp tiếng nói (Google Chirp 3 HD) từ đáp án mẫu...")
            tts_file = os.path.abspath("voice/temp_admin_reply.mp3")
            
            generate_speech_file(self.text_to_speak, tts_file)
            
            log.info("Phát tín hiệu Play Audio về giao diện Admin UI.")
            self.play_audio_signal.emit(tts_file)
            self.finished_signal.emit()
            
        except Exception as e:
            log.error(f"Lỗi TTS văng ra ở quá trình Admin: {e}")
            self.progress_signal.emit(f"⚠️ Lỗi tạo âm thanh: {e}")
            self.finished_signal.emit()
