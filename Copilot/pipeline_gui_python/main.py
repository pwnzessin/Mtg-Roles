import sys
import json
import html
import copy
import math
import subprocess
from pathlib import Path
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QTabWidget, QLabel, QLineEdit, QPushButton, QTextEdit,
    QMessageBox, QFileDialog, QComboBox, QStackedWidget, QDialog,
    QDialogButtonBox, QTextBrowser, QScrollArea, QFrame,
    QSpinBox, QDoubleSpinBox, QCheckBox, QFormLayout,
)
from PyQt6.QtCore import QThread, QTimer, Qt, pyqtSignal
from PyQt6.QtGui import QColor, QFont, QPainter, QPainterPath, QPen, QPixmap

import theme
import highlighter as _hl
import pipeline


# ── Config editor infrastructure ──────────────────────────────────────────────

class _FieldDef:
    """Schema definition for a single field in the config editor dialog."""

    __slots__ = ("key", "label", "ftype", "desc", "options", "min_val", "max_val", "nullable", "editable")

    def __init__(self, key, label, ftype, desc="", options=None,
                 min_val=0, max_val=99999, nullable=False, editable=False):
        self.key      = key
        self.label    = label
        self.ftype    = ftype      # "str" | "bool" | "int" | "float" | "combo" | "section"
        self.desc     = desc
        self.options  = options or []  # combo: list of (display_str, raw_value)
        self.min_val  = min_val
        self.max_val  = max_val
        self.nullable = nullable
        self.editable = editable   # combo: allow free-text entry in addition to preset choices


def _nested_get(d: dict, dotted_key: str):
    """Read a value from a nested dict via dot-separated key (e.g. 'fetch.artDir')."""
    cur = d
    for k in dotted_key.split("."):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(k)
    return cur


def _nested_set(d: dict, dotted_key: str, value) -> None:
    """Write a value into a nested dict via dot-separated key, creating sub-dicts as needed."""
    keys = dotted_key.split(".")
    cur  = d
    for k in keys[:-1]:
        if k not in cur or not isinstance(cur[k], dict):
            cur[k] = {}
        cur = cur[k]
    cur[keys[-1]] = value


class ConfigEditorDialog(QDialog):
    """Renders a list of _FieldDef entries as a scrollable, user-friendly config form."""

    def __init__(self, title: str, config: dict, schema: list, parent=None):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.resize(620, 560)
        self._config    = config    # modified in-place on accept
        self._schema    = schema
        self._widgets   = {}        # key → (FieldDef, widget)
        self._text_refs = {}        # key → QLineEdit for dir/file fields
        self._init_ui()

    # ── UI construction ───────────────────────────────────────────────────────

    def _init_ui(self):
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 8)

        hint = QLabel(
            "Edit config values below.  Click <b>OK</b> to apply changes to the JSON preview, "
            "then click <b>Save</b> in the main window to write to disk."
        )
        hint.setWordWrap(True)
        hint.setContentsMargins(16, 10, 16, 4)
        outer.addWidget(hint)

        tab_widget = QTabWidget()
        outer.addWidget(tab_widget, stretch=1)

        current_form: QFormLayout | None = None

        for fd in self._schema:
            if fd.ftype == "section":
                # Each section becomes a new tab with its own scrollable form
                inner = QWidget()
                form  = QFormLayout(inner)
                form.setContentsMargins(14, 10, 14, 10)
                form.setSpacing(7)
                form.setHorizontalSpacing(14)
                form.setFieldGrowthPolicy(QFormLayout.FieldGrowthPolicy.ExpandingFieldsGrow)

                scroll = QScrollArea()
                scroll.setWidgetResizable(True)
                scroll.setFrameShape(QFrame.Shape.NoFrame)
                scroll.setWidget(inner)

                tab_widget.addTab(scroll, fd.label)
                current_form = form
                continue

            if current_form is None:
                # Fields before the first section — add a fallback "General" tab
                inner = QWidget()
                current_form = QFormLayout(inner)
                current_form.setContentsMargins(14, 10, 14, 10)
                current_form.setSpacing(7)
                current_form.setHorizontalSpacing(14)
                current_form.setFieldGrowthPolicy(
                    QFormLayout.FieldGrowthPolicy.ExpandingFieldsGrow)
                scroll = QScrollArea()
                scroll.setWidgetResizable(True)
                scroll.setFrameShape(QFrame.Shape.NoFrame)
                scroll.setWidget(inner)
                tab_widget.addTab(scroll, "General")

            current = _nested_get(self._config, fd.key)
            widget  = self._make_widget(fd, current)
            self._widgets[fd.key] = (fd, widget)

            lbl = QLabel(fd.label + ":")
            if fd.desc:
                lbl.setToolTip(fd.desc)
                widget.setToolTip(fd.desc)
            current_form.addRow(lbl, widget)

        btns = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        btns.accepted.connect(self._on_accept)
        btns.rejected.connect(self.reject)
        outer.addWidget(btns)

    def _make_widget(self, fd: _FieldDef, current):
        if fd.ftype == "bool":
            w = QCheckBox()
            w.setChecked(bool(current))
            return w

        if fd.ftype == "int":
            w = QSpinBox()
            w.setRange(fd.min_val, fd.max_val)
            if fd.nullable:
                w.setSpecialValueText("(none / auto)")
            if fd.nullable and current is None:
                w.setValue(fd.min_val)
            else:
                w.setValue(int(current) if current is not None else fd.min_val)
            return w

        if fd.ftype == "float":
            w = QDoubleSpinBox()
            w.setRange(fd.min_val, fd.max_val)
            w.setValue(float(current) if current is not None else fd.min_val)
            return w

        if fd.ftype == "combo":
            w = QComboBox()
            for disp, _ in fd.options:
                w.addItem(disp)
            if fd.editable:
                w.setEditable(True)
                w.setCurrentText(str(current) if current is not None else "")
            else:
                for i, (_, val) in enumerate(fd.options):
                    if val == current:
                        w.setCurrentIndex(i)
                        break
            return w

        if fd.ftype in ("dir", "file"):
            return self._make_browse_widget(fd, current)

        # str (default)
        w = QLineEdit()
        w.setText(str(current) if current is not None else "")
        if fd.desc:
            w.setPlaceholderText(fd.desc[:70])
        return w

    def _make_browse_widget(self, fd: _FieldDef, current) -> QWidget:
        """QLineEdit + Browse button for directory or file path fields."""
        container = QWidget()
        layout = QHBoxLayout(container)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)

        line = QLineEdit()
        line.setText(str(current) if current is not None else "")
        if fd.desc:
            line.setPlaceholderText(fd.desc[:70])
        layout.addWidget(line)

        btn = QPushButton("Browse\u2026")
        btn.setFixedWidth(84)
        if fd.ftype == "dir":
            btn.clicked.connect(lambda checked=False, l=line: self._browse_dir(l))
        else:
            btn.clicked.connect(lambda checked=False, l=line: self._browse_file(l))
        layout.addWidget(btn)

        self._text_refs[fd.key] = line
        return container

    def _browse_dir(self, line: QLineEdit) -> None:
        start = line.text().strip() or ""
        path = QFileDialog.getExistingDirectory(self, "Select Folder", start)
        if path:
            line.setText(path)

    def _browse_file(self, line: QLineEdit) -> None:
        start = str(Path(line.text().strip()).parent) if line.text().strip() else ""
        path, _ = QFileDialog.getOpenFileName(self, "Select File", start, "All Files (*)")
        if path:
            line.setText(path)

    # ── Accept ────────────────────────────────────────────────────────────────

    def _on_accept(self):
        for key, (fd, w) in self._widgets.items():
            if fd.ftype == "bool":
                val = w.isChecked()
            elif fd.ftype == "int":
                v   = w.value()
                val = None if (fd.nullable and v == fd.min_val) else v
            elif fd.ftype == "float":
                val = w.value()
            elif fd.ftype == "combo":
                if fd.editable:
                    val = w.currentText().strip()
                    val = None if (fd.nullable and val == "") else val
                else:
                    idx = w.currentIndex()
                    val = fd.options[idx][1] if 0 <= idx < len(fd.options) else None
            elif fd.ftype in ("dir", "file"):
                t   = self._text_refs[fd.key].text().strip()
                val = None if (fd.nullable and t == "") else t
            else:   # str
                t   = w.text().strip()
                val = None if (fd.nullable and t == "") else t
            _nested_set(self._config, key, val)
        self.accept()

    def updated_json(self) -> str:
        """Return the updated config as a pretty-printed JSON string."""
        return json.dumps(self._config, indent=4, ensure_ascii=False)


