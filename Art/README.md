# Pourfect – raster art set

Painted artwork for *Pourfect Potion Lab*, generated on Replicate on 2026-11-15.
Every image is generated, not hand-drawn. This file records how each one was made so it can be regenerated or extended in the same style.

- **Generator:** `black-forest-labs/flux-1.1-pro-ultra` (official Replicate model), `raw: false`, `output_format: png`, `safety_tolerance: 2`, explicit integer `seed`.
- **Background removal:** `bria/remove-background` (Replicate). Bria returns a 1024 px cut-out. Its alpha mask was upscaled and applied locally (CoreGraphics) to the 2048 px original, so the colours stay full resolution.
- **Style reference:** an approved flux-1.1-pro test (prediction `s4v92w88k9rmr0d1w24vd0r4f0`, seed 35792, 1344×768). Its style wording is reused in every prompt. It is not in this folder; it was replaced by the Ultra-resolution version below.
- Rejected attempts are not kept. Their prediction ids are listed so they can be looked up.

## Licensing

FLUX 1.1 [pro] / [pro] Ultra outputs generated through the API (here via Replicate) may be used commercially under Black Forest Labs' API terms of service. Bria's remove-background model is trained on licensed data and is offered for commercial use. **Check the current terms of Black Forest Labs, Bria and Replicate before shipping**, because terms change.

## Roadmap mapping

| Folder | Roadmap step |
|---|---|
| `backgrounds/`, `map/`, `chapters/` | **R2** |
| `characters/` (apprentice, alchemist, villagers), `themes/` | **R7** |
| `icon/` | **R8** |

## Shared prompt fragments

To keep the tables readable, prompts are written with these placeholders. Each **full prompt** is the text with the placeholder expanded verbatim.

- **{STYLE-BG}** = `Painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no people, no letters, no logos.`
- **{CH-HEAD}** = `Cozy hand-painted storybook-style painting filling the whole square canvas edge to edge, no border, no frame, no paper.`
- **{CH-TAIL}** = `Textured painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no writing, no letters, no signature, no watermark, no people, no logos.`
- **{PORTRAIT-TAIL}** = `Facing the viewer, centred, whole head and shoulders inside the frame. Plain flat solid pale cream background with nothing else. Textured painterly brushwork, soft warm lighting, muted teal shadows and warm amber highlights. No text, no letters, no signature, no watermark, no logos.`
- **{VIL-TAIL}** = `Facing the viewer, centred, whole head and shoulders inside the frame, clean soft edges. Plain flat solid pale cream background with nothing else, clean empty corners. Textured painterly brushwork, soft warm lighting, muted teal shadows and warm amber highlights. No text, no lettering, no words, no symbols, no artist signature, no watermark, no logos.`

---

## backgrounds/ (R2)

### backgrounds/workbench_landscape.png
- **Purpose:** in-game workbench background, landscape (iPad / Mac / iPhone landscape). Empty table centre behind the bottles.
- **Model / aspect / size:** flux-1.1-pro-ultra · 16:9 · 2752×1536
- **Seed:** 1101 · **Prediction:** `xv4myn9dr5rmy0d1w29t41czac`
- **Prompt (the approved prompt, unchanged):**
  > Cozy hand-painted storybook illustration of an alchemist's wooden workbench in a stone tower room, seen from the front at table height. Warm candlelight, dusty bookshelves and hanging dried herbs softly blurred in the background, a few small potion bottles and a brass scale at the far left and right edges. The centre of the table is an empty, calm, slightly darker wooden surface with soft even lighting (space for game objects). Painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no people, no letters, no logos.
- Rejected: `y14zpzzbjhrmy0d1w28tabyfc8` (Ultra, seed 35792, flatter and less faithful), `jh8xacwzbxrmw0d1w25ahe99r0` (flux-1.1-pro, seed 1101, Edison bulb and labels).

### backgrounds/workbench_portrait.png
- **Purpose:** in-game workbench background, portrait (iPhone). Table fills the lower half and its centre is empty.
- **Model / aspect / size:** flux-1.1-pro-ultra · 9:21 · 1344×3136
- **Seed:** 1202 · **Prediction:** `ar737pa37xrmw0d1w2984s9kyc`
- **Prompt:**
  > Cozy hand-painted storybook illustration of an alchemist's stone tower room in a tall vertical phone-wallpaper composition. Top half: dusty bookshelves, hanging dried herbs and a softly glowing arched window, gently blurred. Bottom half: a large, wide wooden workbench tabletop seen from the front at table height fills the entire lower half of the picture edge to edge. Only a couple of small potion bottles stand at the extreme left and right edges of the table. The middle of the tabletop is completely empty, calm, slightly darker wood with soft even lighting, nothing on it (space for game objects). Warm candlelight, painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no people, no letters, no logos, no scales in the middle.
