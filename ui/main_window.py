import os
from PyQt6.QtWidgets import QMainWindow, QPushButton, QVBoxLayout, QHBoxLayout, QWidget, QTextEdit
from PyQt6.QtCore import QUrl
from PyQt6.QtWebEngineWidgets import QWebEngineView
from PyQt6.QtWebEngineCore import QWebEngineSettings, QWebEnginePage

from utils.logger import log
from workers.ai_worker import AIVoiceWorker

class JSConsolePage(QWebEnginePage):
    def javaScriptConsoleMessage(self, level, message, lineNumber, sourceID):
        log.warning(f"JS Console [Line {lineNumber}]: {message}")

class TestVoiceUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("S-Socrates - AI Voice Assistant (3D Avatar)")
        log.info("Đang khởi tạo giao diện chính UI...")
        
        main_layout = QHBoxLayout()
        left_layout = QVBoxLayout()
        
        self.log_area = QTextEdit()
        self.log_area.setReadOnly(True)
        self.log_area.setStyleSheet("font-size: 16px; background: #000000; color: #ffffff; border-radius: 8px; padding: 10px;")
        left_layout.addWidget(self.log_area)
        
        self.btn_voice = QPushButton("🎤 Bấm để nói chuyện với AI")
        self.btn_voice.setStyleSheet("font-size: 20px; font-weight: bold; padding: 25px; background-color: #f44336; color: white; border-radius: 10px;")
        self.btn_voice.clicked.connect(self.start_voice_test)
        left_layout.addWidget(self.btn_voice)
        
        self.btn_stop = QPushButton("🛑 Dừng nói & Nộp câu hỏi ngay")
        self.btn_stop.setStyleSheet("font-size: 16px; font-weight: bold; padding: 15px; background-color: #FF9800; color: white; border-radius: 10px;")
        self.btn_stop.clicked.connect(self.stop_recording)
        self.btn_stop.hide()
        left_layout.addWidget(self.btn_stop)
        
        # Thiết lập trình duyệt nhúng WebEngine để load Avatar 3D
        log.debug("Khởi tạo QWebEngineView tải môi trường 3D Khởi nguyên...")
        self.web_view = QWebEngineView()
        
        # Bắt log lỗi JS
        self.web_page = JSConsolePage(self.web_view)
        self.web_view.setPage(self.web_page)
        
        # Bật cấu hình bỏ qua CORS để tránh lỗi web chặn tải model 3D
        settings = self.web_view.settings()
        settings.setAttribute(QWebEngineSettings.WebAttribute.LocalContentCanAccessRemoteUrls, True)
        settings.setAttribute(QWebEngineSettings.WebAttribute.LocalContentCanAccessFileUrls, True)
        
        # Bắt buộc cho phép AudioContext chạy mượt mà không cần màn hình Web bị click (Autoplay policy)
        settings.setAttribute(QWebEngineSettings.WebAttribute.PlaybackRequiresUserGesture, False)
        
        self.web_view.setMinimumWidth(700)
        
        avatar_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "avatar.html"))
        self.web_view.setUrl(QUrl.fromLocalFile(avatar_path))
        self.web_view.titleChanged.connect(self.on_title_changed)
        
        main_layout.addLayout(left_layout)
        main_layout.addWidget(self.web_view)
        
        widget = QWidget()
        widget.setLayout(main_layout)
        self.setCentralWidget(widget)
        self.resize(1300, 750)
        
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
        log.debug(f"Đẩy Voice Audio sang Nhân vật 3D WebEngine: {file_path}")
        self.current_audio_file = file_path
        
        safe_url = QUrl.fromLocalFile(file_path).toString()
        js_code = f"playSpeech('{safe_url}');"
        self.web_view.page().runJavaScript(js_code)
        
    def on_title_changed(self, title):
        if title == "AUDIO_ENDED":
            log.debug("Avatar 3D báo cáo đã phát xong. Tiến hành xóa Voice tạm...")
            if hasattr(self, 'current_audio_file') and os.path.exists(self.current_audio_file):
                try:
                    os.remove(self.current_audio_file)
                    log.debug("Đã xóa file tạm: " + self.current_audio_file)
                except Exception as e:
                    log.warning(f"Không thể xóa file tạm: {e}")
        
    def on_ai_response(self, text):
        if text:
            self.log_area.append(text)
        
        log.info("Kết thúc luồng. Sẵn sàng trò chuyện tiếp.\n")
        self.btn_voice.setText("🎤 Bấm để nói chuyện với AI")
        self.btn_voice.setStyleSheet("font-size: 20px; font-weight: bold; padding: 25px; background-color: #f44336; color: white; border-radius: 10px;")
        self.btn_voice.setEnabled(True)
        self.btn_stop.hide()
