"""Hidden-object art proof of concept: place cut-out objects into a painted scene.

Usage: python compose.py <poc dir>   (needs Pillow + numpy)
Reads raw/background.png, objects/<name>.png and scene_spec.json; writes out/ and layers/.
Each object becomes up to three layers so an app can make it vanish cleanly:
  shadow (soft contact shadow), object (tinted to the scene), occluder (scene pixels drawn back on top).
"""
import json, sys, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hocommon import clean_cutout, match_to_scene as _match, shadow_for as _shadow

root = Path(sys.argv[1])
spec = json.loads((root / "scene_spec.json").read_text())
bg = Image.open(root / "raw/background.png").convert("RGBA")
W, H = bg.size
(root / "out").mkdir(exist_ok=True)
(root / "layers").mkdir(exist_ok=True)

def prepare(name, o):
    im = clean_cutout(Image.open(root / f"objects/{name}.png"), o, legacy_blob=True)
    h = o["height"]
    im = im.resize((max(1, round(im.width * h / im.height)), h), Image.LANCZOS)
    if o.get("rotate"):
        im = im.rotate(o["rotate"], resample=Image.BICUBIC, expand=True)
    if o.get("flip"):
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return im

scene = bg.copy()
manifest = []
for name, o in spec["objects"].items():
    im = prepare(name, o)
    x, y = o["x"] - im.width // 2, o["y"] - im.height   # anchor: bottom centre on the surface
    im = _match(im, bg, (x, y, im.width, im.height), o.get("tint", 0.18))
    sh, pad = _shadow(im, o.get("shadow", 0.38))
    sx, sy = x - pad + o.get("shadowDx", 5), y - pad + o.get("shadowDy", 4)
    layer = {"name": name, "label": o["label"], "object": {"file": f"layers/{name}.png", "x": x, "y": y, "w": im.width, "h": im.height},
             "shadow": {"file": f"layers/{name}_shadow.png", "x": sx, "y": sy}}
    im.save(root / f"layers/{name}.png"); sh.save(root / f"layers/{name}_shadow.png")
    scene.alpha_composite(sh, (sx, sy))
    scene.alpha_composite(im, (x, y))
    if "occludeBelow" in o:                                  # e.g. sitting inside a basket or bowl
        cut = o["occludeBelow"]
        feather = 6
        box = (x - 4, cut - feather, x + im.width + 4, y + im.height + 6)
        patch = bg.crop(box)
        m = Image.new("L", patch.size, 0)
        d = ImageDraw.Draw(m)
        for i in range(patch.height):
            d.line([(0, i), (patch.width, i)], fill=min(255, int(255 * i / (2 * feather))))
        patch.putalpha(m)
        patch.save(root / f"layers/{name}_occluder.png")
        scene.alpha_composite(patch, box[:2])
        layer["occluder"] = {"file": f"layers/{name}_occluder.png", "x": box[0], "y": box[1]}
    manifest.append(layer)

(root / "layers/scene.json").write_text(json.dumps({"background": "raw/background.png", "size": [W, H], "objects": manifest}, indent=2))
scene.convert("RGB").save(root / "out/scene_full.png")

# vanished version: draw everything except the "found" ones (as the app would)
found = set(spec.get("foundForDemo", []))
s2 = bg.copy()
for L in manifest:
    if L["name"] in found: continue
    s2.alpha_composite(Image.open(root / L["shadow"]["file"]), (L["shadow"]["x"], L["shadow"]["y"]))
    s2.alpha_composite(Image.open(root / L["object"]["file"]), (L["object"]["x"], L["object"]["y"]))
    if "occluder" in L:
        s2.alpha_composite(Image.open(root / L["occluder"]["file"]), (L["occluder"]["x"], L["occluder"]["y"]))
s2.convert("RGB").save(root / "out/scene_some_found.png")

# debug overlay: where everything is
dbg = scene.copy()
d = ImageDraw.Draw(dbg)
try: font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 30)
except Exception: font = ImageFont.load_default()
for L in manifest:
    b = L["object"]; d.rectangle([b["x"], b["y"], b["x"] + b["w"], b["y"] + b["h"]], outline=(255, 40, 120), width=4)
    d.text((b["x"], b["y"] - 34), L["label"], fill=(255, 40, 120), font=font, stroke_width=3, stroke_fill="white")
dbg.convert("RGB").save(root / "out/scene_debug.png")

# closeups of each placement (2x) to judge blending
tiles = []
for L in manifest:
    b = L["object"]; m = 70
    c = scene.crop((b["x"] - m, b["y"] - m, b["x"] + b["w"] + m, b["y"] + b["h"] + m)).convert("RGB")
    c.thumbnail((300, 300)); tiles.append(c)
sheet = Image.new("RGB", (4 * 310, math.ceil(len(tiles) / 4) * 310), (30, 30, 30))
for i, t in enumerate(tiles): sheet.paste(t, ((i % 4) * 310 + 5, (i // 4) * 310 + 5))
sheet.save(root / "out/closeups.png")
print("ok", len(manifest), "objects")
