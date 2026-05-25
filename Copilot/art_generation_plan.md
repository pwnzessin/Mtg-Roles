# Art Generation Pipeline — Implementation Plan

## Goal

Add a new "Art Generation" tab to CardWeaver that reads the same card list `.txt`
files used by the Generic pipeline, generates artwork for each card via
[Pollinations.ai](https://image.pollinations.ai/) (free, no API key), and saves
the images to a chosen output folder — ready to be used as card art by
`generate_generic_card.mjs`.

The tab follows the **exact same structure** as the existing pipeline tabs:
config JSON file → PowerShell wrapper script → Node worker script.

---

## Files to Create / Modify

| File | Action |
|---|---|
| `Copilot/cardconjurer_batch/generate_art.mjs` | **Create** — Node ESM worker |
| `Copilot/cardconjurer_batch/generate_art_pipeline.ps1` | **Create** — PowerShell wrapper (same pattern as `generic_card_pipeline.ps1`) |
| `Copilot/cardconjurer_batch/art_gen_config.json` | **Create** — default config (same pattern as `generic_card_config.json`) |
| `Copilot/pipeline_gui_python/main.py` | **Modify** — add `ArtGenerationTab` + help dialog + wire into tab bar |

---

## 1. `art_gen_config.json` — default config

```json
{
    "_comment": "Default values for generate_art_pipeline.ps1. All paths are relative to workspaceRoot unless absolute.",
    "workspaceRoot": null,
    "cardlistsDir":  "Copilot\\cardconjurer_batch\\Cardlists",
    "outputDir":     "Artworks\\Generated",
    "style":         "fantasy card art, digital painting, highly detailed, no text, no borders",
    "prefix":        "",
    "overwrite":     false,
    "concurrency":   1,
    "width":         626,
    "height":        457,
    "seed":          null,
    "dryRun":        false
}
```

---

## 2. `generate_art.mjs` — Node ESM worker

### CLI flags

| Flag | Description |
|---|---|
| `--names <csv>` | Comma-separated card names (mode 1) |
| `--cardlist <path>` | Path to a cardlist `.txt` (one name per line) (mode 2) |
| `--output <path>` | Folder where generated art images are saved |
| `--style <string>` | Prompt suffix (style descriptor) |
| `--prefix <string>` | Optional freeform text prepended to each prompt |
| `--overwrite` | Re-generate even if output file already exists |
| `--dry-run` | Print prompts without downloading |
| `--concurrency <n>` | Max simultaneous requests (default: 1) |
| `--width <n>` | Image width px (default: 626) |
| `--height <n>` | Image height px (default: 457) |
| `--seed <n>` | Optional fixed seed |

When `--cardlist` points to a folder of fetched `.txt` card files, the script
reads `<TITLE>`, `<TYPE>`, and `<COLOR>` from each file to build richer prompts.

### Prompt construction

```
{prefix} {CardName}, {type_hint}, {style}
```

Examples:
- `"Sol Ring, artifact, fantasy card art, digital painting, highly detailed"`
- `"Invasion of Zendikar, battle siege, green, fantasy card art, digital painting"`

### Pollinations.ai API call

```
GET https://image.pollinations.ai/prompt/{encodedPrompt}
    ?width=626&height=457&nologo=true&model=flux[&seed=N]
```

Response is a raw JPEG. Saved as `{safeName}.jpg` in `--output`.

### Progress / reporting

- One line per card: `OK → Sol Ring.jpg` or `SKIP → Sol Ring.jpg (exists)`
- Final summary: `Done. X generated, Y skipped, Z failed.`

---

## 3. `generate_art_pipeline.ps1` — PowerShell wrapper

Same structure as `generic_card_pipeline.ps1`:

```
param(
    [string]$ConfigFile   = "$PSScriptRoot\art_gen_config.json",
    [int]   $RunMode      = 0,        # 1 = card names, 2 = card list file; 0 = ask
    [string]$CardListFile = "",
    [switch]$Yes
)
```

- Loads config JSON via `Read-Config`
- Resolves `outputDir` relative to `workspaceRoot`
- Calls `node "$PSScriptRoot\generate_art.mjs"` with flags derived from config +
  mode/card-input args
- Same `Ask-*` helper pattern for interactive fallback when `-Yes` is not set

---

## 4. `main.py` — `ArtGenerationTab`

Extends `_PipelineTabBase` — identical structure to `GenericPipelineTab`:

```python
class ArtGenerationTab(_PipelineTabBase):
    SCRIPT_NAME  = "generate_art_pipeline.ps1"
    RUN_LABEL    = "Generate Art"
    HAS_MODES    = True    # mode 1 = card names, mode 2 = card list file
    SETTINGS_KEY = "art_gen_config"
```

- Uses the same config file browse/save/preview widget from the base class
- Uses the same mode combo + card name / card list stack from the base class
- No `_init_extra_ui` override needed

Wired as the 4th tab:
```python
self.tabs.addTab(ArtGenerationTab(), "Art Generation")
```

Help button opens `ArtGenerationHelpDialog` (same pattern as
`GenericConfigHelpDialog`).

---

## 5. Implementation order

- [x] Write this plan
- [ ] Create `art_gen_config.json`
- [ ] Create `generate_art.mjs`
- [ ] Create `generate_art_pipeline.ps1`
- [ ] Test pipeline from terminal on one card
- [ ] Add `ArtGenerationTab` + `ArtGenerationHelpDialog` to `main.py`
- [ ] Wire tab + help dialog into `PipelineGUI`
- [ ] Smoke test in the GUI
