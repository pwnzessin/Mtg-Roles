# Room Card Support Plan

## Background

Wizards of the Coast released **Rooms** — a new enchantment subtype with a horizontal two-door layout — in Duskmourn: House of Horror (2024). CardConjurer has no Room frame support and is no longer in active development, so Room cards must be handled outside the standard pipeline.

Reference image: `Copilot/room_example_output.jpg`  
Example card: *Underwater Tunnel // Slimy Aquarium* (DSK 79)

---

## Card Structure (from Scryfall)

- `layout`: `"split"` (same Scryfall layout type as Fire // Ice)
- `card_faces`: array of 2 face objects
  - Each face: `name`, `mana_cost`, `type_line: "Enchantment — Room"`, `oracle_text`, `artist`
- `image_uris`: **single** image (landscape crop of full card, one art for both doors)
- Distinguishing feature: both face `type_line` values contain `"Room"`

---

## Design Decisions

| Question | Decision |
|---|---|
| Art split | One shared art image for both doors (from Scryfall `art_crop`) |
| Visual target | Pixel-accurate — matches Room card layout as closely as possible |
| Frame assets | Reuse existing `m15/split/<color>.png` from CardConjurer (same structural geometry) |
| Output format | Standard portrait PNG 745×1040 (same as all other cards, MPC-compatible) |

---

## Key Technical Insight

The **existing `m15/split/<color>.png` frame assets** already have the correct structural geometry for Room cards:
- Portrait card, two equal halves stacked vertically
- Narrow title/mana strip on left of each half
- Large art area in center
- Rules text box on right
- Horizontal black divider between halves

`packSplit.js` (CardConjurer) provides the exact text coordinates — all elements use `rotation: -90`.

**The only structural difference** from a standard split card is that Room cards use **one shared art** spanning both halves, whereas standard split uses two separate quarter-arts.

---

## Room Card `.txt` Format (Phase 1)

```xml
<LAYOUT>room</LAYOUT>
<COLOR>U</COLOR>
<SETCODE>DSK C</SETCODE>
<ARTIST>Titus Lunter</ARTIST>

<FACE1_TITLE>Underwater Tunnel</FACE1_TITLE>
<FACE1_MANA>{U}</FACE1_MANA>
<FACE1_RULES>
When you unlock this door, surveil 2.
(You may cast either half. That door unlocks on the battlefield. As a sorcery, you may pay the mana cost of a locked door to unlock it.)
</FACE1_RULES>

<FACE2_TITLE>Slimy Aquarium</FACE2_TITLE>
<FACE2_MANA>{3}{U}</FACE2_MANA>
<FACE2_RULES>
When you unlock this door, manifest dread, then put a +1/+1 counter on that creature.
(You may cast either half. That door unlocks on the battlefield. As a sorcery, you may pay the mana cost of a locked door to unlock it.)
</FACE2_RULES>
```

- No `<TYPE>` tag — type line is always `"Enchantment — Room"` for both halves
- `<COLOR>` uses the same single-letter values as standard cards (`W`, `U`, `B`, `R`, `G`, `M`, `A`)
- `<FACE1_*>` = left door (when card is held landscape); bottom half in portrait output
- `<FACE2_*>` = right door (when card is held landscape); top half in portrait output
- Art file: one image with same filename stem as the `.txt` file (or placed in `--art-dir`)

---

## Text Coordinates (from `packSplit.js`)

All text fields use `rotation: -90`. Portrait card height runs 0→1 top to bottom.

| Field | x | y | Notes |
|---|---|---|---|
| `mana` (face 2) | 0.0847 | 0.4381 | Mana cost of right door |
| `title` (face 2) | 0.072 | 0.4381 | Title of right door |
| `type` (shared) | ~0.47 | 0.4381 | "Enchantment — Room"; repositioned to center divider |
| `rules` (face 2) | 0.6087 | 0.4334 | Rules of right door |
| `mana2` (face 1) | 0.0847 | 0.8943 | Mana cost of left door |
| `title2` (face 1) | 0.072 | 0.8943 | Title of left door |
| `type2` | — | — | Not used; both halves share one type line |
| `rules2` (face 1) | 0.6087 | 0.8896 | Rules of left door |

---

## `artBounds` Adaptation

Standard split (one art per half):
```js
artBounds = { x: 0.158, y: 0.0534, width: 0.3734, height: 0.3886 }
```

Room card (one shared art spanning both halves):
```js
artBounds = { x: 0.158, y: 0.0534, width: 0.3734, height: 0.842 }
```

The frame PNG is drawn on top of the art, so the center divider naturally overlaps the art.

Set symbol repositioned to the center divider area:
```js
setSymbolBounds = { x: 0.14, y: 0.44, width: 0.12, height: 0.041, vertical: 'center', horizontal: 'right' }
```

---

## Implementation Phases

### Phase 1 — Room `.txt` format *(small)*
- Define the format (documented above)
- Add Room format documentation to `Copilot/Generic_Card_Api.md`

### Phase 2 — `fetch_card.mjs` update *(small)*
- Detect Room cards: `card.layout === "split"` **AND** both face `type_line` values contain `"Room"`
- Write Phase 1 `.txt` format instead of standard front-face-only format
- Art download: use Scryfall `art_crop` (single combined image)
- Insert Room detection **before** the existing `card_faces && !json.oracle_text` branch (which discards face 2)

### Phase 3 — `generate_room_card.mjs` *(medium)*
New file: `Copilot/cardconjurer_batch/generate_room_card.mjs`

Modelled on `generate_generic_card.mjs`. Key differences:
- Parse `<FACE1_TITLE>`, `<FACE1_MANA>`, `<FACE1_RULES>`, `<FACE2_*>` tags
- Build card object with `version: "split"`, adapted `artBounds`, repositioned `type` text
- Set both `type` and `type2` to `"Enchantment — Room"` with `type` repositioned to divider
- Uses same headless Puppeteer rendering loop as the existing generators

### Phase 4 — Pipeline integration *(small)*
- In `generate_generic_card.mjs` parser: detect `<LAYOUT>room</LAYOUT>`, delegate to `generate_room_card.mjs`
- No changes needed in `generic_card_pipeline.ps1` — Room `.txt` files live in the same `Cards/Generic/` folder
- MPC XML export: no changes — Room output is a standard portrait PNG

---

## Files Changed / Created

| File | Action |
|---|---|
| `Copilot/cardconjurer_batch/generate_room_card.mjs` | **New** — Room card renderer |
| `Copilot/cardconjurer_batch/fetch_card.mjs` | **Update** — Room detection + `.txt` output |
| `Copilot/cardconjurer_batch/generate_generic_card.mjs` | **Update** — detect Room layout, delegate |
| `Copilot/Generic_Card_Api.md` | **Update** — document Room format |

---

## Status

- [x] Phase 1 — Room `.txt` format defined + `Generic_Card_Api.md` updated
- [x] Phase 2 — `fetch_card.mjs` Room detection (`isRoomCard` + `buildRoomTxt`)
- [x] Phase 3 — `generate_room_card.mjs` renderer created
- [x] Phase 4 — `generate_generic_card.mjs` skips Room cards with delegation message
- [ ] Phase 4 — pipeline integration
