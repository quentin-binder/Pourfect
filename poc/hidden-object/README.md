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

## Scene 2: market stall (`market/`)
A second style test with the same pipeline and scripts: a busy medieval-fantasy market stall plus 8 objects.
**Open `market/out/review.html`.** Rebuild: `cd market && python3 ../tools/compose.py . && python3 ../tools/build_review.py .`

- Objects: brass scale and coin purse on the back shelves, lantern between bottles, red apple in the garlic basket
  and wool skein in the herb basket (both with occluders), carrot on a grain sack, hand bell on the yellow pot,
  glass marble on the paving.
- `compose.py` has a new per-object option `keepLargest` (keeps only the main connected blob; used to drop the loose
  coins under the purse). `scene_spec.json` may set `title` and `note` for the review page.
- Rejected generations are kept in `market/rejected/` (not committed).

## Art for scene generation
Every image of both scenes, recorded like `Art/README.md`. Images are not committed; regenerate from these.
All flux calls: `output_format: png`, `safety_tolerance: 2`; Ultra also `raw: false`. Cut-outs: `bria/remove-background`
(1024 px output, used as-is).

**{OBJ}** = `centred, whole object visible with generous margin, isolated on a plain flat solid pale cream background
with nothing else. Cozy hand-painted storybook illustration style, painterly brushwork, soft warm lighting from the
upper left, muted teal shadows and warm amber highlights.`
**{OBJ2}** (market) = `centred, whole object visible with generous margin, floating, isolated on a plain flat solid pale
cream background with nothing else. Cozy hand-painted storybook illustration style, painterly brushwork, soft warm
lighting from the upper left, muted teal shadows and warm amber highlights.`

### Attic (scene 1)
**Background** `raw/background.png` · flux-1.1-pro-ultra · 16:9 · 2752×1536 · seed 9101 · `mx4jza3mr1rmt0d1x568hepz84`
> Cozy hand-painted storybook illustration of a cluttered alchemist's attic, seen from the front, filling the whole wide canvas edge to edge. Crowded wooden shelves, stacks of old books, rolled maps, baskets, copper pots, dried herbs hanging from beams, glass jars and bottles, a big wooden chest, a round window with warm evening light, rugs, boxes and trinkets everywhere, rich layered clutter with many nooks, soft even lighting across the whole scene, no strong dark areas. Painterly brushwork, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no people, no animals, no letters, no logos.

**Objects** · flux-1.1-pro · 1:1. Prompt = `A single <subject>, ` + {OBJ} + ` <negatives>`.

| File | Seed | Subject | Negatives | Prediction |
|---|---|---|---|---|
| key | 9201 | ornate antique silver key | No text, no letters, no cast shadow, no logos. | `2fqff159adrmw0d1x56tqgkxm0` |
| hourglass | 9202 | small brass hourglass with blue sand | No text, no letters, no cast shadow, no logos. | `rz0db9ejasrmt0d1x56vy5cy5r` |
| owl | 9203 | small carved wooden owl figurine | No text, no letters, no cast shadow, no logos. | `58kgvbfvj9rmy0d1x56ry11nn4` |
| mushroom | 9204 | red toadstool mushroom with white spots | No text, no letters, no cast shadow, no grass, no logos. | `0dsw7xs3znrmy0d1x5789pd9ac` |
| crystal | 9205 | glowing violet amethyst crystal cluster | No text, no letters, no cast shadow, no logos. | `fn9zwr2dmdrmw0d1x57886x87c` |
| quill | 9206 | white feather quill pen, lying diagonally | No text, no letters, no cast shadow, no ink, no logos. | `6svfc2vqn9rmr0d1x579d98q6w` |
| watch | 9207 | golden pocket watch with a short chain, lid open | No text, no letters, no numbers, no cast shadow, no logos. | `a6jjcz509hrmy0d1x578hnrpa0` |
| potion | 9208 | small round glass potion bottle with glowing green liquid and a cork | No text, no letters, no label, no cast shadow, no logos. | `tbtvhpe90nrmy0d1x579yz2p4r` |
| horseshoe | 9209 | old iron horseshoe | No text, no letters, no cast shadow, no logos. | `f9fhnjzhf1rmy0d1x579xzst0r` |
| teacup | 9210 | porcelain teacup with a blue flower pattern on a small saucer | No text, no letters, no cast shadow, no logos. | `bqecze8sn1rmy0d1x57vtkd7zc` |
| scroll | 9211 | rolled parchment scroll tied with a red ribbon | No text, no letters, no writing, no cast shadow, no logos. | `bq5r4y49enrmy0d1x58tzpx3g0` |
| egg | 9212 | speckled teal dragon egg with golden swirl markings | No text, no letters, no cast shadow, no nest, no logos. | `gjrnwedm5drmw0d1x58vt786q0` |

