import sys
import json
from pathlib import Path
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QTabWidget, QLabel, QLineEdit, QPushButton, QTextEdit,
    QMessageBox, QFileDialog, QComboBox, QStackedWidget,
)
from PyQt6.QtCore import QThread, pyqtSignal
from PyQt6.QtGui import QFont

import theme
import pipeline


def _copilot_root() -> Path:
    """Return the Copilot/ folder regardless of frozen vs. source mode.

    Frozen (.exe in dist/):  exe -> dist -> pipeline_gui_python -> Copilot
    Source (main.py):        file -> pipeline_gui_python -> Copilot
    """
    if getattr(sys, 'frozen', False):
        return Path(sys.executable).resolve().parent.parent.parent
    return Path(__file__).resolve().parent.parent


class PipelineThread(QThread):
    output_signal = pyqtSignal(str)
    error_signal = pyqtSignal(str)
    finished_signal = pyqtSignal(int)

    def __init__(self, script_path, args):
        super().__init__()
        self.script_path = script_path
        self.args = args

    def run(self):
        try:
            result = pipeline.run_pipeline(self.script_path, self.args, self.output_signal.emit)
            self.finished_signal.emit(result)
        except Exception as e:
            self.error_signal.emit(str(e))
            self.finished_signal.emit(1)


