# CardConjurer Refactor Plan

Primary target: `cardconjurer-master/cardconjurer-master/js/creator-23.js` (~5200 lines / 205 KB)

---

## Safety Strategy

### Git discipline
- Create one branch per phase: `refactor/phase-1-bugs`, `refactor/phase-2-quality`, `refactor/phase-3-arch`
- Each branch is based on the previous merged branch, not `main` directly
- Merge each phase only after the test gate passes
- Keep commits small and single-purpose; one commit per numbered fix below

### Test gate after every phase
Run in order — stop and fix if anything fails:

```powershell
# 1. Dry-run (no server needed, validates parsing/config)
cd Copilot/cardconjurer_batch
npm run generate -- --role Assassins --dry-run true

# 2. Real render of one card (requires launcher running)
npm run generate -- --role Assassins --base-url http://localhost:8080 --headless true --overwrite true --limit 1

# 3. Generic card pipeline (covers borderless + PW code paths)
npm run generate:generic -- --headless true --overwrite true --limit 1
```

### Functions the headless pipeline depends on — treat with extra care
These are called directly from the batch scripts via `page.evaluate()` or `window.*`:

| Function | Called by | Risk if changed |
|---|---|---|
| `loadCard(key)` | role + generic pipelines | High — every card |
| `addFrame(frameObj)` | called by `loadCard` | High — frame visibility |
| `drawFrames()` | pipeline after `loadCard` | High — renders output |
| `loadFramePack(url)` | pipeline pre-load step | Medium — crash if called twice |
| `fixPlaneswalkerInputs(cb)` | generic pipeline | Medium — PW cards |
| `downloadCard()` / canvas API | pipeline download step | High — final PNG |

### Known headless pipeline gotchas (do NOT break these invariants)
These bugs were hit and fixed in the batch scripts. Any creator-23.js change must preserve these invariants:

**H1 — `loadFramePack()` must only be called once per page load.**
Calling it twice causes a Chromium crash (exit -1073740791 / STATUS_STACK_BUFFER_OVERRUN). Do not add any auto-preload logic inside `loadCard` or `addFrame` that re-invokes `loadFramePack`.

**H2 — `fixPlaneswalkerInputs(callback)` must return `undefined`.**
The function calls `callback` internally and returns nothing. The pipeline call is `window.fixPlaneswalkerInputs(window.planeswalkerEdited)` (no trailing `()`). Do not change the function to return a callable.

**H3 — `masks: []` in a card's frame object must result in a fully-visible frame.**
The `drawFrames()` compositing loop uses `source-in` for each mask. With zero masks the frame PNG renders unclipped. If you refactor the mask loop, ensure an empty array still skips all masking. Never add "default mask population" logic in `addFrame()` or `loadCard()`.

---

## Phase 1 — Trivial Bug Fixes (branch: `refactor/phase-1-bugs`)

**Pipeline risk: None** — these fix dead or broken code paths the pipeline never hits, or add declarations that don't change runtime behavior.

Each fix is a 1–5 line change. No behavior change for any currently-working code path.

### 1. `findManaSymbolIndex` uses undeclared `key` instead of its parameter
```js
// BROKEN
function findManaSymbolIndex(string) {
    return mana.get(key) || -1;   // `key` is not defined here
}
```
Fix: replace `key` with `string`, or delete the function (it is never called in the file).

---

### 2. `resetDoubleClick` only resets one variable
```js
// BROKEN — comma operator: only lastMaskClick is set to null
function resetDoubleClick() {
    lastFrameClick, lastMaskClick = null, null;
}
```
Fix:
```js
function resetDoubleClick() {
    lastFrameClick = null;
    lastMaskClick  = null;
}
```

---

### 3. `scryfallCardFromText` uses `Array.count` (always `undefined`)
`lines.count` is always `undefined`; JavaScript arrays use `.length`. Every early-return guard in this function is dead code.

Fix: replace all `lines.count` with `lines.length`.

---

