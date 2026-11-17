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

## Version 1 art set: 3 scenes for random play
The app will pick a random subset of objects and spots per play, so each scene now has an **object library** (40
findable objects) and a **spot map** (about 60 candidate places), instead of a fixed placement.

| Scene | Folder | Objects | Spots (with occluder / take medium) | Review page (random layout) |
|---|---|---|---|---|
| Alchemist's attic | `.` | 40 (12 PoC + 28 new) | 65 (10 / 18) | `out/review_random_s1.html`, `out/review_random_s2.html` |
| Market stall | `market/` | 40 (8 PoC + 32 new) | 61 (15 / 14) | `market/out/review_random_s1.html` |
| Dragon's hoard (new) | `hoard/` | 40 new | 59 (6 / 25) | `hoard/out/review_random_s1.html` |

**App export:** `export/<scene>/` holds `background.jpg` (2752×1536, JPEG q90), `background_1376.jpg`, `objects/<id>.png`
(alpha, long side ≤ 220 px, untinted) and `scene.json` (format `pourfect-hidden-v1`: scene id, title, background sizes,
objects with id/name/size class/png/natural size, spots with id/x/y/maxSize/sizeClass/surface/occlusion polygon, and the
placement and blending rules the PoC uses). Only the `scene.json` files are committed; the images are regenerated with
the commands below (sizes: attic 3.4 MB, market 3.4 MB, hoard 3.7 MB).