- Earlier flux-1.1-pro drafts (made while Ultra was out of credit, not used): `pes6mxtkb5rmw0d1w25sa0134g`, `rjbg3c20xnrmw0d1w26azmz9eg`.

## map/ (R2)

### map/chapter_map.png
- **Purpose:** scrolling chapter-select map. Path climbs from the cellar (bottom) to the dragon (top), with open clearings for level buttons. No labels; the app adds them.
- **Model / aspect / size:** flux-1.1-pro-ultra · 9:21 · 1344×3136
- **Seed:** 3103 · **Prediction:** `yy9m3qas51rmr0d1w29v38rv8w`
- **Prompt:**
  > Cozy hand-painted storybook painting of a tall vertical fantasy landscape seen from high above, filling the whole canvas edge to edge with no border and no frame. A single winding dirt path zig-zags from the bottom edge up to the top edge, passing ten distinct small landmarks stacked one above another: at the bottom a cellar door in a hillside, then a stone vault door with a glowing sigil, a misty marsh, a tall library tower with glowing windows, a glassblower's workshop with a glowing furnace, an icy snow-capped peak, a green bog with bubbling cauldrons, two towers linked by a silver chain, a grand domed alchemist's hall, and at the very top a sleeping red dragon curled on a pile of gold in a mountain cave. Beside each landmark the path widens into a small empty round clearing. Textured painterly brushwork, soft atmospheric depth, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no labels, no letters, no people, no logos, no compass, no border.
- Note: the landmarks are suggestive, not one-to-one. Button positions will need to be placed by hand along the path.
- Rejected: `q5vhp3ves5rmt0d1w29ave5v5w` (Ultra, seed 3102, ornate side frame). flux-1.1-pro drafts: `0dfm0jvvj9rmw0d1w25r7z4qbg`, `trf9rj3bh5rmw0d1w26ae89rfw`.

## chapters/ (R2)

One square vignette per chapter. flux-1.1-pro-ultra · 1:1 · 2048×2048. Each prompt is `{CH-HEAD} <subject> {CH-TAIL}`, with these exceptions:
- 01–04 used the earlier tail `… no letters, no people, no logos.` without "no signature, no watermark".
- 02 and 04 add "no alphabet characters" (04 says "No readable text").
- 07 and 08 use "clean unmarked corners" and "no artist signature".

The full prompts are below.

| File | Seed | Prediction | Rejected attempts |
|---|---|---|---|
| 01_apprentice_cellar.png | 4001 | `x3xy1jw395rmr0d1w29vsgkqxg` | – |
| 02_rune_vault.png | 4002 | `rsqbbyde51rmt0d1w29vby4gfw` | – |
| 03_misty_marsh.png | 4003 | `k9p7vbept9rmy0d1w29vnczb80` | – |
| 04_glyph_library.png | 4004 | `45tgbpg165rmy0d1w2abymjst0` | – |
| 05_glass_works.png | 4015 | `wngsnf0gkxrmr0d1w2arw1mcw8` | `by2n0n9bmsrmy0d1w2aa9p6420` (seed 4005, signature scrawl) |
| 06_frost_peak.png | 4006 | `b91d8gsxhnrmr0d1w2at0t251g` | – |
| 07_bubbling_bog.png | 4017 | `mc3dcfzepsrmr0d1w2b8tqgzk0` | `nrd4gvk7hnrmw0d1w2avyw1sjw` (seed 4007, signature scrawl) |
| 08_twin_towers.png | 4018 | `dwf3nvgrbsrmy0d1w2bt4vrtc0` | `frr4pr4ethrmr0d1w2asjqb4z8` (seed 4008, one castle, no chain) |
| 09_alchemists_hall.png | 4009 | `ap14ggxs6srmy0d1w2asw9ee00` | – |
| 10_dragons_hoard.png | 4010 | `crp08gz2y9rmy0d1w2atdew2rw` | – |

