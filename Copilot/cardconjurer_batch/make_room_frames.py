"""
Create custom Room card frame PNGs by removing the divider in the art-column area.

In the M15 split frame, the divider bar (y=927-1071) goes all the way across.
For Room cards, the divider should only show in the text-box side (x >= 800).
The art column (x=240-790) should be transparent so art flows continuously
through both door windows.

Output: cardconjurer-master/.../img/frames/m15/room/<color>.png
"""

from pathlib import Path
from PIL import Image

SPLIT_DIR = Path(__file__).parents[2] / "cardconjurer-master" / "cardconjurer-master" / "img" / "frames" / "m15" / "split"
ROOM_DIR  = SPLIT_DIR.parent / "room"
ROOM_DIR.mkdir(exist_ok=True)

# Pixel bounds derived by sampling u.png (1500×2100):
#   Art window interior (transparent): x=240-790 at any y inside the window
#   Top art window ends at:    y~926  (alpha goes from 0 → 255)
#   Bottom art window starts:  y~1072 (alpha goes from 255 → 0)
#   Divider band to clear:     x=240-790, y=926-1072  (inclusive)
ART_X_START = 240
ART_X_END   = 791   # exclusive end
DIV_Y_START = 926
DIV_Y_END   = 1073  # exclusive end

COLORS = ["w", "u", "b", "r", "g", "m", "a", "l", "v"]

for color in COLORS:
    src = SPLIT_DIR / f"{color}.png"
    if not src.exists():
        print(f"  skip {color} (not found)")
        continue

    img  = Image.open(src).convert("RGBA")
    data = img.load()

    for y in range(DIV_Y_START, DIV_Y_END):
        for x in range(ART_X_START, ART_X_END):
            r, g, b, a = data[x, y]
            data[x, y] = (r, g, b, 0)

    dest = ROOM_DIR / f"{color}.png"
    img.save(dest)
    print(f"  saved {dest.relative_to(SPLIT_DIR.parents[3])}")

print("Done.")