### 7. `getSetSymbolWatermark` uses implicit global `xhttp`
```js
xhttp = new XMLHttpRequest();   // no var/let/const
```
Fix: `const xhttp = new XMLHttpRequest();`

---

### 10. `var colors = colors` in `cardFrameProperties`
```js
function cardFrameProperties(colors, ...) {
    var colors = colors.map(...)  // redeclares its own parameter
```
In non-strict mode this is harmless but confusing. Remove the `var` keyword so it's a plain reassignment.

---

### 13. `innerHTML` with user-controlled frame names (Security)
In `addFrame` and the drag-reorder code, `frameElementLabel.innerHTML` is set directly from `frameToAdd.name`. Use `textContent` instead to prevent XSS if users share `.cardconjurer` files.

---

## Phase 2 — Moderate Bug Fixes (branch: `refactor/phase-2-bugs`)

**Pipeline risk: Low–Medium** — these touch functions the pipeline does use. Each fix needs the render test gate to pass before merging.

### 4. `makeM15EighthUBFrameByLetter` — `style` is undefined in Inner Crown branch
The function has no `style` parameter, but the Inner Crown handler references it:
```js
'src': '/img/frames/m15/innerCrowns/m15InnerCrown' + letter + style + '.png',
```
This will throw `ReferenceError` for any UB Inner Crown card. Fix: add `style = 'regular'` as a default parameter, or remove the dead branch if it is unused.

UB Inner Crown cards are not used in the current pipeline, so pipeline risk is nil — but fix it before adding new card types that use this frame.

---

### 5. Implicit global variables in `drawFrames()`
```js
frameX = Math.round(scaleX(bounds.x || 0));   // no var/let/const
frameY = Math.round(scaleY(bounds.y || 0));
frameWidth  = ...;
frameHeight = ...;
```
These leak onto `window`. Declare with `let` inside the loop.

**Pipeline risk**: The pipeline calls `drawFrames()` directly. After the fix, run the full render test gate to confirm frame positions are unaffected.

---

### 6. Orphaned `fillRect` call in `loadCard`
Near the end of `loadCard` there is a stray line:
```js
guidelinesContext.fillRect(setSymbolX, setSymbolY, setSymbolWidth, setSymbolHeight);
```
`setSymbolX/Y/Width/Height` are not defined in scope here. This likely throws a silent `ReferenceError` on every `loadCard` call — including every headless render.

**Before fixing**: search the file for where `setSymbolX` is defined and whether it is *supposed* to be called here. If it is genuinely orphaned, remove the line. If it belongs in a `setSymbol` drawing helper, move it there.

**Pipeline risk**: High. `loadCard` is on the critical path. After removing/moving this line, run the full render test gate immediately.

---

## Phase 3 — Code Quality (branch: `refactor/phase-3-quality`)

**Pipeline risk: None** — these are dead code removals and comment cleanups that don't affect any live code path.

### 8. `getStandardWidth` / `getStandardHeight` — dead high-res system
The adaptive high-res functions are commented out; stubs return hardcoded `2010` / `2814`. `highResScale = 1.34` is defined but never used. Options:
- Remove dead commented-out code and the unused constant (safest), **or**
- Re-implement high-res using the constant if that feature is wanted.

---

### 9. `fixUri` is a no-op stub
The entire body is commented-out redirect logic; the function just returns `input`. All 60+ call sites are pointless overhead. Options:
- Delete `fixUri` and inline `input` at all call sites, **or**
- Re-enable the CDN-prefix logic if it is still needed for a hosted deployment.

---

### 11. Redundant `watermarkEdited` commented-out DOM reads
Two lines setting `card.watermarkLeft` / `card.watermarkRight` from the DOM are commented out, replaced with a conditional that only updates `card.watermarkLeft` when it equals `'none'`. The intent is unclear. Clean up or add an explaining comment.

---

### 12. Debug canvas always injected into DOM
`sizeCanvas` unconditionally appends a `fake-hidden` `<div>` wrapper around the `line` canvas on every page load. Gate it behind the `debugging` flag:
```js
if (name == 'line' && debugging) { ... }
```