(flux-1.1-pro tests for 01–03, not used: `dqfek7r3bnrmw0d1w26r04rcxg`, `q8skw4saz1rmt0d1w26s8p1msc`, `10rk80jnahrmt0d1w26tz08pzr`.)

**01** – Cozy hand-painted storybook-style painting filling the whole square canvas edge to edge, no border, no frame, no paper. An apprentice alchemist's cellar: a low vaulted stone cellar with oak barrels and dusty shelves softly blurred, and in the centre a small wooden table holding a single glowing round potion flask as the clear focal subject. Warm candlelight, textured painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no writing, no letters, no people, no logos.

**02** – Cozy hand-painted storybook-style painting filling the whole square canvas edge to edge, no border, no frame, no paper. A rune vault: a massive round sealed stone vault door set in a rocky cavern wall, iron bands and rivets, and in its centre a single glowing teal magical sigil made of concentric circles and spirals as the clear focal subject, soft mist on the floor. Warm torchlight, textured painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no writing, no letters, no alphabet characters, no people, no logos.

**03** – Cozy hand-painted storybook-style painting filling the whole square canvas edge to edge, no border, no frame, no paper. A misty marsh at dusk: thick fog over still water and reeds, and in the centre a mossy tree stump holding a cluster of murky green and grey potion bottles as the clear focal subject, faint glowing fireflies. Textured painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no writing, no letters, no people, no logos.

**04** – Cozy hand-painted storybook-style painting filling the whole square canvas edge to edge, no border, no frame, no paper. A glyph library: tall dark wooden bookshelves full of old leather books reaching up into shadow, and in the centre abstract glowing teal magical glyph symbols made of circles and spirals floating in the air as the clear focal subject, a rolling ladder, warm lamp glow. Textured painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No readable text, no writing, no letters, no alphabet characters, no people, no logos.

**05** – Cozy hand-painted storybook-style painting filling the whole square canvas edge to edge, no border, no frame, no paper. A glassworks: a round brick glassblower's furnace with a bright glowing orange mouth in the centre as the clear focal subject, freshly blown glass flasks and alembics on wooden shelves around it catching the light. Textured painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating sparks and dust motes. No text, no writing, no letters, no signature, no watermark, no people, no logos.

**06** – Cozy hand-painted storybook-style painting filling the whole square canvas edge to edge, no border, no frame, no paper. Frost Peak: a small icy alchemy laboratory hut built into a snowy mountain summit, frosted windows glowing warm amber, icicles and frozen glass flasks outside, as the clear focal subject, snowy peaks and gentle snowfall softly blurred behind. Textured painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating snow and dust motes. No text, no writing, no letters, no signature, no watermark, no people, no logos.

**07** – Cozy hand-painted storybook-style painting filling the whole square canvas edge to edge, no border, no frame, no paper, clean unmarked corners. Bubbling Bog: a murky green swamp with gnarled trees and hanging moss, and in the centre a large black iron cauldron bubbling with glowing green potion as the clear focal subject, two smaller cauldrons steaming nearby, rising bubbles and wisps of vapour. Textured painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no writing, no letters, no artist signature, no watermark, no people, no logos.

**08** – Cozy hand-painted storybook-style painting filling the whole square canvas edge to edge, no border, no frame, no paper, clean unmarked corners. Twin Towers: exactly two identical tall slender round stone wizard towers with pointed teal roofs, one on the left and one on the right, standing apart on two rocky pinnacles with a gap between them. A single thick shining silver chain hangs in a long curve across the gap, connecting the top of the left tower to the top of the right tower, as the clear focal subject. Glowing amber windows, twilight sky with soft clouds. Textured painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no writing, no letters, no artist signature, no watermark, no people, no logos.

**09** – Cozy hand-painted storybook-style painting filling the whole square canvas edge to edge, no border, no frame, no paper. Alchemist's Hall: a grand vaulted stone hall with tall arched windows, columns and shelves of potions, and in the centre a large ornate brass mixing cauldron on a dais swirling with glowing teal and amber liquid as the clear focal subject. Warm candlelight, textured painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no writing, no letters, no signature, no watermark, no people, no logos.

**10** – Cozy hand-painted storybook-style painting filling the whole square canvas edge to edge, no border, no frame, no paper. Dragon's Hoard: a friendly-looking red dragon curled up peacefully asleep on a big pile of gold coins and glowing colourful potion bottles inside a mountain cave, as the clear focal subject, warm glints of treasure. Textured painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes. No text, no writing, no letters, no signature, no watermark, no people, no logos.

