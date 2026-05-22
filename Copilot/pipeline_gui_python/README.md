# CardWeaver (Python/PyQt6)

A modern, standalone GUI for running MTG Roles pipeline tasks (Generic and Rolecard card generation).

## Features

- **Two Pipeline Tabs**: Generic Card Pipeline & Rolecard Pipeline
- **Modern Design**: Lichess-inspired, clean aesthetic
- **Theme Support**: Dark mode (default) & Light mode toggle
- **Config Management**: Load/Save pipeline configurations
- **Directory Browsing**: Easy file/folder selection
- **Live Output**: Real-time pipeline execution logs
- **Responsive UI**: Pipeline execution runs on background thread

## System Requirements

- Windows 10+
- Python 3.10+ (if running from source)
- PowerShell 5.1+ (for pipeline scripts)

## Quick Start

### Run Standalone Executable

```bash
# From command line
.\dist\CardWeaver.exe

# Or double-click the exe file
```

The GUI opens immediately. No Python installation required for the .exe version.

### Run from Source

1. **Install dependencies:**
   ```bash
   python -m pip install PyQt6==6.7.1
   ```

2. **Run the application:**
   ```bash
   python main.py
   ```

## Architecture

- `main.py` — Main application entry point, tab UI, and event handling
- `theme.py` — Lichess-style dark/light mode stylesheets
- `pipeline.py` — PowerShell subprocess wrapper
- `build.py` — PyInstaller build script
- Settings are saved to `cardweaver_settings.json` next to the exe

## Building the Executable

To rebuild the standalone .exe from source:

```bash
python build.py
```

Output: `dist/CardWeaver.exe`

## Usage

### Generic Pipeline

1. **Select Tab**: Click "Generic Pipeline" tab
2. **Load Config**: Browse to `Copilot/cardconjurer_batch/generic_card_config.json` to pre-fill all defaults.
3. **Choose a Mode**:

   | Mode | Name | What it does |
   |---|---|---|
   | 1 | Fetch + Render | Enter card names; fetches data + art from Scryfall, then renders |
   | 2 | Render custom art files | Scans your `artScanDir` for images, derives card names from filenames, fetches only the `.txt` from Scryfall (no art re-download), then renders |
   | 3 | Fetch only | Downloads card data + art without rendering |
   | 4 | Card list file | Loads a `.txt` card list, then fetches + renders |
   | 5 | Clear folders | Removes rendered PNGs and/or downloaded art |

4. **Card Input** (modes 1 & 3): type card names, comma-separated.
5. **Card Input** (mode 4): browse to a card list `.txt` file.
6. **Card Input** (mode 2 & 5): no card input needed — mode 2 reads names from artwork filenames automatically.
7. **Run**: Click "Run Generic Pipeline".
8. **Monitor**: Watch real-time output in the log area.

#### Custom Art Workflow (Mode 2)

Name your artwork files exactly after the card (e.g. `Lightning Bolt.jpg`) and place them in the directory configured as `fetch.artScanDir` in `generic_card_config.json`. Run the pipeline in mode 2 — it scans that folder, fetches the matching card data from Scryfall, and renders PNGs alongside the artwork.

### Rolecard Pipeline

Same workflow as Generic Pipeline, but for rolecard-specific rendering.

### Theme Toggle

- Click **☀️ Light Mode** (dark mode) or **🌙 Dark Mode** (light mode) button in top-right
- Theme persists for the current session

## Pipeline Scripts

The GUI calls these PowerShell scripts:

- Generic: `Copilot/cardconjurer_batch/generic_card_pipeline.ps1`
- Rolecard: `Copilot/cardconjurer_batch/role_card_pipeline.ps1`

Both must be present and executable.

## Troubleshooting

### "Pipeline script not found"
Verify the PowerShell `.ps1` script exists at the expected path relative to the project.

### No output appears
- Check PowerShell execution policy: `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser`
- Verify the script path is correct

### GUI freezes
The GUI is responsive — pipeline runs in background thread. If frozen, close and restart.

## Development Notes

Built with:
- **PyQt6** — Professional cross-platform GUI framework
- **PyInstaller** — Package Python app as standalone .exe
- **Subprocess** — PowerShell script execution

## License

Part of MTG Roles project.
