"""JSON syntax highlighter — VS Code-inspired colour palette."""

import re
from PyQt6.QtGui import QSyntaxHighlighter, QTextCharFormat, QColor


class JsonHighlighter(QSyntaxHighlighter):

    _DARK = {
        "key":    "#9cdcfe",   # light blue  (VS Code JSON key)
        "string": "#ce9178",   # orange      (VS Code string value)
        "number": "#b5cea8",   # light green (VS Code number)
        "bool":   "#569cd6",   # blue        (VS Code keyword)
    }
    _LIGHT = {
        "key":    "#001080",   # dark blue
        "string": "#a31515",   # dark red
        "number": "#098658",   # dark green
        "bool":   "#0000ff",   # blue
    }

    # Order matters: 'string' is applied first, 'key' overrides it for keys.
    _PATTERNS = [
        ("string", re.compile(r'"(?:[^"\\]|\\.)*"')),
        ("key",    re.compile(r'"(?:[^"\\]|\\.)*"(?=\s*:)')),
        ("number", re.compile(r'(?<!["\w])-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?(?!["\w])')),
        ("bool",   re.compile(r'\b(?:true|false|null)\b')),
    ]

    def __init__(self, document, dark: bool = True):
        super().__init__(document)
        self._formats: dict[str, QTextCharFormat] = {}
        self.set_dark(dark)

    def set_dark(self, dark: bool) -> None:
        palette = self._DARK if dark else self._LIGHT
        self._formats = {}
        for name, color in palette.items():
            fmt = QTextCharFormat()
            fmt.setForeground(QColor(color))
            self._formats[name] = fmt
        self.rehighlight()

    def highlightBlock(self, text: str) -> None:
        for name, pattern in self._PATTERNS:
            fmt = self._formats.get(name)
            if fmt is None:
                continue
            for m in pattern.finditer(text):
                self.setFormat(m.start(), m.end() - m.start(), fmt)
