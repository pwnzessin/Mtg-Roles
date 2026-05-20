#!/usr/bin/env python3
import os, subprocess, sys
from pathlib import Path

def build():
    script_dir = Path(__file__).parent
    os.chdir(script_dir)
    cmd = [sys.executable, "-m", "PyInstaller", "--onefile", "--windowed", "--name", "mtg-pipeline-gui", "--distpath", str(script_dir / "dist"), "--workpath", str(script_dir / "build"), "main.py"]
    print(f"Building executable...")
    result = subprocess.run(cmd, cwd=script_dir)
    if result.returncode == 0:
        exe_path = script_dir / "dist" / "mtg-pipeline-gui.exe"
        print(f"Build successful! Executable: {exe_path}")
    else:
        print(f"Build failed with exit code {result.returncode}")
        sys.exit(1)

if __name__ == "__main__":
    build()
