# CardConjurer File Structure

This note describes the structure used by the `*.cardconjurer` template files in this workspace, based on `Cards/templates/Assassin_Layout.cardconjurer` and the other role layouts.

## File Shape

The file is JSON, not a line-oriented text format.

At the top level it is a JSON array with one entry:

```json
[
  {
    "key": "Assassin_Layout",
    "data": {
      "...": "template data"
    }
  }
]
```

The important parts are:

- `key`: the template name
- `data`: the full layout definition used by CardConjurer

## Main Data Object

The `data` object contains the card layout, art placement, text box placement, metadata blocks, and rendering settings.

Common top-level fields include:

- `width`, `height`, `marginX`, `marginY`
- `frames`
- `artSource`, `artX`, `artY`, `artZoom`, `artRotate`
- `setSymbolSource`, `setSymbolX`, `setSymbolY`, `setSymbolZoom`
- `watermarkSource`, `watermarkX`, `watermarkY`, `watermarkZoom`
- `watermarkLeft`, `watermarkRight`, `watermarkOpacity`
- `version`, `manaSymbols`, `infoYear`
- `margins`, `bottomInfoTranslate`, `bottomInfoRotate`, `bottomInfoZoom`, `bottomInfoColor`
- `onload`, `hideBottomInfoBorder`, `showsFlavorBar`
- `bottomInfo`, `artBounds`, `setSymbolBounds`, `watermarkBounds`
- `text`
- `infoNumber`, `infoRarity`, `infoSet`, `infoLanguage`, `infoArtist`, `infoNote`
- `serialNumber`, `serialTotal`, `serialX`, `serialY`, `serialScale`

## Frame Definition

The `frames` property is an array. In the current templates it contains one frame entry.

Each frame object includes:

- `name`
- `src`
- `masks`

## Text Blocks

The `text` object groups the editable text regions on the card.

Current keys under `text` are:

- `mana`
- `title`
- `type`
- `rules`
- `reminder`
- `pt`

Each text block contains placement and styling data such as:

- `name`
- `text`
- `x`, `y`
- `width`, `height`
- `font`
- `size`
- `oneLine`
- `align`

Not every block uses every property. For example, `rules` and `pt` expose different styling fields depending on how the card frame renders them.

## Practical Reading Pattern

The batch generator already reads the file as JSON:

```js
const templateBundle = JSON.parse(fs.readFileSync(templatePath, "utf8"));
const templateCard = templateBundle?.[0]?.data;
```

That means any code consuming these files should:

1. Read the whole file as UTF-8 text.
2. Parse it with `JSON.parse`.
3. Use the first array item’s `data` object as the actual template payload.

## Notes

- All role layout files in `Cards/templates/` follow this same outer JSON wrapper.
- The real card layout lives inside the `data` object.
- If parsing fails, the file is malformed JSON rather than a custom CardConjurer text format.