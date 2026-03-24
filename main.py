import sys
import os

# Load .env file first (DEEPGRAM_API_KEY, GOOGLE_APPLICATION_CREDENTIALS)
from dotenv import load_dotenv
load_dotenv()

# Set GOOGLE_APPLICATION_CREDENTIALS if specified in .env
google_creds = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
if google_creds:
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = google_creds

import torch
from PyQt6.QtWidgets import QApplication
from utils.logger import log
from ui.main_window import TestVoiceUI

def main():
    log.info("="*60)
    log.info("      KHỞI ĐỘNG S-SOCRATES DESKTOP APP (ALL-IN-PYTHON)")
    log.info("="*60)
    
    app = QApplication(sys.argv)
    window = TestVoiceUI()
    window.show()
    
    log.info("Entering Application Event Loop...")
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
