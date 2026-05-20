"""Lichess-inspired theme for MTG Pipeline GUI."""

# Dark mode (default) - inspired by Lichess's dark theme
DARK_STYLESHEET = """
    QMainWindow, QWidget {
        background-color: #1a1a1a;
        color: #e0e0e0;
    }
    
    QTabWidget::pane {
        border: 1px solid #333;
    }
    
    QTabBar::tab {
        background-color: #2a2a2a;
        color: #b0b0b0;
        padding: 6px 16px;
        border-right: 1px solid #333;
    }
    
    QTabBar::tab:selected {
        background-color: #1a1a1a;
        color: #e0e0e0;
        border-bottom: 2px solid #7fb329;
    }
    
    QTabBar::tab:hover:!selected {
        background-color: #333;
    }
    
    QLineEdit, QTextEdit {
        background-color: #2a2a2a;
        color: #e0e0e0;
        border: 1px solid #444;
        border-radius: 3px;
        padding: 4px;
    }
    
    QLineEdit:focus, QTextEdit:focus {
        border: 1px solid #7fb329;
    }
    
    QPushButton {
        background-color: #3a3a3a;
        color: #e0e0e0;
        border: 1px solid #444;
        border-radius: 3px;
        padding: 6px 12px;
        font-weight: bold;
    }
    
    QPushButton:hover {
        background-color: #4a4a4a;
        border: 1px solid #7fb329;
    }
    
    QPushButton:pressed {
        background-color: #2a2a2a;
    }
    
    QPushButton:default {
        background-color: #7fb329;
        color: #1a1a1a;
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
        border: 1px solid #444;
        border-radius: 3px;
        background-color: #2a2a2a;
    }
    
    QCheckBox::indicator:checked {
        background-color: #7fb329;
        border: 1px solid #7fb329;
    }
    
    QLabel {
        color: #e0e0e0;
    }
    
    QComboBox {
        background-color: #2a2a2a;
        color: #e0e0e0;
        border: 1px solid #444;
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
        background-color: #2a2a2a;
        color: #e0e0e0;
        border: 1px solid #444;
        border-radius: 3px;
        padding: 4px;
    }
    
    QScrollBar:vertical {
        background-color: #1a1a1a;
        width: 12px;
        border: none;
    }
    
    QScrollBar::handle:vertical {
        background-color: #444;
        border-radius: 6px;
        min-height: 20px;
    }
    
    QScrollBar::handle:vertical:hover {
        background-color: #555;
    }
    
    QMessageBox {
        background-color: #1a1a1a;
    }
    
    QMessageBox QLabel {
        color: #e0e0e0;
    }
    
    QMessageBox QPushButton {
        min-width: 60px;
    }
"""

# Light mode - clean Lichess light theme
LIGHT_STYLESHEET = """
    QMainWindow, QWidget {
        background-color: #f5f5f5;
        color: #333333;
    }
    
    QTabWidget::pane {
        border: 1px solid #ddd;
    }
    
    QTabBar::tab {
        background-color: #eeeeee;
        color: #666;
        padding: 6px 16px;
        border-right: 1px solid #ddd;
    }
    
    QTabBar::tab:selected {
        background-color: #f5f5f5;
        color: #333;
        border-bottom: 2px solid #7fb329;
    }
    
    QTabBar::tab:hover:!selected {
        background-color: #e8e8e8;
    }
    
    QLineEdit, QTextEdit {
        background-color: #ffffff;
        color: #333;
        border: 1px solid #ddd;
        border-radius: 3px;
        padding: 4px;
    }
    
    QLineEdit:focus, QTextEdit:focus {
        border: 1px solid #7fb329;
    }
    
    QPushButton {
        background-color: #ffffff;
        color: #333;
        border: 1px solid #ddd;
        border-radius: 3px;
        padding: 6px 12px;
        font-weight: bold;
    }
    
    QPushButton:hover {
        background-color: #f0f0f0;
        border: 1px solid #7fb329;
    }
    
    QPushButton:pressed {
        background-color: #e8e8e8;
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
        border: 1px solid #ccc;
        border-radius: 3px;
        background-color: #fff;
    }
    
    QCheckBox::indicator:checked {
        background-color: #7fb329;
        border: 1px solid #7fb329;
    }
    
    QLabel {
        color: #333;
    }
    
    QComboBox {
        background-color: #fff;
        color: #333;
        border: 1px solid #ddd;
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
        background-color: #fff;
        color: #333;
        border: 1px solid #ddd;
        border-radius: 3px;
        padding: 4px;
    }
    
    QScrollBar:vertical {
        background-color: #f5f5f5;
        width: 12px;
        border: none;
    }
    
    QScrollBar::handle:vertical {
        background-color: #ccc;
        border-radius: 6px;
        min-height: 20px;
    }
    
    QScrollBar::handle:vertical:hover {
        background-color: #bbb;
    }
    
    QMessageBox {
        background-color: #f5f5f5;
    }
    
    QMessageBox QLabel {
        color: #333;
    }
    
    QMessageBox QPushButton {
        min-width: 60px;
    }
"""
