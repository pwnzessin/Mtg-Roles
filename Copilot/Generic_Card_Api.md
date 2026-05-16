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
