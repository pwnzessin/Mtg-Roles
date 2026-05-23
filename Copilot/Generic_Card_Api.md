The final goal will be to have a tool that can take txt files which describe basic magic cards + an artwork with the same name and create the png out of that.

Steps to achieve that:

- Find out how we can define different frames etc for the cards
- If it is possible to list all possible frames from cardconjurer to select?
- Create a description for txt template, which should contain all the fields that have to be filled for the card

After this is done we review and decide the next steps

---

## Status

All three steps are resolved. Frame structure is documented in `CardConjurer_File_Structure.md`.
Available M15Regular color frames are listed below. Generator script: `Copilot/cardconjurer_batch/generate_generic_card.mjs`.

---

## Generic Card txt Format

Each card is a `.txt` file using XML-style tags. A `.png` artwork file with the same filename stem placed alongside the `.txt` (or in a folder specified via `--art-dir`) will be used as the card art.

```
<COLOR>W</COLOR>
<TITLE>Inspiring Cleric</TITLE>
<MANA>{2}{W}</MANA>
<TYPE>Creature — Human Cleric</TYPE>
<SETCODE>ONE R</SETCODE>
<ART_YPOS>0.0</ART_YPOS>
<PT>2/3</PT>
<RULES>
When Inspiring Cleric enters the battlefield, you gain 3 life.
</RULES>
<FLAVOR>
Even the smallest spark can light the darkest hall.
</FLAVOR>
<ARTIST>Jane Doe</ARTIST>
```

### Field Reference

| Tag | Required | Description |
|-----|----------|-------------|
| `<COLOR>` | Yes | Single letter: `W` `U` `B` `R` `G` `M` `A` `L` `C` `V` |
| `<TITLE>` | Yes | Card name |
| `<MANA>` | No | Mana cost using CardConjurer symbols, e.g. `{2}{W}` |
| `<TYPE>` | Yes | Full type line, e.g. `Creature — Human Cleric` |
| `<SETCODE>` | No | Set code + rarity + optional zoom, e.g. `ONE R` or `ONE R 1.2` |
| `<ART_YPOS>` | No | Vertical art offset (0.0 = top, positive moves art down) |
| `<PT>` | No | Power/Toughness, e.g. `2/3`. Omit for non-creature cards. |
| `<RULES>` | Yes | Rules text. Supports CardConjurer inline symbols like `{tap}`, `{w}`, `{-}`. |
| `<FLAVOR>` | No | Flavor text. Rendered below rules with a flavor bar separator. |
| `<ARTIST>` | No | Artist name shown in the card footer. |

### Color Values

| Value | Frame |
|-------|-------|
| `W` | White |
| `U` | Blue |
| `B` | Black |
| `R` | Red |
| `G` | Green |
| `M` | Multicolored (gold) |
| `A` | Artifact |
| `L` | Land |
| `C` | Colorless / Eldrazi |
| `V` | Vehicle |

---

## Planeswalker txt Format

Planeswalkers are detected automatically when `<TYPE>` contains "Planeswalker". Omit `<RULES>` and `<PT>`; use `<ABILITY0>`–`<ABILITY3>` instead.

```
<COLOR>W</COLOR>
<TITLE>Elspeth, Sun's Champion</TITLE>
<MANA>{4}{W}{W}</MANA>
<TYPE>Legendary Planeswalker — Elspeth</TYPE>
<SETCODE>THS M</SETCODE>
<LOYALTY>4</LOYALTY>
<ABILITY0>+1 | Create three 1/1 white Soldier creature tokens.</ABILITY0>
<ABILITY1>-3 | Destroy all creatures with power 4 or greater.</ABILITY1>
<ABILITY2>-7 | You get an emblem with "Creatures you control get +2/+2 and have flying."</ABILITY2>
<ARTIST>Eric Deschamps</ARTIST>
```

### Planeswalker-specific tags

| Tag | Required | Description |
|-----|----------|-------------|
| `<LOYALTY>` | No | Starting loyalty value |
| `<ABILITY0>`–`<ABILITY3>` | Yes (at least 1) | Format: `{cost} \| {rules text}` — cost is e.g. `+1`, `-3`, `0` |

---

## Room Card txt Format

Room cards use the M15 Split frame with one shared art spanning both doors. Use `generate_room_card.mjs` to render them.

```
<LAYOUT>room</LAYOUT>
<COLOR>U</COLOR>
<SETCODE>DSK R</SETCODE>
<ARTIST>Slawomir Maniak</ARTIST>

<FACE1_TITLE>Underwater Tunnel</FACE1_TITLE>
<FACE1_MANA>{1}{U}</FACE1_MANA>
<FACE1_RULES>
When you unlock this door, look at the top four cards of your library. Put one into your hand and the rest on the bottom of your library in any order.
</FACE1_RULES>

<FACE2_TITLE>Slimy Aquarium</FACE2_TITLE>
<FACE2_MANA>{3}{U}</FACE2_MANA>
<FACE2_RULES>
When you unlock this door, surveil 2.
(You may cast either half. That door unlocks on the battlefield. As a sorcery, you may pay the mana cost of a locked door to unlock it.)
</FACE2_RULES>
```

### Room-specific tags

