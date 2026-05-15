# CardConjurer Batch Generator

This script batch-creates role card PNGs from `Cards/<RoleFolder>/*.txt` files using your local CardConjurer.

This folder now includes three workflows:
- `generate_role_cards.mjs`: core generator used by npm script
- `Rolecard_Batch_Generator.ps1`: interactive role/count/quality runner
- `generate_all_compressed.ps1`: one-shot all roles with automatic compression

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

## Interactive batch runner (recommended)
Use this when you want prompts for role selection, card limit, and output quality/compression:

```powershell
.\Rolecard_Batch_Generator.ps1
```

Quality presets in this script:
- `1`: Original PNG (full resolution)
- `2`: 50% PNG
- `3`: 37% PNG (`750x1050` at `300 DPI`)
- `4`: 50% JPEG quality 85 (default)

## Generate all roles with auto compression
Use this for unattended generation of all roles with automatic post-processing to compressed output:

```powershell
.\generate_all_compressed.ps1
```

Current compression profile in `generate_all_compressed.ps1`:
- Format: `Jpeg`
- Scale: `0.5`
- Quality: `85`

You can edit the `$compression` block in that script to switch format, scale, target size, DPI, or JPEG quality.

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

## Notes
- When using the launcher flow, default base URL is `http://localhost:8080`.
- Server mode fallback is `http://localhost:4242`.
- Batch reports are written to `Copilot/cardconjurer_batch_<rolefolder>_report.txt`.
