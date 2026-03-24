import sys
import os

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from PyQt6.QtWidgets import QApplication
from utils.logger import log
from ui.admin_window import AdminUI

def main():
    log.info("="*60)
    log.info("      KHỞI ĐỘNG S-SOCRATES ADMIN PANEL (BACKSTAGE)")
    log.info("="*60)
    
    app = QApplication(sys.argv)
    window = AdminUI()
    window.show()
    
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
