"""Hidden-object art proof of concept: place cut-out objects into a painted scene.

Usage: python compose.py <poc dir>   (needs Pillow + numpy)
Reads raw/background.png, objects/<name>.png and scene_spec.json; writes out/ and layers/.
Each object becomes up to three layers so an app can make it vanish cleanly:
  shadow (soft contact shadow), object (tinted to the scene), occluder (scene pixels drawn back on top).
"""
import json, sys, math
from pathlib import Path
from PIL import Image, ImageFilter, ImageEnhance, ImageDraw, ImageFont
import numpy as np

root = Path(sys.argv[1])
spec = json.loads((root / "scene_spec.json").read_text())
bg = Image.open(root / "raw/background.png").convert("RGBA")
W, H = bg.size
(root / "out").mkdir(exist_ok=True)
(root / "layers").mkdir(exist_ok=True)

def keep_main_blob(mask):
    """Connected region (4-neighbour) containing the centre of the mask's bounding box, grown by repeated dilation."""
    ys, xs = np.nonzero(mask)
    cy, cx = (ys.min() + ys.max()) // 2, (xs.min() + xs.max()) // 2
    if not mask[cy, cx]:                             # fall back to the opaque pixel nearest the centre
        k = np.argmin((ys - cy) ** 2 + (xs - cx) ** 2); cy, cx = ys[k], xs[k]
    region = np.zeros_like(mask); region[cy, cx] = True
    while True:
        grown = region.copy()
        grown[1:] |= region[:-1]; grown[:-1] |= region[1:]; grown[:, 1:] |= region[:, :-1]; grown[:, :-1] |= region[:, 1:]
        grown &= mask
        if (grown == region).all(): return region
        region = grown

def prepare(name, o):
    im = Image.open(root / f"objects/{name}.png").convert("RGBA")
    a = np.array(im).astype(np.float32)
    # drop faint halo / painted ground residue: alpha below threshold -> 0, then smooth
    alpha = a[..., 3]
    alpha[alpha < o.get("alphaCut", 40)] = 0
    for (y0, y1) in o.get("eraseRows", []):          # fractions of height, e.g. grass under the mushroom
        alpha[int(y0 * alpha.shape[0]):int(y1 * alpha.shape[0]), :] = 0
    if o.get("keepLargest"):                         # drop stray bits (loose coins, crumbs): keep the blob around the densest pixel
        alpha[~keep_main_blob(alpha > 0)] = 0
    a[..., 3] = alpha
    im = Image.fromarray(a.astype(np.uint8))
    im = im.crop(im.getbbox())
    h = o["height"]
    im = im.resize((max(1, round(im.width * h / im.height)), h), Image.LANCZOS)
    if o.get("rotate"):
        im = im.rotate(o["rotate"], resample=Image.BICUBIC, expand=True)
    if o.get("flip"):
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return im

def match_to_scene(im, box, tint=0.18):
    """Tint and darken the object toward the scene around it so it doesn't 'pop'."""
    x, y, w, h = box
    pad = max(w, h)
    region = bg.crop((max(0, x - pad), max(0, y - pad), min(W, x + w + pad), min(H, y + h + pad))).convert("RGB")
    r = np.array(region).reshape(-1, 3).astype(np.float32)
    mean = r.mean(0)
    lum_scene = (0.299 * mean[0] + 0.587 * mean[1] + 0.114 * mean[2]) / 255
    rgb = np.array(im).astype(np.float32)
    a = rgb[..., 3:4]
    col = rgb[..., :3]
    col = col * (1 - tint) + mean * tint                      # pull toward local colour
    col = col * (0.72 + 0.35 * lum_scene)                      # match local brightness
    gray = col.mean(-1, keepdims=True)
    col = gray + (col - gray) * 0.85                            # slightly less saturated than the cut-out
    out = np.concatenate([np.clip(col, 0, 255), a], -1).astype(np.uint8)
    out = Image.fromarray(out)
    return out.filter(ImageFilter.GaussianBlur(0.35))          # match the painting's softness

def shadow_for(im, o):
    a = im.split()[3]
    sh = Image.new("RGBA", im.size, (40, 25, 15, 0))
    sh.putalpha(a.point(lambda v: int(v * o.get("shadow", 0.38))))
    pad = 16
    canvas = Image.new("RGBA", (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0, 0))
    canvas.alpha_composite(sh, (pad, pad))
    return canvas.filter(ImageFilter.GaussianBlur(5)), pad

scene = bg.copy()
manifest = []
for name, o in spec["objects"].items():
    im = prepare(name, o)
    x, y = o["x"] - im.width // 2, o["y"] - im.height   # anchor: bottom centre on the surface
    im = match_to_scene(im, (x, y, im.width, im.height), o.get("tint", 0.18))
    sh, pad = shadow_for(im, o)
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
