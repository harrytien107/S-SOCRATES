import os
from PyQt6.QtWidgets import QMainWindow, QPushButton, QVBoxLayout, QWidget, QTextEdit
from PyQt6.QtCore import QUrl
from PyQt6.QtMultimedia import QMediaPlayer, QAudioOutput

from utils.logger import log
from workers.ai_worker import AIVoiceWorker

class TestVoiceUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("S-Socrates - AI Voice Assistant (Desktop)")
        log.info("Đang khởi tạo giao diện chính UI...")
        
        self.layout = QVBoxLayout()
        
        self.log_area = QTextEdit()
        self.log_area.setReadOnly(True)
        self.log_area.setStyleSheet("font-size: 16px; background: #000000; color: #ffffff; border-radius: 8px; padding: 10px;")
        self.layout.addWidget(self.log_area)
        
        self.btn_voice = QPushButton("🎤 Bấm để nói chuyện với AI")
        self.btn_voice.setStyleSheet("font-size: 20px; font-weight: bold; padding: 25px; background-color: #f44336; color: white; border-radius: 10px;")
        
        self.btn_voice.clicked.connect(self.start_voice_test)
        self.layout.addWidget(self.btn_voice)
        
        self.btn_stop = QPushButton("🛑 Dừng nói & Nộp câu hỏi ngay")
        self.btn_stop.setStyleSheet("font-size: 16px; font-weight: bold; padding: 15px; background-color: #FF9800; color: white; border-radius: 10px;")
        self.btn_stop.clicked.connect(self.stop_recording)
        self.btn_stop.hide()
        self.layout.addWidget(self.btn_stop)
        
        widget = QWidget()
        widget.setLayout(self.layout)
        self.setCentralWidget(widget)
        self.resize(700, 600)
        
        # Thiết lập trình phát âm thanh (Media Player) cho TTS
        log.debug("Khởi tạo QMediaPlayer Engine cho hệ thống...")
        self.player = QMediaPlayer()
        self.audio_output = QAudioOutput()
        self.player.setAudioOutput(self.audio_output)
        self.audio_output.setVolume(1.0)
        self.player.mediaStatusChanged.connect(self.on_media_status_changed)
        
        log.info("UI sẵn sàng chờ tương tác.")
    
    def start_voice_test(self):
        log.info("--- NGƯỜI DÙNG NHẤN NÚT GHI ÂM ---")
        self.btn_voice.setText("⏳ Đang nghe ... (Tối đa 30 giây)")
        self.btn_voice.setStyleSheet("font-size: 20px; padding: 25px; background-color: #9e9e9e; color: white; border-radius: 10px;")
        self.btn_voice.setEnabled(False) 
        self.btn_stop.show()
        
        self.worker = AIVoiceWorker()
        self.worker.progress_signal.connect(self.on_ai_progress)
        self.worker.finished_signal.connect(self.on_ai_response)
        self.worker.play_audio_signal.connect(self.play_audio)
        self.worker.start()
        
    def stop_recording(self):
        log.info("--- NGƯỜI DÙNG BẤM NÚT DỪNG GHI ÂM SỚM ---")
        if hasattr(self, 'worker'):
            self.worker.stop_recording()
        self.btn_stop.hide()
        self.btn_voice.setText("⏳ Đang xử lý AI...")
        
    def on_ai_progress(self, text):
        self.log_area.append(text)
        
    def play_audio(self, file_path):
        log.debug(f"Trình phát âm thanh kích hoạt cho file: {file_path}")
        self.current_audio_file = file_path
        self.player.setSource(QUrl.fromLocalFile(file_path))
        self.player.play()
        
    def on_media_status_changed(self, status):
        # MediaStatus.EndOfMedia là enum có giá trị bằng 7
        if status == QMediaPlayer.MediaStatus.EndOfMedia:
            log.debug("Phát lại kết thúc. Tiến hành dọn dẹp file MP3 tạm...")
            self.player.setSource(QUrl()) # Release file
            if hasattr(self, 'current_audio_file') and os.path.exists(self.current_audio_file):
                try:
                    os.remove(self.current_audio_file)
                    log.debug("Đã xóa vĩnh viễn file tạm: " + self.current_audio_file)
                except Exception as e:
                    log.warning(f"Không thể xóa file tạm: {e}")
        
    def on_ai_response(self, text):
        if text:
            self.log_area.append(text)
        
        log.info("Kết thúc luồng tương tác AI. Chờ lần nhấn tiếp theo.\n")
        self.btn_voice.setText("🎤 Bấm để nói chuyện với AI")
        self.btn_voice.setStyleSheet("font-size: 20px; font-weight: bold; padding: 25px; background-color: #f44336; color: white; border-radius: 10px;")
        self.btn_voice.setEnabled(True)
        self.btn_stop.hide()