# ──────────────────────────────────────────────────────────────────────────────

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


class AnimatedRunButton(QPushButton):
    """Run button that shows a sine wave sweeping left-to-right while the pipeline is running.

    The animation starts automatically when the button is disabled and stops when re-enabled,
    so no extra call-sites are needed beyond the existing setEnabled(False/True) calls.
    """

    _INTERVAL = 25    # ms between frames  (~40 fps)
    _SPEED    = 0.10  # phase increment per frame
    _FREQ     = 0.6   # sine cycles visible across the button width
    _ALPHA    = 50    # wave overlay opacity (0–255)

    def __init__(self, text, parent=None):
        super().__init__(text, parent)
        self._phase     = 0.0
        self._animating = False
        self._anim_timer = QTimer(self)
        self._anim_timer.setInterval(self._INTERVAL)
        self._anim_timer.timeout.connect(self._tick)

    # ── public ────────────────────────────────────────────────────────────

    def setEnabled(self, enabled: bool):
        super().setEnabled(enabled)
        if not enabled:
            self._start()
        else:
            self._stop()

    # ── internals ─────────────────────────────────────────────────────────

    def _start(self):
        self._animating = True
        self._phase = 0.0
        self._anim_timer.start()

    def _stop(self):
        self._animating = False
        self._anim_timer.stop()
        self.update()

    def _tick(self):
        self._phase = (self._phase + self._SPEED) % (2 * math.pi)
        self.update()

    def paintEvent(self, event):
        super().paintEvent(event)
        if not self._animating:
            return

        w, h = self.width(), self.height()
        amp  = h * 0.28

        # Build the wave-filled region path
        path = QPainterPath()
        y0   = h * 0.5 + amp * math.sin(-self._phase)
        path.moveTo(0.0, y0)
        for x in range(1, w + 1):
            t = x / w
            y = h * 0.5 + amp * math.sin(2 * math.pi * self._FREQ * t - self._phase)
            path.lineTo(float(x), y)
        path.lineTo(float(w), float(h))
        path.lineTo(0.0, float(h))
        path.closeSubpath()

        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setClipRect(self.rect())
        painter.fillPath(path, QColor(127, 179, 41, self._ALPHA))
        painter.end()


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
        root.addWidget(self._section_label("Config"))
        self.config_preview = QTextEdit()
        self.config_preview.setFont(QFont("Courier New", 9))
        self.config_preview.setPlaceholderText("Load a config file to preview its contents here…")
        self.config_preview.setMinimumHeight(330)
        self.config_preview.setMaximumHeight(420)
        root.addWidget(self.config_preview)
        self._highlighter = _hl.JsonHighlighter(self.config_preview.document(), dark=True)

        # Config Help / Edit Config buttons — sit directly below the JSON editor
        help_row = QHBoxLayout()
        self._help_btn = QPushButton("Config Help")
        self._help_btn.setObjectName("helpButton")
        self._help_btn.clicked.connect(self._open_help)
        help_row.addWidget(self._help_btn)
        self._edit_cfg_btn = QPushButton("Edit Config\u2026")
        self._edit_cfg_btn.setObjectName("helpButton")
        self._edit_cfg_btn.clicked.connect(self._open_config_editor)
        help_row.addWidget(self._edit_cfg_btn)
        help_row.addStretch()
        root.addLayout(help_row)

        if self.HAS_MODES:
            # Mode selector
            root.addWidget(self._section_label("Mode"))
            self.mode_combo = QComboBox()
            self.mode_combo.addItems([
                "1 \u2014 Render custom art files",
                "2 \u2014 Load card list + fetch + render",
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
        self.run_btn = AnimatedRunButton(self.RUN_LABEL)
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

    def _open_help(self):
        """Subclass hook: open the tab's config help dialog."""
        pass

    def _open_config_editor(self):
        """Open the visual config editor dialog for the current tab."""
        if not self._config_data:
            QMessageBox.information(
                self, "No Config Loaded",
                "Load a config file first (Browse\u2026), then click Edit Config."
            )
            return
        schema = self._config_schema()
        if not schema:
            return
        config_copy = copy.deepcopy(self._config_data)
        dlg = ConfigEditorDialog(
            f"{self.RUN_LABEL} \u2014 Edit Config", config_copy, schema, self
        )
        if dlg.exec() == QDialog.DialogCode.Accepted:
            new_json = dlg.updated_json()
            self._config_data = json.loads(new_json)
            self.config_preview.setPlainText(new_json)

    def _config_schema(self) -> list:
        """Subclass hook: return list of _FieldDef entries for the config editor."""
        return []

    def update_theme(self, dark: bool) -> None:
        self._highlighter.set_dark(dark)

    def _section_label(self, text):
        lbl = QLabel(text)
        lbl.setObjectName("sectionLabel")
        return lbl

    def _on_mode_changed(self, index):
        """Switch card input page to match selected mode."""
        # mode 1 (index 0) = custom art - no card input
        # mode 2 (index 1) = card list file
        if index == 1:   # mode 2 - card list file
            self._card_stack.setCurrentIndex(1)
        else:            # mode 1 - no card input
            self._card_stack.setCurrentIndex(2)

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

            # Validate card input for mode 2 (card list)
            if run_mode == 2:
                card_list = self.card_list_input.text().strip()
                if not card_list or not Path(card_list).exists():
                    QMessageBox.warning(self, "No Card List",
                                        "Browse to a valid card list .txt file.")
                    return

            extra_args += ["-RunMode", str(run_mode), "-Yes"]

            config_path = self.config_input.text().strip()
            if config_path and Path(config_path).exists():
                extra_args += ["-ConfigFile", config_path]

            if run_mode == 2:
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

    def _open_help(self):
        GenericConfigHelpDialog(self).exec()

    def _config_schema(self):
        return [
            _FieldDef("", "Fetch", "section"),
            _FieldDef("fetch.cardsDir", "Cards Dir", "dir",
                      "Output folder for fetched .txt card data files."),
            _FieldDef("fetch.artDir", "Art Dir", "dir",
                      "Output folder for downloaded artwork."),
            _FieldDef("fetch.cardlistsDir", "Card Lists Dir", "dir",
                      "Folder shown when browsing for a card list file."),
            _FieldDef("fetch.artScanDir", "Art Scan Dir", "dir",
                      "Folder scanned in mode 1 for custom art (also used as fallback art dir)."),
            _FieldDef("fetch.preferSet", "Prefer Set", "str",
                      "Preferred MTG set code (e.g. m21). Leave blank for default."),
            _FieldDef("fetch.artMode", "Art Mode", "combo", "How artwork is downloaded.",
                      options=[
                          ("1 — Direct art download", 1),
                          ("2 — Full card PNG then auto-crop", 2),
                      ]),
            _FieldDef("fetch.artVersion", "Art Version", "combo",
                      "Scryfall image variant (art mode 1 only).",
                      options=[
                          ("art_crop", "art_crop"),
                          ("border_crop", "border_crop"),
                          ("normal", "normal"),
                          ("large", "large"),
                          ("png", "png"),
                      ]),
            _FieldDef("fetch.pngCropJpegQuality", "PNG Crop JPEG Quality", "int",
                      "JPEG quality for art mode 2 (1–100).", min_val=1, max_val=100),
            _FieldDef("fetch.upscaleEnabled", "Upscale (Fetch)", "bool",
                      "Upscale downloaded art after fetch."),
            _FieldDef("fetch.upscaleEngine", "Upscale Engine (Fetch)", "combo",
                      "Engine for fetched art upscaling.",
                      options=[
                          ("auto (Real-ESRGAN if available, else Lanczos)", "auto"),
                          ("realesrgan (must be in PATH)", "realesrgan"),
                          ("lanczos (no extra tools needed)", "lanczos"),
                      ]),
            _FieldDef("fetch.upscaleFactor", "Upscale Factor (Fetch)", "combo",
                      "Scale multiplier.", options=[("2\xd7", 2), ("4\xd7", 4)]),
            _FieldDef("fetch.overwrite", "Overwrite (Fetch)", "bool",
                      "Overwrite existing .txt and art files."),
            _FieldDef("fetch.downloadArt", "Download Art", "bool",
                      "Download artwork during mode 2 fetch."),
            _FieldDef("fetch.dryRun", "Dry Run (Fetch)", "bool",
                      "Log what would happen but write no files."),
            _FieldDef("fetch.chunkSize", "Chunk Size", "int",
                      "Cards per fetch\u2192render batch. 0 = no chunking.", min_val=0, max_val=9999),
            _FieldDef("", "Generate", "section"),
            _FieldDef("generate.outputSubDir", "Output Sub-dir", "str",
                      "Sub-folder relative to the .txt input dir for rendered PNGs."),
            _FieldDef("generate.baseUrl", "Base URL", "str",
                      "URL of the local CardConjurer server."),
            _FieldDef("generate.headless", "Headless Browser", "bool",
                      "Run Playwright browser invisibly."),
            _FieldDef("generate.startLauncher", "Auto-start Launcher", "bool",
                      "Auto-start CardConjurer before rendering."),
            _FieldDef("generate.overwrite", "Overwrite (Generate)", "bool",
                      "Overwrite existing output PNG files."),
            _FieldDef("generate.upscaleEnabled", "Upscale (Generate)", "bool",
                      "Upscale rendered PNG after generation."),
            _FieldDef("generate.upscaleEngine", "Upscale Engine (Generate)", "combo",
                      "Engine for rendered output upscaling.",
                      options=[
                          ("auto (Real-ESRGAN if available, else Lanczos)", "auto"),
                          ("realesrgan (must be in PATH)", "realesrgan"),
                          ("lanczos (no extra tools needed)", "lanczos"),
                      ]),
            _FieldDef("generate.upscaleFactor", "Upscale Factor (Generate)", "combo",
                      "Scale multiplier.", options=[("2\xd7", 2), ("4\xd7", 4)]),
            _FieldDef("generate.limit", "Render Limit", "int",
                      "Max cards to render. 0 = all.", min_val=0, max_val=9999),
            _FieldDef("generate.dryRun", "Dry Run (Generate)", "bool",
                      "Log which cards would be processed, skip rendering."),
            _FieldDef("", "Layouts", "section"),
            _FieldDef("layouts.default", "Default Frame", "combo",
                      "Frame style used for all non-basic-land cards.",
                      options=[
                          ("standard \u2014 regular M15 frame", "standard"),
                          ("borderless \u2014 Generic Showcase frame", "borderless"),
                      ]),
            _FieldDef("layouts.basicLand", "Basic Land Layout", "combo",
                      "Layout used for basic land cards.",
                      options=[
                          ("standard \u2014 normal M15 frame", "standard"),
                          ("fullart \u2014 art fills entire card", "fullart"),
                      ]),
        ]


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
            "Renegades",
        ])
        root.addWidget(self.role_combo)

    def _extra_run_args(self):
        idx = self.role_combo.currentIndex()
        role_values = ["A", "Assassins", "Bandits", "Guardians", "Kings", "Renegades"]
        return ["-Roles", role_values[idx], "-Yes"]

    def _open_help(self):
        RolecardConfigHelpDialog(self).exec()

    def _config_schema(self):
        return [
            _FieldDef("", "General", "section"),
            _FieldDef("limit", "Card Limit", "int",
                      "Max cards per role. 0 = all cards.", min_val=0, max_val=9999),
            _FieldDef("qualityChoice", "Quality", "combo",
                      "Output image quality preset.",
                      options=[
                          ("1 \u2014 Original PNG (full res, lossless)", "1"),
                          ("2 \u2014 50% PNG (half res, lossless)", "2"),
                          ("3 \u2014 37% PNG, 750\xd71050 px @ 300 DPI", "3"),
                          ("4 \u2014 50% JPEG Q85 (default)", "4"),
                      ]),
            _FieldDef("applyMargin", "Apply Margin", "bool",
                      "Add a white print margin around each card."),
            _FieldDef("finalUpscaleEnabled", "Final Upscale", "bool",
                      "Upscale final output using bicubic interpolation."),
            _FieldDef("finalUpscaleFactor", "Upscale Factor", "int",
                      "Scale multiplier when Final Upscale is enabled.", min_val=1, max_val=8),
            _FieldDef("baseUrl", "Base URL", "str",
                      "URL of the CardConjurer server."),
            _FieldDef("headless", "Headless Browser", "bool",
                      "Run Playwright browser invisibly."),
            _FieldDef("startLauncher", "Auto-start Launcher", "bool",
                      "Auto-start the CardConjurer launcher before rendering."),
            _FieldDef("overwrite", "Overwrite", "bool",
                      "Re-render cards that already have an output PNG."),
            _FieldDef("", "Paths", "section"),
            _FieldDef("paths.cardsDir", "Cards Dir", "dir",
                      "Folder containing per-role card .txt files."),
            _FieldDef("paths.artworksDir", "Artworks Dir", "dir",
                      "Folder containing per-role artwork images."),
            _FieldDef("paths.templatesDir", "Templates Dir", "dir",
                      "Folder holding role template .cardconjurer files."),
            _FieldDef("paths.cardConjurerRoot", "CardConjurer Root", "dir",
                      "Root of the CardConjurer installation."),
            _FieldDef("paths.setCodesFile", "Set Codes File", "file",
                      "Path to the set-codes definition file."),
            _FieldDef("paths.reportDir", "Report Dir", "dir",
                      "Folder where generation report files are written."),
        ]