| Tag | Required | Description |
|-----|----------|-------------|
| `<LAYOUT>room</LAYOUT>` | Yes | Marks the file as a Room card; `generate_generic_card.mjs` skips it |
| `<COLOR>` | Yes | Same color values as standard cards; `U` is default if omitted |
| `<FACE1_TITLE>` | Yes | Left-door name (bottom half in portrait output) |
| `<FACE1_MANA>` | No | Left-door mana cost |
| `<FACE1_RULES>` | No | Left-door rules text |
| `<FACE2_TITLE>` | Yes | Right-door name (top half in portrait output) |
| `<FACE2_MANA>` | No | Right-door mana cost |
| `<FACE2_RULES>` | No | Right-door rules text |
| `<SETCODE>` | No | Same format as standard cards |
| `<ARTIST>` | No | Shared artist credit |

**Notes:**
- `<TYPE>` is not used — the type line is always "Enchantment — Room" (hardcoded in the renderer).
- The artwork file (`{stem}.jpg` / `.png`) is the full landscape-crop art; it spans both halves.
- `fetch_card.mjs` auto-detects Room cards from Scryfall and writes this format automatically.

### Room generator usage

```powershell
node Copilot/cardconjurer_batch/generate_room_card.mjs `
  --input  Cards/Generic/myRooms `
  --output Cards/Generic/myRooms/output `
  --headless true `
  --overwrite true
```

Options are identical to `generate_generic_card.mjs` (`--input`, `--output`, `--art-dir`, `--base-url`, `--headless`, `--start-launcher`, `--overwrite`, `--dry-run`, `--limit`). The script ignores any non-Room `.txt` files in the input directory.

---

## Generator Usage

```powershell
node Copilot/cardconjurer_batch/generate_generic_card.mjs `
  --input <dir|file> `
  --output <output-dir> `
  --base-url http://localhost:8080 `
  --headless true `
  --overwrite true
```

Full option list:

| Option | Default | Description |
|--------|---------|-------------|
| `--input` | _(required)_ | Path to a `.txt` file or a directory of `.txt` files |
| `--output` | `Cards/Generic/` | Where to save the generated `.png` files |
| `--art-dir` | same as input | Directory to look for artwork `.png` files |
| `--base-url` | `http://localhost:8080` | CardConjurer server URL |
| `--headless` | `false` | Run browser headlessly |
| `--start-launcher` | `true` | Auto-start `launcher.exe` if server is not up |
| `--overwrite` | `false` | Re-generate even if output file already exists |
| `--dry-run` | `false` | Parse and report without rendering |
| `--limit` | `0` (all) | Cap how many cards to process |

---

## Scryfall Fetch Tool

`Copilot/cardconjurer_batch/fetch_card.mjs` looks up one or more cards on Scryfall and writes a ready-to-render `.txt` file **plus** artwork alongside it — no manual file preparation needed.

### Usage

```powershell
node Copilot/cardconjurer_batch/fetch_card.mjs `
  "Lightning Bolt" "Llanowar Elves" "Sol Ring" `
  --output Cards/Generic/myCards
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--output <dir>` | `.` (current dir) | Directory to write `.txt` + `.jpg` files |
| `--set <code>` | _(any printing)_ | Prefer a specific set, e.g. `m21` |
| `--art-version <name>` | `art_crop` | Scryfall image variant: `art_crop`, `border_crop`, `normal`, `large`, `png` |
| `--overwrite` | `false` | Re-fetch even if files already exist |
| `--no-art` | `false` | Skip downloading the artwork image |
| `--dry-run` | `false` | Print the generated `.txt` to stdout without writing files |

### What gets written

For each card name passed on the command line, two files are created in `--output`:

- **`{Card Name}.txt`** — fully populated generic card file in the format above
- **`{Card Name}.jpg`** — for `art_crop`, `border_crop`, `normal`, or `large`
- **`{Card Name}.png`** — when `--art-version png` is used

Double-faced cards (DFC) automatically use the front face data and artwork.

### Symbol conversion

Scryfall mana symbols are automatically converted to the CardConjurer format used in `<RULES>` text:

| Scryfall | CardConjurer |
|----------|--------------|
| `{T}` | `{t}` |
| `{W}` / `{U}` / `{B}` / `{R}` / `{G}` | `{w}` / `{u}` / `{b}` / `{r}` / `{g}` |
| `{C}` | `{c}` |
| `{X}` | `{x}` |
| `{W/U}` | `{wu}` |
| `{W/P}` | `{wp}` |
| `{Q}` | `{untap}` |

Mana cost symbols in `<MANA>` are kept as-is (uppercase Scryfall format works in CardConjurer).

---

## Full Pipeline: Scryfall → Card PNG

Fetch data + art, then render — two commands from the workspace root:

```powershell
# Step 1: fetch card data and artwork from Scryfall
node Copilot/cardconjurer_batch/fetch_card.mjs `
  "Lightning Bolt" "Llanowar Elves" `
  --output Cards/Generic/myCards

# Step 2: render to card PNG
node Copilot/cardconjurer_batch/generate_generic_card.mjs `
  --input  Cards/Generic/myCards `
  --output Cards/Generic/myCards/output `
  --overwrite
```

The generator automatically pairs each `.txt` with the `.jpg` of the same stem — no `--art-dir` needed when artwork sits in the same folder.