class _PipelineTabBase(QWidget):
    """Shared base for Generic and Rolecard pipeline tabs."""

    SCRIPT_NAME = ""
    RUN_LABEL   = "Run Pipeline"

    def __init__(self, parent=None):
        super().__init__(parent)
        self.pipeline_thread = None
        self._config_data = {}
        self._init_ui()

    # ── UI construction ──────────────────────────────────────────────────────

    def _init_ui(self):
        root = QVBoxLayout(self)
        root.setSpacing(8)
        root.setContentsMargins(16, 16, 16, 16)

        # Config row
        root.addWidget(self._section_label("Config File"))
        cfg_row = QHBoxLayout()
        self.config_input = QLineEdit()
        self.config_input.setPlaceholderText("No config file loaded")
        self.config_input.setReadOnly(True)
        cfg_row.addWidget(self.config_input)
        for label, slot in [("Browse…", self._browse_config),
                             ("Load",    self._load_config),
                             ("Save",    self._save_config)]:
            btn = QPushButton(label)
            btn.setFixedWidth(72)
            btn.clicked.connect(slot)
            cfg_row.addWidget(btn)
        root.addLayout(cfg_row)

        # Config preview
        root.addWidget(self._section_label("Config Preview"))
        self.config_preview = QTextEdit()
        self.config_preview.setReadOnly(True)
        self.config_preview.setFont(QFont("Courier New", 9))
        self.config_preview.setPlaceholderText("Load a config file to preview its contents here…")
        self.config_preview.setMaximumHeight(140)
        root.addWidget(self.config_preview)

        # Mode selector
        root.addWidget(self._section_label("Mode"))
        self.mode_combo = QComboBox()
        self.mode_combo.addItems([
            "1 \u2014 Fetch from Scryfall + render",
            "2 \u2014 Render existing .txt files",
            "3 \u2014 Fetch from Scryfall only",
            "4 \u2014 Load card list + fetch + render",
            "5 \u2014 Clear output / downloaded art",
        ])
        self.mode_combo.setCurrentIndex(0)
        self.mode_combo.currentIndexChanged.connect(self._on_mode_changed)
        root.addWidget(self.mode_combo)

        # Card input stack (pages switch by mode)
        self._card_stack = QStackedWidget()

        # Page 0: card names entry (modes 1 / 3)
        names_page = QWidget()
        names_layout = QHBoxLayout(names_page)
        names_layout.setContentsMargins(0, 0, 0, 0)
        self.card_names_input = QLineEdit()
        self.card_names_input.setPlaceholderText("Card names, comma-separated (e.g. Sol Ring, Black Lotus)")
        names_layout.addWidget(self.card_names_input)
        self._card_stack.addWidget(names_page)   # index 0

        # Page 1: card list file picker (mode 4)
        list_page = QWidget()
        list_layout = QHBoxLayout(list_page)
        list_layout.setContentsMargins(0, 0, 0, 0)
        self.card_list_input = QLineEdit()
        self.card_list_input.setPlaceholderText("Card list .txt file")
        list_layout.addWidget(self.card_list_input)
        browse_list_btn = QPushButton("Browse\u2026")
        browse_list_btn.setFixedWidth(72)
        browse_list_btn.clicked.connect(self._browse_card_list)
        list_layout.addWidget(browse_list_btn)
        self._card_stack.addWidget(list_page)    # index 1

        # Page 2: no input needed (modes 2 / 5)
        empty_page = QWidget()
        empty_layout = QHBoxLayout(empty_page)
        empty_layout.setContentsMargins(0, 0, 0, 0)
        hint_lbl = QLabel("No card input required for this mode.")
        hint_lbl.setObjectName("hintLabel")
        empty_layout.addWidget(hint_lbl)
        self._card_stack.addWidget(empty_page)   # index 2

        root.addWidget(self._section_label("Card Input"))
        root.addWidget(self._card_stack)
        self._on_mode_changed(0)  # set correct page for default mode

        # Run button
        self.run_btn = QPushButton(self.RUN_LABEL)
        self.run_btn.setMinimumHeight(38)
        self.run_btn.setObjectName("runButton")
        self.run_btn.clicked.connect(self._run_pipeline)
        root.addWidget(self.run_btn)

        # Log area
        root.addWidget(self._section_label("Output Log"))
        self.output_text = QTextEdit()
        self.output_text.setReadOnly(True)
        self.output_text.setFont(QFont("Courier New", 9))
        root.addWidget(self.output_text, stretch=1)

    def _section_label(self, text):
        lbl = QLabel(text)
        lbl.setObjectName("sectionLabel")
        return lbl

    def _on_mode_changed(self, index):
        """Switch card input page to match selected mode."""
        # modes: 0=fetch+render, 1=render only, 2=fetch only, 3=cardlist, 4=clear
        if index == 3:          # mode 4 — card list file
            self._card_stack.setCurrentIndex(1)
        elif index in (1, 4):   # mode 2 / 5 — no card input
            self._card_stack.setCurrentIndex(2)
        else:                   # mode 1 / 3 — card names
            self._card_stack.setCurrentIndex(0)

    def _browse_card_list(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "Select Card List", "", "Text Files (*.txt);;All Files (*)")
        if path:
            self.card_list_input.setText(path)

    # ── Config helpers ───────────────────────────────────────────────────────

    def _browse_config(self):
        path, _ = QFileDialog.getOpenFileName(
            self, "Select Config File", "", "JSON Files (*.json);;All Files (*)")
        if path:
            self.config_input.setText(path)

    def _load_config(self):
        path = self.config_input.text()
        if not path:
            QMessageBox.warning(self, "No Config", "Browse to a config file first.")
            return
        try:
            with open(path, encoding="utf-8-sig") as f:
                raw = f.read()
            self._config_data = json.loads(raw)
            self.config_preview.setPlainText(raw)
            self._apply_config(self._config_data)
        except Exception as e:
            QMessageBox.critical(self, "Load Error", str(e))

    def _save_config(self):
        path = self.config_input.text()
        if not path:
            path, _ = QFileDialog.getSaveFileName(
                self, "Save Config File", "", "JSON Files (*.json)")
            if not path:
                return
            self.config_input.setText(path)
        try:
            raw = self.config_preview.toPlainText()
            # Validate JSON before saving
            json.loads(raw)
            with open(path, "w", encoding="utf-8") as f:
                f.write(raw)
        except json.JSONDecodeError as e:
            QMessageBox.critical(self, "Invalid JSON", str(e))
        except Exception as e:
            QMessageBox.critical(self, "Save Error", str(e))

    def _apply_config(self, cfg):
        # populate card list dir hint if mode 4 and cardlists dir exists
        fetch = cfg.get("fetch", {})
        cardlists_rel = fetch.get("cardlistsDir", "")
        if cardlists_rel and not self.card_list_input.text():
            root = cfg.get("workspaceRoot") or ""
            if not root:
                # auto-detect: config lives in Copilot/cardconjurer_batch/
                config_path = self.config_input.text()
                if config_path:
                    root = str(Path(config_path).parent.parent.parent)
            candidate = Path(root) / cardlists_rel if root else None
            if candidate and candidate.exists():
                # pick first .txt file as default hint
                txts = sorted(candidate.glob("*.txt"))
                if txts:
                    self.card_list_input.setText(str(txts[0]))

    # ── Pipeline execution ───────────────────────────────────────────────────

    def _run_pipeline(self):
        script_path = _copilot_root() / "cardconjurer_batch" / self.SCRIPT_NAME
        if not script_path.exists():
            QMessageBox.critical(self, "Script Not Found",
                                 f"Pipeline script not found:\n{script_path}")
            return

        mode_index = self.mode_combo.currentIndex()  # 0-based
        run_mode   = mode_index + 1                  # 1-based for PS script

        # Validate card input for modes that need it
        if run_mode in (1, 3):
            names = self.card_names_input.text().strip()
            if not names:
                QMessageBox.warning(self, "No Card Names",
                                    "Enter at least one card name.")
                return
        elif run_mode == 4:
            card_list = self.card_list_input.text().strip()
            if not card_list or not Path(card_list).exists():
                QMessageBox.warning(self, "No Card List",
                                    "Browse to a valid card list .txt file.")
                return

        # Build argument list for the PS script
        extra_args = ["-RunMode", str(run_mode), "-Yes"]

        config_path = self.config_input.text().strip()
        if config_path and Path(config_path).exists():
            extra_args += ["-ConfigFile", config_path]

        if run_mode in (1, 3):
            extra_args += ["-CardNames", self.card_names_input.text().strip()]
        elif run_mode == 4:
            extra_args += ["-CardListFile", self.card_list_input.text().strip()]

        self.run_btn.setEnabled(False)
        self.output_text.clear()
        self.output_text.append("[Pipeline started]\n")

        self.pipeline_thread = PipelineThread(str(script_path), extra_args)
        self.pipeline_thread.output_signal.connect(self._on_output)
        self.pipeline_thread.error_signal.connect(self._on_error)
        self.pipeline_thread.finished_signal.connect(self._on_finished)
        self.pipeline_thread.start()

    def _on_output(self, text):
        self.output_text.append(text)
        sb = self.output_text.verticalScrollBar()
        sb.setValue(sb.maximum())

    def _on_error(self, error):
        self.output_text.append(f"\n[ERROR] {error}")

    def _on_finished(self, exit_code):
        self.run_btn.setEnabled(True)
        if exit_code == 0:
            self.output_text.append("\n[Pipeline completed successfully]")
        else:
            self.output_text.append(f"\n[Pipeline failed — exit code {exit_code}]")