class XmlExportTab(_PipelineTabBase):
    """Tab for running Generate-MpcFillXml.ps1.

    All settings live in the JSON config file.  The only in-GUI option is
    the mode selector (Manual vs RoleCard) which mirrors the ``mode`` key.
    """

    SCRIPT_NAME  = "Generate-MpcFillXml.ps1"
    RUN_LABEL    = "Generate XML"
    HAS_MODES    = False
    SETTINGS_KEY = "xml_export_config"

    _STOCK_NAMES = [
        "(S30) Standard Smooth",
        "(S33) Superior Smooth",
        "(M31) Linen",
        "(P10) Plastic",
    ]
    _ROLE_VALUES = ["A", "Assassins", "Bandits", "Guardians", "Kings", "Renegades"]

    # ── Extra UI: mode combo only ─────────────────────────────────────────

    def _init_extra_ui(self, root):
        root.addWidget(self._section_label("Mode"))
        self.mode_combo = QComboBox()
        self.mode_combo.addItems([
            "Standard \u2014 use inputFolder",
            "RoleCard \u2014 pick roles",
        ])
        root.addWidget(self.mode_combo)

    def _apply_config(self, cfg):
        self.mode_combo.setCurrentIndex(int(cfg.get("mode", 0)))

    def update_theme(self, dark: bool) -> None:
        self._highlighter.set_dark(dark)

    # ── Restore: fall back to default config next to the script ──────────

    def _restore_last_config(self):
        settings = _load_settings()
        path = settings.get(self.SETTINGS_KEY, "")
        if not path:
            candidate = _copilot_root() / "cardconjurer_batch" / "xml_export_config.json"
            if candidate.exists():
                path = str(candidate)
        if path and Path(path).exists():
            self.config_input.setText(path)
            try:
                with open(path, encoding="utf-8-sig") as f:
                    raw = f.read()
                self._config_data = json.loads(raw)
                self.config_preview.setPlainText(raw)
                self._apply_config(self._config_data)
            except Exception:
                pass

    # ── Run: read all params from the JSON preview ────────────────────────

    def _run_pipeline(self):
        script_path = _copilot_root() / "cardconjurer_batch" / self.SCRIPT_NAME
        if not script_path.exists():
            QMessageBox.critical(self, "Script Not Found",
                                 f"Script not found:\n{script_path}")
            return

        # Parse the live JSON from the preview (user may have edited it)
        try:
            cfg = json.loads(self.config_preview.toPlainText())
        except json.JSONDecodeError as e:
            QMessageBox.critical(self, "Invalid JSON",
                                 f"Fix the config before running:\n{e}")
            return

        mode_index = self.mode_combo.currentIndex()
        args = ["-Mode", "RoleCard" if mode_index == 1 else "Manual"]

        if mode_index == 0:  # Manual
            m = cfg.get("manual", {})
            folder = m.get("inputFolder", "").strip()
            if folder:
                p = Path(folder)
                if not p.is_absolute():
                    p = _copilot_root().parent / folder
                folder = str(p)
            if not folder or not Path(folder).is_dir():
                QMessageBox.warning(self, "No Input Folder",
                                    'Set a valid "manual.inputFolder" in the config JSON.')
                return
            args += ["-InputFolder", folder]
            args += ["-Recurse", "true" if m.get("recurse", False) else "false"]
        else:  # RoleCard
            r = cfg.get("rolecard", {})
            roles_idx = min(int(r.get("roles", 0)), len(self._ROLE_VALUES) - 1)
            args += ["-Roles", self._ROLE_VALUES[roles_idx]]
            tmpl = r.get("templatesRoot", "").strip()
            if tmpl:
                args += ["-TemplatesRoot", tmpl]

        cardback = cfg.get("cardbackPath", "").strip()
        if cardback:
            args += ["-CardbackPath", cardback]

        cbd = cfg.get("cardbacksDir", "").strip()
        if cbd:
            args += ["-CardbacksDir", cbd]

        afd = cfg.get("autofillDir", "").strip()
        if afd:
            args += ["-AutofillDir", afd]

        stock_idx = min(int(cfg.get("stock", 0)), len(self._STOCK_NAMES) - 1)
        args += ["-Stock", self._STOCK_NAMES[stock_idx]]
        args += ["-Foil", "true" if cfg.get("foil", False) else "false"]

        out_xml = cfg.get("outputXml", "").strip()
        if out_xml:
            args += ["-OutputXml", out_xml]

        self.run_btn.setEnabled(False)
        self.output_text.clear()
        self.output_text.append("[XML export started]\n")

        self.pipeline_thread = PipelineThread(str(script_path), args)
        self.pipeline_thread.output_signal.connect(self._on_output)
        self.pipeline_thread.error_signal.connect(self._on_error)
        self.pipeline_thread.finished_signal.connect(self._on_finished)
        self.pipeline_thread.start()

    def _open_help(self):
        XmlExportConfigHelpDialog(self).exec()

    def _config_schema(self):
        return [
            _FieldDef("", "General", "section"),
            _FieldDef("mode", "Mode", "combo",
                      "Which input source to use at run time.",
                      options=[
                          ("0 \u2014 Manual (inputFolder)", 0),
                          ("1 \u2014 RoleCard (role-based)", 1),
                      ]),
            _FieldDef("cardbackPath", "Cardback Path", "file",
                      "Path to a specific cardback image. Leave blank to omit."),
            _FieldDef("cardbacksDir", "Cardbacks Dir", "dir",
                      "Folder scanned for cardback images when no explicit path is set."),
            _FieldDef("stock", "Stock", "combo",
                      "MPC card stock.",
                      options=[
                          ("(S30) Standard Smooth", 0),
                          ("(S33) Superior Smooth", 1),
                          ("(M31) Linen", 2),
                          ("(P10) Plastic", 3),
                      ]),
            _FieldDef("foil", "Foil", "bool",
                      "Mark all front faces as foil in the XML."),
            _FieldDef("autofillDir", "Autofill Dir", "dir",
                      "Folder where the XML file is written when outputXml is blank."),
            _FieldDef("outputXml", "Output XML", "file",
                      "Path for the generated XML file. Leave blank for auto-name."),
            _FieldDef("", "Manual Settings", "section"),
            _FieldDef("manual.inputFolder", "Input Folder", "dir",
                      "Folder containing rendered card images to include in the XML."),
            _FieldDef("manual.recurse", "Recurse Sub-folders", "bool",
                      "Include images in sub-folders recursively."),
            _FieldDef("", "RoleCard Settings", "section"),
            _FieldDef("rolecard.roles", "Roles", "combo",
                      "Which role(s) to include.",
                      options=[
                          ("0 \u2014 All roles", 0),
                          ("1 \u2014 Assassins", 1),
                          ("2 \u2014 Bandits", 2),
                          ("3 \u2014 Guardians", 3),
                          ("4 \u2014 Kings", 4),
                          ("5 \u2014 Renegades", 5),
                      ]),
            _FieldDef("rolecard.templatesRoot", "Templates Root", "dir",
                      "Path to Cards\\templates folder. Leave blank to auto-detect."),
        ]