---

## Phase 4 — Architecture (branch: `refactor/phase-4-arch`)

**Pipeline risk: Very High** — splitting the monolith changes how global functions are exposed. The headless pipeline relies on `window.*` access to `loadCard`, `drawFrames`, `loadFramePack`, etc.

### 14. Split the 5200-line monolith into ES modules
Proposed split:
- `canvas.js` — canvas creation, `sizeCanvas`, `drawFrames`
- `frames.js` — `loadFramePack`, `addFrame`, `makeM15*` helpers
- `text.js` — text rendering engine, mana symbol handling
- `scryfall.js` — `scryfallCardFromText`, Scryfall API helpers
- `io.js` — `loadCard`, `downloadCard`, save/export

**Prerequisites before starting:**
1. Phases 1–3 must be merged (clean codebase to split)
2. Decide on delivery mechanism: `<script type="module">` (no bundler, works with local server) vs. Rollup/Vite bundle
3. The pipeline's `page.evaluate()` calls reference `window.loadCard` etc. — after the split, either re-export these onto `window` explicitly, or update the pipeline scripts to import from the new module URLs

**Suggested approach**: Use `<script type="module">` in `index.html` and explicitly assign pipeline-critical functions to `window` at the end of each module:
```js
// in io.js
window.loadCard = loadCard;
window.downloadCard = downloadCard;
```

---

## Summary Table

| # | Phase | Type | Effort | Pipeline Risk | Impact |
|---|---|---|---|---|---|
| 1 | 1 | Bug | Trivial | None | Medium |
| 2 | 1 | Bug | Trivial | None | Low |
| 3 | 1 | Bug | Trivial | None | Low |
| 7 | 1 | Bug | Trivial | None | Low |
| 10 | 1 | Quality | Trivial | None | Low |
| 13 | 1 | Security | Trivial | None | Medium |
| 4 | 2 | Bug | Small | None (unused path) | Low |
| 5 | 2 | Bug | Small | Low | Low |
| 6 | 2 | Bug | Small | **High** | Medium |
| 8 | 3 | Quality | Small | None | Low |
| 9 | 3 | Quality | Medium | None | Low |
| 11 | 3 | Quality | Small | None | Low |
| 12 | 3 | Quality | Trivial | None | Low |
| 14 | 4 | Architecture | Large | Very High | High |

---

## Bugs (wrong behaviour / crash risk)

### 1. `findManaSymbolIndex` uses undeclared `key` instead of its parameter
```js
// BROKEN
function findManaSymbolIndex(string) {
    return mana.get(key) || -1;   // `key` is not defined here
}
```
Fix: replace `key` with `string`, or delete the function (it is never called in the file).

---

### 2. `resetDoubleClick` only resets one variable
```js
// BROKEN — comma operator: only lastMaskClick is set to null
function resetDoubleClick() {
    lastFrameClick, lastMaskClick = null, null;
}
```
Fix:
```js
function resetDoubleClick() {
    lastFrameClick = null;
    lastMaskClick  = null;
}
```

---

### 3. `scryfallCardFromText` uses `Array.count` (always `undefined`)
`lines.count` is always `undefined`; JavaScript arrays use `.length`. Every early-return guard in this function is dead code.

Fix: replace all `lines.count` with `lines.length`.

---

### 4. `makeM15EighthUBFrameByLetter` — `style` is undefined in Inner Crown branch
The function has no `style` parameter, but the `Inner Crown` handler references it:
```js
'src': '/img/frames/m15/innerCrowns/m15InnerCrown' + letter + style + '.png',
```
This will throw a `ReferenceError`. Fix: add `style = 'regular'` as a default parameter, or remove the unused branch.

---

### 5. Implicit global variables in `drawFrames()`
```js
frameX = Math.round(scaleX(bounds.x || 0));   // no var/let/const
frameY = Math.round(scaleY(bounds.y || 0));
frameWidth  = ...;
frameHeight = ...;
```
These leak onto `window`. Fix: declare with `let` or `const` inside the loop.

---

