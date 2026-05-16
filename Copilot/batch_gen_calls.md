# Batch Card Generation

## Script

```powershell
.\Copilot\cardconjurer_batch\Rolecard_Batch_Generator.ps1
```

## Compressed All-Roles Script

```powershell
.\Copilot\cardconjurer_batch\generate_all_compressed.ps1
```

Run from the workspace root. This runs all roles and auto-compresses output images using the compression profile in `generate_all_compressed.ps1`.

Run from the workspace root. The script will interactively prompt for:

1. **Which roles to generate**
   - Enter comma-separated numbers (e.g. `1,3`) to pick specific roles
   - Enter `A` to generate all four roles
   - Available roles: `1. Assassins`, `2. Bandits`, `3. Guardians`, `4. Kings`

2. **How many cards per role**
   - Enter a number (e.g. `5`) to limit to the first N cards per role
   - Enter `A` to generate every card in the role's folder

3. **Output quality**
   - `1` — Original full resolution (~7 MB PNG, 2010×2814)
   - `2` — 50% PNG (~2.4 MB, 1005×1407)
   - `3` — 37% PNG (~1.4 MB, 750×1050, 300 DPI at card size)
   - `4` — 50% JPEG 85% (~300 KB, 1005×1407) *(default)*

## Apply Margin Frame to Existing JPGs

```powershell
.\Copilot\cardconjurer_batch\apply_margin_frame.ps1
```

Run from the workspace root. Stamps a solid black 1/8-inch border on every existing `.jpg` in all role template folders. Use this after initial generation or whenever the margin needs to be re-applied without regenerating cards.

## Examples

| Roles | Count | Quality | Effect |
|---|---|---|---|
| `A` | `A` | `4` | All roles, all cards, JPEG |
| `A` | `1` | `4` | Smoke test — 1 card per role |
| `2,3` | `10` | `2` | Bandits + Guardians, 10 cards, 50% PNG |
| `1` | `A` | `1` | Assassins only, all cards, full resolution |

---

## Generic Card Pipeline

Fetch card data + artwork from Scryfall, then render to PNG. Run from the workspace root.

```powershell
# Fetch .txt + art_crop .jpg from Scryfall
node Copilot/cardconjurer_batch/fetch_card.mjs `
  "Card Name 1" "Card Name 2" `
  --output Cards/Generic/myCards

# Render to card PNG
node Copilot/cardconjurer_batch/generate_generic_card.mjs `
  --input  Cards/Generic/myCards `
  --output Cards/Generic/myCards/output `
  --overwrite
```

See `Generic_Card_Api.md` for the full option reference and `.txt` format.