"""Pipeline subprocess wrapper for calling PowerShell scripts."""

import subprocess
from pathlib import Path

# Hide the PowerShell console window; process runs invisibly, stdout piped to GUI.
_CREATE_NO_WINDOW = 0x08000000


def run_pipeline(script_path, extra_args, output_callback=None):
    """
    Run a PowerShell pipeline script non-interactively, streaming its stdout
    line-by-line to output_callback.

    The script must be called with -Yes so it needs no stdin.
    extra_args should include -RunMode, -CardListFile/-CardNames, -ConfigFile, -Yes.

    Returns exit code (0 = success).
    """
    try:
        script_path = Path(script_path).absolute()
        if not script_path.exists():
            raise FileNotFoundError(f"Script not found: {script_path}")

        ps_cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", str(script_path),
        ] + extra_args

        process = subprocess.Popen(
            ps_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,   # merge stderr into stdout stream
            text=True,
            bufsize=1,
            encoding="utf-8",
            errors="replace",
            cwd=str(script_path.parent),
            creationflags=_CREATE_NO_WINDOW,
        )

        for line in process.stdout:
            if output_callback:
                output_callback(line.rstrip())

        process.wait()
        return process.returncode

    except Exception as e:
        if output_callback:
            output_callback(f"[ERROR] {e}")
        return 1
