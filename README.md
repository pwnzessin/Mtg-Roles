# MTG Role Card Proxies

> Original Google Doc with rulings and comments:
> [Google Doc Rulings](https://docs.google.com/document/d/1WVIjvqHFHGFpTnv9X1YS4IiVvw83WomYdH_6MYAuHkE/edit?tab=t.0#heading=h.be1u1vegqr31)

---

## To Do

- [ ] ~~Add 1/8 inch margin to layout~~ _(done)_
- [ ] Simplify layout usage — should work with any downloaded layout
- [ ] Add `Y_POS` parameter to cards for artwork vertical position
- [ ] Verify syntax across all cards
- [ ] Set artwork Y-positions manually
- [ ] _(Future)_ Automate artwork Y-position detection

---

## Card File Format

Each card is defined in a `.txt` file with the following tag structure:

```
<TITLE>Card Name</TITLE>
<ROLE>Roletype</ROLE>
<SETCODE>XXX x</SETCODE>
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
