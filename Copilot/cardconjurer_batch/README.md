# CardConjurer Batch Generator

This script batch-creates role card PNGs from `Cards/<RoleFolder>/*.txt` files using your local CardConjurer.

It expects each card text file to use:
- `<TITLE>...</TITLE>`
- `<ROLE>...</ROLE>`
- `<RULES>...</RULES>`

## What it does
- Loads `Cards/templates/Assassin_Layout.cardconjurer` as the base layout for every generated card
- Starts `cardconjurer-master/cardconjurer-master/launcher.exe` (optional)
- Opens `http://localhost:8080/creator` when using the bundled launcher
- Use `--base-url http://localhost:4242` if you are running Card Conjurer through Docker or another server on port 4242
- Imports each card's title/type/rules
- Tries to apply matching artwork from `Artworks/<RoleFolder>/<CardName>.png`
- Downloads the rendered PNG to `Cards/templates/<RoleFolder>/<CardName>.png`
- Writes a run report to `Copilot/cardconjurer_batch_<rolefolder>_report.txt`

## Setup
Run from this folder:

```powershell
npm install
npx playwright install chromium
```

## Example: generate all Bandits
```powershell
npm run generate -- --role Bandits --headless false --start-launcher true --overwrite false
```

## Useful flags
- `--role <FolderName>`: Role folder under `Cards/` and `Artworks/` (default `Bandits`)
- `--headless true|false`: Playwright headless mode (default `false`)
- `--start-launcher true|false`: auto-start launcher.exe (default `true`)
- `--overwrite true|false`: overwrite existing PNGs (default `false`)
- `--artist "Name"`: artist credit text used for download checks (default `Unknown`)
- `--dry-run true|false`: parse/list cards only, no browser automation (default `false`)
- `--limit <N>`: process first N cards for quick testing (default `0`, meaning all)

## First test (recommended)
```powershell
npm run generate -- --role Bandits --dry-run true --limit 5
npm run generate -- --role Bandits --limit 3
```
