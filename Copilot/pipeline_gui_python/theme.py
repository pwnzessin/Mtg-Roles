"""Lichess-inspired theme for MTG Pipeline GUI."""

# Dark mode (default) - Lichess-inspired with a subtle blue tint
DARK_STYLESHEET = """
    QMainWindow, QWidget {
        background-color: #1a1e28;
        color: #e0e0e0;
    }
    
    QTabWidget::pane {
        border: 1px solid #2e3648;
    }
    
    QTabWidget::tab-bar {
        left: 16px;
    }
    
    QTabBar::tab {
        background-color: #252c3a;
        color: #b0b0b0;
        padding: 6px 16px;
        min-width: 140px;
        border: 1px solid #2e3648;
        border-bottom: none;
        border-top-left-radius: 5px;
        border-top-right-radius: 5px;
        margin-right: 2px;
    }
    
    QTabBar::tab:selected {
        background-color: #2e3a50;
        color: #e0e0e0;
        border: 1px solid #3a4a60;
        border-bottom: 2px solid #7fb329;
        border-top-left-radius: 5px;
        border-top-right-radius: 5px;
    }
    
    QTabBar::tab:hover:!selected {
        background-color: #2e3648;
    }

    QPushButton#helpButton, QPushButton#themeButton {
        background-color: #252c3a;
        color: #b0b0b0;
        border: 1px solid #2e3648;
        border-radius: 5px;
        padding: 6px 16px;
        min-width: 140px;
        font-weight: normal;
    }

    QPushButton#helpButton:hover, QPushButton#themeButton:hover {
        background-color: #2e3648;
        border: 1px solid #3a4a60;
        color: #e0e0e0;
    }

    QPushButton#helpButton:pressed, QPushButton#themeButton:pressed {
        background-color: #1a1e28;
    }
    
    QLineEdit, QTextEdit {
        background-color: #252c3a;
        color: #e0e0e0;
        border: 1px solid #3a4456;
        border-radius: 3px;
        padding: 4px;
    }
    
    QLineEdit:focus, QTextEdit:focus {
        border: 1px solid #7fb329;
    }
    
    QPushButton {
        background-color: #2e3648;
        color: #e0e0e0;
        border: 1px solid #3a4456;
        border-radius: 3px;
        padding: 6px 12px;
        font-weight: bold;
    }
    
    QPushButton:hover {
        background-color: #3a4456;
        border: 1px solid #7fb329;
    }
    
    QPushButton:pressed {
        background-color: #252c3a;
    }
    
    QPushButton:default {
        background-color: #7fb329;
        color: #1a1e28;
        border: none;
    }
    
    QPushButton:default:hover {
        background-color: #8fc42f;
    }
    
    QCheckBox {
        color: #e0e0e0;
        spacing: 5px;
    }
    
    QCheckBox::indicator {
        width: 16px;
        height: 16px;
        border: 1px solid #3a4456;
        border-radius: 3px;
        background-color: #252c3a;
    }
    
    QCheckBox::indicator:checked {
        background-color: #7fb329;
        border: 1px solid #7fb329;
    }
    
    QLabel {
        color: #e0e0e0;
    }
    
    QComboBox {
        background-color: #252c3a;
        color: #e0e0e0;
        border: 1px solid #3a4456;
        border-radius: 3px;
        padding: 4px;
    }
    
    QComboBox::drop-down {
        border: none;
    }
    
    QComboBox::down-arrow {
        image: url(none);
    }
    
    QSpinBox {
        background-color: #252c3a;
        color: #e0e0e0;
        border: 1px solid #3a4456;
        border-radius: 3px;
        padding: 4px;
    }
    
    QScrollBar:vertical {
        background-color: #1a1e28;
        width: 12px;
        border: none;
    }
    
    QScrollBar::handle:vertical {
        background-color: #3a4456;
        border-radius: 6px;
        min-height: 20px;
    }
    
    QScrollBar::handle:vertical:hover {
        background-color: #4a5570;
    }
    
    QMessageBox {
        background-color: #1a1e28;
    }
    
    QMessageBox QLabel {
        color: #e0e0e0;
    }
    
    QMessageBox QPushButton {
        min-width: 60px;
    }
"""