class ArtGenerationTab(_PipelineTabBase):
    """Tab for generate_art_pipeline.ps1 — same structure as GenericPipelineTab."""

    SCRIPT_NAME  = "generate_art_pipeline.ps1"
    RUN_LABEL    = "Generate Art"
    HAS_MODES    = True
    SETTINGS_KEY = "art_gen_config"

    def _init_extra_ui(self, root):
        # Replace the generic mode labels with art-gen specific labels.
        # The combo is already created by the base class before this hook is called.
        self.mode_combo.clear()
        self.mode_combo.addItems([
            "1 \u2014 Enter card names",
            "2 \u2014 Load card list file",
        ])
        self.mode_combo.setCurrentIndex(0)

    def _on_mode_changed(self, index):
        # index 0 → card names entry  (stack page 0)
        # index 1 → card list file    (stack page 1)
        if index == 1:
            self._card_stack.setCurrentIndex(1)
        else:
            self._card_stack.setCurrentIndex(0)

    def _apply_config(self, cfg):
        # art_gen_config.json has cardlistsDir at the top level (not under "fetch")
        cardlists_rel = cfg.get("cardlistsDir", "")
        if cardlists_rel and not self.card_list_input.text():
            root = cfg.get("workspaceRoot") or ""
            if not root:
                config_path = self.config_input.text()
                if config_path:
                    root = str(Path(config_path).parent.parent.parent)
            candidate = Path(root) / cardlists_rel if root else None
            if candidate and candidate.exists():
                txts = sorted(candidate.glob("*.txt"))
                if txts:
                    self.card_list_input.setText(str(txts[0]))

    def _restore_last_config(self):
        settings = _load_settings()
        path_str = settings.get(self.SETTINGS_KEY, "")
        if not path_str:
            candidate = _copilot_root() / "cardconjurer_batch" / "art_gen_config.json"
            if candidate.exists():
                path_str = str(candidate)
        if path_str and Path(path_str).exists():
            self.config_input.setText(path_str)
            try:
                with open(path_str, encoding="utf-8-sig") as f:
                    raw = f.read()
                self._config_data = json.loads(raw)
                self.config_preview.setPlainText(raw)
                self._apply_config(self._config_data)
            except Exception:
                pass

    def _run_pipeline(self):
        script_path = _copilot_root() / "cardconjurer_batch" / self.SCRIPT_NAME
        if not script_path.exists():
            QMessageBox.critical(self, "Script Not Found",
                                 f"Pipeline script not found:\n{script_path}")
            return

        mode_index = self.mode_combo.currentIndex()
        run_mode   = mode_index + 1
        extra_args = ["-RunMode", str(run_mode), "-Yes"]

        config_path = self.config_input.text().strip()
        if config_path and Path(config_path).exists():
            extra_args += ["-ConfigFile", config_path]

        if run_mode == 1:
            names = self.card_names_input.text().strip()
            if not names:
                QMessageBox.warning(self, "No Card Names",
                                    "Enter one or more card names (comma-separated).")
                return
            extra_args += ["-CardNames", names]
        else:
            card_list = self.card_list_input.text().strip()
            if not card_list or not Path(card_list).exists():
                QMessageBox.warning(self, "No Card List",
                                    "Browse to a valid card list .txt file.")
                return
            extra_args += ["-CardListFile", card_list]

        self.run_btn.setEnabled(False)
        self.output_text.clear()
        self.output_text.append("[Art generation started]\n")

        self.pipeline_thread = PipelineThread(str(script_path), extra_args)
        self.pipeline_thread.output_signal.connect(self._on_output)
        self.pipeline_thread.error_signal.connect(self._on_error)
        self.pipeline_thread.finished_signal.connect(self._on_finished)
        self.pipeline_thread.start()

    def _open_help(self):
        ArtGenerationHelpDialog(self).exec()

    def _config_schema(self):
        return [
            _FieldDef("", "General", "section"),
            _FieldDef("model", "Model", "combo",
                      "AI provider / model. Select Midjourney or a HuggingFace model ID.",
                      options=[
                          ("midjourney",                             "midjourney"),
                          ("FLUX.1-schnell  (HF, fast)",            "black-forest-labs/FLUX.1-schnell"),
                          ("FLUX.1-dev  (HF, quality)",             "black-forest-labs/FLUX.1-dev"),
                          ("stable-diffusion-xl-base-1.0  (HF)",   "stabilityai/stable-diffusion-xl-base-1.0"),
                      ],
                      editable=True),
            _FieldDef("cardlistsDir", "Card Lists Dir", "dir",
                      "Workspace-relative folder scanned for card list .txt files."),
            _FieldDef("outputDir", "Output Dir", "dir",
                      "Folder where generated art images are saved."),
            _FieldDef("style", "Style", "str",
                      "Art style descriptor appended to every prompt after the card name."),
            _FieldDef("prefix", "Prefix", "str",
                      "Free text prepended to every prompt before the card name (optional)."),
            _FieldDef("overwrite", "Overwrite", "bool",
                      "Regenerate art even if output file already exists."),
            _FieldDef("concurrency", "Concurrency", "int",
                      "Simultaneous requests. Keep at 1 for Midjourney to avoid rate limits.",
                      min_val=1, max_val=10),
            _FieldDef("dryRun", "Dry Run", "bool",
                      "Print prompts without downloading images."),
            _FieldDef("width", "Width (px)", "int",
                      "Output image width in pixels (HuggingFace only).", min_val=64, max_val=2048),
            _FieldDef("height", "Height (px)", "int",
                      "Output image height in pixels (HuggingFace only).", min_val=64, max_val=2048),
            _FieldDef("seed", "Seed", "int",
                      "Integer seed for reproducibility. Set to 0 (shown as 'none / auto') for a random result.",
                      min_val=0, max_val=2147483647, nullable=True),
            _FieldDef("", "HuggingFace", "section"),
            _FieldDef("apiToken", "API Token", "str",
                      "HuggingFace API token (hf_...). Leave blank to use HF_TOKEN env var."),
            _FieldDef("", "Midjourney", "section"),
            _FieldDef("discordToken", "Discord Token", "str",
                      "Discord user token (browser DevTools → Network tab → Authorization header)."),
            _FieldDef("discordChannelId", "Channel ID", "str",
                      "ID of the Discord channel where the Midjourney bot is active."),
            _FieldDef("discordGuildId", "Guild ID", "str",
                      "ID of the Discord server (guild) containing the Midjourney channel."),
        ]


