import sys

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
