@echo off
REM CardWeaver Launcher
REM Runs the standalone PyQt6 GUI application

setlocal enabledelayedexpansion

REM Get the directory where this script is located
set SCRIPT_DIR=%~dp0

REM Path to the executable
set EXE_PATH=%SCRIPT_DIR%dist\CardWeaver.exe

REM Check if exe exists
if not exist "!EXE_PATH!" (
    echo Error: CardWeaver.exe not found at:
    echo !EXE_PATH!
    echo.
    echo Please run build.py first to create the executable:
    echo   python build.py
    pause
    exit /b 1
)

REM Launch the GUI
echo Launching CardWeaver...
start "" "!EXE_PATH!"

exit /b 0
