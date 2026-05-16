# CardConjurer Refactor Plan

Target file: `cardconjurer-master/cardconjurer-master/js/creator-23.js` (~5200 lines)

Each item below is a self-contained fix or improvement, ordered roughly by severity.

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
