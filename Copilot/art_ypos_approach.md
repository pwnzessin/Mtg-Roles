# ART_YPOS Tag — Implementation Approach

## Goal

Add an optional `<ART_YPOS>` tag to `.txt` card files that overrides the artwork vertical position after CardConjurer's `autoFit` runs.

---

## CardConjurer Coordinate System (researched)

From `js/creator-23.js`:

```js
card.artY = document.querySelector('#art-y').value / card.height;
// card.height = 2814 (full-res)
```

- `card.artY` is a **fraction of `card.height`** (float, typically −0.5 to +0.5)
- `0` = top/default position (as stored in the template)
- Positive = art shifts **down**, negative = art shifts **up**
- Same unit as what is saved in `.cardconjurer` template files (`artY` field)

### Why autoFit timing matters

`uploadArt(url, 'autoFit')` only sets `art.src` synchronously.  
The actual Y position is set **asynchronously** inside `art.onload → autoFitArt() → artEdited()`.  
Any override must happen **after** the art has fully loaded.

---

## Tag Format

```
<ART_YPOS>0.15</ART_YPOS>
```

- Value is the raw `card.artY` fraction (same units as the `.cardconjurer` file)
- Tag is **optional** — omitting it falls back to `autoFit` positioning
- To find the right value: open CardConjurer, drag art to desired position, save card, inspect `artY` in the exported `.cardconjurer` JSON

---

## Implementation Plan

### 1. `parseTaggedCardFile()` — parse the new tag

```js
const artYPosMatch = raw.match(/<ART_YPOS>([\s\S]*?)<\/ART_YPOS>/i);

return {
  title: ...,
  role: ...,
  setCode: ...,
  rules: ...,
  artYPos: artYPosMatch ? parseFloat(artYPosMatch[1].trim()) : null
};
```

### 2. Card queue object — pass through

```js
cards.push({
  stem, filePath, title, role, setCode, rarity, number, rules, artUrl, outputPath,
  artYPos: parsed.artYPos   // null if tag absent
});
```

### 3. Generate loop — inject override AFTER art-ready wait

Current sequence per card:
```
page.evaluate(...)           ← sets text, calls uploadArt(url, 'autoFit')
page.waitForFunction(...)    ← waits for drawFrames / frames ready
page.waitForFunction(art.complete && art.naturalWidth > 0)
page.waitForTimeout(700)     ← autoFit has now run
↑ INSERT HERE
downloadCard(...)
```

Add after `waitForTimeout(700)`:

```js
if (c.artYPos !== null) {
  await page.evaluate((artYPos) => {
    card.artY = artYPos;
    // Keep the #art-y input in sync so any subsequent artEdited() calls
    // don't overwrite our value
    const input = document.querySelector('#art-y');
    if (input) input.value = Math.round(artYPos * card.height);
    if (typeof window.drawCard === 'function') window.drawCard();
  }, c.artYPos);
  // Small wait to let the redraw settle before download
  await page.waitForTimeout(200);
}
```

### 4. `batch_gen_calls.md` / README update

Document the tag in the Card File Format section and the inline symbols table.

---

## Files to Change

| File | Change |
|---|---|
| `Copilot/cardconjurer_batch/generate_role_cards.mjs` | `parseTaggedCardFile`, card object, generate loop |
| `README.md` | Field Reference table — add `<ART_YPOS>` row |
| `Copilot/Card_conjurer_conventions.md` | (optional) note new tag |

---

## Out of Scope

- X position (`artX`) — not needed yet, same pattern would apply
- Zoom (`artZoom`) — same pattern would apply if needed
