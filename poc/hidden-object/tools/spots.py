"""Turns a hand-written spot list into the scene's spot map, and draws it for checking.

Usage: python spots.py <scene dir> <spots txt>   (needs Pillow + numpy)
The txt has one spot per line: `id x y maxSize classes surface [occludeBelow]`
  x, y        bottom-centre anchor on the surface, in background pixels (2752x1536)
  maxSize     largest allowed long side of an object placed here, in background pixels
  classes     s = small objects only, sm = small or medium objects
  surface     shelf, floor, rug, basket, books, ... (free text, for the app's tuning)
  occludeBelow  for container spots: scene pixels below this y are drawn back over the object
Writes <scene>/spots.json and <scene>/out/spots_debug.jpg (each spot as its max box; blue = small only,
green = small or medium, orange line = occlusion cut).
"""
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OCC_FEATHER = 6

def occlusion_polygon(x, y, max_size, cut):
    half = round(max_size * 0.65)
    return [[x - half, cut], [x + half, cut], [x + half, y + 10], [x - half, y + 10]]

def load_spots(txt):
    spots = []
    for line in Path(txt).read_text().splitlines():
        line = line.split("#")[0].strip()
        if not line: continue
        p = line.split()
        sid, x, y, ms, cls, surf = p[0], int(p[1]), int(p[2]), int(p[3]), p[4], p[5]
        s = {"id": sid, "x": x, "y": y, "maxSize": ms, "sizeClass": ["small"] if cls == "s" else ["small", "medium"], "surface": surf}
        if len(p) > 6:
            cut = int(p[6])
            s["occlusion"] = {"cutY": cut, "polygon": occlusion_polygon(x, y, ms, cut), "feather": OCC_FEATHER}
        spots.append(s)
    return spots

if __name__ == "__main__":
    root, txt = Path(sys.argv[1]), sys.argv[2]
    spots = load_spots(txt)
    bg = Image.open(root / "raw/background.png").convert("RGB")
    (root / "spots.json").write_text(json.dumps({"size": list(bg.size), "spots": spots}, indent=1))
    d = ImageDraw.Draw(bg)
    try: font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 24)
    except Exception: font = ImageFont.load_default()
    for s in spots:
        x, y, m = s["x"], s["y"], s["maxSize"]
        col = (60, 200, 90) if "medium" in s["sizeClass"] else (60, 140, 255)
        d.rectangle([x - m // 2, y - m, x + m // 2, y], outline=col, width=4)
        d.ellipse([x - 6, y - 6, x + 6, y + 6], fill=col)
        if "occlusion" in s:
            c = s["occlusion"]["cutY"]; d.line([x - m // 2 - 10, c, x + m // 2 + 10, c], fill=(255, 140, 0), width=4)
        d.text((x - m // 2, y - m - 28), s["id"], fill="white", font=font, stroke_width=3, stroke_fill="black")
    (root / "out").mkdir(exist_ok=True)
    bg.save(root / "out/spots_debug.jpg", quality=82)
    xs = sorted(s["x"] for s in spots); ys = sorted(s["y"] for s in spots)
    W, H = bg.size
    grid = [[0] * 4 for _ in range(3)]
    for s in spots: grid[min(2, s["y"] * 3 // H)][min(3, s["x"] * 4 // W)] += 1
    print(len(spots), "spots;", sum("occlusion" in s for s in spots), "with occlusion;",
          sum("medium" in s["sizeClass"] for s in spots), "take medium; spread (3 rows x 4 cols):", grid)