class GenericPipelineTab(_PipelineTabBase):
    SCRIPT_NAME = "generic_card_pipeline.ps1"
    RUN_LABEL   = "Run Generic Pipeline"


class RolecardPipelineTab(_PipelineTabBase):
    SCRIPT_NAME = "role_card_pipeline.ps1"
    RUN_LABEL   = "Run Rolecard Pipeline"


class PipelineGUI(QMainWindow):

    def __init__(self):
        super().__init__()
        self.dark_mode = True
        self._init_ui()
        self._apply_theme()

    def _init_ui(self):
        self.setWindowTitle("MTG Roles — Pipeline GUI")
        self.setGeometry(100, 100, 980, 680)

        central = QWidget()
        self.setCentralWidget(central)
        root = QVBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        # Top bar
        top_bar = QWidget()
        top_bar.setObjectName("topBar")
        top_bar.setFixedHeight(40)
        top_layout = QHBoxLayout(top_bar)
        top_layout.setContentsMargins(12, 0, 12, 0)

        title_lbl = QLabel("MTG Roles Pipeline GUI")
        title_lbl.setObjectName("appTitle")
        top_layout.addWidget(title_lbl)
        top_layout.addStretch()

        self.theme_btn = QPushButton("☀ Light")
        self.theme_btn.setObjectName("themeButton")
        self.theme_btn.setFixedWidth(80)
        self.theme_btn.clicked.connect(self._toggle_theme)
        top_layout.addWidget(self.theme_btn)

        root.addWidget(top_bar)

        # Tabs
        self.tabs = QTabWidget()
        self.tabs.addTab(GenericPipelineTab(),  "Generic Pipeline")
        self.tabs.addTab(RolecardPipelineTab(), "Rolecard Pipeline")
        root.addWidget(self.tabs)

    def _toggle_theme(self):
        self.dark_mode = not self.dark_mode
        self._apply_theme()

    def _apply_theme(self):
        if self.dark_mode:
            self.setStyleSheet(theme.DARK_STYLESHEET)
            self.theme_btn.setText("☀ Light")
        else:
            self.setStyleSheet(theme.LIGHT_STYLESHEET)
            self.theme_btn.setText("☾ Dark")


def main():
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    window = PipelineGUI()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
