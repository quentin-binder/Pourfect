"""Random hidden-object layout: picks N library objects and N suitable spots (seeded) and composes them,
the way the app will do it per play. Used to check that random placement looks natural.

Usage: python layout.py <scene dir> <seed> [count=12]   (needs Pillow + numpy)
Reads <scene>/library.json, <scene>/lib/<id>.png (from library.py), <scene>/spots.json (from spots.py),
<scene>/raw/background.png. Writes <scene>/random/s<seed>/ (layer PNGs + scene.json, same format as compose.py)
and <scene>/out/random_s<seed>.png; then build_review.py turns it into <scene>/out/review_random_s<seed>.html.

Placement rules (the app should copy these; they are also written into export scene.json "placement"):
- an object may use a spot only if its size class is in the spot's sizeClass list;
- rendered long side = min(spot.maxSize, CLASS_CAP[size]) x random(0.88..1.0); thin objects
  (aspect > 1.6) get up to +25 %, never above 1.25 x maxSize;
- chosen spots keep their anchors at least 0.6 x (sizeA + sizeB) apart;
- medium objects are placed first (fewer spots accept them);
- tint 0.18-0.26 toward the local colours, soft contact shadow, container spots get their occluder.
"""
import json, sys, random, math
from pathlib import Path
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hocommon import match_to_scene, shadow_for, occluder_from_polygon

CLASS_CAP = {"small": 68, "medium": 112}
MIN_GAP = 0.6


def render_size(obj_im, size_class, spot, rng):
    long_side = min(spot["maxSize"], CLASS_CAP[size_class]) * rng.uniform(0.88, 1.0)
    aspect = max(obj_im.size) / min(obj_im.size)
    if aspect > 1.6:
        long_side = min(long_side * (1 + 0.25 * min(1.0, (aspect - 1.6) / 1.4)), spot["maxSize"] * 1.25)
    return max(8, round(long_side))


def pick(library, spots, count, rng):
    objs = rng.sample(library, count)
    objs.sort(key=lambda o: o["size"] != "medium")          # medium first
    free = spots[:]; rng.shuffle(free)
    chosen = []
    for o in objs:
        for s in free:
            if o["size"] not in s["sizeClass"]: continue
            if all(math.hypot(s["x"] - c[1]["x"], s["y"] - c[1]["y"]) >= MIN_GAP * (s["maxSize"] + c[1]["maxSize"]) for c in chosen):
                chosen.append((o, s)); free.remove(s); break
        else:
            raise SystemExit(f"no free spot for {o['id']} ({o['size']})")
    return chosen


def main():
    root, seed = Path(sys.argv[1]), int(sys.argv[2])
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    lib = json.loads((root / "library.json").read_text())
    spots = json.loads((root / "spots.json").read_text())["spots"]
    bg = Image.open(root / "raw/background.png").convert("RGBA")
    rng = random.Random(seed)
    chosen = pick(lib["objects"], spots, count, rng)

    rel = Path("random") / f"s{seed}"
    (root / rel).mkdir(parents=True, exist_ok=True)
    scene = bg.copy(); manifest = []
    for o, s in sorted(chosen, key=lambda c: c[1]["y"]):      # back to front
        im = Image.open(root / f"lib/{o['id']}.png").convert("RGBA")
        L = render_size(im, o["size"], s, rng)
        k = L / max(im.size)
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
        if rng.random() < 0.3 and o["id"] not in lib.get("noFlip", []):
            im = im.transpose(Image.FLIP_LEFT_RIGHT)          # light comes from the upper left; a mild flip is fine
        x, y = s["x"] - im.width // 2, s["y"] - im.height
        im = match_to_scene(im, bg, (x, y, im.width, im.height), rng.uniform(0.18, 0.26))
        sh, pad = shadow_for(im, 0.38)
        sx, sy = x - pad + 5, y - pad + 4
        name = o["id"]
        layer = {"name": name, "label": o["name"], "spot": s["id"], "thumb": f"lib/{name}.png",
                 "object": {"file": str(rel / f"{name}.png"), "x": x, "y": y, "w": im.width, "h": im.height},
                 "shadow": {"file": str(rel / f"{name}_shadow.png"), "x": sx, "y": sy}}
        im.save(root / rel / f"{name}.png"); sh.save(root / rel / f"{name}_shadow.png")
        scene.alpha_composite(sh, (sx, sy)); scene.alpha_composite(im, (x, y))
        if "occlusion" in s:
            patch, (px, py) = occluder_from_polygon(bg, s["occlusion"]["polygon"], s["occlusion"]["feather"])
            patch.save(root / rel / f"{name}_occluder.png")
            scene.alpha_composite(patch, (px, py))
            layer["occluder"] = {"file": str(rel / f"{name}_occluder.png"), "x": px, "y": py}
        manifest.append(layer)

    title = f"{lib['title']} — random layout (seed {seed})"
    note = (f"Random layout test: {count} objects picked at random from the {len(lib['objects'])}-object library and put on "
            f"random suitable spots from the {len(spots)}-spot map (seed {seed}), the way the app will do it per play. "
            "Each object is tinted toward its surroundings, gets a soft contact shadow, and in container spots is partly "
            "hidden behind scene pixels drawn back on top. Click an object to find it; 'show where things are' outlines them.")
    (root / rel / "scene.json").write_text(json.dumps({"background": "raw/background.png", "size": list(bg.size), "seed": seed,
                                                       "title": title, "note": note, "objects": manifest}, indent=1))
    (root / "out").mkdir(exist_ok=True)
    scene.convert("RGB").save(root / f"out/random_s{seed}.png")
    tiles = []                                                 # close-ups of each placement to judge blending
    for L in manifest:
        b = L["object"]; m = 70
        c = scene.crop((b["x"] - m, b["y"] - m, b["x"] + b["w"] + m, b["y"] + b["h"] + m)).convert("RGB")
        c.thumbnail((300, 300)); tiles.append(c)
    sheet = Image.new("RGB", (4 * 310, math.ceil(len(tiles) / 4) * 310), (30, 30, 30))
    for i, t in enumerate(tiles): sheet.paste(t, ((i % 4) * 310 + 5, (i // 4) * 310 + 5))
    sheet.save(root / f"out/random_s{seed}_closeups.png")
    print("layout", lib["scene"], "seed", seed, ":", ", ".join(f"{o['id']}@{s['id']}" for o, s in chosen))


if __name__ == "__main__":
    main()
