# MTG Role Card Proxies

> Original Google Doc with rulings and comments:
> [Google Doc Rulings](https://docs.google.com/document/d/1WVIjvqHFHGFpTnv9X1YS4IiVvw83WomYdH_6MYAuHkE/edit?tab=t.0#heading=h.be1u1vegqr31)

---

## What This Project Does

This project generates custom Magic: The Gathering-style "role" cards for multiplayer games, where each player is secretly assigned a role (Assassin, Bandit, Guardian, King, or Renegade) with unique passive abilities. Cards are defined in simple tagged `.txt` files and rendered into print-quality JPGs using a Node.js + Playwright automation pipeline against a local CardConjurer instance. Output images include 1/8-inch print margins and are ready for upload to a card printing service like MakePlayingCards.

---

## Setup

**Requirements:** Node.js **v18 or higher** ([nodejs.org](https://nodejs.org)).

> **Note:** If you cloned this repository at commit [`abb2aad`](https://github.com/pwnzessin/Mtg-Roles/commit/abb2aad), the CardConjurer application is stored as a zip and must be extracted manually.

1. Unzip `Cardconjurer-v1.0.zip` in the repository root.
2. Rename the extracted folder to `cardconjurer-master` — it must sit at the top level of the workspace.
3. Start the CardConjurer server by running the exe; the batch scripts expect it at `http://localhost:8080`.

---

## To Do

- [x] ~~Add 1/8 inch margin to layout~~ _(done)_
- [x] Simplify layout usage — should work with any downloaded layout
- [x] ~~Add `Y_POS` parameter to cards for artwork vertical position~~ _(done)_
- [ ] Verify syntax across all cards !!When you check make sure to regerate the artworks first!!
  - [ ] Flavor text and explain text in cursive
  - [ ] loyality counters where appropriate
- [x] Final Check of different card compressions in makeplayingcards
- [ ] Set artwork Y-positions manually
  - [x] ~~Assassins~~ _(done)_
  - [ ] Bandits
  - [ ] Guardians
  - [x] ~~Kings~~ _(done)_
  - [ ] Renegades
- [x] ~~Create generic card api~~ _(done)_
- [x] ~~Fix scryfall usage limit~~ _(done)_
- [x] ~~Enable mpcautofill support~~ _(done)_
- [ ] _(Future)_ Automate artwork Y-position detection, currently you can run claude against it but takes alot of tokens to do so, currently faster manually

---

## MPC Autofill Export

`Copilot/cardconjurer_batch/Generate-MpcFillXml.ps1` scans a folder of rendered PNG/JPG images and writes an XML order file compatible with the [MPC Autofill](https://github.com/chilli-axe/mpc-autofill) desktop tool for upload to MakePlayingCards.com.

### Running

```powershell
cd Copilot\cardconjurer_batch
.\Generate-MpcFillXml.ps1
```

### What it prompts for

| Prompt | Description |
|---|---|
| Input folder | Folder containing the rendered card PNGs/JPGs |
| Include sub-folders | Recurse into sub-directories (default N) |
| Cardback image | Picks from files in `Cards/Cardbacks/`, or skip, or enter path manually |
| Cardstock | Choice of S30 / S33 / M31 / P10 (default S30 Standard Smooth) |
| Foil fronts | Y/N (default N) |
| Output XML | Defaults to `Autofill/order.xml` |

### Cardbacks

Place cardback images in `Cards/Cardbacks/`. The script lists them as numbered options when building the order. Currently contains `scryfall_standard.png` as a placeholder — replace with a real MTG card-back image when available.

---

## Generic Card Pipeline

An interactive PowerShell wizard (`Copilot/cardconjurer_batch/generic_card_pipeline.ps1`) that fetches real MTG cards from Scryfall and renders them as PNGs using the CardConjurer pipeline.

### Running

```powershell
.\Copilot\cardconjurer_batch\generic_card_pipeline.ps1
```

### Modes

| # | Mode | Description |
|---|---|---|
| 1 | Fetch + Render | Fetch card data from Scryfall and immediately render all cards |
| 2 | Render only | Render `.txt` files already in `Cards\Generic\` (no Scryfall fetch) |
| 3 | Fetch only | Download card data + art from Scryfall without rendering |
| 4 | Card list file | Load a deck-list `.txt` from `Copilot\cardconjurer_batch\Cardlists\`, then fetch + render |
| 5 | Clear folders | Interactively remove rendered PNGs, `.txt` files, and/or downloaded artwork |

### Chunked Pipeline

When a large card list is used (default threshold: 15 cards per chunk), the pipeline automatically splits the work into chunks. Each chunk's fetch and render run back-to-back, so CardConjurer is rendering the previous batch while the next Scryfall fetch waits out rate-limit delays. This significantly reduces total wall-clock time for large lists.

Chunk size is controlled by `"chunkSize"` in `Copilot/cardconjurer_batch/generic_card_config.json`. Set to `0` to disable chunking.

### Scryfall Rate Limiting

The fetch script (`fetch_card.mjs`) enforces a 200 ms delay between requests (≈5 req/s, under Scryfall's 10 req/s limit). If a 429 response is returned, it reads the `Retry-After` header and automatically waits before retrying (up to 3 retries before aborting).

### Configuration

Default values live in `Copilot/cardconjurer_batch/generic_card_config.json`:

| Key | Default | Description |
|---|---|---|
| `fetch.cardsDir` | `Cards\Generic` | Where `.txt` files are written |
| `fetch.artDir` | `Artworks\Downloaded` | Where art crops are saved |
| `fetch.cardlistsDir` | `Copilot\cardconjurer_batch\Cardlists` | Card list files directory |
| `fetch.preferSet` | _(empty)_ | Prefer a specific set code when fetching |
| `fetch.overwrite` | `true` | Overwrite existing `.txt` / art files |
| `fetch.chunkSize` | `15` | Cards per chunk (0 = no chunking) |
| `generate.outputSubDir` | `output` | Sub-folder inside `cardsDir` for rendered PNGs |
| `generate.headless` | `true` | Run Playwright headless |
| `generate.startLauncher` | `true` | Auto-start CardConjurer if not running |
| `generate.overwrite` | `true` | Overwrite existing PNG files |

---

## Generic Card File Format

Cards in `Cards/Generic/` use a simpler format than role cards. Flavor text is stored in a separate `<FLAVOR>` tag; the pipeline appends it to the rules text with the `{flavor}` marker when rendering.

```
<COLOR>A</COLOR>
<TITLE>Card Name</TITLE>
<MANA>{2}{u}</MANA>
<TYPE>Instant</TYPE>
<SETCODE>MOM R</SETCODE>
<RULES>
Rules text here.
</RULES>
<FLAVOR>
Flavor text here.
</FLAVOR>
<PT>2/3</PT>
<ARTIST>Artist Name</ARTIST>
```

### Field Reference

| Tag | Description |
|---|---|
| `<COLOR>` | Color key: `W` `U` `B` `R` `G` `M` (multi) `A` (artifact) `C` (colorless). Auto-detected on fetch. |
| `<TITLE>` | Card name |
| `<MANA>` | Mana cost in brace notation, e.g. `{2}{u}` |
| `<TYPE>` | Full type line |
| `<SETCODE>` | Set code + rarity + optional zoom, e.g. `KLD R` or `MOM R 1.2` |
| `<RULES>` | Rules text block |
| `<FLAVOR>` | _(Optional)_ Flavor text; rendered in italics below a divider bar |
| `<PT>` | _(Optional)_ Power/toughness, e.g. `3/3` |
| `<ARTIST>` | Artist credit |
| `<ART_YPOS>` | _(Optional)_ Artwork vertical offset (see Role Card format above) |


---

## Card File Format

Each card is defined in a `.txt` file with the following tag structure:

```
<TITLE>Card Name</TITLE>
<ROLE>Roletype</ROLE>
<SETCODE>XXX x</SETCODE>
<ART_YPOS>0.05</ART_YPOS>
<RULES>
Rules text line 1
Rules text line 2
</RULES>
```

### Field Reference

| Tag | Description |
|---|---|
| `<TITLE>` | Display name of the card |
| `<ROLE>` | Role type (e.g. `Assassin`, `Bandit`, `Guardian`, `King`) |
| `<SETCODE>` | Set code and rarity letter (e.g. `PD3 c`) |
| `<ART_YPOS>` | _(Optional)_ Artwork vertical offset as a fraction of card height (e.g. `0.05`). Positive values shift art downward. Range: `0.0` – `0.2`. Omit to use the layout default. |
| `<RULES>` | Rules text block; supports inline symbols (see below) |

### Inline Symbols

| Syntax | Output |
|---|---|
| `{1}` `{w}` `{u}` `{b}` `{r}` `{g}` `{X}` | Mana symbols |
| `{-}` | Em dash |
| `{flavor}` | Flavor text (italicised) |
| `{center}` | Centered text |
| `{fontcolor_#000000}` | Custom font color (hex) |
| `•` + `{indent}` | Bulleted choice option with indent |


