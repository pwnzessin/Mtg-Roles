import sys
import json
import html
import subprocess
from pathlib import Path
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QTabWidget, QLabel, QLineEdit, QPushButton, QTextEdit,
    QMessageBox, QFileDialog, QComboBox, QStackedWidget, QDialog,
    QDialogButtonBox, QTextBrowser,
)
from PyQt6.QtCore import QThread, QTimer, Qt, pyqtSignal
from PyQt6.QtGui import QColor, QFont, QPainter, QPixmap

import theme
import pipeline


def _check_dependencies() -> list[str]:
    """Return a list of human-readable problem strings, empty if all good."""
    problems = []

    # 1. Node.js
    try:
        result = subprocess.run(
            ["node", "--version"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            problems.append("Node.js is not working correctly (node --version failed).")
    except FileNotFoundError:
        problems.append(
            "Node.js is not installed or not on PATH.\n"
            "Download it from https://nodejs.org/ (LTS recommended)."
        )
    except Exception as e:
        problems.append(f"Could not check Node.js: {e}")

    if problems:
        # No point checking npm packages if node itself is missing
        return problems

    # 2. npm packages (node_modules must exist next to the .mjs scripts)
    scripts_dir = _copilot_root() / "cardconjurer_batch"
    node_modules = scripts_dir / "node_modules" / "playwright"
    if not node_modules.exists():
        problems.append(
            "npm packages are not installed.\n"
            f"Run:  cd \"{scripts_dir}\"  then  npm install\n"
            f"Then: npx playwright install chromium"
        )

    return problems


def _copilot_root() -> Path:
    """Return the Copilot/ folder regardless of frozen vs. source mode.

    Frozen (.exe in dist/):  exe -> dist -> pipeline_gui_python -> Copilot
    Source (main.py):        file -> pipeline_gui_python -> Copilot
    """
    if getattr(sys, 'frozen', False):
        return Path(sys.executable).resolve().parent.parent.parent
    return Path(__file__).resolve().parent.parent


def _settings_path() -> Path:
    """Path to the small GUI settings JSON (last config paths, theme, etc.)."""
    if getattr(sys, 'frozen', False):
        return Path(sys.executable).resolve().parent / "cardweaver_settings.json"
    return Path(__file__).resolve().parent / "cardweaver_settings.json"


def _load_settings() -> dict:
    try:
        p = _settings_path()
        if p.exists():
            return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        pass
    return {}


def _save_settings(data: dict) -> None:
    try:
        _settings_path().write_text(json.dumps(data, indent=2), encoding="utf-8")
    except Exception:
        pass


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

    SCRIPT_NAME  = ""
    RUN_LABEL    = "Run Pipeline"
    HAS_MODES    = True   # set False in subclass to hide mode/card-input rows
    SETTINGS_KEY = ""     # key used in cardweaver_settings.json

    def __init__(self, parent=None):
        super().__init__(parent)
        self.pipeline_thread = None
        self._config_data = {}
        self._init_ui()
        self._restore_last_config()

    # ── UI construction ──────────────────────────────────────────────────────

    def _init_ui(self):
        root = QVBoxLayout(self)
        root.setSpacing(8)
        root.setContentsMargins(16, 16, 16, 16)

        # Config row
        root.addWidget(self._section_label("Config File"))
        cfg_row = QHBoxLayout()
        self.config_input = QLineEdit()
        self.config_input.setPlaceholderText("No config file selected")
        self.config_input.setReadOnly(True)
        cfg_row.addWidget(self.config_input)
        for label, slot in [("Browse\u2026", self._browse_config),
                             ("Save",    self._save_config)]:
            btn = QPushButton(label)
            btn.setFixedWidth(72)
            btn.clicked.connect(slot)
            cfg_row.addWidget(btn)
        root.addLayout(cfg_row)

        # Config preview / editor
        root.addWidget(self._section_label("Config (editable — click Save to write changes)"))
        self.config_preview = QTextEdit()
        self.config_preview.setFont(QFont("Courier New", 9))
        self.config_preview.setPlaceholderText("Load a config file to preview its contents here…")
        self.config_preview.setMinimumHeight(330)
        self.config_preview.setMaximumHeight(420)
        root.addWidget(self.config_preview)

        if self.HAS_MODES:
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

        # Extra controls (subclass hook)
        self._init_extra_ui(root)

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
        self.output_text.setMinimumHeight(80)
        root.addWidget(self.output_text, stretch=1)

    def _init_extra_ui(self, root):
        """Subclass hook for extra controls inserted before the Run button."""
        pass

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
            self._load_config()

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
            # Persist path so it's restored next launch
            if self.SETTINGS_KEY:
                settings = _load_settings()
                settings[self.SETTINGS_KEY] = path
                _save_settings(settings)
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
        if not self.HAS_MODES:
            return
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

    def _restore_last_config(self):
        """On startup, restore the last used config path and silently load it."""
        if not self.SETTINGS_KEY:
            return
        settings = _load_settings()
        path = settings.get(self.SETTINGS_KEY, "")
        if path and Path(path).exists():
            self.config_input.setText(path)
            try:
                with open(path, encoding="utf-8-sig") as f:
                    raw = f.read()
                self._config_data = json.loads(raw)
                self.config_preview.setPlainText(raw)
                self._apply_config(self._config_data)
            except Exception:
                pass  # silently ignore on startup

    # ── Pipeline execution ───────────────────────────────────────────────────

    def _run_pipeline(self):
        script_path = _copilot_root() / "cardconjurer_batch" / self.SCRIPT_NAME
        if not script_path.exists():
            QMessageBox.critical(self, "Script Not Found",
                                 f"Pipeline script not found:\n{script_path}")
            return

        extra_args = []

        if self.HAS_MODES:
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

            extra_args += ["-RunMode", str(run_mode), "-Yes"]

            config_path = self.config_input.text().strip()
            if config_path and Path(config_path).exists():
                extra_args += ["-ConfigFile", config_path]

            if run_mode in (1, 3):
                extra_args += ["-CardNames", self.card_names_input.text().strip()]
            elif run_mode == 4:
                extra_args += ["-CardListFile", self.card_list_input.text().strip()]
        else:
            config_path = self.config_input.text().strip()
            if config_path and Path(config_path).exists():
                extra_args += ["-ConfigFile", config_path]
            extra_args += self._extra_run_args()

        self.run_btn.setEnabled(False)
        self.output_text.clear()
        self.output_text.append("[Pipeline started]\n")

        self.pipeline_thread = PipelineThread(str(script_path), extra_args)
        self.pipeline_thread.output_signal.connect(self._on_output)
        self.pipeline_thread.error_signal.connect(self._on_error)
        self.pipeline_thread.finished_signal.connect(self._on_finished)
        self.pipeline_thread.start()

    def _extra_run_args(self):
        """Subclass hook for additional PS args when HAS_MODES is False."""
        return []

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
    SCRIPT_NAME  = "generic_card_pipeline.ps1"
    RUN_LABEL    = "Run Generic Pipeline"
    SETTINGS_KEY = "generic_config"


class RolecardPipelineTab(_PipelineTabBase):
    SCRIPT_NAME  = "Rolecard_Batch_Generator.ps1"
    RUN_LABEL    = "Run Rolecard Pipeline"
    HAS_MODES    = False
    SETTINGS_KEY = "rolecard_config"

    def _init_extra_ui(self, root):
        root.addWidget(self._section_label("Roles"))
        self.role_combo = QComboBox()
        self.role_combo.addItems([
            "A \u2014 All roles",
            "Assassins",
            "Bandits",
            "Guardians",
            "Kings",
        ])
        root.addWidget(self.role_combo)

    def _extra_run_args(self):
        idx = self.role_combo.currentIndex()
        role_values = ["A", "Assassins", "Bandits", "Guardians", "Kings"]
        return ["-Roles", role_values[idx], "-Yes"]


class PipelineGUI(QMainWindow):

    def __init__(self):
        super().__init__()
        self.dark_mode = True
        self._init_ui()
        self._apply_theme()

    def _init_ui(self):
        self.setWindowTitle("CardWeaver")
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

        title_lbl = QLabel("CardWeaver")
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


class MissingDependenciesDialog(QDialog):
    """Dependency warning dialog with a clickable output area."""

    def __init__(self, problems: list[str], parent=None):
        super().__init__(parent)
        self.setWindowTitle("Missing Dependencies")
        self.resize(760, 360)

        root = QVBoxLayout(self)

        intro = QLabel(
            "<b>One or more required dependencies are missing.</b><br>"
            "The GUI will open but pipelines will not run until these are fixed."
        )
        intro.setWordWrap(True)
        root.addWidget(intro)

        output = QTextBrowser()
        output.setReadOnly(True)
        output.setOpenExternalLinks(True)
        output.setHtml(self._problems_to_html(problems))
        root.addWidget(output, stretch=1)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok)
        buttons.accepted.connect(self.accept)
        root.addWidget(buttons)

    @staticmethod
    def _problems_to_html(problems: list[str]) -> str:
        formatted = []
        for problem in problems:
            line = html.escape(problem).replace("\n", "<br>")
            line = line.replace(
                "https://nodejs.org/",
                '<a href="https://nodejs.org/">https://nodejs.org/</a>'
            )
            formatted.append(f"&bull; {line}")
        return "<br><br>".join(formatted)


class SplashScreen(QWidget):
    """Frameless CardWeaver startup splash — auto-closes after DISPLAY_MS or on click."""

    DISPLAY_MS = 2500
    clicked = pyqtSignal()

    def __init__(self):
        super().__init__()
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint |
            Qt.WindowType.WindowStaysOnTopHint |
            Qt.WindowType.SplashScreen
        )
        self.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)

        # ── Background image ──────────────────────────────────────────────
        assets = _assets_dir() / "CardWeaver_Logo.png"
        pixmap = QPixmap(str(assets))
        if pixmap.isNull():
            pixmap = QPixmap(720, 460)
            pixmap.fill(QColor(20, 20, 35))
        # Scale to portrait-friendly bounds so the image is never too narrow
        # for the title text (min width ~500 px).
        max_w, max_h = 520, 730
        pixmap = pixmap.scaled(
            max_w, max_h,
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation,
        )
        self._bg = pixmap
        self.setFixedSize(pixmap.size())

        # ── Layout ────────────────────────────────────────────────────────
        root = QVBoxLayout(self)
        root.setContentsMargins(30, 28, 30, 18)
        root.setSpacing(0)

        title = QLabel("CardWeaver")
        title.setAlignment(Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignTop)
        font = QFont()
        font.setFamilies(["Palatino Linotype", "Book Antiqua", "Garamond", "Georgia", "serif"])
        font.setPointSize(46)
        font.setBold(True)
        title.setFont(font)
        title.setStyleSheet(
            "color: #d4af37;"
            "background: transparent;"
        )
        root.addWidget(title)
        root.addStretch()

        copyright_lbl = QLabel("\u00a9 2026 CardWeaver  \u2014  All rights reserved")
        copyright_lbl.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignBottom)
        copyright_lbl.setStyleSheet(
            "color: rgba(220, 220, 220, 200);"
            "background: transparent;"
            "font-size: 10px;"
        )
        root.addWidget(copyright_lbl)

    def paintEvent(self, event):  # noqa: N802
        painter = QPainter(self)
        painter.drawPixmap(0, 0, self._bg)

    def mousePressEvent(self, event):  # noqa: N802
        self.clicked.emit()