# Light mode - soft blue-tinted light theme
LIGHT_STYLESHEET = """
    QMainWindow, QWidget {
        background-color: #eef3fc;
        color: #333333;
    }
    
    QTabWidget::pane {
        border: 1px solid #c5d4ee;
    }
    
    QTabWidget::tab-bar {
        left: 16px;
    }
    
    QTabBar::tab {
        background-color: #dde8f7;
        color: #555;
        padding: 6px 16px;
        min-width: 140px;
        border: 1px solid #c5d4ee;
        border-bottom: none;
        border-top-left-radius: 5px;
        border-top-right-radius: 5px;
        margin-right: 2px;
    }
    
    QTabBar::tab:selected {
        background-color: #eef3fc;
        color: #222;
        border: 1px solid #b8cce8;
        border-bottom: 2px solid #7fb329;
        border-top-left-radius: 5px;
        border-top-right-radius: 5px;
    }
    
    QTabBar::tab:hover:!selected {
        background-color: #cfddf4;
    }

    QPushButton#helpButton, QPushButton#themeButton {
        background-color: #dde8f7;
        color: #555;
        border: 1px solid #c5d4ee;
        border-radius: 5px;
        padding: 6px 16px;
        min-width: 140px;
        font-weight: normal;
    }

    QPushButton#helpButton:hover, QPushButton#themeButton:hover {
        background-color: #cfddf4;
        border: 1px solid #b8cce8;
        color: #222;
    }

    QPushButton#helpButton:pressed, QPushButton#themeButton:pressed {
        background-color: #eef3fc;
    }
    
    QLineEdit, QTextEdit {
        background-color: #f8fbff;
        color: #333;
        border: 1px solid #b8cce8;
        border-radius: 3px;
        padding: 4px;
    }
    
    QLineEdit:focus, QTextEdit:focus {
        border: 1px solid #7fb329;
    }
    
    QPushButton {
        background-color: #f0f5ff;
        color: #333;
        border: 1px solid #b8cce8;
        border-radius: 3px;
        padding: 6px 12px;
        font-weight: bold;
    }
    
    QPushButton:hover {
        background-color: #dde8f7;
        border: 1px solid #7fb329;
    }
    
    QPushButton:pressed {
        background-color: #cfddf4;
    }
    
    QPushButton:default {
        background-color: #7fb329;
        color: #fff;
        border: none;
    }
    
    QPushButton:default:hover {
        background-color: #8fc42f;
    }
    
    QCheckBox {
        color: #333;
        spacing: 5px;
    }
    
    QCheckBox::indicator {
        width: 16px;
        height: 16px;
        border: 1px solid #b8cce8;
        border-radius: 3px;
        background-color: #f8fbff;
    }
    
    QCheckBox::indicator:checked {
        background-color: #7fb329;
        border: 1px solid #7fb329;
    }
    
    QLabel {
        color: #333;
    }
    
    QComboBox {
        background-color: #f8fbff;
        color: #333;
        border: 1px solid #b8cce8;
        border-radius: 3px;
        padding: 4px;
    }
    
    QComboBox::drop-down {
        border: none;
    }
    
    QComboBox::down-arrow {
        image: url(none);
    }
    
    QSpinBox {
        background-color: #f8fbff;
        color: #333;
        border: 1px solid #b8cce8;
        border-radius: 3px;
        padding: 4px;
    }
    
    QScrollBar:vertical {
        background-color: #eef3fc;
        width: 12px;
        border: none;
    }
    
    QScrollBar::handle:vertical {
        background-color: #b8cce8;
        border-radius: 6px;
        min-height: 20px;
    }
    
    QScrollBar::handle:vertical:hover {
        background-color: #93afd4;
    }
    
    QMessageBox {
        background-color: #eef3fc;
    }
    
    QMessageBox QLabel {
        color: #333;
    }
    
    QMessageBox QPushButton {
        min-width: 60px;
    }
"""
