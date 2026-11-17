# Hidden-object art proof of concept (not part of the app)

A one-off test of whether painted hidden-object scenes can be made from generated art, with every findable object
as its own layer so it can vanish cleanly. No game engine; just the art and the layering.

**Open `out/review.html`.** It is a single self-contained file: click objects to find them, and use the toggles to see
where everything is or the background alone.

## How the scene is built
1. **Background:** `raw/background.png`, a cluttered alchemist's attic. flux-1.1-pro-ultra, 16:9, 2752×1536,
   seed 9101, prediction `mx4jza3mr1rmt0d1x568hepz84`. The prompt asks for even lighting and many nooks.
2. **Objects:** `raw/<name>.png`, 12 items, each generated alone on cream. flux-1.1-pro, 1:1, seeds 9201–9212,
   shared style suffix. They are cut out with `bria/remove-background`; the cut-outs are in `objects/<name>.png`.
3. **Compose:** `tools/compose.py` does the following for each object (the placement data is in `scene_spec.json`):
   - trims the faint halo and erases rows of painted ground;
   - scales the object and anchors it bottom-centre on a surface, with optional rotation;
   - tints it 18–28 % toward the surrounding colours, matches local brightness, desaturates it slightly and softens it a little;
   - adds a soft warm contact shadow as its own layer;
   - optionally adds an **occluder**: scene pixels drawn back on top below a cut line, so the toadstool sits in
     the fruit bowl and the egg in the basket.
   It writes `layers/` (object, shadow and occluder PNGs plus `scene.json` with positions; this is what an app would use)
   and `out/`: `scene_full.png`, `scene_some_found.png`, `scene_debug.png` and `closeups.png`.
4. `tools/build_review.py` builds `out/review.html`, with an alpha hit-test per object and a vanish animation.

Rebuild: `python3 tools/compose.py . && python3 tools/build_review.py .` (needs Pillow and numpy).

## Findings
- The style match is good: objects from the same style suffix sit well in the painting after tinting and a soft shadow.
- Bria cut-outs are clean. Painted ground under objects (grass, puddles, scroll shadow) has to be trimmed, and the
  prompts should say "floating, no ground".
- Placement is the manual part: picking surfaces and scale takes about 1 minute per object with the debug view. For
  many scenes, mark candidate spots once per background (a list of surface points with scale) and let the app choose
  objects and spots per play.
- Occluders work well for containers (basket, bowl). Hiding objects behind arbitrary shapes needs a hand-made mask
  per spot.
- Difficulty comes from scale (60–110 px on a 2752 px scene), tint strength and camouflage colours (the key on the
  patterned rug is the hardest). On iPhone this needs pinch-zoom.
- Cost for this test: 1 Ultra image + 12 pro images + 12 background removals.