def _assets_dir() -> Path:
    """Return the assets/ folder next to the executable (frozen) or source file."""
    if getattr(sys, 'frozen', False):
        # --onefile extracts to sys._MEIPASS; --onedir also sets it
        base = Path(getattr(sys, '_MEIPASS', Path(sys.executable).resolve().parent))
        return base / "assets"
    return Path(__file__).resolve().parent / "assets"


def main():
    app = QApplication(sys.argv)
    app.setStyle("Fusion")

    # ── Splash screen ─────────────────────────────────────────────────────
    splash = SplashScreen()
    splash.show()
    screen = app.primaryScreen().availableGeometry()
    splash.move(
        screen.center().x() - splash.width() // 2,
        screen.center().y() - splash.height() // 2,
    )
    app.processEvents()

    # Run dependency check while splash is visible
    problems = _check_dependencies()
    window = PipelineGUI()

    _launched = [False]

    def _launch():
        if _launched[0]:
            return
        _launched[0] = True
        splash.close()
        if problems:
            msg = MissingDependenciesDialog(problems)
            msg.show()
            app.processEvents()
            geo = app.primaryScreen().availableGeometry()
            msg.move(
                geo.center().x() - msg.width() // 2,
                geo.center().y() - msg.height() // 2,
            )
            msg.exec()
        window.show()

    QTimer.singleShot(SplashScreen.DISPLAY_MS, _launch)
    splash.clicked.connect(_launch)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
