# Batch Card Generation

## Script

```powershell
.\Copilot\cardconjurer_batch\Rolecard_Batch_Generator.ps1
```

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

## Examples

| Roles | Count | Quality | Effect |
|---|---|---|---|
| `A` | `A` | `4` | All roles, all cards, JPEG |
| `A` | `1` | `4` | Smoke test — 1 card per role |
| `2,3` | `10` | `2` | Bandits + Guardians, 10 cards, 50% PNG |
| `1` | `A` | `1` | Assassins only, all cards, full resolution |