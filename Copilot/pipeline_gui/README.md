# MTG Pipeline GUI (Tauri)

Desktop GUI wrapper for the existing MTG PowerShell pipelines.

## Features
- Generic Pipeline tab
- Rolecard Pipeline tab
- Load/edit/save JSON config files
- Run each pipeline from the app
- Status log output in the UI

## Scripts
- `npm install`
- `npm run build`
- `npm run tauri -- dev`
- `npm run tauri -- build --debug`

## Notes
- The default script/config paths are prefilled for this workspace.
- Backend commands are in `src-tauri/src/main.rs`.
- Frontend UI is in `src/main.ts` and `src/styles.css`.
