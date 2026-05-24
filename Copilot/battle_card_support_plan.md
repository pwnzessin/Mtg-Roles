# Battle Card Support — Implementation Plan

Battle cards (introduced in *March of the Machine*) are double-faced:
- **Front** — a "Battle — Siege" with a Defense value (like loyalty but bottom-right)
- **Back** — a separate card (creature, enchantment, etc.) that it transforms into

Each battle must produce **two** output `.txt` files and (optionally) two art images.

---

## Checklist

### 1. Research — Scryfall data ✅
- [x] Run `node fetch_card.mjs "Invasion of Zendikar" --dry-run` and inspect the raw JSON
- [x] Note which `layout` value Scryfall uses for battles
      → **`"transform"`** (same as regular DFCs — must also check `card_faces[0].type_line` for "Battle")
- [x] Check whether `card_faces[1]` (back face) always has its own `image_uris`
      → **Yes** — each face has its own `image_uris` with all variants (art_crop, png, etc.)

**Confirmed Scryfall shape (Invasion of Zendikar):**
- `layout` = `"transform"`, root has no `oracle_text`, no `colors`, no `image_uris`
- `card_faces[0]`: name, type "Battle — Siege", mana_cost, oracle_text, **`defense`**, colors, artist, image_uris
- `card_faces[1]`: name, type "Creature — …", oracle_text, power, toughness, colors, artist, image_uris
- Detection: `card.layout === "transform"` **AND** `card_faces[0].type_line` matches `/\bBattle\b/`

### 2. Research — CardConjurer frame assets ✅
- [x] Scan `cardconjurer-master/.../img/frames/` for a `battle/` subfolder
      → **No battle frame exists.** Folders present: m15, planeswalker, saga, modal, etc.
- [x] Check `custom/` folder → no battle assets there either

**Decision: use `m15` regular frame for the front face.**
The battle front face has the same layout as a normal card (title, mana, art, type, rules)
except the bottom-right shows a **Defense** counter instead of P/T.
We will render it as an m15 card and place the defense value in the P/T box
(formatted as `DEF: N`) until a dedicated battle frame is available.
The back face uses whatever frame matches its own type (creature → m15, etc.) —
no special case needed if `buildBattleBackTxt` produces a standard `.txt`.

### 3. `fetch_card.mjs` — detection & .txt builders ✅

#### 3a. Add `isBattleCard(card)` ✅
- [x] Returns `true` when `card.layout === "transform"` AND `card_faces[0].type_line` ∋ "Battle"

#### 3b. Add `buildBattleFrontTxt(card)` ✅
- [x] Uses `card_faces[0]` — emits `<LAYOUT>battle</LAYOUT>`, `<DEFENSE>N</DEFENSE>`, all standard fields

#### 3c. Add `buildBattleBackTxt(card)` ✅
- [x] Synthesises a root-card object from `card_faces[1]` and calls `buildTxt()` — back face gets its natural frame

#### 3d. Fixed `fetchCard()` — battle cards no longer flattened ✅
- [x] Battle check fires before the generic DFC merge; both faces are preserved

#### 3e. Updated main loop ✅
- [x] Detects battle cards and writes two `.txt` files + downloads two art images (one per face, using face-level `image_uris`)

### 4. `generate_generic_card.mjs` — rendering ✅

#### 4a. Front face (Battle — Siege) ✅
- [x] `parseGenericCardFile` detects `<LAYOUT>battle</LAYOUT>`, returns `isBattle: true` + `defense`
- [x] `buildCardObject` has a new `isBattle` branch: M15 regular frame, defense value in P/T box slot
      (no P/T frame overlay added — battles have no power/toughness)

#### 4b. Back face ✅
- [x] Back face `.txt` uses standard layout tags → falls through to M15Regular as a creature — no special case needed

### 5. `generic_card_pipeline.ps1` ✅
- [x] No changes needed — pipeline processes all `.txt` files in the input folder unchanged

### 6. Testing ✅
- [x] `fetch_card.mjs --dry-run` confirmed correct field output for both faces
- [x] `fetch_card.mjs` (real) wrote two `.txt` files (`Invasion of Zendikar.txt` + `Awakened Skyclave.txt`)
- [x] `generate_generic_card.mjs --dry-run` confirmed:
      — front face parsed as `type=battle`, color=G
      — back face parsed as `type=regular`, color=G (creature, renders normally)
- [ ] **Visual check pending** — run pipeline on both `.txt` files and inspect output PNGs

---

## Notes / Decisions Log
*(fill in as we go)*

- Scryfall `layout` for battles: **`"transform"`** — detection uses `card_faces[0].type_line` ∋ "Battle"
- CardConjurer battle frame: **does not exist** → m15 regular fallback, defense in P/T box as `DEF: N`
- Defense field tag chosen: `<DEFENSE>` (mirrors `<LOYALTY>`)
- Back-face rendering strategy: reuse `buildTxt()` with face data injected as root card