### Pipeline (tools/)
- `library.py <scene>`: `library.json` (id, display name, size class, source cut-out, cleanup options) → `lib/<id>.png`
  (cleaned, trimmed) and `out/library_sheet.png` (all objects on magenta, to check for halos and smears).
  Cleanup options: `alphaCut`, `eraseRowsFull` (the PoC's eraseRows on the untrimmed cut-out), `eraseRows`, `keepLargest`
  (largest connected blob), `eraseRect`, `dropPale` (pale unsaturated pixels in the bottom band: painted ground smears).
- `spots.py <scene> spots/<scene>.txt`: hand-written spot list → `spots.json` and `out/spots_debug.jpg`
  (blue box = small objects only, green = small or medium, orange line = occlusion cut). Spots were placed by reading the
  background on a 100 px grid; x, y is the bottom-centre anchor on the surface.
- `layout.py <scene> <seed> [12]`: picks 12 random objects and compatible, well-spaced spots (seeded), tints each object
  toward its surroundings, adds the soft contact shadow and, for container spots, the occluder; writes
  `random/s<seed>/` (layers + `scene.json` in the compose.py format), `out/random_s<seed>.png` and `_closeups.png`.
- `build_review.py <scene> random/s<seed>/scene.json out/review_random_s<seed>.html`: the click-to-find review page.
- `export.py <scene> <id> export/<id>`: the app export.
- `hocommon.py`: shared cleanup/tint/shadow/occluder code; `compose.py` (hand-placed PoC scenes) now uses it and gives
  byte-identical layers.

Rebuild everything (Pillow + numpy):
```
python3 tools/library.py . && python3 tools/spots.py . spots/attic.txt
python3 tools/layout.py . 1 && python3 tools/build_review.py . random/s1/scene.json out/review_random_s1.html
python3 tools/layout.py . 2 && python3 tools/build_review.py . random/s2/scene.json out/review_random_s2.html
python3 tools/export.py . attic export/attic
cd market && python3 ../tools/library.py . && python3 ../tools/spots.py . ../spots/market.txt && python3 ../tools/layout.py . 1 \
  && python3 ../tools/build_review.py . random/s1/scene.json out/review_random_s1.html && python3 ../tools/export.py . market ../export/market
cd ../hoard && python3 ../tools/library.py . && python3 ../tools/spots.py . ../spots/hoard.txt && python3 ../tools/layout.py . 1 \
  && python3 ../tools/build_review.py . random/s1/scene.json out/review_random_s1.html && python3 ../tools/export.py . hoard ../export/hoard
```
Generated images (`raw/`, `objects/`, `lib/`, `out/`, `random/`, `export/*/` images, `*/rejected/`) are not committed
(`.gitignore`); regenerate them from the log below.

### Findings (v1)
- Random placement reads as natural in most cases: objects sit on shelves, piles, rugs and in baskets with a shadow and
  local tint. Weak cases: thin diagonal objects (quill, paintbrush, wand) anchored bottom-centre can look propped up
  rather than lying; very saturated objects (gems, die, book) still pop a little against the muted paintings.
- Spot coverage follows the paintings: the market's awning and the hoard's cave ceiling have no plausible surfaces, so
  their top quarter has only a few spots (market beam, hoard ledges). The attic is evenly covered.
- Hoard: gold objects on gold coin piles are hard to find (good for late levels, frustrating early). The app may want
  to prefer non-gold objects for easy rounds.
- The "painterly, inked outline, soft brushwork" suffix gave a consistent, slightly crisper storybook look than the PoC
  objects; it did not remove the occasional digital/sticker feel of gems, gold bar and helmet.
- Flux still adds painted ground smears and shadow blots; most are removed by `keepLargest`, `dropPale` or a small
  `eraseRect`. Two needed a regeneration for fused smears (jewel box, cheese); see the rejected list below for the rest.
- Text remains the main failure: the compass got N/E/S/W letters twice (replaced by a starfish), the broom got a
  "Witch's broom" caption, and a key bit looked like an "E". The PoC's pocket watch (numbers on the dial) and silver key
  (E-shaped bit) are kept as approved, but are the same kind of problem.

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

### Version 1 (all three scenes)
Every generation and cut-out of v1 is also in `library/gen_log.tsv` (scene, id, kind, seed, prediction, output URL; the
URLs expire) and the object list with seeds and subjects in `library/new_objects.tsv`.

**Dragon's hoard background** `hoard/raw/background.png` · flux-1.1-pro-ultra · 16:9 · 2752×1536 · seed 9503 · `mpshf1r4rsrmr0d1x5ptenvv10`
> Cozy hand-painted storybook illustration of a dragon's treasure hoard deep inside a mountain cave, seen from the front, filling the whole wide canvas edge to edge. Heaped mounds of gold coins, open treasure chests, golden goblets and plates, crowns, jewelled swords and round shields, scattered gems, ancient urns and vases, carved stone ledges and alcoves in the cave walls crowded with trinkets, broken stone pillars, a few warm hanging lanterns, the scaled tip of a sleeping dragon's tail curling along the lower right edge, rich layered clutter with many nooks, soft even warm lighting across the whole scene, no strong dark areas. Painterly brushwork, muted teal shadows and warm amber and gold highlights, magical floating dust motes. No text, no people, no dragon head, no letters, no runes, no inscriptions, no logos.

- Rejected: seed 9501 `pn7k7pxfr1rmy0d1x5p8r5vqgc` (best composition, but a fake signature "© the by calisme" in the
  lower right corner); seed 9502 `59gjv9erxxrmw0d1x5p8t4bt9c` (a full dragon head on the right, which the brief excluded).
  Same prompt for all three. 9503 is a little flatter and more poster-like than the attic, with a large empty rock
  ceiling; it has no text and only the tail.

**Objects** · flux-1.1-pro · 1:1 · `output_format: png`, `safety_tolerance: 2`. Prompt = `A single <subject>, ` + {OBJ3} + ` <negatives>`.
Cut-outs: `bria/remove-background` on the flux output URL.

**{OBJ3}** = `centred, whole object visible with generous margin, floating, isolated on a plain flat solid pale cream
background with nothing else, clean empty background. Cozy hand-painted storybook illustration style, painterly, inked
outline, soft brushwork, soft warm lighting from the upper left, muted teal shadows and warm amber highlights.`
Standard negatives = `No text, no letters, no numbers, no signature, no cast shadow, no paint splash, no ground, no logos.`
Exceptions are noted in the subject column. Seeds: attic 96xx, market 97xx, hoard 98xx.

#### attic — new objects

| id | Name | Size | Seed | Subject | Prediction | Bria |
|---|---|---|---|---|---|---|
| candle | Candle | m | 9601 | short white candle in a small brass candle holder with a ring handle, unlit | `609pntys39rmw0d1x5qa4stgwc` | `rnxgvp00xdrmy0d1x5qvwsca44` |
| magnifier | Magnifying glass | m | 9602 | round magnifying glass with a brass rim and a turned wooden handle, lying diagonally | `wa5kcjc9r1rmt0d1x5qr3frvk0` | `kpka7z9a29rmr0d1x6183njkt0` |
| starfish | Starfish | s | 9643 | dried orange starfish with five arms (standard negatives with `no sand` before `no logos`) | `qkvgy7bv4hrmy0d1x689mfg9b4` | `3aw0gyf90drmw0d1x68b7r1h6r` |
| spectacles | Spectacles | s | 9604 | pair of round wire-rimmed reading spectacles, folded | `3bgy48pvr9rmt0d1x5qvrrsce0` | `2ctcnm39hsrmw0d1x61r2d3358` |
| inkwell | Inkwell | s | 9605 | small square glass inkwell full of dark blue ink with a brass lid | `6fh7t906s5rmy0d1x5rbbcwj6c` | `4d3zzczkwdrmy0d1x60verj3kr` |
| mortar | Mortar and pestle | m | 9606 | small grey stone mortar bowl with a wooden pestle leaning in it | `2bvdresf7hrmw0d1x5r8pejz8m` | `f4fj3cbrksrmt0d1x61bb47jm4` |
| book | Red book | m | 9607 | small closed red leather-bound book with brass corners, blank cover | `c1q1xsy8j1rmt0d1x5rb70em3c` | `qnexb8b2d1rmy0d1x608q74k1w` |
| frog | Frog figurine | s | 9608 | small green ceramic frog figurine sitting | `9afcxa8bh1rmr0d1x5rvv3zfp8` | `nt251mkd19rmw0d1x60rbxqqkw` |
| flask | Blue flask | m | 9609 | conical glass laboratory flask with glowing blue liquid and a cork | `yp0dvh1pb1rmr0d1x5rvpdkagr` | `ct08h7tx6drmr0d1x60v2244n4` |
| telescope | Telescope | m | 9610 | small extended brass telescope, lying diagonally | `r9d6v4tz5nrmy0d1x5rsdwfeb4` | `01qtx8kr0srmr0d1x61sj45mb4` |
| globe | Desk globe | m | 9611 | small antique desk globe in a wooden stand, teal seas and beige land, no writing | `hcvyx0w7e9rmy0d1x5rr64xsp4` | `nj8br3kwkxrmt0d1x60v7z8284` |
| die | Bone die | s | 9612 | single ivory six-sided die with dark dot pips | `1ras9jxga5rmw0d1x5rskrpzyw` | `kg5t831zb1rmw0d1x60te5bqs0` |
| ring | Ruby ring | s | 9613 | gold ring with a single large red ruby | `htk793te35rmw0d1x5s97240zw` | `49nza5hnvhrmt0d1x61r81zkm8` |
| pinecone | Pinecone | s | 9614 | brown pinecone | `8mfn4kkp91rmy0d1x5s84z0jxg` | `1xy6ftn58nrmy0d1x61b3wrvnr` |
| acorn | Acorn | s | 9615 | acorn with its cap and a tiny stem | `0hxr1y446srmt0d1x5sb366pfw` | `epqkwstj1hrmt0d1x60bn21h6r` |
| shell | Seashell | s | 9616 | spiral seashell in cream and coral colours | `pj7341ncf5rmw0d1x5sadfr66m` | `fep5catqrxrmy0d1x61vmqv7yw` |
| lavender | Lavender bundle | m | 9617 | small bundle of dried purple lavender tied with twine | `nykvjeeqpxrmw0d1x5s9v4emwg` | `scwc5krtkdrmt0d1x61azgbjpw` |
| lamp | Oil lamp | m | 9618 | small brass genie oil lamp with a curved spout | `rasghzvdmnrmw0d1x5ss6v9y7r` | `401vyv04m5rmr0d1x61bh3pt3c` |
| scissors | Scissors | s | 9629 | pair of old black iron tailor's shears, closed | `1p7js64sadrmr0d1x5tvbkb4cm` | `2vgf0ya4tdrmt0d1x61saa30rc` |
| paintbrush | Paintbrush | m | 9620 | wooden artist paintbrush with a red-tipped bristle head, lying diagonally | `kg50etp2w5rmw0d1x5svqw4ykr` | `f2gkef4pf9rmw0d1x6189ta97m` |
| firefly_jar | Firefly jar | m | 9621 | small corked glass jar with tiny glowing yellow fireflies inside | `00fjfvfdrsrmr0d1x5sr815rmw` | `cb8m51ae7xrmy0d1x60vwj46kr` |
| chess_knight | Chess knight | s | 9622 | carved black wooden chess knight piece (horse head) | `dy32w18p0nrmt0d1x5t9qdebxr` | `dyz59r4p9nrmr0d1x60bk8r3j4` |
| butterfly | Butterfly | s | 9623 | blue morpho butterfly with open wings, seen from above | `vzxhb89y09rmy0d1x5tb5rra6m` | `ghkx11c53srmy0d1x609m1shwc` |
| pumpkin | Pumpkin | m | 9624 | small orange pumpkin with a curly stem | `z3y8rjb5p5rmw0d1x5t9qnxd64` | `4210qsdkm5rmr0d1x619wc90gm` |
| broom | Broom | m | 9641 | small witch's broom with a twig brush and a crooked wooden handle, lying diagonally (`No text, no letters, no words, no caption, no label, no numbers, no signature, no cast shadow, no paint splash, no ground, no logos.`) | `ntt6q0jnq5rmw0d1x5zr1h755r` | `7m101mvnvxrmw0d1x60a88y17r` |
| wand | Magic wand | m | 9626 | slim dark wooden magic wand with a small golden star tip, lying diagonally | `dfg1jd0xx5rmr0d1x5tr0x13x8` | `dhw967473hrmt0d1x61s6s0hz0` |
| mirror | Hand mirror | m | 9627 | oval silver hand mirror with an ornate handle | `s99sf228exrmy0d1x5ts5jtz0g` | `nvbcfvt16hrmy0d1x6185qx34r` |
| padlock | Padlock | s | 9628 | old black iron padlock with a curved shackle | `104x373gfhrmw0d1x5tvfnes5g` | `k63errw85drmr0d1x61a992thr` |

#### market — new objects

| id | Name | Size | Seed | Subject | Prediction | Bria |
|---|---|---|---|---|---|---|
| pear | Pear | s | 9701 | ripe green-yellow pear with a stem | `cphxfms5j5rmw0d1x5v99a550m` | `50kdyqf865rmr0d1x65ans4wkw` |
| cheese | Cheese wedge | s | 9742 | wedge of yellow cheese with holes (`No text, no letters, no numbers, no signature, no cast shadow, no shadow under the object, no paint splash, no colour wash, no plate, no ground, no logos.` (it painted a plate anyway; kept)) | `xgxs02yw75rmy0d1x68971cdjc` | `7xbv8gs8dnrmr0d1x68v818kmw` |
| bread | Bread loaf | m | 9703 | round crusty brown bread loaf with scored top | `bcg97kvt2srmy0d1x5v9ry8pvr` | `skdr2sneysrmr0d1x64adr632m` |
| fish | Fish | m | 9704 | silver-blue fresh fish lying sideways | `7qmjpkx2b5rmy0d1x5vaasexnm` | `vgy3mtk0dhrmr0d1x64v1bnec0` |
| eggplant | Eggplant | m | 9705 | glossy purple eggplant with a green cap, lying diagonally | `h7h2rvdevdrmw0d1x5v9esqf7w` | `myqkxdaj35rmt0d1x64tz1mye0` |
| lemon | Lemon | s | 9706 | bright yellow lemon with a small green leaf | `rnj0e4dwb1rmr0d1x5v9d06jsc` | `t4ktcy57chrmr0d1x659z1kq7g` |
| grapes | Grapes | m | 9707 | bunch of purple grapes with a vine leaf | `phbxhf16yxrmt0d1x5vtyw9a1m` | `vgtnsxf7rxrmt0d1x64r69d8p0` |
| cherries | Cherries | s | 9708 | pair of red cherries joined at the stems | `wcnkvpsm99rmy0d1x5vva7drx0` | `mx5z2tscasrmt0d1x64srjen98` |
| strawberry | Strawberry | s | 9709 | big red strawberry with a green top | `amd43wa1nxrmt0d1x5vr8s9ftw` | `zzxcn356dnrmr0d1x66as2j78m` |
| melon_slice | Melon slice | s | 9710 | slice of watermelon, red flesh with black seeds and green rind | `mc76rwac8nrmt0d1x5vts397zg` | `1cnbfz66txrmw0d1x65aacxa8c` |
| corn | Corn cob | m | 9711 | yellow ear of corn with peeled-back green husk, lying diagonally | `tq2a6mtrysrmt0d1x5vvbpre5r` | `y4jdd2j12drmy0d1x64tye883c` |
| pepper | Red pepper | s | 9712 | shiny red bell pepper with a green stem | `t8brrkb5vnrmt0d1x5vv6n5nnw` | `9pxtb0fqcsrmr0d1x65bja7yew` |
| radish | Radish bunch | m | 9713 | small bunch of three pink radishes with green leaves | `tfaxsypk65rmw0d1x5vs0k6r10` | `1y40x6bfp5rmr0d1x65sbgvm74` |
| honey | Honey pot | m | 9714 | small round clay honey pot with a wooden honey dipper, honey dripping on the dipper | `jfz546q065rmw0d1x5vvw7v02m` | `jmrms1109srmy0d1x65bdf12tg` |
| jug | Clay jug | m | 9715 | small terracotta clay jug with one handle | `zn106zqb29rmr0d1x5vrm9cfhc` | `wm65sxhfgnrmw0d1x65adkx85c` |
| hen_egg | Brown egg | s | 9716 | single brown hen's egg | `mrvj167pc5rmy0d1x5vs14sxrg` | `sxbr84rjhnrmw0d1x65aa939vc` |
| peacock_feather | Peacock feather | m | 9717 | peacock feather with an iridescent eye, lying diagonally | `w2zw5k02jhrmy0d1x5w99hdftm` | `6jwnat6nt5rmw0d1x65beacv6c` |
| straw_hat | Straw hat | m | 9718 | woven straw sun hat with a red ribbon band | `te0406gdx5rmt0d1x5w839a198` | `0kjc0z1xxsrmw0d1x66a3cnvpm` |
| boot | Leather boot | m | 9719 | single old brown leather boot | `hmayaqkqdxrmt0d1x5wb3yhemr` | `9wfvz2wtb1rmt0d1x649rgm0dr` |
| spoon | Wooden spoon | m | 9720 | carved wooden spoon, lying diagonally | `a3ggkhm50nrmy0d1x5w92ty8e4` | `tzktnbsb7xrmr0d1x669c4m7tw` |
| ladle | Copper ladle | m | 9741 | copper soup ladle with a deep round bowl and a long handle ending in a hook, lying diagonally | `sm52ea32anrmw0d1x5zrmq3wq0` | `pf3hbj9zgdrmy0d1x658c39jv4` |
| teapot | Copper teapot | m | 9722 | small copper teapot with a curved spout | `ea0cet4twsrmt0d1x5wb07esvg` | `x9g96b6qkhrmw0d1x66a2kp62c` |
| spool | Thread spool | s | 9723 | wooden spool of red thread | `j1071rn5rnrmt0d1x5wbc19mmr` | `95mc1mgsd5rmw0d1x66a4165ag` |
| pretzel | Pretzel | s | 9724 | golden brown baked pretzel with salt | `6057eb5gj1rmy0d1x5wahfmncm` | `fyeatk2ykhrmy0d1x65t0xm1nr` |
| toy_horse | Toy horse | m | 9725 | small painted wooden toy horse on wheels | `79hak2gxg9rmt0d1x5wv67q7sm` | `wd34saq7a1rmr0d1x66bjv13dm` |
| sunflower | Sunflower | m | 9726 | single yellow sunflower with a short stem and one leaf | `p0ez9nhah5rmw0d1x5wsqc1k88` | `2d711mdnyhrmt0d1x669jcyc6w` |
| rose | Rose | m | 9727 | single red rose with a green stem, lying diagonally | `2wayd1hn2xrmr0d1x5ws211sym` | `7dmqjj41z5rmr0d1x65swgg434` |
| tankard | Tankard | m | 9728 | wooden beer tankard with metal bands and a handle | `vxsqyshzznrmr0d1x5wvzfgpm4` | `7nwd9f64y5rmr0d1x669yj6pk0` |
| wine_bottle | Green bottle | m | 9729 | dark green glass wine bottle with a cork, no label | `9sjeqktcqhrmw0d1x5wrs6hxag` | `hcggvt7qenrmt0d1x669yktj4m` |
| hammer | Hammer | m | 9730 | small wooden-handled iron hammer, lying diagonally | `ffr7s9tq7hrmy0d1x5wrvqd478` | `smwxjr7xpsrmr0d1x64r2mgg7c` |
| lute | Lute | m | 9731 | small wooden lute with a round body, lying diagonally | `qq061263qsrmy0d1x5wr524sh8` | `98f02knptnrmr0d1x65843wrem` |
| glove | Leather glove | s | 9732 | single brown leather glove | `6bab07phmsrmy0d1x5wt34mrx8` | `vpanp53gjxrmy0d1x64rh7fjjr` |

#### hoard — new objects

| id | Name | Size | Seed | Subject | Prediction | Bria |
|---|---|---|---|---|---|---|
| goblet | Golden goblet | m | 9801 | golden goblet studded with small red gems | `bsc6x5ew9hrmt0d1x5wvqk8qd4` | `7b66xfmqrxrmt0d1x62r6mz7kr` |
| crown | Crown | m | 9802 | golden royal crown with red and blue jewels | `f8h838q8ssrmr0d1x5wtc1n138` | `4zxzmjxz0xrmy0d1x628yssj44` |
| ruby | Ruby | s | 9803 | large faceted red ruby gemstone | `kw2a08fkznrmw0d1x5wrcy3tf8` | `x7z84970hxrmt0d1x63t3sh8e8` |
| emerald | Emerald | s | 9804 | large emerald-cut green emerald gemstone | `6fsg8500tnrmt0d1x5x8jen60m` | `hj0hh4vexxrmw0d1x62rr0qe1c` |
| sapphire | Sapphire | s | 9805 | large round faceted blue sapphire gemstone | `njj6k9kc4xrmt0d1x5x9p5ssyc` | `rdp7pzaz8srmt0d1x64adbb7mg` |
| coin_pouch | Coin pouch | s | 9806 | small red velvet pouch tied with gold cord, bulging with coins, coins hidden inside (standard negatives with `no loose coins` before `no logos`) | `rsgf753shdrmy0d1x5xaeh6j78` | `yxpe9adeedrmy0d1x628swvzt8` |
| dragon_scale | Dragon scale | s | 9807 | single large shiny teal dragon scale, shield shaped | `3b8hnbw4hsrmr0d1x5x9jcgp2r` | `w7edwm7v65rmy0d1x62aamg5mc` |
| rune_stone | Rune stone | s | 9808 | smooth grey river stone with a glowing blue carved spiral symbol | `zkmmp1wj81rmt0d1x5x95ky130` | `1xkrpazh4srmr0d1x63t4w8xhw` |
| dagger | Jewelled dagger | m | 9809 | jewelled dagger with a golden hilt and a short silver blade, lying diagonally | `70x638mxrhrmr0d1x5xbkkpt7w` | `g9ggr1ewg9rmr0d1x629r12vnr` |
| dragon_egg | Red dragon egg | s | 9810 | scaly crimson red dragon egg (standard negatives with `no nest` before `no logos`) | `f15mtsn8g1rmy0d1x5x8kmb48w` | `1dtbtzfbb1rmy0d1x62bf0f330` |
| tiara | Tiara | s | 9811 | delicate silver tiara with pearls and a blue gem | `8rxv1h0qr5rmt0d1x5xvvyrm28` | `p8w5kjktynrmw0d1x648t7r7cc` |
| pearl_necklace | Pearl necklace | m | 9812 | white pearl necklace loosely coiled | `y617563b2hrmr0d1x5xsmxps1g` | `defd4dmr61rmw0d1x63vhpt1q0` |
| amulet | Amulet | s | 9813 | golden amulet pendant with a green gem on a short chain | `kzw73nkrg9rmt0d1x5xv931v8w` | `vyvkf8za2hrmr0d1x61thf2j00` |
| round_shield | Round shield | m | 9814 | small round wooden shield with a blue painted rim and an iron boss | `67dxsfp5jhrmy0d1x5xs175qbw` | `dkf60y61xdrmw0d1x63t661yfc` |
| helmet | Knight's helmet | m | 9815 | silver knight's helmet with a red plume | `r4tk4kpjp1rmt0d1x5xrxzw9fw` | `1fwqqnbpkhrmt0d1x63ae91ztg` |
| gold_plate | Golden plate | m | 9816 | ornate round golden plate with an embossed rim, standing upright | `dn4ba8f2g9rmy0d1x5xvfpsz0r` | `zms4mr5vy5rmr0d1x62t9rj5p4` |
| jewel_box | Jewel box | m | 9845 | small open purple velvet jewel box with gold trim (`No text, no letters, no numbers, no signature, no cast shadow, no shadow under the object, no paint splash, no colour wash, no ground, no logos.`) | `x4hp8beh99rmy0d1x68bxxg2f4` | `wwwtbs8p51rmw0d1x68rw92kxr` |
| scepter | Scepter | m | 9818 | golden royal scepter with a purple gem on top, lying diagonally | `rdy95atgbhrmr0d1x5yash2dfm` | `qn22pvkdv9rmy0d1x64azjyy4g` |
| royal_orb | Royal orb | s | 9819 | golden royal orb with a small cross on top and a band of jewels | `xar17ejyc5rmr0d1x5y9mzwczg` | `c19avmehtxrmw0d1x63vm8k168` |
| gold_bar | Gold bar | s | 9820 | single shiny gold ingot bar, blank, no stamp | `1k7zbhkchdrmr0d1x5yam7j1a0` | `x8cyqhd74hrmw0d1x62r318qd8` |
| oyster_pearl | Oyster pearl | s | 9821 | open oyster shell holding one big white pearl | `f3q3gbvqynrmy0d1x5y9npdax0` | `75ehyrhdshrmt0d1x63sb2y0g8` |
| harp | Golden harp | m | 9822 | small golden harp with strings | `hjq3hbc3esrmw0d1x5y9qzjsem` | `q7m7rvv52drmr0d1x63808qvz0` |
| drinking_horn | Drinking horn | m | 9823 | ivory drinking horn with silver bands | `jwkp95z8r9rmt0d1x5ya3ayeq4` | `9yd99dawcxrmt0d1x62smq3ke0` |
| bracelet | Bracelet | s | 9824 | golden bangle bracelet set with green gems | `v1c0vhzq35rmt0d1x5yact3vkm` | `bg1zbj0yw1rmt0d1x62a3w0bjw` |
| brooch | Brooch | s | 9825 | ornate silver brooch with a large oval purple amethyst | `c5p7da0791rmt0d1x5ytjyf600` | `d34d2ehkg1rmt0d1x629ewrsk4` |
| candelabra | Candelabra | m | 9826 | small silver three-armed candelabra with three unlit white candles | `3vv1ewrjrnrmr0d1x5yvaqhsqg` | `fy28dft6c1rmt0d1x62bk61kqw` |
| blue_vase | Blue vase | m | 9827 | small blue and white porcelain vase with a flower pattern | `mba2bary21rmr0d1x5yvvr4ctg` | `0zvn72084xrmw0d1x62861eyvm` |
| mini_chest | Little chest | s | 9844 | tiny closed wooden treasure chest with iron bands and a brass lock plate (standard negatives with `no coins` before `no logos`) | `qgsjw5qe7srmw0d1x5zr6ccf7g` | `0pvvqkgtknrmt0d1x63s62v23r` |
| golden_mask | Golden mask | m | 9829 | ornate golden masquerade mask with eye holes | `cvwce84khsrmr0d1x5yrre9m9w` | `4hmrabajshrmy0d1x63anb9t1c` |
| jade_dragon | Jade dragon | m | 9830 | small carved green jade dragon statuette, coiled | `js5nh0cycnrmr0d1x5ytv51ye8` | `x6cpatpxfxrmy0d1x63a201k9g` |
| golden_apple | Golden apple | s | 9831 | shiny golden apple with a golden leaf | `g1kvt5d979rmt0d1x5yt2rjcaw` | `79ryn3s32xrmt0d1x63bqkzrz0` |
| crystal_ball | Crystal ball | s | 9832 | clear crystal ball with a faint violet mist inside on a small bronze stand | `235q645n1hrmr0d1x5ysrfq2k4` | `35r2hapcshrmw0d1x62aag1fpg` |
| phoenix_feather | Phoenix feather | m | 9833 | fiery red and orange phoenix feather, lying diagonally | `44vj0y8jb1rmr0d1x5zbyc5x0c` | `d7g89vdgg5rmt0d1x63r2aw8h4` |
| battle_axe | Battle axe | m | 9834 | small steel battle axe with a wooden handle, lying diagonally | `sanyj0rxcxrmt0d1x5zb4xjvfg` | `es2fd17s61rmy0d1x61svfb27w` |
| gauntlet | Gauntlet | m | 9835 | single steel armoured knight's gauntlet | `0qkqh5saj9rmt0d1x5zadwzn0c` | `2gksa5m32srmr0d1x62v1hh3vc` |
| golden_key | Golden key | s | 9843 | large ornate golden key with a round jewelled bow and a simple square bit | `chtfwhm80drmr0d1x5zrqv0e1g` | `gs5bacj385rmy0d1x639nybz7c` |
| medallion | Medallion | s | 9842 | round bronze medallion embossed with a coiled dragon, hanging from a short red ribbon loop, small in the frame (standard; "whole object and whole ribbon visible" instead of "whole object visible") | `k9pvbh3x1srmy0d1x5zs898a7m` | `c794r4gbv1rmw0d1x63sj0m3am` |
| golden_bird | Golden bird | s | 9838 | small golden songbird figurine | `zj8dkwme0drmr0d1x5z8r6nrqr` | `p1mgrrhjyhrmw0d1x63br2pq0c` |
| jeweled_egg | Jewelled egg | s | 9839 | ornate jewelled egg, white enamel with gold filigree and pink gems | `3jf8jnwvg1rmr0d1x5z8hjyb6c` | `xw7v3jqvwxrmy0d1x63a457b18` |
| treasure_map | Treasure map | m | 9840 | rolled-up old treasure map tied with a leather cord, closed (standard negatives with `no writing` after `no signature`) | `2x43ebn8ksrmw0d1x5za3567rg` | `bnpfgw4b45rmw0d1x64aj78bdw` |

**Rejected objects** (images kept in `rejected/`, `market/rejected/`, `hoard/rejected/`, not committed):
- attic broom 9625 `jwc4w14e3xrmr0d1x5t9ppbwv4`: painted caption "Witch's broom". Regenerated as 9641 with extra "no words, no caption, no label".
- attic scissors 9619 `mqze2pwqqhrmy0d1x5sv6sbv70`: failed, false NSFW flag. Regenerated as "tailor's shears", 9629.
- attic compass 9603 `kz71c75h99rmr0d1x5qv5rey6g` (bria `3tcsawr4fsrmy0d1x60v0bxjhr`) and 9642 `f2fghdw4n5rmr0d1x67teqsw3w`
  (bria `w3wabe4xbxrmw0d1x67vtz0m3c`; "plain teal face ... blank dial with only a simple star shape", "no compass letters,
  no markings"): N/E/S/W letters both times. Replaced by the starfish (9643).
- market ladle 9721 `87je62mfrxrmr0d1x5w8x2481m`: came out as a spoon (the library already has a spoon). Regenerated 9741.
- market cheese 9702 `0rk94ztf15rmt0d1x5vaqmzgr0` (bria `5r10nt0xaxrmt0d1x64r5a23a8`): teal smear fused to the underside. Regenerated 9742.
- hoard dragon claw 9828 `p6g3sxc7nnrmy0d1x5yrpxmvgw` and 9841 `sjzs26bex5rmw0d1x5zr4zs7q8` ("large curved dragon talon,
  a thick hooked ivory-white claw with a dark tip, solid and clearly outlined"): faint wisps, not recognisable. Replaced by the little chest (9844).
- hoard medallion 9837 `shzsfyt0k1rmr0d1x5zat1eh2m`: ribbon cut by the frame. 9842 still ran the ribbon off the top; it
  is erased in cleanup (`eraseRows` top 42 %).
- hoard golden key 9836 `12rh79snm9rmr0d1x5zbq72jsm`: the bit read as a letter "E". Regenerated 9843.
- hoard jewel box 9817 `rqwamhqfn5rmt0d1x5xsjgysr4` (bria `37n40sfd55rmw0d1x63826hn38`): pink smear fused to the box. Regenerated 9845 (still a pale smear, removed with `dropPale`).

Kept with cleanup: goblet (tiny corner mark, dropped by `keepLargest`), coin pouch (two loose coins at its foot remain),
tankard and strawberry (crumbs/shadow dropped), mortar (ground smear, `dropPale`), medallion (ribbon erased).