### 6. Orphaned line in `loadCard`
Near the end of `loadCard` there is a stray line that looks misplaced:
```js
guidelinesContext.fillRect(setSymbolX, setSymbolY, setSymbolWidth, setSymbolHeight);
```
`setSymbolX/Y/Width/Height` are not defined in scope here. This likely causes a silent error on every card load. Investigate and remove or move.

---

### 7. `getSetSymbolWatermark` uses implicit global `xhttp`
```js
xhttp = new XMLHttpRequest();   // no var/let/const
```
Fix: add `var xhttp = ...` (or `const`).

---

## Code Quality / Misleading Code

### 8. `getStandardWidth` / `getStandardHeight` — dead high-res system
The original adaptive high-res functions are fully commented out and replaced with stubs that return hardcoded `2010` / `2814`. The constant `highResScale = 1.34` is defined but never used. Either:
- Remove the dead commented-out code and the unused constant, **or**
- Re-implement high-res properly using the constant.

---

### 9. `fixUri` is a no-op stub
The entire body is a commented-out redirect logic; the function just returns `input`. All 60+ call sites (`fixUri(...)`) are pointless overhead. Either:
- Delete `fixUri` and all call sites, **or**
- Re-enable the CDN-prefix logic if it is still needed for a hosted version.

---

### 10. `var colors = colors` in `cardFrameProperties`
```js
function cardFrameProperties(colors, ...) {
    var colors = colors.map(...)  // redeclares its own parameter
```
In non-strict mode this is harmless but confusing. Remove the `var` keyword so it's a plain reassignment.

---

### 11. Redundant `watermarkEdited` commented-out DOM reads
Two lines that set `card.watermarkLeft` / `card.watermarkRight` directly from DOM are commented out and replaced with a conditional that only updates `card.watermarkLeft` when it equals `'none'`. The intent and the actual behavior are unclear. Clean up or document why only the conditional form is correct.

---

### 12. Debug canvas always injected into DOM
`sizeCanvas` unconditionally appends the `line` canvas element (styled `fake-hidden`) on every page load:
```js
if (name == 'line') {
    window[name + 'Canvas'].style = '...';
    const label = document.createElement('div');
    ...
    label.classList = 'fake-hidden'; // Comment this out to view canvases
    document.body.appendChild(label);
}
```
This creates a hidden `<div>` in the real DOM on every page load. Gate it behind the `debugging` flag:
```js
if (name == 'line' && debugging) { ... }
```

---

## Security

### 13. `innerHTML` with user-controlled frame names
In `addFrame` and the drag-reorder code, `frameElementLabel.innerHTML` is set directly from `frameToAdd.name`, which can contain user-uploaded frame names. Use `textContent` instead to prevent XSS if users ever share `.cardconjurer` files.

---

## Architecture (longer-term)

### 14. Monolithic 5200-line JS file
Everything — canvas management, text rendering, frame building, Scryfall API calls, import/export, UI event handlers — is in one file. Consider splitting into ES modules:
- `canvas.js` — canvas creation and drawing
- `frames.js` — frame pack loading and auto-frame logic  
- `text.js` — text rendering engine
- `scryfall.js` — Scryfall API helpers
- `io.js` — save/load/download

This would require either a bundler (Rollup/Vite) or `<script type="module">` in `index.html`, both of which work with the existing local server setup.

---

## Summary Table

| # | Type | Effort | Impact |
|---|---|---|---|
| 1 | Bug | Trivial | Medium |
| 2 | Bug | Trivial | Low |
| 3 | Bug | Trivial | Low |
| 4 | Bug | Small | Low |
| 5 | Bug | Small | Low |
| 6 | Bug | Small | Medium |
| 7 | Bug | Trivial | Low |
| 8 | Quality | Small | Low |
| 9 | Quality | Medium | Low |
| 10 | Quality | Trivial | Low |
| 11 | Quality | Small | Low |
| 12 | Quality | Trivial | Low |
| 13 | Security | Trivial | Medium |
| 14 | Architecture | Large | High |