---

## characters/ (R7)

Bust portraits with transparent backgrounds. The originals on a plain cream background are in `characters/originals/<name>_raw.png`. flux-1.1-pro-ultra · 1:1 · 2048×2048. Each character's three expressions use the same text and the same seed; only the expression phrase changes.

**Apprentice** (seed **5001**): `Hand-painted storybook-style character portrait, head-and-shoulders bust of a young apprentice alchemist of ambiguous gender, about fourteen years old, with messy tousled chestnut-brown hair, wearing an oversized teal robe with a wide hood resting on the shoulders, a small dark ink smudge on the left cheek, <EXPRESSION>, looking at the viewer.` + {PORTRAIT-TAIL}

**Alchemist** (seed **5101**): `Hand-painted storybook-style character portrait, head-and-shoulders bust of an old wise alchemist with a long flowing white beard, round brass spectacles, a tall pointed dark amber wizard hat and a warm amber robe with gold trim, <EXPRESSION>, looking at the viewer. Facing the viewer, centred, whole head, hat tip and shoulders inside the frame.` + the rest of {PORTRAIT-TAIL} from "Plain flat solid pale cream background…"

| File | Seed | Expression phrase | Generation prediction | Bria prediction |
|---|---|---|---|---|
| apprentice_neutral.png | 5001 | calm neutral expression with mouth closed | `jrb65ttf7nrmy0d1w2brjk6pfr` | `26rvgm996srmy0d1w2g9rxxpm8` |
| apprentice_happy.png | 5001 | big joyful open smile with bright happy eyes | `s7pk6avtbnrmr0d1w2btz70tvw` | `qh04dy80cxrmy0d1w2gtr8a7yg` |
| apprentice_worried.png | 5001 | worried anxious expression with eyebrows raised and drawn together and a nervous frown | `80yrqr54chrmy0d1w2bvaestrr` | `24kzfs9bedrmy0d1w2gvahvd2g` |
| alchemist_neutral.png | 5101 | calm neutral expression with mouth closed | `hzjvejpckhrmw0d1w2brtwaybw` | `vypmt62nh1rmr0d1w2gtqthv08` |
| alchemist_happy.png | 5101 | big warm joyful smile with crinkled happy eyes | `sk3p8sq49xrmw0d1w2c8t5p01w` | `8ecpsbkx5drmw0d1w2gv72xx30` |
| alchemist_worried.png | 5101 | worried concerned expression with eyebrows raised and drawn together and a troubled frown | `hspqta8cc1rmr0d1w2cvvykrp0` | `ky6hmxn6ksrmr0d1w2gsyqcef4` |

Notes: the apprentice came out with the hood up instead of resting on the shoulders, consistently across all three expressions. The alchemist's "happy" smile is mostly hidden by the beard.

### Villagers (potion-shop customers)

Prompt pattern: `Hand-painted storybook-style character portrait, head-and-shoulders bust of <DESCRIPTION>, a customer of a potion shop, <EXPRESSION>, looking at the viewer.` + a tail. Villagers 1, 2 and 6 use {PORTRAIT-TAIL}; villagers 3, 4 and 5 (the regenerated ones) use {VIL-TAIL}. Villager 5 says "whole heads and shoulders".

