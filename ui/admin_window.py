import os
import json
from PyQt6.QtWidgets import (QMainWindow, QVBoxLayout, QHBoxLayout, QWidget, 
                             QPushButton, QListWidget, QLineEdit, QTextEdit, QLabel, QMessageBox)
from PyQt6.QtCore import QUrl
from PyQt6.QtMultimedia import QMediaPlayer, QAudioOutput

from utils.logger import log
from workers.tts_worker import TTSWorker

PRESETS_FILE = "qa_presets.json"

class AdminUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("S-Socrates - Backstage Control Panel")
        self.presets = self.load_presets()
        
        self.layout = QVBoxLayout()
        
        # --- Danh sách QA Mẫu ---
        self.layout.addWidget(QLabel("<b>Danh sách Câu Hỏi & Đáp Án Mẫu:</b>"))
        self.list_widget = QListWidget()
        self.list_widget.currentRowChanged.connect(self.on_select_preset)
        self.layout.addWidget(self.list_widget)
        self.refresh_list()
        
        # --- Vùng soạn thảo câu hỏi (nhãn) và đáp án (âm thanh) ---
        self.q_input = QLineEdit()
        self.q_input.setPlaceholderText("Nhập câu hỏi dự kiến của diễn giả...")
        self.layout.addWidget(self.q_input)
        
        self.a_input = QTextEdit()
        self.a_input.setPlaceholderText("Nhập Đáp án mẫu S-Socrates muốn phát ra...")
        self.a_input.setFixedHeight(120)
        self.layout.addWidget(self.a_input)
        
        # --- Nút Thêm sửa xóa ---
        btn_layout = QHBoxLayout()
        self.btn_add = QPushButton("💾 Thêm mới / Cập nhật")
        self.btn_add.setStyleSheet("background-color: #4CAF50; color: white; font-weight: bold; padding: 10px;")
        self.btn_add.clicked.connect(self.save_preset)
        btn_layout.addWidget(self.btn_add)
        
        self.btn_del = QPushButton("❌ Xóa")
        self.btn_del.setStyleSheet("background-color: #f44336; color: white; font-weight: bold; padding: 10px;")
        self.btn_del.clicked.connect(self.delete_preset)
        btn_layout.addWidget(self.btn_del)
        
        self.btn_clear = QPushButton("🔄 Xóa bộ tạo")
        self.btn_clear.setStyleSheet("background-color: #9e9e9e; color: white; font-weight: bold; padding: 10px;")
        self.btn_clear.clicked.connect(self.clear_inputs)
        btn_layout.addWidget(self.btn_clear)
        
        self.layout.addLayout(btn_layout)
        
        # --- Màn hình log ---
        self.log_area = QTextEdit()
        self.log_area.setReadOnly(True)
        self.log_area.setStyleSheet("background: #000; color: #fff;")
        self.log_area.setFixedHeight(100)
        self.layout.addWidget(self.log_area)
        
        # --- Nút Action "Cứu Cánh" ---
        self.btn_play = QPushButton("▶️ PHÁT LÊN LOA NGAY BÂY GIỜ")
        self.btn_play.setStyleSheet("font-size: 20px; font-weight: bold; padding: 25px; background-color: #2196F3; color: white; border-radius: 10px;")
        self.btn_play.clicked.connect(self.play_tts_answer)
        self.layout.addWidget(self.btn_play)
        
        widget = QWidget()
        widget.setLayout(self.layout)
        self.setCentralWidget(widget)
        self.resize(700, 700)
        
        # Setup Trình phát thanh MediaPlayer
        self.player = QMediaPlayer()
        self.audio_output = QAudioOutput()
        self.player.setAudioOutput(self.audio_output)
        self.audio_output.setVolume(1.0)
        self.player.mediaStatusChanged.connect(self.on_media_status_changed)

    def load_presets(self):
        if os.path.exists(PRESETS_FILE):
            with open(PRESETS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        return []
        
    def save_presets_file(self):
        with open(PRESETS_FILE, "w", encoding="utf-8") as f:
            json.dump(self.presets, f, ensure_ascii=False, indent=4)
            
    def refresh_list(self):
        self.list_widget.clear()
        for p in self.presets:
            self.list_widget.addItem(p['question'])
            
    def on_select_preset(self, index):
        if index >= 0 and index < len(self.presets):
            self.q_input.setText(self.presets[index]['question'])
            self.a_input.setText(self.presets[index]['answer'])
            
    def clear_inputs(self):
        self.list_widget.clearSelection()
        self.q_input.clear()
        self.a_input.clear()
            
    def save_preset(self):
        q = self.q_input.text().strip()
        a = self.a_input.toPlainText().strip()
        if not q or not a:
            return QMessageBox.warning(self, "Lỗi", "Vui lòng nhập đủ câu hỏi và đáp án!")
            
        # Update if element is selected, otherwise add new
        idx = self.list_widget.currentRow()
        if idx >= 0:
            self.presets[idx] = {"question": q, "answer": a}
            self.log_area.append(f"Đã cập nhật preset: {q}")
        else:
            self.presets.append({"question": q, "answer": a})
            self.log_area.append(f"Đã thêm preset: {q}")
            
        self.save_presets_file()
        self.refresh_list()
        
    def delete_preset(self):
        idx = self.list_widget.currentRow()
        if idx >= 0:
            del self.presets[idx]
            self.save_presets_file()
            self.refresh_list()
            self.clear_inputs()
            self.log_area.append("Đã xóa vĩnh viễn preset.")
            
    def play_tts_answer(self):
        a = self.a_input.toPlainText().strip()
        if not a:
            return QMessageBox.warning(self, "Cảnh báo", "Không có đáp án (script) để trợ lý AI đọc!")
            
        self.btn_play.setEnabled(False)
        self.btn_play.setText("⏳ Đang Tải Script ra File...")
        
        self.worker = TTSWorker(a)
        self.worker.progress_signal.connect(lambda t: self.log_area.append(t))
        self.worker.play_audio_signal.connect(self.play_audio)
        self.worker.finished_signal.connect(self.on_worker_finished)
        self.worker.start()
        
    def play_audio(self, file_path):
        self.current_audio_file = file_path
        self.player.setSource(QUrl.fromLocalFile(file_path))
        self.player.play()
        
    def on_worker_finished(self):
        self.btn_play.setEnabled(True)
        self.btn_play.setText("▶️ PHÁT LÊN LOA NGAY BÂY GIỜ")
        
    def on_media_status_changed(self, status):
        if status == QMediaPlayer.MediaStatus.EndOfMedia:
            self.player.setSource(QUrl())
            if hasattr(self, 'current_audio_file') and os.path.exists(self.current_audio_file):
                try: os.remove(self.current_audio_file)
                except: pass