class ArtGenerationHelpDialog(QDialog):
    """Explains every parameter in art_gen_config.json."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Art Generation \u2014 Config Reference")
        self.resize(680, 480)

        root = QVBoxLayout(self)

        browser = QTextBrowser()
        browser.setOpenExternalLinks(False)
        browser.setHtml(self._help_html())
        root.addWidget(browser, stretch=1)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        root.addWidget(buttons)

    @staticmethod
    def _help_html() -> str:
        return """
<style>
  body  { font-family: Segoe UI, Arial, sans-serif; font-size: 13px; margin: 8px; }
  h3    { color: #d4af37; margin-bottom: 4px; }
  h4    { border-bottom: 1px solid #666; padding-bottom: 3px; margin-top: 14px; }
  table { border-collapse: collapse; width: 100%; }
  td    { padding: 4px 6px; vertical-align: top; }
  td:first-child { width: 160px; white-space: nowrap; font-weight: bold; }
  tr:nth-child(even) { background: rgba(128,128,128,0.08); }
  code  { background: rgba(128,128,128,0.15); padding: 0 3px; border-radius: 3px; }
  p     { margin: 4px 0 10px; }
</style>
<h3>Art Generation Pipeline &mdash; Config Reference</h3>
<p>Generates card artwork via <b>Midjourney</b> (Discord self-bot) or the <b>HuggingFace Inference API</b>.<br>
Select the provider in the <b>Model</b> combo box — choosing <code>midjourney</code> uses Midjourney,
any other value is treated as a HuggingFace model ID.<br>
Edit values directly in the JSON preview, then click <b>Save</b>.</p>

<h4>Provider / Model</h4>
<table>
  <tr><td>model</td><td>AI provider and model.<br>
    <b><code>midjourney</code></b> — use Midjourney via Discord self-bot (requires Discord credentials below).<br>
    Any other value is treated as a HuggingFace model ID, e.g. <code>black-forest-labs/FLUX.1-schnell</code>.<br>
    You can type a custom HuggingFace model ID directly into the combo box.</td></tr>
</table>

<h4>HuggingFace Authentication</h4>
<table>
  <tr><td>apiToken</td><td>Your HuggingFace API token (<code>hf_...</code>). Required when model is a HuggingFace ID.<br>
    Get a free read-access token at <code>https://huggingface.co/settings/tokens</code>.<br>
    Alternatively, set the <code>HF_TOKEN</code> environment variable and leave this blank.</td></tr>
</table>

<h4>Midjourney (Discord)</h4>
<table>
  <tr><td>discordToken</td><td>Your Discord <b>user</b> token (not a bot token).<br>
    Find it in browser DevTools → Network tab → any Discord request → <code>Authorization</code> header.</td></tr>
  <tr><td>discordChannelId</td><td>ID of the Discord text channel where the Midjourney bot is active.<br>
    Right-click the channel → <i>Copy Channel ID</i> (Developer Mode must be on).</td></tr>
  <tr><td>discordGuildId</td><td>ID of the Discord server containing that channel.<br>
    Right-click the server icon → <i>Copy Server ID</i>.</td></tr>
</table>

<h4>Paths</h4>
<table>
  <tr><td>cardlistsDir</td><td>Workspace-relative folder scanned for card list <code>.txt</code> files,
    used to pre-fill the card-list file picker on startup.<br>
    Default: <code>Copilot\\cardconjurer_batch\\Cardlists</code></td></tr>
  <tr><td>outputDir</td><td>Workspace-relative (or absolute) folder where generated <code>.jpg</code>
    art images are saved.<br>
    Default: <code>Artworks\\Generated</code></td></tr>
</table>

<h4>Prompt</h4>
<table>
  <tr><td>style</td><td>Art style descriptor appended to every prompt after the card name and type.<br>
    Example: <code>fantasy card art, digital painting, highly detailed, no text, no borders</code></td></tr>
  <tr><td>prefix</td><td>Optional free text prepended to every prompt before the card name.<br>
    Leave blank to omit. Example: <code>dark fantasy portrait of</code></td></tr>
</table>

<h4>Generation</h4>
<table>
  <tr><td>overwrite</td><td><code>true</code> = regenerate art even if the output file already exists.<br>
    <code>false</code> = skip cards that already have an output image (default).</td></tr>
  <tr><td>concurrency</td><td>Number of simultaneous HuggingFace requests.<br>
    Keep at <code>1</code> to avoid rate limits; raise to <code>2</code> with caution.<br>
    Default: <code>1</code></td></tr>
  <tr><td>dryRun</td><td><code>true</code> = print prompts without downloading any images.<br>
    <code>false</code> = download and save images (default).</td></tr>
</table>

<h4>Image Size</h4>
<table>
  <tr><td>width</td><td>Output image width in pixels.<br>Default: <code>626</code> (standard MTG art crop width).</td></tr>
  <tr><td>height</td><td>Output image height in pixels.<br>Default: <code>457</code> (standard MTG art crop height).</td></tr>
  <tr><td>seed</td><td>Optional integer seed for reproducibility. Set to <code>null</code> for a random result each run.</td></tr>
</table>
"""


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
        root.setContentsMargins(0, 6, 0, 0)
        root.setSpacing(0)

        # Toolbar row above tabs (keeps tab bar uncluttered)
        toolbar = QWidget()
        toolbar_layout = QHBoxLayout(toolbar)
        toolbar_layout.setContentsMargins(8, 0, 8, 4)
        toolbar_layout.setSpacing(6)
        toolbar_layout.addStretch()

        self.theme_btn = QPushButton("☀ Light")
        self.theme_btn.setObjectName("themeButton")
        self.theme_btn.clicked.connect(self._toggle_theme)
        toolbar_layout.addWidget(self.theme_btn)

        root.addWidget(toolbar)

        # Tabs
        self.tabs = QTabWidget()
        self.tabs.addTab(GenericPipelineTab(),    "Generic Pipeline")
        self.tabs.addTab(RolecardPipelineTab(),  "Rolecard Pipeline")
        self.tabs.addTab(XmlExportTab(),          "XML Export")
        self.tabs.addTab(ArtGenerationTab(),      "Art Generation")

        root.addWidget(self.tabs)

    def _toggle_theme(self):
        self.dark_mode = not self.dark_mode
        self._apply_theme()

    def paintEvent(self, event):  # noqa: N802
        super().paintEvent(event)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        w, h = self.width(), self.height()
        for offset, alpha in ((0, 60), (1, 180)):
            pen = QPen(QColor(212, 175, 55, alpha))
            pen.setWidth(1)
            painter.setPen(pen)
            painter.drawRect(offset, offset, w - 1 - 2 * offset, h - 1 - 2 * offset)

    def _apply_theme(self):
        if self.dark_mode:
            self.setStyleSheet(theme.DARK_STYLESHEET)
            self.theme_btn.setText("☀ Light")
        else:
            self.setStyleSheet(theme.LIGHT_STYLESHEET)
            self.theme_btn.setText("☾ Dark")
        for i in range(self.tabs.count()):
            self.tabs.widget(i).update_theme(self.dark_mode)


class RolecardConfigHelpDialog(QDialog):
    """Explains every parameter in Rolecard_Batch_Generator.config.json."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Rolecard Pipeline \u2014 Config Reference")
        self.resize(680, 440)

        root = QVBoxLayout(self)

        browser = QTextBrowser()
        browser.setOpenExternalLinks(False)
        browser.setHtml(self._help_html())
        root.addWidget(browser, stretch=1)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        root.addWidget(buttons)

    @staticmethod
    def _help_html() -> str:
        return """
<style>
  body  { font-family: Segoe UI, Arial, sans-serif; font-size: 13px; margin: 8px; }
  h3    { color: #d4af37; margin-bottom: 4px; }
  h4    { border-bottom: 1px solid #666; padding-bottom: 3px; margin-top: 14px; }
  table { border-collapse: collapse; width: 100%; }
  td    { padding: 4px 6px; vertical-align: top; }
  td:first-child { width: 190px; white-space: nowrap; font-weight: bold; }
  tr:nth-child(even) { background: rgba(128,128,128,0.08); }
  code  { background: rgba(128,128,128,0.15); padding: 0 3px; border-radius: 3px; }
  p     { margin: 4px 0 10px; }
</style>
<h3>Rolecard Pipeline &mdash; Config Reference</h3>
<p>Settings are saved automatically after each run, persisting your last-used values.</p>

<h4>Parameters</h4>
<table>
  <tr><td>limit</td><td>Maximum number of cards to render per role. <code>0</code> = render all cards in the role folder.<br>Default: <code>0</code></td></tr>
  <tr><td>qualityChoice</td><td>Output image quality preset:<br>
    <code>1</code> &mdash; Original PNG (full resolution, lossless)<br>
    <code>2</code> &mdash; 50% PNG (half resolution, lossless)<br>
    <code>3</code> &mdash; 37% PNG, fixed 750&times;1050 px @ 300 DPI (print-ready)<br>
    <code>4</code> &mdash; 50% JPEG Q85 (half resolution, lossy &mdash; default)<br>
    Default: <code>4</code></td></tr>
  <tr><td>applyMargin</td><td>Add a white print margin around each rendered card.<br><code>true</code> = include margin &nbsp; <code>false</code> = no margin.<br>Has no effect when quality is set to <code>3</code> (fixed-size preset already includes margins).<br>Default: <code>false</code></td></tr>
  <tr><td>finalUpscaleEnabled</td><td>Upscale the final rendered output using bicubic interpolation after all processing steps.<br><code>false</code> = skip upscale &nbsp; <code>true</code> = upscale by <b>finalUpscaleFactor</b>.<br>Default: <code>false</code></td></tr>
  <tr><td>finalUpscaleFactor</td><td>Integer scale multiplier applied when <b>finalUpscaleEnabled</b> is <code>true</code>. For example, <code>2</code> doubles both width and height.<br>Default: <code>2</code></td></tr>
</table>

<h4>Server &amp; Generation</h4>
<table>
  <tr><td>baseUrl</td><td>URL of the CardConjurer server used for rendering.<br>Default: <code>http://localhost:8080</code></td></tr>
  <tr><td>headless</td><td><code>true</code> = run the Playwright browser invisibly (recommended).<br><code>false</code> = show the browser window (useful for debugging).<br>Default: <code>true</code></td></tr>
  <tr><td>startLauncher</td><td><code>true</code> = auto-start the CardConjurer launcher before rendering the first role.<br><code>false</code> = assume the server is already running.<br>Default: <code>true</code></td></tr>
  <tr><td>overwrite</td><td><code>true</code> = re-render cards that already have an output PNG.<br><code>false</code> = skip already-rendered cards.<br>Default: <code>true</code></td></tr>
  <tr><td>reportDir</td><td>Sub-folder relative to the workspace root where per-role generation report files (<code>cardconjurer_batch_{role}_report.txt</code>) are read from after each role completes.<br>Default: <code>Copilot</code></td></tr>
</table>

<h4>paths</h4>
<p>All values are relative to the workspace root (the folder two levels above the script). Defaults match the standard project layout; only change these if you have moved folders.</p>
<table>
  <tr><td>paths.cardsDir</td><td>Folder containing per-role card <code>.txt</code> files. A sub-folder named after the role is appended at run time.<br>Default: <code>Cards</code></td></tr>
  <tr><td>paths.artworksDir</td><td>Folder containing per-role artwork images. A sub-folder named after the role is appended at run time.<br>Default: <code>Artworks</code></td></tr>
  <tr><td>paths.templatesDir</td><td>Folder holding role template <code>.cardconjurer</code> files and where rendered PNGs are written (into a role sub-folder).<br>Default: <code>Cards/templates</code></td></tr>
  <tr><td>paths.cardConjurerRoot</td><td>Root of the CardConjurer installation. Used to locate <code>local_art/auto/</code> for art staging.<br>Default: <code>cardconjurer-master/cardconjurer-master</code></td></tr>
  <tr><td>paths.setCodesFile</td><td>Path to the set-codes definition file used to assign set symbols per role.<br>Default: <code>Copilot/SetCodes.txt</code></td></tr>
  <tr><td>paths.reportDir</td><td>Folder where per-role generation report files (<code>cardconjurer_batch_{role}_report.txt</code>) are written and read back.<br>Default: <code>Copilot</code></td></tr>
</table>
"""


class GenericConfigHelpDialog(QDialog):
    """Explains every parameter in generic_card_config.json."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Generic Pipeline \u2014 Config Reference")
        self.resize(700, 580)

        root = QVBoxLayout(self)

        browser = QTextBrowser()
        browser.setOpenExternalLinks(False)
        browser.setHtml(self._help_html())
        root.addWidget(browser, stretch=1)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        root.addWidget(buttons)

    @staticmethod
    def _help_html() -> str:
        return """
<style>
  body  { font-family: Segoe UI, Arial, sans-serif; font-size: 13px; margin: 8px; }
  h3    { color: #d4af37; margin-bottom: 4px; }
  h4    { border-bottom: 1px solid #666; padding-bottom: 3px; margin-top: 14px; }
  table { border-collapse: collapse; width: 100%; }
  td    { padding: 4px 6px; vertical-align: top; }
  td:first-child { width: 170px; white-space: nowrap; font-weight: bold; }
  tr:nth-child(even) { background: rgba(128,128,128,0.08); }
  code  { background: rgba(128,128,128,0.15); padding: 0 3px; border-radius: 3px; }
  p     { margin: 4px 0 10px; }
</style>
<h3>Generic Card Pipeline &mdash; Config Reference</h3>
<p>All paths are relative to the workspace root unless absolute.
The config file is saved automatically after each pipeline run, persisting your last-used settings.</p>

<h4>fetch</h4>
<table>
  <tr><td>cardsDir</td><td>Output folder for fetched <code>.txt</code> card data files.<br>Default: <code>Cards\\Generic</code></td></tr>
  <tr><td>artDir</td><td>Output folder for downloaded artwork (used in mode 2 when art download is enabled).
    During rendering this folder is always searched for card art, and also serves as the primary art source in generate-only runs.<br>Default: <code>Artworks\\Downloaded</code></td></tr>
  <tr><td>cardlistsDir</td><td>Folder shown when browsing for a card list file in mode 2.<br>Default: <code>Copilot\\cardconjurer_batch\\Cardlists</code></td></tr>
  <tr><td>artScanDir</td><td>Folder scanned in mode 1. Each image filename (without extension) becomes a card name to fetch from Scryfall. Supports <code>.jpg</code>, <code>.jpeg</code>, <code>.png</code>.<br>
    This folder is also passed to the renderer as a <b>fallback art directory</b>: if a card&rsquo;s artwork is not found in <b>artDir</b>, the renderer automatically checks here. This means custom art placed in this folder is always picked up, even during generate-only runs.</td></tr>
  <tr><td>preferSet</td><td>Preferred MTG set code (e.g. <code>m21</code>, <code>lea</code>). Leave blank to use the default printing returned by Scryfall.</td></tr>
  <tr><td>artMode</td><td><code>1</code> &mdash; download the art image variant directly (see <b>artVersion</b>).<br><code>2</code> &mdash; download the full-card PNG then auto-crop to the art box and save as JPEG (see <b>pngCropJpegQuality</b>).</td></tr>
  <tr><td>artVersion</td><td>Scryfall image variant used when <b>artMode</b> is <code>1</code>.<br>Options: <code>art_crop</code>, <code>border_crop</code>, <code>normal</code>, <code>large</code>, <code>png</code>.</td></tr>
  <tr><td>pngCropJpegQuality</td><td>JPEG compression quality (1&ndash;100) for art produced by artMode 2. Higher = better quality, larger file.<br>Default: <code>95</code></td></tr>
  <tr><td>upscaleEnabled</td><td>Upscale downloaded/cropped artwork after fetch. <code>false</code> = skip, <code>true</code> = upscale using <b>upscaleEngine</b>.</td></tr>
  <tr><td>upscaleEngine</td><td><code>auto</code> &mdash; use Real-ESRGAN if found in PATH, otherwise fall back to Lanczos.<br><code>realesrgan</code> &mdash; force Real-ESRGAN (must be in PATH).<br><code>lanczos</code> &mdash; high-quality bicubic resize, no extra tools needed.</td></tr>
  <tr><td>upscaleFactor</td><td>Scale multiplier applied during upscale. Accepted values: <code>2</code> or <code>4</code>.</td></tr>
  <tr><td>overwrite</td><td>Whether to overwrite existing <code>.txt</code> and art files.<br><code>true</code> = always overwrite &nbsp; <code>false</code> = skip already-existing files.</td></tr>
  <tr><td>downloadArt</td><td>Pre-filled default for the &ldquo;Download artwork?&rdquo; prompt shown in mode 2.<br><code>false</code> = fetch <code>.txt</code> only &nbsp; <code>true</code> = fetch <code>.txt</code> + artwork.<br>Always ignored in mode 1 (art is already on disk).</td></tr>
  <tr><td>dryRun</td><td>If <code>true</code>, the fetch step logs what it would do but writes no files and makes no Scryfall requests. Useful for testing card lists.</td></tr>
  <tr><td>chunkSize</td><td>Cards per batch when chaining fetch&rarr;render. <code>0</code> disables chunking (fetch all first, then render all). Chunking is useful for large lists to avoid Playwright memory issues.</td></tr>
</table>

<h4>generate</h4>
<table>
  <tr><td>outputSubDir</td><td>Sub-folder relative to the <code>.txt</code> input directory where rendered PNGs are saved.<br>Default: <code>output</code></td></tr>
  <tr><td>baseUrl</td><td>URL of the local CardConjurer server. Change only if you run it on a custom port.<br>Default: <code>http://localhost:8080</code></td></tr>
  <tr><td>headless</td><td><code>true</code> = run the Playwright browser invisibly (recommended for batch runs).<br><code>false</code> = show the browser window (useful for debugging renders).</td></tr>
  <tr><td>startLauncher</td><td><code>true</code> = auto-start the CardConjurer launcher before rendering.<br><code>false</code> = assume the server is already running.</td></tr>
  <tr><td>overwrite</td><td>Whether to overwrite existing output PNG files.<br><code>false</code> = skip cards that already have a rendered PNG.</td></tr>
  <tr><td>upscaleEnabled</td><td>Upscale rendered PNG output after generation. Uses the same engine/factor options as the fetch upscale.</td></tr>
  <tr><td>upscaleEngine</td><td>Upscale engine for rendered output. Same options as <b>fetch.upscaleEngine</b>.</td></tr>
  <tr><td>upscaleFactor</td><td>Scale multiplier for rendered output: <code>2</code> or <code>4</code>.</td></tr>
  <tr><td>limit</td><td>Maximum number of cards to render in one run. <code>0</code> = render all cards found in the input directory.</td></tr>
  <tr><td>dryRun</td><td>If <code>true</code>, the render step logs which cards it would process but skips all Playwright calls.</td></tr>
</table>

<h4>layouts</h4>
<p>Per-card-type layout overrides applied during rendering. Each key is a card type; the value selects the visual layout variant for all cards of that type.</p>
<table>
  <tr><td>basicLand</td><td>Layout used for cards whose type line contains &ldquo;Basic&rdquo; (i.e. basic lands only &mdash; Forest, Island, Mountain, Plains, Swamp, Snow-covered variants, etc.).<br>
    <code>standard</code> &mdash; normal M15 frame with a regular art window (default).<br>
    <code>fullArt</code> &mdash; art fills the entire card; the frame is a single full-art overlay from <code>img/frames/m15/new/fullart/</code>.
    The frame variant is chosen automatically from the card&rsquo;s color key
    (<code>lw</code>, <code>lu</code>, <code>lb</code>, <code>lr</code>, <code>lg</code>, <code>lm</code>, or <code>l</code> for colorless).
    Only the title and type line are rendered; rules, mana, and P/T fields are omitted.</td></tr>
</table>
"""


class XmlExportConfigHelpDialog(QDialog):
    """Explains every key in xml_export_config.json."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("XML Export \u2014 Config Reference")
        self.resize(680, 520)

        root = QVBoxLayout(self)

        browser = QTextBrowser()
        browser.setOpenExternalLinks(False)
        browser.setHtml(self._help_html())
        root.addWidget(browser, stretch=1)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Close)
        buttons.rejected.connect(self.reject)
        root.addWidget(buttons)

    @staticmethod
    def _help_html() -> str:
        return """
<style>
  body  { font-family: Segoe UI, Arial, sans-serif; font-size: 13px; margin: 8px; }
  h3    { color: #d4af37; margin-bottom: 4px; }
  h4    { border-bottom: 1px solid #666; padding-bottom: 3px; margin-top: 14px; }
  table { border-collapse: collapse; width: 100%; }
  td    { padding: 4px 6px; vertical-align: top; }
  td:first-child { width: 160px; white-space: nowrap; font-weight: bold; }
  tr:nth-child(even) { background: rgba(128,128,128,0.08); }
  code  { background: rgba(128,128,128,0.15); padding: 0 3px; border-radius: 3px; }
  p     { margin: 4px 0 10px; }
</style>
<h3>XML Export &mdash; Config Reference</h3>
<p>Edit values directly in the JSON preview, then click <b>Save</b>.
The <b>Mode</b> combo in the GUI always overrides the <code>mode</code> key at run time.</p>

<h4>mode</h4>
<table>
  <tr><td>mode</td><td>Which input section to use.<br>
    <code>0</code> &mdash; Manual (uses the <code>manual</code> block)<br>
    <code>1</code> &mdash; RoleCard (uses the <code>rolecard</code> block)<br>
    Overridden by the Mode combo in the GUI.</td></tr>
</table>

<h4>manual</h4>
<table>
  <tr><td>inputFolder</td><td>Absolute or workspace-relative path to the folder containing rendered card images to include in the XML.<br>
    Example: <code>Cards\\Generic\\output</code> or <code>C:\\...\\Cards\\Generic\\output</code></td></tr>
  <tr><td>recurse</td><td><code>true</code> = include images in all sub-folders recursively.<br>
    <code>false</code> = top-level folder only.</td></tr>
</table>

<h4>rolecard</h4>
<table>
  <tr><td>roles</td><td>Which role(s) to include.<br>
    <code>0</code> &mdash; A &mdash; all roles<br>
    <code>1</code> Assassins &nbsp; <code>2</code> Bandits &nbsp; <code>3</code> Guardians &nbsp; <code>4</code> Kings &nbsp; <code>5</code> Renegades</td></tr>
  <tr><td>templatesRoot</td><td>Absolute or workspace-relative path to the <code>Cards\\templates</code> folder. Used to locate each role&rsquo;s rendered output sub-directory.<br>
    Leave blank to auto-detect relative to the script.</td></tr>
</table>

<h4>Cardback</h4>
<table>
  <tr><td>cardbackPath</td><td>Absolute or workspace-relative path to a specific cardback image to include as the back face of every card.
    Leave blank to omit the cardback entirely.</td></tr>
  <tr><td>cardbacksDir</td><td>Absolute or workspace-relative folder scanned for cardback image files when no explicit <b>cardbackPath</b> is set.<br>
    Example: <code>Cards\\Cardbacks</code></td></tr>
</table>

<h4>Print Settings</h4>
<table>
  <tr><td>stock</td><td>MPC card stock index:<br>
    <code>0</code> &mdash; (S30) Standard Smooth<br>
    <code>1</code> &mdash; (S33) Superior Smooth<br>
    <code>2</code> &mdash; (M31) Linen<br>
    <code>3</code> &mdash; (P10) Plastic</td></tr>
  <tr><td>foil</td><td><code>true</code> = mark all front faces as foil in the XML.<br>
    <code>false</code> = standard (non-foil).</td></tr>
</table>

<h4>Output</h4>
<table>
  <tr><td>autofillDir</td><td>Absolute or workspace-relative folder where the XML file is written when <b>outputXml</b> is blank.<br>
    Example: <code>Autofill</code></td></tr>
  <tr><td>outputXml</td><td>Absolute or workspace-relative path for the generated XML file. Leave blank to auto-name the file inside <b>autofillDir</b>.</td></tr>
</table>
"""


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
        root.setContentsMargins(30, 28, 30, 14)
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

        self._status_lbl = QLabel("")
        self._status_lbl.setAlignment(Qt.AlignmentFlag.AlignHCenter)
        self._status_lbl.setStyleSheet(
            "color: #d4af37;"
            "background: transparent;"
            "font-size: 11px;"
        )
        root.addWidget(self._status_lbl)

        copyright_lbl = QLabel("\u00a9 2026 CardWeaver  \u2014  do what you want with this")
        copyright_lbl.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignBottom)
        copyright_lbl.setStyleSheet(
            "color: rgba(220, 220, 220, 200);"
            "background: transparent;"
            "font-size: 10px;"
        )
        root.addWidget(copyright_lbl)

    def paintEvent(self, event):  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.drawPixmap(0, 0, self._bg)

        overlay = QColor(10, 10, 22, 175)
        # Bottom band — covers status + copyright
        painter.fillRect(0, self.height() - 58, self.width(), 58, overlay)

        # Border: faint outer glow + solid inner ring (gold, matches title)
        w, h = self.width(), self.height()
        for offset, alpha in ((0, 60), (1, 180)):
            pen = QPen(QColor(212, 175, 55, alpha))
            pen.setWidth(1)
            painter.setPen(pen)
            painter.drawRect(offset, offset, w - 1 - 2 * offset, h - 1 - 2 * offset)

    def set_status(self, text: str) -> None:
        self._status_lbl.setText(text)
        QApplication.processEvents()

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
    splash.set_status("Checking dependencies\u2026")
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
        window.raise_()
        window.activateWindow()

    QTimer.singleShot(SplashScreen.DISPLAY_MS, _launch)
    splash.clicked.connect(_launch)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