| File | Who | Seed | Description · expression (verbatim) | Generation prediction | Bria prediction | Rejected |
|---|---|---|---|---|---|---|
| villager_1.png | baker | 6001 | a plump cheerful village baker with rosy cheeks, flour on the nose, a white baker's cap and an apron over a brown shirt · friendly expression | `x11sgv92r1rmw0d1w2d80de6h8` | `y0mpzqyh6nrmt0d1w2grbhns5c` | – |
| villager_2.png | knight | 6002 | a brave young knight in slightly dented silver plate armour with a teal cloak, helmet tucked away so the face and short hair are visible, a small bandage on the chin · friendly confident expression | `gjmay1je75rmy0d1w2d9gj4y0w` | `9e0jqeqw2srmw0d1w2gvwtdrb8` | – |
| villager_3.png | farmer | 6013 | a sun-tanned middle-aged farmer woman with a wide straw hat, a braid, freckles and plain green overalls over a linen shirt · friendly expression | `jznkcns5dnrmy0d1w2e8q2c2gg` | `jp1w9596csrmt0d1w2h91nf6m0` | `830rdcks3xrmy0d1w2d91yk7vw` (seed 6003, lettering) |
| villager_4.png | merchant | 6014 | a travelling merchant with a neat curled moustache, a burgundy velvet coat with plain round gold buttons, a feathered cap and a plain leather satchel strap across the chest · friendly shrewd smile (tail also adds "no currency signs") | `z04tvyte31rmy0d1w2ea47dd8r` | `znmn93aey1rmt0d1w2hah8jj8g` | `brf589x4gsrmw0d1w2db024az4` (seed 6004, "$" on pouch) |
| villager_5.png | child with cat | 6015 | a small cheerful child of about eight with curly hair and a patched blue tunic, holding a fluffy orange tabby cat against their shoulder, the cat's face clearly visible · friendly hopeful expression | `1d3c0j3pv5rmy0d1w2eawwdpbg` | `tcr3c1krw9rmw0d1w2h9mn7t9w` | `jhw19t6f0hrmy0d1w2d85az27m` (seed 6005, signature) |
| villager_6.png | elderly herbalist | 6006 | a kind elderly herbalist woman with silver hair in a loose bun, a sage-green shawl, a sprig of lavender tucked behind one ear and small herb bundles pinned to her shawl · gentle wise smile | `cjmwt17qy5rmt0d1w2d9f9w674` | `fsvn96x2nsrmt0d1w2hahhnrv0` | – |

---

## themes/ (R7)

Unlockable workbench themes using the same composition rules as `backgrounds/`. flux-1.1-pro-ultra; landscape 16:9 (2752×1536), portrait 9:21 (1344×3136).

| File | Seed | Prediction | Rejected |
|---|---|---|---|
| frost_lab_landscape.png | 7021 | `vq7b176my9rmt0d1w2fspb0534` | `y77f4r4zqxrmt0d1w2e9am3fg8` (7001, sharp busy windows), `m7689vm35nrmw0d1w2fbna3prc` (7011, watermark) |
| frost_lab_portrait.png | 7012 | `azt4aqnbr5rmw0d1w2f9xpnqz8` | `81gbw9y87hrmy0d1w2ebehahfr` (7002, clutter on table centre) |
| dragon_lair_landscape.png | 7023 | `z4z5s1fychrmt0d1w2ftgqyz9w` | `g8hbv3fjz9rmr0d1w2eb23met8` (7003, dragon tail behind centre), `6y4tff6n2srmw0d1w2fbr25sj4` (7013, parchment on table) |
| dragon_lair_portrait.png | 7004 | `4ybaadgw3hrmy0d1w2ev8vn504` | – |
| forest_hut_landscape.png | 7015 | `z8eed8qzs5rmr0d1w2f9a0sfm4` | `26h62cj7d9rmw0d1w2etdpf4jg` (7005, busy) |
| forest_hut_portrait.png | 7006 | `cj2ncp3hgnrmw0d1w2etqp6yjg` | – |

**frost_lab_landscape** – Cozy hand-painted storybook illustration of an alchemist's wooden workbench in a frozen ice-crystal laboratory high on a snowy mountain, seen from the front at table height, strong shallow depth of field. The background is heavily out of focus, dim and calm: soft blurred shapes of a frosted window, icicles and pale blue ice shelves, melting into gentle bokeh. A few small frosted potion bottles and a brass scale only at the far left and right edges. The centre of the table is bare, empty, calm, slightly darker wood with soft even lighting (space for game objects), and the area directly behind it is a smooth soft blur. Painterly brushwork, cool icy teal shadows and warm amber candle highlights, magical floating snowflakes and dust motes. Clean unmarked corners. No text, no people, no letters, no logos, no artist signature, no watermark.

**frost_lab_portrait** – Cozy hand-painted storybook illustration of a frozen ice-crystal alchemy laboratory in a tall vertical phone-wallpaper composition, strong shallow depth of field. Top half: a frosted arched window with snowy peaks, icicles and pale blue ice shelves with frosty flasks, all softly blurred. Bottom half: a large, wide wooden workbench tabletop seen from the front at table height fills the entire lower half of the picture edge to edge. Only a couple of small frosted potion bottles stand at the extreme left and right edges of the table. The middle of the tabletop is completely bare and empty, calm, slightly darker wood with soft even lighting, no books, no papers, nothing on it (space for game objects). Painterly brushwork, gentle bokeh, cool icy teal shadows and warm amber candle highlights, magical floating snowflakes and dust motes. No text, no people, no letters, no logos, no signature.

