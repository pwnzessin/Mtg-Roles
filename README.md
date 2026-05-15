# MTG Role Card Proxies

> Original Google Doc with rulings and comments:
> [Google Doc Rulings](https://docs.google.com/document/d/1WVIjvqHFHGFpTnv9X1YS4IiVvw83WomYdH_6MYAuHkE/edit?tab=t.0#heading=h.be1u1vegqr31)

---

## What This Project Does

This project generates custom Magic: The Gathering-style "role" cards for multiplayer games, where each player is secretly assigned a role (Assassin, Bandit, Guardian, King, or Renegade) with unique passive abilities. Cards are defined in simple tagged `.txt` files and rendered into print-quality JPGs using a Node.js + Playwright automation pipeline against a local CardConjurer instance. Output images include 1/8-inch print margins and are ready for upload to a card printing service like MakePlayingCards.

---

## To Do

- [x] ~~Add 1/8 inch margin to layout~~ _(done)_
- [ ] Simplify layout usage — should work with any downloaded layout
- [x] ~~Add `Y_POS` parameter to cards for artwork vertical position~~ _(done)_
- [ ] Verify syntax across all cards
- [ ] Final Check of different card compressions in makeplayingcards
- [ ] Set artwork Y-positions manually
  - [x] ~~Assassins~~ _(done)_
  - [ ] Bandits
  - [ ] Guardians
  - [x] ~~Kings~~ _(done)_
  - [ ] Renegades
- [ ] Create generic card api
- [ ] _(Future)_ Automate artwork Y-position detection


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