Bria predictions for the attic, in run order (the per-object mapping was not recorded): `grcc3s5acnrmr0d1x57tvejw0g`,
`zq3rgerfz9rmw0d1x5884mnx7c`, `jstjcrhvp1rmy0d1x588gygrpc`, `4qdkh033mdrmy0d1x58bfwkpjw`, `gxztyxmbc9rmw0d1x58831p7fm`,
`tx0asxdp91rmy0d1x589f3cmy0`, `jjvnp1z1ksrmt0d1x588kxk9mr`, `jjvbanr961rmr0d1x58rc3z67w`, `rfy5tv1ktnrmy0d1x58vsvvyj4`,
`8d726kjz1nrmw0d1x58tmgm5pw`, `hsfatmpx69rmy0d1x58t75cw38`, `dydrdp87r5rmr0d1x59afjzpbr`.

### Market (scene 2)
**Background** `market/raw/background.png` · flux-1.1-pro-ultra · 16:9 · 2752×1536 · seed 9301 · `xmrvgng511rmt0d1x5g8ay8htc`
> Cozy hand-painted storybook illustration of a busy medieval fantasy market stall in a village market square, seen from the front, filling the whole wide canvas edge to edge. A big wooden stall under a faded striped fabric awning, stacked wooden crates of apples and pears, woven baskets of carrots, onions and cabbages, bundles of dried herbs and garlic hanging from the awning, folded bolts of colourful cloth and wool, rows of glass potion bottles and jars, copper pots, sacks of grain, barrels, hanging lanterns and blank wooden signboards, more stalls and timber-framed houses behind, rich layered clutter with many nooks, soft even daylight across the whole scene, no strong dark areas. Painterly brushwork, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no people, no animals, no letters, no logos, no writing on the signs.

- Rejected: seed 9302, `92sazz6f5srmw0d1x5g95w9aqm` (same prompt but "at golden late afternoon", "faded teal and cream
  striped fabric awning", "glowing hanging lanterns", "soft even warm lighting"). Closer palette to the attic, but
  pseudo-lettering on three signs.

**Objects** · flux-1.1-pro · 1:1. Prompt = `A single <subject>, ` + {OBJ2} + ` <negatives>`.

| File | Seed | Subject | Negatives | Prediction | Bria |
|---|---|---|---|---|---|
| scale | 9401 | small brass merchant's balance scale with two round pans hanging from chains | No text, no letters, no cast shadow, no ground, no table, no logos. | `8jer0mm2dhrmt0d1x5gswppqrr` | `987xm5fyddrmy0d1x5h9ky4r50` |
| purse | 9403 | small brown leather coin purse tied shut with a drawstring, plump with coins | No text, no letters, no symbols, no currency signs, no loose coins, no cast shadow, no ground, no logos. | `4k2ff7em3drmt0d1x5gv97k6nr` | `9n4vesvj6hrmw0d1x5ht81bc1g` |
| lantern | 9404 | small old iron and glass hand lantern with a ring handle and a softly glowing candle inside | No text, no letters, no cast shadow, no ground, no glow halo on the background, no logos. | `hxdjerqybdrmy0d1x5gr92jx0m` | `ys8rhvctksrmt0d1x5htssnev4` |
| wool | 9405 | twisted skein of soft teal blue wool yarn | No text, no letters, no label, no knitting needles, no cast shadow, no ground, no logos. | `145ptjh72nrmy0d1x5h8appxs8` | `18f1mzy2mxrmr0d1x5hvjrwpe4` |
| carrot | 9406 | fresh orange carrot with its green leafy top, lying diagonally | No text, no letters, no soil, no cast shadow, no ground, no logos. | `xc7tsk2hf5rmw0d1x5h98wagaw` | `c7v1p9fb6nrmr0d1x5hsftdj70` |
| bell | 9407 | small brass hand bell with a turned wooden handle | No text, no letters, no engraving, no cast shadow, no ground, no logos. | `9avghc3tcnrmy0d1x5hbpvf56c` | `jsebjr8pc1rmt0d1x5jbe7nzj0` |
| apple | 9412 | shiny red apple with a short stem and one green leaf | (after {OBJ2}: `clean empty background.` and "highlights on the apple only.") No text, no letters, no signature, no cast shadow, no paint splash, no colour blot, no ground, no logos. | `c6f73cxvb5rmt0d1x5j9kjkzhm` | `5cevnqs2bdrmt0d1x5js5pfzsr` |
| marble | 9418 | small clear glass marble with a thin twisted teal and amber ribbon swirl inside | (after {OBJ2}: `clean empty background.` and "highlights on the marble only.") No text, no letters, no signature, no cast shadow, no reflection, no paint splash, no ground, no logos. | `xk8kcp7325rmy0d1x5j95bpp9m` | `4pcqhma9zhrmr0d1x5jv5wgmnc` |

Rejected objects: apple seed 9402 `ctswhx5besrmr0d1x5gs0zb1c4` (bria `386cpea761rmt0d1x5htdcm1zw`; teal paint blot
fused to the apple, tiny signature mark; negatives were `No text, no letters, no cast shadow, no ground, no logos.`),
marble seed 9408 `j5sb1p52c5rmw0d1x5haddppnm` (bria `rmx2q4a141rmw0d1x5jakd8seg`; "round glass marble with a swirl of
teal and amber colour inside", teal shadow smear kept by bria, very loud colours).

Notes: "floating, no ground" helped (no ground rows to erase this time), but flux still adds painted splashes or
shadow smears as a style flourish (apple, marble, purse coins); bria keeps them when they touch the object. Check every
cut-out on a magenta background before placing it.
