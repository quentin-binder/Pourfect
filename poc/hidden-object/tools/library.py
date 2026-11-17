"""Builds a scene's object library: cleaned, trimmed cut-outs ready for random placement.

Usage: python library.py <scene dir>   (needs Pillow + numpy)
Reads <scene>/library.json and the Bria cut-outs it lists (objects/<id>.png);
writes <scene>/lib/<id>.png (cleaned, trimmed, long side at most 512 px) and <scene>/out/library_sheet.png
(every object on magenta, to spot halos, shadow smears and stray bits).
"""
import json, sys, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hocommon import clean_cutout

MAX_SIDE = 512

root = Path(sys.argv[1])
lib = json.loads((root / "library.json").read_text())
(root / "lib").mkdir(exist_ok=True)
(root / "out").mkdir(exist_ok=True)

tiles = []
for o in lib["objects"]:
    im = clean_cutout(Image.open(root / o["src"]), o.get("clean", {}))
    if max(im.size) > MAX_SIDE:
        im.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    im.save(root / f"lib/{o['id']}.png")
    tiles.append((o, im))

try: font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15)
except Exception: font = ImageFont.load_default()
T, cols = 200, 8
sheet = Image.new("RGB", (cols * T, math.ceil(len(tiles) / cols) * (T + 22)), (40, 40, 40))
d = ImageDraw.Draw(sheet)
for i, (o, im) in enumerate(tiles):
    t = Image.new("RGBA", (T - 8, T - 8), (255, 0, 255, 255))
    c = im.copy(); c.thumbnail((T - 16, T - 16))
    t.alpha_composite(c, ((t.width - c.width) // 2, (t.height - c.height) // 2))
    x, y = (i % cols) * T, (i // cols) * (T + 22)
    sheet.paste(t.convert("RGB"), (x + 4, y + 4))
    d.text((x + 6, y + T - 2), f"{o['id']} ({o['size'][0]})", fill="white", font=font)
sheet.save(root / "out/library_sheet.png")
print("library", lib["scene"], len(tiles), "objects")