**dragon_lair_landscape** – Cozy hand-painted storybook illustration of an alchemist's wooden workbench inside a dragon's lair cave, seen from the front at table height, strong shallow depth of field. The background is heavily out of focus, dim and calm: soft blurred glints of gold coin heaps and treasure chests at the sides melting into warm ember bokeh, a dark calm cave wall behind the middle. A few small potion bottles and a brass scale only at the far left and right edges. The centre of the table is bare wooden planks, empty, calm, slightly darker wood with soft even lighting, no paper, no parchment, no cloth, nothing on it (space for game objects), and the area directly behind it is a smooth soft blur. Painterly brushwork, muted teal shadows and warm amber highlights, magical floating embers and dust motes. Clean unmarked corners. No text, no people, no letters, no logos, no artist signature, no watermark.

**dragon_lair_portrait** – Cozy hand-painted storybook illustration of a dragon's lair cave in a tall vertical phone-wallpaper composition. Top half: heaps of glittering gold coins, treasure chests and a glimpse of a sleeping red dragon's tail, warm ember glow, gently blurred. Bottom half: a large, wide wooden workbench tabletop seen from the front at table height fills the entire lower half of the picture edge to edge. Only a couple of small potion bottles stand at the extreme left and right edges of the table. The middle of the tabletop is completely empty, calm, slightly darker wood with soft even lighting, nothing on it (space for game objects). Painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating embers and dust motes. No text, no people, no letters, no logos, no signature.

**forest_hut_landscape** – Cozy hand-painted storybook illustration of an alchemist's wooden workbench inside a cozy forest hut, seen from the front at table height, strong shallow depth of field. The background is heavily out of focus, dim and calm: soft blurred mossy timber walls, a round window glowing with green forest light, mushrooms, potted plants and hanging dried herbs melting into gentle bokeh. A few small potion bottles and a brass scale only at the far left and right edges. The centre of the table is an empty, calm, slightly darker wooden surface with soft even lighting (space for game objects), and the area directly behind it is a smooth soft blur. Painterly brushwork, muted teal shadows and warm amber highlights, magical floating dust motes and fireflies. No text, no people, no letters, no logos, no signature.

**forest_hut_portrait** – Cozy hand-painted storybook illustration of a cozy forest hut interior in a tall vertical phone-wallpaper composition. Top half: mossy timber walls, a round window with soft green forest light, glowing mushrooms, potted plants and hanging dried herbs, gently blurred. Bottom half: a large, wide wooden workbench tabletop seen from the front at table height fills the entire lower half of the picture edge to edge. Only a couple of small potion bottles stand at the extreme left and right edges of the table. The middle of the tabletop is completely empty, calm, slightly darker wood with soft even lighting, nothing on it (space for game objects). Painterly brushwork, gentle bokeh, muted teal shadows and warm amber highlights, magical floating dust motes and fireflies. No text, no people, no letters, no logos, no signature.

Note: Ultra renders the theme backgrounds sharper than requested, despite the "shallow depth of field" wording. The table centres are empty, but the frost and forest backdrops are fairly detailed. A blur or dim overlay in-app behind the bottles may help.

---

## icon/ (R8)

### icon/app_icon_candidate.png
- **Purpose:** app icon candidate. Full-bleed square; the OS applies the corner mask.
- **Model / aspect / size:** flux-1.1-pro-ultra · 1:1 · 2048×2048 (downscale to 1024 for the asset catalogue)
- **Seed:** 8001 · **Prediction:** `f6mdjbcvmhrmt0d1w2etwm7ksg`
- **Prompt:**
  > Bold simple app icon illustration: a single round-bottomed glass potion flask with a short neck and a cork, large and centred, glowing from within with swirling teal and warm amber liquid, soft inner light and a gentle glow halo, on a solid dark plum purple background that fills the whole square edge to edge. Clean bold readable silhouette that works at small size, subtle hand-painted shading, minimal detail. No text, no letters, no border, no rounded corners, no frame, no watermark, no signature.

---

## Notes for integration

- Total folder size is about 200 MB of PNGs at full resolution. Before adding them to the asset catalogue, downscale and compress them (e.g. backgrounds to the largest device size, and HEIC/JPEG for the opaque images).
- Regenerating with the same prompt and seed on flux-1.1-pro-ultra should give very similar but not guaranteed identical images.
