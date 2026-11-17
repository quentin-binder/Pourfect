"""App export for one hidden-object scene (format "pourfect-hidden-v1").

Usage: python export.py <scene dir> <scene id> <out dir>   (needs Pillow + numpy)
Reads <scene>/library.json, <scene>/lib/<id>.png (library.py), <scene>/spots.json (spots.py), <scene>/raw/background.png.
Writes <out dir>/background.jpg (2752 px), background_1376.jpg, objects/<id>.png (long side <= 220 px, alpha,
untinted: the app tints per spot) and scene.json. All coordinates in scene.json are in background.jpg pixels;
multiply by 0.5 for background_1376.jpg.
"""
import json, sys
from pathlib import Path
from PIL import Image

OBJ_MAX = 220
JPEG_Q = 90

root, scene_id, out = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
lib = json.loads((root / "library.json").read_text())
spots = json.loads((root / "spots.json").read_text())["spots"]
(out / "objects").mkdir(parents=True, exist_ok=True)

bg = Image.open(root / "raw/background.png").convert("RGB")
W, H = bg.size
bg.save(out / "background.jpg", quality=JPEG_Q, optimize=True, progressive=True)
half = bg.resize((W // 2, H // 2), Image.LANCZOS)
half.save(out / "background_1376.jpg", quality=JPEG_Q, optimize=True, progressive=True)

objects = []
for o in lib["objects"]:
    im = Image.open(root / f"lib/{o['id']}.png").convert("RGBA")
    im.thumbnail((OBJ_MAX, OBJ_MAX), Image.LANCZOS)
    im.save(out / f"objects/{o['id']}.png", optimize=True)
    objects.append({"id": o["id"], "name": o["name"], "sizeClass": o["size"], "png": f"objects/{o['id']}.png",
                    "size": list(im.size)})

doc = {
    "format": "pourfect-hidden-v1",
    "scene": scene_id,
    "title": lib["title"],
    "background": {"size": [W, H], "images": [
        {"file": "background.jpg", "size": [W, H], "scale": 1.0},
        {"file": "background_1376.jpg", "size": list(half.size), "scale": half.width / W}]},
    "coordinates": "background pixels of background.jpg; spot x,y is the bottom-centre anchor of the object",
    "objects": objects,
    "spots": [{k: s[k] for k in ("id", "x", "y", "maxSize", "sizeClass", "surface", "occlusion") if k in s} for s in spots],
    "placement": {
        "note": "Rules used by the PoC's tools/layout.py to make the review pages; the app can copy them.",
        "classCap": {"small": 68, "medium": 112},
        "renderLongSide": "min(spot.maxSize, classCap[object.sizeClass]) * random(0.88, 1.0); if the object's aspect "
                          "ratio > 1.6, multiply by 1 + 0.25 * min(1, (aspect - 1.6) / 1.4), capped at 1.25 * spot.maxSize",
        "compatible": "object.sizeClass must be in spot.sizeClass",
        "minGap": "anchors of two chosen spots at least 0.6 * (maxSizeA + maxSizeB) apart",
        "order": "place medium objects first; draw back to front by spot y",
        "flip": "optional horizontal flip with probability 0.3",
        "anchor": "object image bottom-centre at (spot.x, spot.y)",
    },
    "render": {
        "note": "How the PoC blends an object into the painting (tools/hocommon.py). Colours are 0-255.",
        "tint": "mean colour of the background in the object's box grown by max(w, h) on every side; "
                "rgb = rgb * (1 - t) + mean * t with t = random(0.18, 0.26); then rgb *= 0.72 + 0.35 * luminance(mean)/255; "
                "then saturation *= 0.85 (toward the per-pixel grey); then Gaussian blur 0.35 px",
        "shadow": {"color": [40, 25, 15], "alpha": 0.38, "blur": 5, "offset": [5, 4],
                   "how": "object alpha * 0.38 as a dark silhouette, blurred, drawn under the object at +5, +4 px"},
        "occlusion": "for spots with 'occlusion': after drawing the object, draw the background again clipped to "
                     "occlusion.polygon, with its top edge feathered over occlusion.feather px (vertical box blur of the mask)",
        "hitTest": "object alpha > 60 within 6 px of the tap (PoC review page)",
    },
}
(out / "scene.json").write_text(json.dumps(doc, indent=1))
total = sum(f.stat().st_size for f in out.rglob("*") if f.is_file())
print(f"export {scene_id}: {len(objects)} objects, {len(spots)} spots, {total / 1e6:.2f} MB")
