# Pourfect

A liquid-sorting puzzle game for **iPhone, iPad and Mac** (native Apple silicon), built with SwiftUI.
Pour colored layers between bottles until every bottle is empty or full with one color.

The app is shown to players as **Pourfect**, a potion-lab game: in the UI bottles are *flasks*, levels are *recipes*
and packs are *chapters*. The Xcode project, target, scheme and app folder are named `Pourfect` (renamed from
`LiquidPour` in R8; the repository folder keeps its old name); the logic package stays neutral (`BottleSortCore`).

Progress is tracked in [`PLAN.md`](PLAN.md); design choices are in [`DECISIONS.md`](DECISIONS.md).

## Level packs

Main path (chapters, star-gated: a chapter opens when the previous one has at least half of its stars):

| File | Chapter | Ids | Recipes | Moves | Score | What it adds |
|---|---|---|---|---|---|---|
| `chapter_01` | 1 Apprentice Cellar | `p1_001…` | 40 | 5–26 | 15–52 | Basic sorting: 3 → 8 colors (the original Starter pack) |
| `chapter_02` | 2 Rune Vault | `c2_001…` | 30 | 6–25 | 15–53 | Sealed flasks and rune-stone keys: 1 seal, then 2 |
| `chapter_03` | 3 Misty Marsh | `c3_001…` | 30 | 5–25 | 15–54 | Murky "?" layers; the last 8 also have one seal |
| `chapter_04` | 4 Glyph Library | `c4_001…` | 30 | 7–26 | 16–55 | Essence flasks (one color only): 1–2 runes, then runes with murky layers or one seal |
| `chapter_05` | 5 Glass Works | `c5_001…` | 30 | 6–24 | 17–56 | Narrow necks, then funnels, then taps; at the end all three and murky layers, a seal or a rune |
| `chapter_06` | 6 Frost Peak | `c6_001…` | 30 | 7–27 | 18–50 | Frozen layers: a tutorial (two empty flasks), then one layer (one empty flask), then two; at the end with murky layers, a rune or a seal |
| `chapter_07` | 7 Bubbling Bog | `c7_001…` | 30 | 4–25 | 15–52 | Bubbling flasks: one, then two (4 colors); at the end with murky layers and seals |
| `chapter_08` | 8 Twin Towers | `c8_001…` | 32 | 4–25 | 11–56 | Twin flasks (every one needs a split), then pressure pipes (tutorial `c8_013`, then 4–5 colors; every pipe must be pushed through), then murky twins and pipes, seals and 7 colors; the last two recipes have both links |
| `chapter_09` | 9 Alchemist's Hall | `c9_001…` | 30 | 4–19 | 15–52 | Mixing cauldron: one recipe with ingredients that must all be brewed, then ingredients that are potions of their own (one pair to brew for the shortest win), then two recipes; at the end murky layers, a seal and 8 colors. Built backwards from a solved board |
| `chapter_10` | 10 Dragon's Hoard | `c10_001…` | 32 | 6–32 | 14–63 | Switch flasks and gates: one switch (gate full of potion, empty gate, empty switch), then two; then one earlier mechanic each (murky, seal, rune, narrow neck, ice, bubbling, twins); the finale 26–30 (8–9 colors, 58–63) is the hardest of the main path; 31–32 (41, 50) add a mixing cauldron to a switch (appended after the finale so 1–30 keep their ids) |

All ten chapters of `ChapterOutline.plan` ship. **Customer orders (R7)**: chapters 2–10 each end with three order
recipes, appended after the chapter's own recipes (ids `c2_031…033`, …, `c8_033…035`, `c9_031…033`, `c10_033…035`;
earlier ids and content unchanged). A villager orders a flask full of one potion (chapter 3's last one orders two),
using the chapter's own mechanic lightly; chapter 2's first is a tiny tutorial order, and from chapter 4 the third is a
layered recipe (an exact pattern, bottom to top). Order recipes are *bonus recipes*: their stars count towards the
next chapter's gate, but they don't raise it (the gate stays half the stars of the chapter's own recipes).
Optional **Challenges** (never gated):

| File | Pack | Ids | Levels | Moves | Score | What makes it hard |
|---|---|---|---|---|---|---|
| `challenge_challenger` | Challenger | `p2_…` | 30 | 15–34 | 43–72 | 8–10 colors, taller flasks, one-empty-flask levels |
| `challenge_expert` | Expert | `p3_…` | 30 | 20–41 | 50–84 | 10–12 colors, flask size 5, one empty flask |
| `challenge_master` | Master | `p6_…` | 20 | 22–43 | 53–96 | 12 colors, size-5 flasks, 2 locks, hidden 10-color boards |

Each chapter starts with a tiny tutorial recipe and then rises in difficulty score; challenges keep only the
highest-scoring levels from a larger generated pool. Level ids of the original packs are unchanged, so saved
stars keep counting. (The old Locks & Keys and Hidden Depths packs were replaced by chapters 2 and 3; stars saved
for their `p4_`/`p5_` ids are ignored.)

The app loads every `chapter_*.json`, `challenge_*.json` and (older) `pack_*.json` in the bundle. Kind and chapter
number come from the pack metadata; a file without it falls back to its name (`chapter_NN` = chapter NN, anything
else is a challenge).

### Screens

- **Chapter map** (home): the painted `chapter_map` scrolls from the cellar (chapter 1, bottom) up to the dragon
  (chapter 10, top). Each chapter is a round vignette button on a clearing of the path, placed by hand as fractions
  of the image size (`ChapterArt.mapSpots`), with its number, name and stars, a lock with the stars still needed,
  or "coming soon". The map opens scrolled to the chapter you're on, which glows. On wide windows (Mac, iPad) the
  map is a framed column beside a panel with the total stars, a **Continue** card and **Challenges**; on narrow
  ones it fills the width with a Continue / Challenges bar at the bottom. The toolbar has Challenges and Settings.
  A **Today** card sits at the top of the panel (and as a row in the bottom bar on iPhone): every daily game
  (Daily Brew, Daily Gathering, Daily Distillery, Secret Recipe) with today's flavour, won state and streak flame, "N of 4 done"
  and "New dailies in 3 h 12 m" (UTC midnight); it opens the daily hub, which leads to each daily's own screen.
  The Distillery wing (R10) climbs the map's left edge.
- **Daily Brew:** today's puzzle (weekday · difficulty, mode, difficulty pips, **Play** / **Replay**), current and
  best streak, brews solved and perfect count, and a month calendar (Monday first, navigable back to your first
  result) with solved days in amber, perfect days in gold with a seal, today ringed and future days dimmed. All
  days are UTC dates ("Resets at midnight UTC"). Playing uses the normal game screen; the win card shows
  "Daily solved!", the **Perfect** badge (fewest moves, no hint), the streak and a **Share Result** button with
  spoiler-free text such as `Pourfect Daily 2026-11-15 · 22 moves (perfect) · 🔥 6`. Daily results never touch
  chapter stars.
- **Settings → About Pourfect:** version and build, the art licensing note (FLUX 1.1 [pro] Ultra via Replicate,
  Bria background removal), sound and font credits and the privacy note (no data collected). A pushed page on iOS,
  a sheet over the Settings window on the Mac.
- **Chapter screen:** vignette header with name, subtitle, stars, gold seals ("Gold seals 4 / 30") and what the
  stars open ("Earn 12 more stars to open Misty Marsh"), then the recipe grid (recipes open in order; a cleared
  recipe with a gold seal wears it in its corner).
- **Gold seals ("perfect brewer"):** a recipe solved in exactly its solver minimum *without a hint* earns a gold
  seal (Undo is fine, only the final count matters, as for stars; a hint forfeits it until another recipe starts,
  Restart included). Stored per recipe apart from the stars (`progress.goldSeals.v1`). The win card then says
  **Perfect brew!** with the seal stamping in over a burst of gold rays and a bell chime (a still seal with Reduce
  Motion); 3 stars after a hint add "A hint was used, so no gold seal this time". A chapter whose every recipe has
  its seal gets a small gold seal on its map button. Random brews show the card too but save nothing; the daily
  keeps its own "Perfect" badge (same look).
- **Challenges** (trophy on the map; never gated, nothing here counts toward the chapter map's star gates):
  - **Rush:** solve as many generated recipes as you can in **3:00**. Each solve adds **+5 s**, **Skip** costs
    **10 s**, no hints (Undo and Restart are fine). The clock stops while the next recipe is still brewing (they
    are made one ahead in the background, so normally there is no wait), during the short "Brewed! +5 s" pause,
    as soon as the board is solved (the winning pour counts even if its animation lands after 0:00), while a
    "?" tip is open and while the app is in the background. Recipes start at 3 colors and ramp up; from the sixth
    on they take turns with the mechanics you have met on the map (a chapter's tutorial recipe cleared): rune
    seals, murky potions, essence flasks, narrow necks, frozen layers. End card: recipes brewed, best, skips,
    **New best!** with the gold seal. Best and runs are stored on their own keys (`rush.best.v1`,
    `rush.runs.v1`); leaving a run before time is up records nothing.
  - **Recipe books:** Challenger, Expert and Master, with their stars and gold seals (recipes inside open in order).
  - **Random Brew** (below).
- **Story:** the first time a chapter's recipe list opens, a short scene (2–4 speech bubbles) plays between the
  apprentice and the old alchemist about the place and its new mechanic; after the last recipe of Dragon's Hoard is
  solved for the first time (its own last recipe: the customer orders after it are bonus recipes), the ending plays
  over the win card. A scene always comes before a recipe's first-time tips, which wait until it ends. Portraits change expression per line (generated
  `portrait_apprentice_*` / `portrait_alchemist_*`, 512 px). Tap or click anywhere, Space, Return or **Next** to go
  on, **Skip** (Esc) to end; **Story** on a chapter screen replays its scene (on Dragon's Hoard also the ending once
  seen). Reduce Motion swaps lines without sliding or bouncing; VoiceOver reads "Alchemist: …" and announces each
  new line. Lines are in `StoryScript.swift` (String catalog), when they play is core logic (`Story`); seen scenes
  are stored in `progress.storySeen.v1`.
- **Lab Style (cosmetic rewards):** the palette button on the map opens the rewards: **workbench themes**
  (Alchemist's Workbench, Forest Hut, Frost Lab, Dragon's Lair), **flask shapes** (Classic, Potion Bottle,
  Round-Bottom, Conical: one silhouette for every flask of the board, same capacity, frames and tap areas) and
  **potion effects** when a flask is corked (Sparkles, Bubble Pop, Fireflies, Starburst; none with Reduce Motion).
  Rewards unlock by milestones, no currency; locked ones say how to earn them with your progress. Customer orders
  count like the chapter gate counts them: their stars and gold seals count, but finishing a chapter doesn't need
  them, so orders added to a finished chapter never take a theme back:

  | Reward | Milestone |
  |---|---|
  | Forest Hut | solve every recipe in Misty Marsh (ch. 3; customer orders not needed) |
  | Frost Lab | solve every recipe in Frost Peak (ch. 6; customer orders not needed) |
  | Dragon's Lair | solve every recipe in Dragon's Hoard (ch. 10; customer orders not needed) |
  | Potion Bottle | 100 stars in the chapters |
  | Round-Bottom Flask | 10 gold seals |
  | Conical Flask | 10 recipes in one Rush |
  | Bubble Pop | Daily Brew 3 days in a row (best streak) |
  | Fireflies | 400 stars in the chapters |
  | Starburst | 50 gold seals |

  A **New reward!** banner drops in when one unlocks (tap it to open Lab Style; it waits until a story scene is over). The choice is a setting
  (`settings.theme`, `settings.flaskShape`, `settings.potionEffect`); a choice that isn't unlocked shows the
  default. Announced rewards: `progress.rewardsAnnounced.v1`.
- **Tips:** the first time a recipe uses a mechanic (basic pouring, rune seals, murky potions, essence flasks, narrow
  necks, funnels, taps, frozen layers, bubbling flasks, twin flasks, pressure pipes, the mixing cauldron, switches and
  gates) the game shows a
  short illustrated tip drawn with the real flasks (2–3 steps, **Got it**). The **?** in the game's top bar (⌘/)
  shows the tips for the current recipe again. Seen tips are stored per mechanic (`TutorialStore`, UserDefaults).

## Layout

```
Pourfect.xcodeproj           Xcode project (one multiplatform app target: iOS 17+ / macOS 14+)
Pourfect/                    SwiftUI app
  Model/                     GameViewModel, LevelCatalog, ProgressStore, Tutorials, AppSettings, Palette, RandomLevelMaker
  Views/                     RootView, ChapterMapView (home), PackView (chapter / challenge recipes), ChallengesView,
                             GameView, TutorialOverlay, BottleView, RandomLevelView, PourAnimationView,
                             TiltedLiquid, FlaskDecor, GlassDecor, FrostDecor, BubbleDecor, LinkDecor, CauldronDecor,
                             SwitchDecor, WorkbenchBackground, SettingsView, AboutView
  Assets.xcassets            Optimized painted art (workbench backgrounds, chapter map, chapter vignettes)
  Localizable.xcstrings      English String catalog for all UI text; InfoPlist.xcstrings names the app
  Feedback/                  SoundEngine (synthesized sounds), Haptics, FeedbackPlayer
  PrivacyInfo.xcprivacy      Privacy manifest (no tracking, no collected data, UserDefaults CA92.1)
  Info-iOS.plist             iOS-only Info.plist keys (launch screen); everything else is generated
Packages/BottleSortCore/     Swift package — pure game logic, no UI imports
  Sources/BottleSortCore/    Model, Mechanics, Rules, StateKey, Solver, Difficulty, Generator, LevelFile, GameSession,
                             RandomLevel, Settings
  Sources/levelgen/          Command-line level generator
  Tests/BottleSortCoreTests/ Swift Testing suite
  Sources/Match3Core/        Ingredient gathering (match-3) rules, bots, daily (R9); Sources/m3gen its CLI
  Sources/DistilleryCore/    Distillery (R10): pipe flow, solver, generator, level format, daily; Sources/distillgen its CLI
  Sources/SecretRecipeCore/  Secret Recipe (R10b): recipe codes, feedback, game, candidates, daily, share, stats
  Sources/HiddenCore/        Hidden-object rooms (R11): scene files, placement + blending, rounds with decoys, hit tests
scripts/                     test-fast.sh (optimized core tests), testflight.sh + ExportOptions.plist (release upload),
                             appstore-caption.swift / appstore-flatten.swift (App Store screenshots)
docs/APP_STORE.md            Store category, age rating, privacy answers, size report, App Store Connect steps
Levels/chapter_0N.json       Main-path chapters 1–3; challenge_*.json: optional challenges (synchronized folder: every JSON file is bundled)
HiddenScenes/<room>/         Hidden-object rooms: scene.json, backgrounds, object PNGs (folder reference, bundled as is)
poc/hidden-object/           The rooms' art pipeline (Python scripts, libraries, spot lists; images not committed)
```

No third-party dependencies, only Apple frameworks.

## Run the app

**In Xcode:** open `Pourfect.xcodeproj`, choose the **Pourfect** scheme, then pick a destination:

- **My Mac** for the native macOS app, or
- any **iPhone / iPad simulator**,

and press **⌘R**. If Xcode reports a signing error, open the target's *Signing & Capabilities* tab
and pick your team (or *Sign to Run Locally* on the Mac).

**From the command line:**

```sh
# macOS
xcodebuild -project Pourfect.xcodeproj -scheme Pourfect -destination 'platform=macOS' build
# iOS Simulator
xcodebuild -project Pourfect.xcodeproj -scheme Pourfect -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Release builds

```sh
# Unsigned iOS Release archive only (nothing is signed or uploaded)
scripts/testflight.sh 7 --archive-only
# Archive, then sign (automatic, team MVC97L8VQ3) and upload to App Store Connect for TestFlight
scripts/testflight.sh 7
```

The argument is the build number (`CFBundleVersion`, must grow with every upload); the version comes from
`MARKETING_VERSION`. Output goes to a new temporary directory printed by the script. The export uses
`scripts/ExportOptions.plist` (method `app-store-connect`, destination `upload`, symbols uploaded) and the Apple ID
signed in to Xcode. Every DEBUG launch argument and demo hook is inside `#if DEBUG` and absent from a Release
binary (`strings` finds none of the `LP…` keys). Store metadata, age rating and privacy answers: `docs/APP_STORE.md`.

### How to play

- Tap or click a bottle to pick it up, then tap the bottle to pour into. Tap it again to put it down.
- You can pour onto an empty bottle or onto the same color, as long as there's room. The whole top run pours, or as much as fits.
- **Undo** (⌘Z), **Restart** (⌘R) and **Hint** (⇧⌘H) are at the bottom of the screen.
- Finish in the optimal number of moves for 3 stars, within 3 extra moves for 2 stars, and in any number of moves for 1 star.
  Clearing a recipe unlocks the next one in its chapter (and a cleared recipe always stays open); a chapter opens once the previous chapter has half of its
  stars. Progress is saved on the device.
- A pour is animated: the bottle flies over the target, tilts, and a stream fills the target. Taps made during
  a pour are queued. With *Reduce Motion* on, the levels just change in place.

### Modes

- **Classic**: chapter 1 (Apprentice Cellar), the challenges and random levels.
- **Rune seals / Locks & Keys** (chapter 2, the end of chapter 3, Master, random levels): a locked bottle shows a lock in its key's color and its contents are dimmed.
  It can't be poured from or into. A key is a dark layer with a key icon. It always moves alone, and only into the
  bottle with the matching lock. That bottle unlocks (the key drops into the lock and the lock pops off) and the key
  disappears. You win when every bottle is sorted, so all keys must be used.
- **Murky / Hidden layers** (chapter 3, Master, random levels): every layer below a bottle's top run is shown as a grey "?". A layer flips over
  to its real color once it becomes part of the top run, and stays revealed. Undo and restart restore the "?" layers.
  This is display-only; the rules and the solver see every layer.
- **Essence flasks** (chapter 4): a flask etched with one color's rune receives only layers of that color: no other
  color and no key (unless it is also sealed and the key is its own: the seal is handled first and opening it leaves
  the rune). It can always be poured from, and may start with other colors, which have to be poured out first. It
  counts as sorted like any flask (empty, or full with one color), so in practice it ends empty or full of its own
  color. An empty essence flask is not a free empty flask. In the app the flask's glass is faintly tinted in
  its color, and the color's rune is etched near the neck in a glowing ring (at rest, in flight, and
  in front of the stream that fills it, which makes it glow brighter). A refused pour shakes the essence flask,
  flares its rune, plays a low glassy hum and says "This essence flask only takes ⟨potion⟩" (also announced to VoiceOver; a full
  essence flask just refuses like any full flask). VoiceOver adds
  "essence flask, accepts ⟨potion⟩ only".
- **Glass flasks** (chapter 5; one of these per flask). A **narrow neck** pours exactly one layer per move, in or
  out, however long the run and however much room there is (a key through it moves as usual). A **funnel** receives
  normally but can never be poured from, so whatever goes in stays: it ends empty or full of one color. A **tap**
  pours from its *bottom*: the bottom run of identical layers (a key alone) leaves, as many as the target takes under
  the usual rules, and the stack above slides down; a tap never receives anything, not even a key, so it must be
  drained completely (or start sorted). In murky levels a tap's bottom run is in view too (it is what it pours),
  and hidden layers stay hidden as the stack slides down.
- **Frozen layers** (chapter 6; at most 2 per recipe). A frozen layer shows how many moves until it thaws (1–5).
  It and every layer below it can't move; layers above it pour normally. While the *top* layer is frozen nothing
  can be poured into the flask either (not even a key), and a tap flask can't pour at all while it holds ice. After
  every move (any pour, anywhere) each counter goes down by one; at 0 the layer thaws and is a normal layer. A
  recipe isn't won while ice remains, so sometimes a move elsewhere is needed just to wait. Undo restores the counters.
- **Bubbling flasks** (chapter 7; at most 2 per recipe). A bubbling flask pours and receives like any flask, but it
  has a period K (2–5): after every move (any pour, anywhere) its phase advances, and every K moves its *bottom*
  layer rises to the *top* of the same flask (after the pour has landed, and after any thaw). An empty, one-layer or
  one-color flask still counts but nothing visibly moves. A full one-color bubbling flask counts as sorted. It never
  carries a tap or ice (a seal or a rune is fine). In murky levels the risen layer is on top, so it is revealed.
  Undo restores the phases. On screen: bubbles rise through its potion (livelier one move before the rise), and a
  small brass dial under the flask lights one segment per move and shows the moves left; when the layer rises it
  swells into a big bubble that climbs through the stack after the pour lands, with a bubbly sound.
- **Twin flasks** (chapter 8). Two flasks joined by a silver chain share every pour *into* either of them: the
  pour is split evenly, k layers into each, taking 2k from the source's top run, where k = min(run / 2, free space
  of each twin). Both twins must take the color (empty or the same top; a rune, ice or tap on either one refuses as
  usual, a narrow neck lets one layer into its own twin). A single layer or a key can't be split, and one twin can
  never pour into the other; pours *out* of a twin are normal. Layers are conserved, so whatever goes into the pair
  must come out again: twins end empty (or start sorted). A twin is never sealed. Undo restores everything.
- **Pressure pipes** (chapter 8; link id `overflow`). A brass pipe runs from flask A's base to flask B's base. A
  pour into A follows A's usual rules (empty or the same color on top). If the run doesn't fit, each extra layer
  pushes A's bottom layer through the pipe into the bottom of B (the bottommost leaves first; B's stack rises, its
  top stays), as long as B has room; the rest of the run stays in the source. Colors (and keys) don't matter for a
  push. So a pour into a full A with the color on top is legal exactly when B has room. Pushes need both ends free
  of modifiers, never go into the source, and happen only for pours into A (one hop; a pour into B is ordinary). A
  pushed murky layer stays hidden at B's bottom. A flask is an end of at most one link (twin chain or pipe).
  Exactly, for a pour whose movable run is `r` layers (after every limit) into A with `f` free slots: `r ≤ f` is an
  ordinary pour. Otherwise `p = min(r − f, free space of B, layers in A)` of A's bottom layers go to B's bottom
  (the bottommost first, so B gets them in A's order under its own layers), A receives `f + p` layers and the
  remaining `r − f − p` stay in the source. If A and B are both full (`f = 0` and B has no room), the pour is refused
  (the pipe glints and says so). A push is forced: a pour that doesn't fit always pushes as far as it can.
  **Push preview:** while a flask is held, every pipe whose flask would push on a pour from it glows, light runs
  along it towards B and its arrow nudges (Reduce Motion: a steady glow), and a brass "+N" tag under B shows how
  many layers would be pushed (`Rules.push(of:in:)`); nothing shows when no pour would push. VoiceOver adds
  "pouring here pushes N layers into flask M" to the pipe flask's description.
- **Mixing cauldron** (chapter 9). A cauldron carries one or two recipes `X + Y → Z` (red + blue → purple). Inside
  it (and only there) a color may be poured onto its recipe partner: each poured layer mixes with one layer of the
  partner's top run into two layers of Z, so n poured layers on a run of m mix min(n, m) pairs:
  `[…, Y×m] + X×n → […, Y×(m−p), Z×2p, X×(n−p)]`, p = min(n, m); unmixed poured layers stay on top, the rest of the
  run stays below. The usual limits apply (free space, a narrow neck or tap on the source); layers are conserved.
  Nothing chains (a recipe's result is never another recipe's ingredient), the result never mixes again by itself,
  and a cauldron never starts with an ingredient directly on its partner. Pours out of a cauldron, onto the same
  color or into an empty cauldron are normal. Since mixing changes how many layers each color has, a cauldron
  level only needs mixing amounts after which every color has 0 or a flask's worth of layers; the win is standard
  (a cauldron ends empty or full of one color). A cauldron carries no other modifier and no link. Undo restores the
  unmixed layers. The mix is part of the pour (before thaw and bubbling) and reported as `TurnEvent.mixed`. On
  screen: the cauldron's glass stands in a wide iron pot on two legs over glowing embers, with a thick rim and ring
  handles, and a parchment card under it shows each recipe as potion drops with runes (X + Y → Z). After a mixing
  pour lands, the two ingredients swirl into each other, the new potion blooms from the middle, bubbles rise, a puff
  of its color leaves the mouth and the recipe glows on the card, with a stirring, bubbling sound and a soft chime
  (Reduce Motion: a cross-fade). A cauldron the mix fills is corked, and the win card shown, once the swirl settles.
- **Switch flasks and gates** (chapter 10). A brass lever joins a *switch* flask to a *gate* flask. While the switch
  is complete (full with a single color, and counted as sorted: no seal and no ice on it) the gate is open and works
  like any flask; otherwise the gate is closed and nothing can be poured into or out of it (its layers stay where they
  are, a key can't reach its seal either). The gate's state is never stored: it is read from the switch every time,
  so it opens the moment a pour completes the switch (or a key unseals a full switch, or the switch's last ice thaws)
  and closes the moment a pour takes potion out of the switch. The switch itself is an ordinary flask, and it may
  even pour into its own open gate (which then closes behind that potion). The win is standard: every flask, the
  gate included, must end sorted, so a gate holding potion has to be opened at some point. Each flask is an end of
  at most one link (a switch drives one gate, a flask is never both, and no switch carries a tap). Turn events:
  `TurnEvent.gateOpened(switch:gate:)` / `.gateClosed(switch:gate:)`, after the pour's `.mixed` (step 2) or after
  the thaw / bubbling that caused them (step 5). Undo restores everything (nothing new is stored).
  On screen: the switch wears a gem in a brass mount on its shoulder (dark while off, glowing gold while it is full of
  one potion), a brass rod with a red-knobbed lever arches from it to a brass housing above the gate's mouth, and a
  shut gate has an iron portcullis hanging over its mouth. When a pour lands that fills the switch, the gem lights,
  the lever swings over towards the gate and the bars slide up into the housing with a ratchet and a clank; when a
  pour empties the switch they drop back with a heavier clank (Reduce Motion: the bars fade). A gate opened by a thaw
  or a mix on its switch waits for that to play. Picking up a shut gate, or pouring into one, shakes it, rattles the
  bars and says "The gate is shut. Fill flask N with one potion to open it." VoiceOver names each switch and gate and
  announces gates opening and shutting.
- **Customer orders** (R7, the last three recipes of chapters 2–10). A villager card above the board shows the
  customer (one of six portraits, always the same one for a recipe), what they want ("Mira needs a flask of Dragon's
  Blood") and the wanted potion drops with their runes. The ordered flask carries a paper ticket in that potion's color;
  the recipe is won when every ordered flask holds its order (no seal or ice on it) and every other flask is sorted as
  usual, so a finished flask of the right potion may still have to move into the ordered flask. A **layered recipe**
  (from chapter 4) asks for an exact pattern, bottom to top, drawn as stacked chips on the ticket; its flask can only
  keep a bottom part of what it holds and top it up, and the rest of each potion must be gathered in one flask (a
  partly used potion ends partly filling one flask). When a pour lands that fills an order, its tick pops in on the
  ticket and the card with a shop bell (Reduce Motion: no bounce); undo takes it off again. VoiceOver reads "order
  flask, wanted: 4 layers of Dragon's Blood" and "order filled". Tips explain orders and layered recipes the first
  time they appear ("?" reopens them).

### Random Brew (random levels)

Open **Challenges** (trophy) from the chapter map and tap **Random Brew**. Pick a mode, the number of
colors (2–12), the flask size (2–6), empty flasks (0–4) and, in Rune Seals (locks & keys), the number of seals (1–2), then
**Brew**. The settings are remembered.

The level is generated off the main thread with a fresh random seed. Up to 6 candidates are tried ("Attempt k of 6");
a candidate is rejected if a bottle is already sorted or the solver can't prove it solvable within 1M states
(no time limit, so a seed gives the same level on every device).
If all 6 fail you get "Couldn't brew a solvable recipe in 6 tries — try more empty flasks or fewer potions".
Boards with no empty bottle are almost always unsolvable. Random levels are played in the normal game screen
(Hint and stuck detection included). They don't change saved progress, and the win card offers
**New Random Brew** with the same settings instead of *Next Recipe*.

### Theme, art and strings

- **Art:** the game screen stands on the painted workbench (`bg_workbench_landscape` for wide windows,
  `bg_workbench_portrait` for tall ones), dimmed in the middle so the flasks read clearly; the Challenges list has a
  blurred, washed copy. Both come from `WorkbenchBackground(style: .game / .menu)`. The chapter map
  (`chapter_map`) is the home screen; the chapter vignettes (`chapter_01`…`chapter_10`) are the map buttons and the
  chapter headers. `PaintedBackdrop(image:)` blurs any painting into a backdrop.
  These are JPEG copies made with `sips` from the full-resolution originals in `Art/` (kept local, see
  `Art/README.md`); about 6 MB in total. R7 adds the three theme paintings (`theme_<name>_landscape`
  2752 × 1536 and `_portrait` 1179 × 2752, JPEG quality 72, ≈ 3.6 MB) and the six story portraits (512 px PNG with
  transparency, ≈ 1.7 MB). The six villager portraits are 256 px (shown at 58 pt at most).
- **App icon and launch:** `AppIcon` holds the approved `Art/icon/app_icon_candidate.png` as the full-bleed iOS
  1024 px icon (the system masks it) and as the Mac sizes 16–1024 px drawn on Apple's grid (824 px rounded-rect body
  with a 100 px margin and a soft shadow, as macOS expects). The iOS launch screen is a plain colour
  (`LaunchBackground`, a dark workbench brown) from `UILaunchScreen` in `Pourfect/Info-iOS.plist` (merged into the
  generated Info.plist on iOS only).
- **Flask shapes:** `FlaskShape(style:)` (`Cosmetics.swift`) draws the body inside the flask's unchanged frame; every
  fill, outline and clip of a flask goes through it (`BottleView.shape(width:style:)`, `.flaskClip(width:)`), the
  narrow neck rises from the shape's mouth, the rim and cork follow the mouth, and the pour leaves from the mouth's
  lip.
- **Potion names:** the 12 palette colors have potion names (`Palette.potionNames`, e.g. Dragon's Blood,
  Mermaid Teal) and the key metals have names (`Palette.keyNames`); VoiceOver reads a flask as
  "Flask 3, 2 Dragon's Blood, Moonshade, corked".
- **Strings:** SwiftUI `Text`/`Button`/`Label` literals are localized automatically; every other user-facing
  string uses `String(localized:)`, and numbers-only text uses `Text(value, format: .number)` or
  `Text(verbatim:)`. Xcode adds new keys to `Localizable.xcstrings` when you build in the IDE; a command-line
  build does not, so after adding UI text from the command line, build in Xcode once (or merge the build's
  `*.stringsdata` into the catalog) before committing. Plural forms are catalog variations.

### Debug launch arguments

DEBUG builds accept these (set them in *Edit Scheme ▸ Run ▸ Arguments*, or pass them to `simctl launch` / `open --args`):

| Argument | Effect |
|---|---|
| `-LPOpenChapter N` | Opens chapter N's recipe list (works for locked chapters). |
| `-LPOpenChallenge NAME` | Opens a challenge book: `challenger`, `expert` or `master` (file or display name). |
| `-LPOpenChallenges 1` | Opens the Challenges area. |
| `-LPOpenLevel N` | Opens recipe N (1-based) directly, ignoring locks: of `-LPOpenChapter` / `-LPOpenChallenge` if given, else of pack `-LPOpenPack`. |
| `-LPOpenPack P` | With `-LPOpenLevel` alone: pack by position, chapters first, then challenges: 1…C = chapters 1…C, then Challenger, Expert, Master (with 4 chapters: 5, 6, 7; default 1). |
| `-LPUnlockAll 1` | Opens every chapter on the map and every recipe in the grids (saved stars are untouched). |
| `-LPResetTutorials 1` | Forgets which tips were seen (at launch), so they show again. |
| `-LPSkipTutorials 1` | Never shows a tip on its own this run (nothing saved); for screenshots. |
| `-LPTutorialPage N` | Opens tips on step N (1-based). |
| `-LPShowStory N` | Plays chapter N's story scene at launch (`-LPShowStory ending`: the ending), over whatever else opens. |
| `-LPStoryLine K` | With `-LPShowStory`: opens the scene on line K (1-based). |
| `-LPResetStory 1` | Forgets which story scenes were played (at launch), so they play again. `-LPSkipTutorials 1` also keeps scenes from starting on their own. |
| `-LPOpenLabStyle 1` | Opens Lab Style (the rewards) at launch. With `-LPUnlockAll 1` every reward is unlocked (and none is announced). |
| `-settings.theme T` / `-settings.flaskShape S` / `-settings.potionEffect E` | Picks a cosmetic: `workbench`, `forestHut`, `frostLab`, `dragonLair` / `classic`, `potionBottle`, `roundBottom`, `conical` / `sparkle`, `bubbles`, `fireflies`, `starburst` (only shown when unlocked, e.g. with `-LPUnlockAll 1`). |
| `-LPMapAnchor Y` | Opens the chapter map scrolled to height Y (0 = top / dragon, 1 = bottom / cellar). |
| `-LPDemoMoves K` | Auto-plays the first K optimal moves through the normal tap path (with the pour animation). A demo win saves no stars and no daily result. |
| `-LPDemoUndo N` | After `-LPDemoMoves`: undoes N moves, one per second. |
| `-LPDemoRefuse S` | After `-LPDemoMoves` (or at once), waits S seconds and tries a pour a flask refuses: an essence, tap or frozen-over flask (flare, message, sound), else picks up a filled funnel flask, else a pour a twin chain or a shut gate refuses (picking up a shut gate). |
| `-LPDemoIcePour S` | After `-LPDemoMoves` (or at once), waits S seconds and plays a legal pour out of a flask that holds ice (the potion above the ice pours, the ice stays pinned). |
| `-LPDemoSelect N` | After `-LPDemoMoves` / `-LPDemoUndo`, picks up flask N (1-based in the shuffled level); `-LPDemoSelect push` picks up the first flask whose pour into a pressure-pipe flask would push (to see the push preview; e.g. chapter 8 recipe 13). |
| `-LPDemoLinkPour S` | After `-LPDemoMoves` (or at once), waits S seconds and plays a pour that uses a link (a push through a pressure pipe, else a split between twins; e.g. chapter 8 recipe 13). |
| `-LPSlowMotion F` | Plays the pour, thaw, bubble-up, cauldron mix and gate animations F times slower (F ≥ 1), to look at single frames. Sounds keep their normal timing. |
| `-LPRandomSettings 1` | Opens the Random Brew screen (inside Challenges). |
| `-LPRandomGenerate 1` | With `-LPRandomSettings 1`: presses *Generate* once. |
| `-LPRandomMode classic\|locks\|hidden` | Generates a random level with the saved settings and opens it. |
| `-LPRandomSeed S` | Seed for `-LPRandomMode` (default 1), so the same level comes back every time. |
| `-LPOpenRush 1` | Opens Challenges and starts a Rush run. |
| `-LPRushSeed N` | Seed of the Rush run (else a random one), so the same recipes come back. |
| `-LPRushDuration S` | Rush starts with S seconds instead of 180 (e.g. 12 to see the end card). |
| `-LPRushAutoplay 1` | Every Rush recipe plays itself (like `-LPDemoMoves 99`); the run's result is not saved. |
| `-LPOpenDaily 1` | Opens the Daily Brew screen. |
| `-LPPlayDaily 1` | Opens the Daily Brew screen and starts today's puzzle (once it is generated). |
| `-LPDailyDate YYYY-MM-DD` | Pretends today is that UTC date (the clock is shifted by whole days, so the countdown and "solved today" still work). Results stay in memory only. |
| `-LPDailySeedResults N` | Adds fake results for the N days before today (a few gaps, mostly perfect, a 5-day run ending yesterday), for calendar screenshots. Results stay in memory only: nothing is saved and the real history is untouched. |
| `-LPOpenMatch3 ID` | Opens an ingredient-gathering (match-3) level by id (`m3-03-2`), or `daily` (today's daily match-3) / `daily-YYYY-MM-DD`. |
| `-LPM3Demo K` | With `-LPOpenMatch3`: plays K greedy-bot moves through the normal swap path, with the animations (a demo win saves nothing). |
| `-LPM3Seed S` | With `-LPOpenMatch3`: replaces the level's seed (another start board and refill stream). |
| `-LPM3Moves N` | With `-LPOpenMatch3`: replaces the move limit (e.g. 3 with `-LPM3Demo 3` to reach the "Out of moves" card). |
| `-LPOpenDistill ID` | Opens a distillery level (R10) by id (`d1-07`, `dx-03`, `dm-12`), `random` (with `-LPDistillTier gentle\|tricky\|fiendish` and `-LPDistillSeed S`), `daily` (today's Daily Distillery) or `daily-YYYY-MM-DD`. |
| `-LPDistillDemo K` | With `-LPOpenDistill`: plays K solver taps (the fewest-taps path, one every 0.45 s) through the normal tap path, with the animations (a demo win saves nothing). |
| `-LPOpenDistillStage N` | Opens distillery stage N's level list (1–3; its story scene plays the first time unless `-LPSkipTutorials 1`; add `-LPUnlockAll 1` to open its levels). |
| `-LPOpenDistillPack P` | Opens a distillery pack's level list: `stage1`…`stage3`, `expert` or `master` (the challenge packs inside Challenges). |
| `-LPOpenDistillRandom 1` | Opens Random Distillery (inside Challenges). |
| `-LPOpenDistillDaily 1` | Opens the Daily Distillery screen (from the daily hub); `-LPPlayDistillDaily 1` also starts today's level. `-LPDailyDate` and `-LPDailySeedResults` apply to it too (memory only). |
| `-LPOpenDailyHub 1` | Opens the daily hub ("Today": every daily game). |
| `-LPShowStory distillery.N` | Plays distillery stage N's story scene. |
| `-LPOpenEpisode N` | Opens ingredient-gathering episode N's level list (its story scene plays the first time unless `-LPSkipTutorials 1`; add `-LPUnlockAll 1` to open its levels). |
| `-LPOpenRecipe daily\|practice\|stats` | Opens today's Secret Recipe game (`daily`, over the daily hub and its daily screen), a practice recipe (`practice`, inside Challenges) or the daily screen (`stats`). `-LPDailyDate` and `-LPDailySeedResults` apply to it too (fake games, memory only). |
| `-LPRecipeSeed N` | With `-LPOpenRecipe practice`: the practice seed (else a random one), so the same recipe comes back. |
| `-LPRecipeDemo K` | With `-LPOpenRecipe`: plays K guesses through the tray (each one still possible after the drops so far). Nothing is saved: the daily runs on a memory store. |
| `-LPOpenM3Daily 1` | Opens the Daily Gathering screen; `-LPPlayM3Daily 1` also starts today's level. `-LPDailyDate` and `-LPDailySeedResults` apply to it too (fake wins, memory only). |
| `-LPShowStory gathering.N` | Plays gathering episode N's story scene (like `-LPShowStory N` for chapters). |
| `-LPOpenSettings 1` | macOS: opens the Settings window at launch. |
| `-LPWindowSize WxH` | macOS: sets the main window's frame to W × H points (title bar included) and centers it, for App Store screenshots (e.g. `1120x700`, 16:10). |
| `-LPOpenAbout 1` | macOS, with `-LPOpenSettings 1`: also opens the About sheet. |
| `-LPExportSounds DIR` | Writes every synthesized sound to `DIR` as WAV files (to listen to or inspect them). |
| `-settings.colorRunes 1`, `-settings.sound 0`, `-settings.reduceMotion always\|never\|system` | Override a setting for this run (not saved unless changed in Settings). |
| `-random.colors N`, `-random.capacity N`, `-random.empty N`, `-random.locks N`, `-random.mode M` | Override the saved Random Brew settings for this run (`M` = `classic`, `locksAndKeys`, `hidden`). |

Example: `xcrun simctl launch <device> <bundle id> -LPRandomMode locks -LPRandomSeed 5 -random.colors 6 -random.locks 2`.
Daily win card: `open -n Pourfect.app --args -LPDailySeedResults 40 -LPPlayDaily 1 -LPSkipTutorials 1 -LPDemoMoves 99`.
Gold-seal win card: `-LPOpenChapter 1 -LPOpenLevel 3 -LPDemoMoves 99 -LPSkipTutorials 1` (a demo win saves nothing).
Story scene: `-LPShowStory 5 -LPStoryLine 2`. Themed board mid-pour: `-LPUnlockAll 1 -LPSkipTutorials 1 -LPOpenChapter 1 -LPOpenLevel 3 -LPDemoMoves 99 -settings.theme dragonLair -settings.flaskShape conical -settings.potionEffect starburst`.
Rush end card with a new best: `-LPOpenRush 1 -LPRushSeed 42 -LPRushAutoplay 1 -LPRushDuration 14 -rush.best.v1 0`.
Saved progress can be faked for one run through the argument domain (nothing is written), e.g.
`-progress.goldSeals.v1 '(p1_001,p1_002)' -progress.bestStars.v1 '<dict><key>p1_001</key><integer>3</integer></dict>'`.
On the Mac, if a killed debug run left no window to restore, add `-ApplePersistenceIgnoreState YES`.

## Run the tests

```sh
scripts/test-fast.sh                     # optimized build, the suite runs in ~2-3 s (plus ~15-50 s to compile)
scripts/test-fast.sh --filter Cauldron   # only matching tests
cd Packages/BottleSortCore && swift test # debug build, ~80 s — run once before committing
LP_SLOW_TESTS=1 scripts/test-fast.sh     # also the slow performance tests (60 days of Daily generation)
scripts/test-fast.sh --filter Match3CoreTests   # only the match-3 suite (~2 s)
scripts/test-fast.sh --filter DistilleryCoreTests   # only the distillery suite (~3 s)
scripts/test-fast.sh --filter HiddenCoreTests   # only the hidden-object suite (< 1 s)
```

The distillery suite (`Tests/DistilleryCoreTests`) covers the flow of every piece, murk, leaks, valves and coils,
taps/undo/stars, the solver against brute force on 300 random tiny boards, the generator, every shipped level
(valid, one solved network, its recorded `minTaps`), packs regenerating byte-identically and daily goldens; the heavy
parts run optimized, and in a debug `swift test` only with `LP_SLOW_TESTS=1`.

The match-3 suite (`Tests/Match3CoreTests`, 70 tests) covers every match shape and where its special goes, each
special and combo, frost, crates, flasks, gravity behind crates and across holes, the refill order from the seed,
cascades and their multiplier, identical results for identical swaps, reshuffles, hints, goals, stars, the finale, the
JSON round trip, every validation error, start boards, the shipped episodes, bots and the tuner, the progression rules
and daily goldens. Its bot-heavy tests (daily goldens, pass-rate sample, preset re-tuning) run in the optimized
`scripts/test-fast.sh`; in a debug `swift test` they are skipped unless `LP_SLOW_TESTS=1`.

Debug builds make the solver 30–40× slower, so iterate with `scripts/test-fast.sh` and do one debug `swift test` at the end.
The 60-day Daily performance test is opt-in (`LP_SLOW_TESTS=1`); run it when Daily, generator or solver code changes.

A full `swift test` runs 678 tests in five suites: 516 in `BottleSortCoreTests`, 70 match-3, 47 distillery, 23
Secret Recipe and 22 hidden-object. The sorting suite covers the rules (including every key and lock rule), undo/restart, hidden layers,
validation, the solver (cross-checked against a naive BFS on 125 random puzzles and 175 random lock levels),
hints, canonical keys, difficulty metrics, the generator's determinism, random levels, the JSON format and pack metadata,
the chapter gate (including the exact-50 % boundary), the lock-impact check, the daily puzzle (UTC dates seen from
UTC+14 and UTC−12, leap days, a golden level, 60 days of generation) and streak rules, and the shipped files (every level
loads and validates, ids are unique across files, chapter 1 keeps the Starter ids, chapters have the expected
shape, every lock in a chapter matters, and every level whose recorded search is small solves in its recorded
`minMoves` — the larger ones are re-solved by `levelgen --report` in release). The mechanics architecture has its own
tests: the modifier pipeline, the `.sealed` modifier against a copy of the old lock rules (same legal moves and
results on up to 720 lock states), StateKey v2 (permutation invariance with modifiers, links and goal targets), JSON v1/v2
round trips, `MechanicImpact`, and golden fingerprints that pin generator, random-level, solver and canonical-key
output to what they were before the refactor (every shipped file also re-encodes byte for byte). Essence flasks
have their own suite: every rule case (with seals), a hand-made puzzle the rune makes longer, the solver against the
naive BFS on 175 random essence levels (with seals too), pruning that keeps every distinct child, permutation-invariant
keys, the JSON round trip, validation, undo/restart, the generator options (murky placement reads no hidden layer),
and chapter 4 (every rune and seal matters). Glass flasks (narrow neck, funnel, tap) have one too: every rule case
(bottom runs, keys, partial pours, refusals, pour events), hand-made puzzles where the neck costs a move and the tap
drains from the bottom, a funnel trap, the solver against the naive BFS on 250 random glass levels (with seals and
runes), safe pruning, canonical keys, JSON, validation, undo/restart with murky masks that follow a tap drain, the
generator options, and chapter 5 (every glass flask, seal and rune matters). Frozen layers have one as well: every
rule case (layers above the ice, ice on top, taps, keys, narrow necks, the thaw step and its turn events, no win
under ice), hand-made puzzles that need waiting moves, the solver against the naive BFS on 250 random ice levels,
pruning that keeps every child while ice remains, keys with counters, JSON, validation, undo/restart restoring the
counters, murky masks, the generator options, and chapter 6 (every frozen layer adds 2+ moves). Bubbling flasks too:
every rule case (phase, rise after the pour, after the thaw, keys, no win change, refused moves don't tick), a
hand-made puzzle that can only be solved with the rise and one the rise makes longer, the solver against the naive
BFS on 250 random bubbling levels, pruning that keeps every distinct child, keys with period and phase, JSON,
validation, undo/restart restoring the phases, murky masks that follow a rise, the generator options and tutorial
checks, and chapter 7 (every bubbling flask changes the optimum by 2+ moves). Twins and pressure pipes
(`LinkTests.swift`): every rule case (even split, free space and per-twin limits, refusals, keys, taps, runes and
ice on a twin; ordinary pours into a pipe flask, pushes one by one, a full flask pushing while the far end has
room, the pipe refusal, keys pushed, plain ends only, one way, one hop, no push into the source, seals), hand-made
puzzles that need a split or a push, the solver against the naive BFS on ~700 random linked levels (also with
modifiers on linked flasks; the pipe configurations push > 1,000 times), pruning that keeps every distinct child,
the linked key fast path against the general encoding, JSON, validation, undo/restart, murky masks for every
landing and push, the generator options (pipes must save 2+ moves) and tutorial checks, and chapter 8 (every link
matters, every pipe recipe's optimal solution pushes). Cauldrons (`CauldronTests.swift`): every rule case (pairs, leftover,
free space, either ingredient poured, no recipe, keys, only inside the cauldron, pouring out, no chaining, taps,
narrow necks, seals, the mix before thaw and bubbling, win), the pure helpers against the rules, a hand-made puzzle
that needs the cauldron, the solver against the naive BFS on random cauldron levels (and positions after a move),
backwards-built levels solvable, pruning that keeps every distinct child (rule 1 off), keys with recipes, JSON,
validation, undo/restart, murky masks, the generator options, and chapter 9 (every recipe has to mix, and an optimal
solution brews exactly the pairs the counts call for). Switches (`SwitchTests.swift`): every rule case (closed gate
both ways, opening and closing with events, the switch pouring into its open gate, a sealed or iced switch opening
on unseal or thaw, a key kept out of a closed gate, modifiers on both ends, the standard win, refusals, helpers), a
hand-made puzzle that needs the switch and one a gate makes unsolvable, the solver against the naive BFS on random
switch levels (and positions a few moves on, with seals, runes, necks, ice, bubbling and twins), pruning that keeps
every distinct child, permutation-invariant keys that tell the lever's direction, JSON, validation, undo/restart,
murky masks, the generator options and placements, switches beside pressure pipes (no flask in both, the shut gate named
as the reason), and chapter 10 (every switch adds 2+ moves, an optimal solution
opens a gate, the finale is the hardest of the main path, the two cauldron recipes mix by counting and their optimal
solution both brews and opens the gate); the backwards cauldron walk places switches after its seals without changing
the walk. Challenge modes (`ChallengeTests.swift`): the gold seal rule (minimum, no hint, always with three stars) and
counts, the main-path gate reading only chapter recipe ids (three-starred challenge, Rush, random and daily ids open
nothing), the Rush clock (bonus, penalty, end), the best-score record, the unlocked mechanics, the Rush plan
(deterministic, difficulty only rises, no mechanic twice in a row, every unlocked one within a round) and every
recipe of a run valid and solvable in its stored minimum with its mechanic; the slow suite generates 300 Rush
recipes and checks each takes under 2 s (worst ≈ 0.3 s in release).
Customer orders (`OrderTests.swift`): every order and layered-recipe win case (wrong flask, seal or ice on the
target, unsorted rest, split remainder, keys), partial orders, sessions and turns through the goal, the solver against
the naive BFS on random small order and layered levels with every mechanic, pruning that keeps every distinct child (a
finished flask still moves into the flask that ordered it, an ordered twin), permutation-invariant keys that tell the
marks apart, JSON, validation, generator placement, determinism and must-matter, the bonus-recipe gate, and the 27
shipped order recipes (appended last, valid, not met at the start, solving in their recorded minimum, the goal
mattering; chapter 2's first a tiny tutorial; layered from chapter 4).
Rewards and story (`RewardsTests.swift`): one
starter per category, thresholds, finishing a chapter needs every own recipe (customer orders are bonus: their
stars count, finishing doesn't need them), only main-path stars and shipped seals count, announcements once and in order, locked choices fall back to the starter, every threshold reachable in the
shipped game, the cosmetic settings round trip (old saves load the defaults), and when story scenes play (the
ending after Dragon's Hoard's last own recipe, not its bonus orders).
You can also run them in Xcode by opening `Packages/BottleSortCore/Package.swift` and pressing ⌘U.

## Ingredient gathering (match-3, R9)

Optional match-3 **episodes**, one after each sorting chapter: the apprentice and the alchemist gather ingredients
for the next chapter. Swap two neighbouring ingredients to line up three or more of one kind; reach the goals
within the move limit. Out of moves → retry for free (no lives, no energy, no purchases). The rules are in the
`Match3Core` library of the same package (pure Swift, no UI frameworks); `m3gen` is its tool. Rules as implemented:
DECISIONS 251–263.

| File (`Levels/match3/`) | Episode (after chapter) | Ids | Levels | Moves | Target pass rate | What it adds |
|---|---|---|---|---|---|---|
| `gathering_01` | 1 Mushroom Hollow | `m3-01-1…8` | 8 | 17–26 | 90 → 87 % | Swapping and collecting; 4 kinds, then 5; a score goal |
| `gathering_02` | 2 Crystal Grotto | `m3-02-…` | 8 | 22–26 | 86 → 83 % | Specials from 4/5/L/T matches, shaped boards, three collect goals |
| `gathering_03` | 3 Moonlit Meadow | `m3-03-…` | 8 | 18–24 | 83 → 80 % | Frost (one layer, then two) |
| `gathering_04` | 4 Ember Hearth | `m3-04-…` | 8 | 18–29 | 79 → 76 % | Double frost, frost rows |
| `gathering_05` | 5 Sealed Storeroom | `m3-05-…` | 8 | 18–37 | 76 → 73 % | Sealed crates (1–3 hits), crates with frost |
| `gathering_06` | 6 Icefall Ridge | `m3-06-…` | 8 | 20–29 | 72 → 69 % | Frost and crates together, 6 kinds |
| `gathering_07` | 7 Bogwater Springs | `m3-07-…` | 8 | 21–37 | 69 → 66 % | Potion flasks to bring down; with frost or crates |
| `gathering_08` | 8 Windy Rookery | `m3-08-…` | 8 | 23–34 | 65 → 62 % | Flasks, crates and frost mixed |
| `gathering_09` | 9 Alchemist's Garden | `m3-09-…` | 8 | 18–34 | 62 → 59 % | Everything, 6 kinds |
| `gathering_10` | 10 Dragon's Larder | `m3-10-…` | 8 | 26–38 | 58 → 55 % | Everything, hardest |

The target is the pass rate of the reference bot (greedy with 15 % random slips): 90 % for the first level, falling
linearly to 55 % for the 80th. The app loads them separately from the recipe packs (`Match3Library`, every
`gathering_*` file in the bundle; the recipe catalog still reads only `chapter_*`, `challenge_*` and `pack_*`).

**On the chapter map** (`Pourfect/Match3/`, DECISIONS 264–268):

- Each episode is a small ingredient-basket token on the path between chapter N and N + 1 (`EpisodeArt.mapSpots`;
  episode 10 up in the tower above Dragon's Hoard), with its stars, a check when every level is won (gold ring at
  all stars), or a lock and "Gathering N" (tapping a locked one, or its tooltip on the Mac, says when it opens). **How episodes unlock:** episode N (1–9) opens together with sorting
  chapter N + 1; episode 10 opens once chapter 10's last own recipe (not a customer order) is brewed. Levels inside
  an episode open in order (level 1 at once, each next one after the previous is won). Episodes never block a
  chapter, and their stars never count towards a chapter gate, a milestone or a reward. With `-LPUnlockAll 1`
  every episode and level is open.
- The episode screen (`EpisodeView`): header with the next chapter's painting ("Supplies for Glyph Library"), the
  episode's subtitle, a basket of its ingredients and its stars, then its eight levels (number, stars and an icon of
  the main goal; locked ones show a lock). The toolbar's **Story** button replays its scene.
- Story: the first time an episode opens, a short scene (`StoryScene.gathering(N)`, the R7 story system with the
  same portraits) tells what the two gather and for which place: glowing mushrooms to light the Rune Vault, crystals
  to see through the marsh mist, moonflowers to read faded glyphs, embers for the glass furnace, … a sleeping
  draught for the dragon. Seen scenes go into the same `progress.storySeen.v1` set (`gathering.N`).
- Progress: `Match3ProgressModel` keeps best stars and scores in `m3.bestStars.v1` / `m3.bestScore.v1` (keyed by the
  `m3-…` ids); older saves simply have none.
- Tips (`M3Tips`, shown in the same `TutorialOverlay` as the sorting tips, with drawn ingredients): *How to gather*
  (swap and match, goals, moves and free retry) on the first level; *glowing specials* (comet, bloom, prism, mixing
  two specials) from episode 2 and in the daily; *frost*, *sealed crates* and *potion flasks* on the first level
  that has them. Seen-state per topic in `tutorial.seen.m3.*`; **?** (⌘/) in the level reopens every topic of that
  level. The idle hint glow waits while a tip or story scene is open, and its 5 s start over when it closes.
- **Daily Gathering** (`M3DailyModel`, `M3DailyViews`): a row of the map's **Today** card and of the daily hub (R10). Its screen shows today's
  weekday · flavour (Gentle, Steady, Frosty, Sealed Crates, Flask Drop, Tricky, Grand Gathering) with difficulty
  pips and the day's ingredients, **Play** / **Replay**, the current and best streak, days gathered, three-star
  days, and the month calendar (won days amber, three-star days gold). The level is built off the main thread
  (`M3Daily.level`, cached per day). The first win finished on its UTC day counts (`DailyStreaks`, kept in
  `m3daily.history.v1`, details in `m3daily.details.v1`); three stars is a "perfect" day. Share text (no board):
  `Pourfect Gathering — 17 Nov ★★☆ 12 moves left` (moves left at the win, before the finale). The Daily Brew and
  its history are untouched.

**Board screen** (`Pourfect/Match3/`):

- `MatchGameView`: HUD (moves left, goals with ingredient / frost / crate / flask icons and counters, score with
  marks at the two- and three-star thresholds), the board, the win card (stars, score, Retry / Map / Next Level) and
  the "Out of moves" card (free Retry, Map). Best stars and score per level go to `m3.bestStars.v1` /
  `m3.bestScore.v1` (`Match3ProgressModel`), apart from the sorting chapters' stars. A daily level's win card adds
  the Daily Gathering streak and **Share**; its Back button returns to the Daily Gathering screen.
- `MatchBoardView`: tray following the cell mask, sealed crates (wood with the rune-key seal of `BottleView`, metal by
  hits left: copper 1, steel 2, gold 3), pieces, flasks, selection ring, idle hint glow (after 5 s, `M3Game.hint()`,
  free) and effects. Input: drag a piece onto a neighbour (touch or mouse), or tap / click one piece, then a
  neighbour. A swap that makes no match slides back with a soft knock; a frozen piece, crate or flask leans and comes
  back. VoiceOver: a board summary, every cell's content, and Swap up / down / left / right actions; a refused or
  matchless swap, the moves and goals after each swap, a reshuffle, the finale, the win and "Out of moves" are
  announced.
- `IngredientArt`: the six ingredients drawn with paths, each with its own silhouette, palette color and that
  color's rune (Color Runes setting): mushroom red ▲, crystal cyan ◆, feather yellow ★, moonflower purple ☾, ember
  orange ⚡, potion drop blue ∿. Comets carry a glowing trail with arrowheads in their direction, blooms a halo with a
  ring of sparks, prisms are rainbow gems. Frost is a see-through ice cover in the Frost Peak colors (two layers:
  thicker, with a crystal showing 2).
- `MatchBoardModel`: plays a swap on `M3Game` at once, then animates its `M3StepResult` phase by phase in the core's
  order: swap; per wave squash of the matched pieces, prism conversions, matched pieces popping with sparkles,
  specials firing in order (comet beam, bloom burst, prism rays, board flash) with what each reaches popping right
  after, frost cracking, crates splintering, new specials growing in, the wave's score floating up; settles (falls
  and new pieces dropping from above their column with a slight bounce); flasks collected; the reshuffle swirl.
  After a win, "Bubbling Over!" turns each move left into a firing special; the core plays the finale and the win
  (stars, best score, next level, Daily Gathering day) is saved before it is animated, so leaving mid-finale keeps it. Input is locked while anything animates;
  after each step the tokens are compared with the game's board and rebuilt from it if they ever differ. Reduce
  Motion: no travel, short fades. `-LPSlowMotion F` slows it down.
- Sounds (synthesized in `SoundEngine`, with their own noise stream so older sounds are unchanged): match pops
  climbing a pentatonic scale with each cascade, swap swish, special whoosh, ice crack, crate knock, flask chime,
  special sparkle; haptics on iOS.

**Format** (`format: "pourfect-match3"`, `version: 1`): `episode {number, name, subtitle, followsChapter}` and
`levels`, each with `id`, `title`, `seed` (< 2^53; drives the start board, every refill and every reshuffle),
`layout` (rows top first, ≤ 8×8: `.` hole, `o` seeded piece, `1`/`2` seeded piece under 1/2 frost layers, `A`/`B`/`C`
crate with 1/2/3 hits, `F` potion flask), `kinds` (3–6 of `mushroom crystal feather moonflower ember drop`), `moves`,
`goals` (`{"type":"collect","kind":…,"count":N}`, `{"type":"frost"}`, `{"type":"crates"}`, `{"type":"drops","count":N}`,
`{"type":"score","count":N}`), `stars {two, three}` (score thresholds; one star = goals met), optional `drops
{total, maxOnBoard, columns}`, optional `pieces [{row, col, kind, special}]` (placed instead of seeded; specials
`row`, `column`, `bloom`, `prism`) and optional `tuning {target, passRate, runs}` (written by `m3gen`, not read by
the rules). `M3EpisodeFile.validate()` / `M3Level.validate()` list every problem.

```sh
cd Packages/BottleSortCore
swift build -c release --product m3gen            # then use .build/release/m3gen
.build/release/m3gen episodes                     # regenerate all ten files from the preset (~30 s, byte-identical)
.build/release/m3gen episodes --only 7            # one episode
.build/release/m3gen report                       # validate every file and re-measure every level with another bot stream (~16 s)
.build/release/m3gen sim ../../Levels/match3/gathering_03.json --policy all --runs 200   # pass rate, moves left, scores
.build/release/m3gen tune ../../Levels/match3/gathering_03.json --level m3-03-2 --target 70  # moves and stars for a target
.build/release/m3gen trace ../../Levels/match3/gathering_07.json --level m3-07-1 --max 10     # boards after each bot move
.build/release/m3gen daily 2026-11-16 --days 7    # m3daily-v1 levels with timings and fingerprints
```

Policies: `greedy` (best one-wave value, random tie-break), `reference` (15 % random slips; tuning and reports),
`novice` (40 %), `random`. The bot's randomness comes from its own stream, never the level's.

**Daily match-3** (`M3Daily`, generator id `m3daily-v1`): one level per UTC date, separate from the Daily Brew (which is
unchanged): Monday Gentle (85 %) → Sunday Grand Gathering (58 %, frost + crates + flasks). Median 55 ms, 96 % of days
under 0.5 s, worst ≈ 1.1 s (release, 365 days).

## Distillery (pipe rotation, R10)

The third pillar: repair the old lab's distillery. A grid (≤ 7×7) of brass pipe pieces lies between cauldron outlets
(sources, one color each) and empty flasks (each wants one color). Tap a piece to turn it a quarter clockwise
(long-press / right-click: counter-clockwise). Liquid fills every pipe connected to a source, live. Won when every
flask holds exactly its color, no two colors meet (a murky junction blocks) and nothing drips from an open end; dry,
unconnected pieces are fine. No tap limit: stars compare the final tap count (Undo takes a tap back) with the
solver's minimum: 3 at the minimum, 2 within `2 + minTaps / 5` more. Pieces: straight, elbow, tee (splitter), cross
(two independent pipes), end cap, empty cell; riveted pieces don't turn; a valve stays shut until its linked flask is
full of its own color; a heat coil turns one color into another (red → orange, blue → purple, yellow → green). Rules,
solver and generator are in the `DistilleryCore` library (pure Swift); `distillgen` is its tool. DECISIONS 270–279.

| File (`Levels/distillery/`) | Pack | Ids | Size | Min taps | What it adds |
|---|---|---|---|---|---|
| `distillery_stage_01.json` | Stage 1 The Cold Still (opens with chapter 3) | `d1-01…20` | 4×4 → 5×5 | 3 → 14 | Turning straights and elbows; decoys; riveted decoys at the end |
| `distillery_stage_02.json` | Stage 2 Copper and Steam (chapter 6) | `d2-…` | 5×5 → 6×6 | 6 → 20 | Tees (1), riveted pieces (5), two colors (9), crossings (13), cap stubs |
| `distillery_stage_03.json` | Stage 3 The Great Alembic (chapter 9) | `d3-…` | 6×6 → 7×7 | 10 → 29 | Heat coils (1), valves (5), then everything; three colors at the end |
| `distillery_expert.json` | Challenges: Distillery Expert | `dx-…` | 6×6 → 7×7 | 17 → 28 | Two to three colors, every mechanic |
| `distillery_master.json` | Challenges: Distillery Master | `dm-…` | 7×7 | 24 → 38 | Up to three colors, valves and coils everywhere |

Stages are optional, open in order of their chapters, never block sorting and keep their own stars
(`DistillProgression`); levels inside a stage open in order; each stage opens with story scene `distillery.N`.
Random Distillery: `DistillRandom.level(tier: .gentle | .tricky | .fiendish, seed:)`. **Daily Distillery**
(`DistillDaily`, generator id `distill-daily-v1`): one level per UTC date, Monday Gentle 5×5 → Sunday Grand Still
7×7, 1–16 ms per day, own streak via `DailyStreaks`.

**For the app:** `DistillGame(level:)` with `tap(_:clockwise:)` / `undo()` / `restart()`, `taps`, `stars`, `isWon`,
`hint()`; each tap returns `DistillTapResult` (old/new rotation, the new `DistillFlow`, channels that became wet in
`tick` order or ran dry, flasks newly satisfied, `didWin`). `DistillFlow` has per channel (`nodes`): `liquid`
(dry / color / murky), `sideColors` (a coil's exit sides carry the heated color), `entry` sides (fill from there),
`tick` (animation step, counted on across valve stages) and `shutValve`; plus `leaks` (cell, side, color, tick),
`seams` (murky meetings), `received` per flask, `valveOpenedAt` (stage) and `isWon`.

**Format** (`format: "pourfect-distillery"`, `version: 1`): `levels` with `id`, `width`, `height`, `grid` (rows of
space-separated tokens: `.` empty, `S` source, `F` flask, `X` cross, `C`/`I`/`L`/`T` + rotation 0–3 for cap /
straight / elbow / tee, `*` riveted), `sources` / `targets` `[{r, c, color, dir}]` (outlet / inlet side n/e/s/w),
optional `valves [{r, c, target}]` and `coils [{r, c, from, to}]`, `minTaps` and informational `stats`.
`validate()` lists structural problems, `validateSolving()` also solves (unique network, `minTaps` matches).

**In the app** (`Pourfect/Distillery/`): the *Distillery wing* climbs the map's left edge, three stills joined by a
brass pipe (`DistillWing`, `DistillStageMarker`): a locked still shows the chapter that opens it (tap: a popover),
an open one its stars, a finished one a check (gold ring at full stars). A stage opens its level list
(`DistillPackView`, twenty stills in order, a brass mark on the level that brings a new piece) and, the first time,
its story scene (`StoryScene.distillery(N)`; **Story** replays it). **Challenges → Distillery**: the Expert and Master
packs (same screen) and **Random Distillery** (`RandomDistillView`: Gentle / Tricky / Fiendish, a fresh seed each
time, nothing saved). The **Daily Distillery** (`DistillDailyModel`, `DistillDailyView`) has its own streak, stats,
calendar and share text (`Pourfect Distillery — 17 Nov ★★★ 12 taps (fewest 12)`), stored in
`distill.daily.history.v1` / `distill.daily.details.v1`. All daily games sit behind one **Today** card on the map
(panel or iPhone bar) that opens the **daily hub** (`DailyHubView`): one row per daily with today's flavour, state
and streak, opening that game's own screen. To add a daily, add a `DailyGameSummary` in `DailyGames.today`.

```sh
cd Packages/BottleSortCore
swift build -c release --product distillgen        # then use .build/release/distillgen
.build/release/distillgen packs                    # regenerate the five files from the presets (~1.5 s, byte-identical)
.build/release/distillgen packs --only stage2      # one pack
.build/release/distillgen report                   # validate + re-solve every level (unique, minTaps), with timings
.build/release/distillgen show ../../Levels/distillery/distillery_stage_03.json --level d3-05   # text picture
.build/release/distillgen daily 2026-11-16 --days 7 [--show]       # distill-daily-v1 levels, timings, fingerprints
.build/release/distillgen random --tier fiendish --seed 3 --count 5 [--show]
.build/release/distillgen gen --size 6x6 --groups 2 --crosses 1-2 --coils 1 --taps 10-18 --count 5
.build/release/distillgen bench                    # solver time per shipped level
```
## Secret Recipe (code-breaking, R10b)

The alchemist locks a **recipe** in the book: an ordered row of **five different ingredients** out of the eight on the
tray (no repeats; 6720 possible recipes). The player has **eight guesses**, each five different ingredients in order.
After each **Brew** the book shows only counts: a **gold drop** for every ingredient in its right slot, a **silver
drop** for every ingredient that is in the recipe but in another slot, never which ones (two guesses always share at
least two ingredients). All five in place opens the book; after eight wrong guesses the recipe is revealed. It never
counts toward the chapter map, the Lab Style rewards or any gate.

- **Ingredients** (tray order = keys 1–8): the six gathering ingredients drawn by `IngredientArt` (mushroom,
  crystal, feather, moonflower, ember, potion drop) plus two new ones in the same style (`RecipeArt`): **honeycomb**
  (four amber wax cells with a honey drip; brown, rune ■) and **starleaf** (a five-pointed leaf with veins and a
  stem; green, rune ›). Every ingredient has its own silhouette and its palette color's rune (Color Runes setting).
- **Screen** (`Pourfect/SecretRecipe/RecipeGameView`): the leather-bound recipe book with a brass lock (it opens on a
  win) and eight ruled parchment lines (each guess with its drops, gold first); the brewing bench (five slots; the
  next tray pick fills the highlighted slot, tapping a filled slot clears it and selects it); the tray of eight;
  **Notes** (a tap then marks an ingredient *ruled out* ✕, then *maybe* ?, then clears; also in the tray's context
  menu and as a VoiceOver action; notes are only a memory aid and last while the screen is open); **Clear**;
  **Brew** (Return). Drag an ingredient onto a slot works too. Keyboard: **1–8** pick, **Delete** clears the last
  slot, **Return** brews, **⌘/** the tip, **⌘R** a new practice recipe (⌘N stays New Window on the Mac). Drops appear one by one with a click
  (gold) or a lower clink (silver); win and loss sounds and haptics; Reduce Motion shows them at once. Wide
  windows put the book left and the bench, tray and buttons right; iPhone stacks them (the tray is one row).
  The end card (win: guesses used, the recipe; loss: the recipe revealed) shows the daily streak, win rate and the
  share grid; "See the book" closes it, and the bench then shows the recipe with Share / Done or New recipe.
- **Daily** (`RecipeDailyModel`, `RecipeDailyView`, generator `recipe-daily-v1`): one recipe per UTC date for
  everyone. Every brew is saved at once (`recipe.daily.v1`), so leaving never resets the day. Only a game finished on
  its own UTC day, and not before a game already saved (clock set back), counts. Streak = consecutive won days (a
  loss or a missed day ends it; today open keeps yesterday's run alive). The screen shows today (Play / Continue /
  See the book, Share, countdown), Played, Cracked %, current and best streak, the **guess distribution** (wins in
  1–8 guesses and ✕ for not cracked, today's bar lit) and the month calendar (won days amber, wins in ≤ 4 guesses
  gold). Share text (no ingredients):
  ```
  Pourfect Secret Recipe · 17 Nov · 4/8
  🟡⚪⚪⚫⚫
  🟡🟡⚪⚪⚫
  🟡🟡🟡⚫⚫
  🟡🟡🟡🟡🟡
  ```
  No hints and no helper count in the daily.
- **Practice** (Challenges → Secret Recipe → *Practice recipe*, also on the daily screen): unlimited random recipes
  (`RecipePractice.secret(seed:)`), nothing saved. It shows **Possible recipes left: N** (from the core's candidate
  counter) after the first guess; the eye button hides it (remembered).
- **Entry points**: the daily is a row of the map's **Today** card and of the daily hub (with Daily Brew, Daily
  Gathering and Daily Distillery; a cracked day shows "4/8", a missed one a grey cross); Practice is the **Secret
  Recipe** section at the end of the Challenges hub (`RecipePracticeCard`) and a button on the daily screen.
  DECISIONS 285–293.
- **Tip**: one topic (`TutorialTopic.recipe`, three pages: goal, gold and silver drops, notes and keys) the first
  time a game opens, again with **?**.

**Core** (`SecretRecipeCore`, depends on `BottleSortCore` for `DailyDate`, `SplitMix64` and `DailyStreaks`):

- `RecipeIngredient` (8, tray order), `RecipeCode` (five different ingredients; `RecipeCode.all` lists the 6720 in
  lexicographic order; Codable as digits `"03571"`), `RecipeCode.feedback(for:) -> RecipeFeedback {exact, misplaced}`.
- `RecipeGame` (`maxGuesses` 8, `brew(_:)`, `status` playing / won / lost, `guessesLeft`, `revealed`, `candidatesLeft`)
  and `RecipeCandidates.count(consistentWith:)` / `consistent(with:)` (all 6720 checked with ingredient bitmasks; fast enough to recount after every brew on the main thread).
- `RecipeDaily.secret(for:)` (`recipe-daily-v1`: FNV-1a of `recipe-daily-v1|YYYY-MM-DD` mixed by SplitMix64, a
  uniform draw from `RecipeCode.all`, redrawn while the recipe follows the tray order strictly up or down),
  `RecipePractice.secret(seed:)`, `RecipeShare` (rows `🟡`/`⚪`/`⚫`, score `4/8` or `X/8`), `RecipeDailyHistory`
  (append-only saves per date, `counts` set once at the end) and `RecipeStats` (played, won, win %, streaks via
  `DailyStreaks`, distribution, lost days, calendar).
- Tests: `scripts/test-fast.sh --filter SecretRecipe` (23 tests: validation, all permutations, feedback examples and
  combinatorics for every guess against 70 secrets, all 45 million pairs against a slot-by-slot reference in the
  optimized run, game end and reveal, candidates against a brute-force filter, daily goldens and spread, practice
  seeds, share text, saving rules, stats and streaks).

## Hidden-object rooms (R11, core and assets)

Search scenes ("Wimmelbild"), the fourth pillar: three rooms — **Alchemist's Attic**, **Market Stall** and
**Dragon's Hoard** — each played as **ten seeded rounds**. A round hides objects from the room's 40-object library on
its hand-placed spots; the player finds the ones on the find list by tapping them. Calm: no timer; stars from hints
and wrong taps. Rooms open with sorting chapters 2 / 5 / 8 and never block anything. The app screens (wing on the
map, viewer with pinch / scroll zoom, find list, lantern hint, sounds, VoiceOver) are the next step; this part ships
the art and the rules. DECISIONS 294–302.

- **Assets**: `HiddenScenes/<attic|market|hoard>/` (bundled as a folder reference, 10.5 MB): `scene.json`
  (`pourfect-hidden-v1`: objects with id / English name / size class / PNG size; spots with anchor, maxSize, size
  classes, surface and an occlusion polygon for containers), `background.jpg` (2752×1536), `background_1376.jpg` and
  `objects/<id>.png` (≤ 220 px, alpha, untinted). They are the art pipeline's export, unchanged; the pipeline (merged
  from the `wimmel-poc` branch, images not committed) lives in `poc/hidden-object/` (see its README).
- **Placement and blending** follow the pipeline's `layout.py` / `hocommon.py` exactly: size from the spot and the
  object's class, thin objects longer, bottom centre on the spot, spacing, flips; each object tinted toward the mean
  colour around it (`HiddenTint`: 3×3 matrix + bias, e.g. for `CIColorMatrix`), a soft contact shadow (α 0.38, blur
  σ 5, offset +5, +4) and, in containers, the background drawn again over its foot (`HiddenBlend.occluderMask`).
- **Rounds**: 8 → 15 objects to find, 8 → 20 decoys (non-findable library objects drawn exactly the same way, never
  covering a target; tapping one is a wrong tap), objects shrinking, harder spots later, gold objects on the hoard's
  find list only from round 6. Same picture for the same round and variant; a replay after finishing gets a new one.
- **Stars**: 3 = no hint and ≤ 3 wrong taps, 2 = ≤ 2 hints and ≤ 10 wrong taps, else 1. The lantern hint circles
  one remaining object and recharges for 30 s; VoiceOver's "reveal next" finds the next object and counts as a hint.

**Core** (`HiddenCore`, no dependencies; linked into the app):

- `HiddenScene(data:)` decodes and validates a `scene.json`; `HiddenSceneID` (`attic`, `market`, `hoard`).
- `HiddenGenerator.round(scene, round:variant:)` → `HiddenRoundLayout` (`targets` = find list, `decoys`,
  `drawOrder` back to front); `HiddenCurve.spec(_:round:)`, `HiddenCurve.goldish(_:)`; `HiddenGenerator.seed`.
- `HiddenPlacement` (size, flip, top-left, tint strength, `shadowRect`, `tintSampleRect`, `occlusion`),
  `HiddenBlend` (shadow constants, `tint(mean:strength:)`, `occluderMask`), `HiddenRaster.mean` for the tint colour.
- `HiddenAlphaMask` (from a PNG's alpha), `HiddenHitTester.hit(at:slop:found:)` → target / decoy / nothing,
  `HiddenTouch.slop(pointsPerBackgroundPixel:)`.
- `HiddenRoundState` (tap, `useHint(now:layout:)` → `HiddenHintGlow`, `revealNext()`, stars), `HiddenStars`,
  `HiddenProgression` (room unlocks, rounds in order, story ids `hidden.<room>`), `HiddenProgress` (best stars and
  finished plays per round, Codable).
- `PythonRandom` (CPython's Mersenne Twister, bit for bit) and `HiddenPoC.layout` (layout.py replayed) for the goldens.
- Tests: `scripts/test-fast.sh --filter HiddenCoreTests` (22 tests, < 1 s). Goldens:
  `poc/hidden-object/tools/swift_goldens.py HiddenScenes Packages/BottleSortCore/Tests/HiddenCoreTests/Goldens/poc_layouts.json`
  (Pillow + numpy, Python 3.9+).

## Generate levels

```sh
cd Packages/BottleSortCore

# Regenerate all thirteen shipped files (output is deterministic; chapter 2 takes the longest)
swift run -c release levelgen --preset all --out-dir ../../Levels

# One file: chapter1 | … | chapter10 | challenger | expert | master
swift run -c release levelgen --preset chapter2 --out ../../Levels/chapter_02.json

# One configuration; --pool 3 keeps the hardest 20 of 60 passing levels, --hidden makes "?" levels
swift run -c release levelgen --colors 9 --capacity 4 --empty 2 --count 20 --pool 3 \
    --min-moves 26 --max-moves 40 --seed 1 --name "My Pack" --out my_pack.json

# Lock levels: N locked full flasks, their keys buried in the others (0 ≤ N < colors);
# --locks-matter rejects levels where a lock only adds the key pour (LockImpact)
swift run -c release levelgen --colors 5 --empty 2 --locks 1 --locks-matter --count 5 --seed 1 --out locks.json

# Essence flasks: N runes of different colors, on empty flasks or on filled flasks (their bottom color;
# with --hidden a random color, so a rune never reveals a murky layer);
# --essence-empty K puts K of them on empty flasks; --essence-cost C rejects levels where a rune adds fewer
# than C moves (EssenceImpact; --essence-matter = cost 1, the chapter uses 2 after its tutorial)
swift run -c release levelgen --colors 5 --empty 2 --essence 1 --essence-cost 2 --count 5 --seed 1 --out runes.json

# Glass flasks (one modifier per flask, never on a sealed or rune flask): --tap N on filled flasks,
# --funnel N on empty flasks, --narrow N on any other plain flask; --glass-cost C rejects levels where a
# narrow neck or tap changes the optimum by fewer than C moves (either way) or a funnel sets no trap
# (GlassImpact; --glass-matter = cost 1, the chapter uses 2)
swift run -c release levelgen --colors 5 --empty 2 --narrow 1 --tap 1 --glass-cost 2 --count 5 --seed 1 --out glass.json

# Frozen layers: --frozen N:MAXTURNS puts N (≤ 2) frozen layers on filled flasks (one each, in the upper half of
# the flask, counter between (MAXTURNS+1)/2 and MAXTURNS ≤ 5); --frozen-cost C rejects levels where a frozen layer
# adds fewer than C moves (FrozenImpact; --frozen-matter = cost 1, the chapter uses 2). Ice rarely matters
# with two empty flasks unless there are two frozen layers: use --empty 1 for a single one
swift run -c release levelgen --colors 4 --empty 1 --frozen 1:5 --frozen-cost 2 --count 5 --seed 1 --out ice.json

# Bubbling flasks: --bubbling N:PERIOD makes N (≤ 2) flasks with 2+ layers (no tap, funnel, narrow neck or ice)
# bubble every PERIOD (2…5) moves, each from a random phase; --bubbling-cost C rejects levels where a bubbling
# flask changes the optimum by fewer than C moves, either way (BubblingImpact; --bubbling-matter = cost 1, the
# chapter uses 2). Each flask multiplies the search: keep two-flask levels at ~4 colors
swift run -c release levelgen --colors 4 --empty 2 --bubbling 1:3 --bubbling-cost 2 --count 5 --seed 1 --out bog.json

# Links: --twins N chains N pairs of plain flasks (twins), --overflow N runs N pipes (each flask in at most one
# link); --link-placement any|filled|empty|mixed picks the flasks (mixed: twins on empty flasks, a pipe from a
# filled flask into an empty one); --link-cost C rejects levels where twins change the optimum by fewer than C
# moves either way, or where a pressure pipe saves fewer than C moves (then every optimal solution pushes;
# LinkImpact, DECISIONS 214; --links-matter = cost 1, the chapter uses 2). Pipes between filled flasks push most
# --needs-split also rejects twins an optimal solution never pours into (the chain would only restrict; DECISIONS 191)
swift run -c release levelgen --colors 4 --empty 2 --twins 1 --link-placement filled --link-cost 2 --needs-split --count 5 --seed 1 --out twins.json

# Mixing cauldron: --cauldron R adds one cauldron with R (1–2) natural recipes (red + blue → purple, …) and builds
# the level BACKWARDS from a solved board: --scramble STEPS reverse moves (verified forward pours), --mix-pairs N
# un-mixed pairs per recipe; --ingredients fresh (the ingredients are extra colors that must all be brewed away) or
# sorted (they are potions of their own: the shortest win brews exactly N pairs). --mixing-matter rejects levels that could be won
# without mixing (CauldronImpact); --teaches-mixing keeps tutorial-friendly ones (empty cauldron, no parked flask,
# no dead-end first move). --locks N seals flasks after the walk, --hidden makes it murky
swift run -c release levelgen --colors 4 --empty 1 --cauldron 1 --mix-pairs 2 --scramble 80 --mixing-matter --count 5 --seed 1 --out brew.json
swift run -c release levelgen --colors 5 --empty 2 --overflow 1 --link-placement filled --link-cost 2 --count 2 --seed 1 --out pipes.json

# Switches: --switch N joins N pairs of plain, unlinked flasks with a lever (switch → gate);
# --switch-placement closed|empty|emptySwitch|any picks them (closed: both start with potion, the gate's is locked
# away; empty: the gate is an empty flask; emptySwitch: the switch is an empty flask to fill with one color).
# --switch-cost C rejects levels where a switch adds fewer than C moves to the optimal solution (SwitchImpact;
# --switch-matter = cost 1, the chapter uses 2); --teaches-switch keeps tutorial-friendly ones (every gate starts
# closed with potion, every star without a pure wait, no dead-end first move)
swift run -c release levelgen --colors 5 --empty 2 --switch 1 --switch-placement closed --switch-cost 2 --count 5 --seed 1 --out hoard.json

# Customer orders (R7): --order N marks N flasks (no tap, no cauldron) that must end full of one potion (with a
# cauldron, its brew); --layered N marks flasks that must end with an exact pattern (a bottom part of the flask topped
# up with its last color: a pour only lands on its own color); --order-cost C rejects levels whose order adds fewer
# than C moves to the optimum (OrderImpact; --order-matter = cost 1, the chapters use 2 after the tutorial)
swift run -c release levelgen --colors 5 --empty 2 --order 1 --order-cost 2 --count 5 --seed 1 --out orders.json
swift run -c release levelgen --colors 3 --empty 2 --layered 1 --count 5 --seed 1 --out layered.json

# Regenerate only the order recipes appended to a chapter, keeping its other recipes byte for byte (the order tiers
# sit in their own last sections, so this equals a full regeneration)
swift run -c release levelgen --preset chapter2 --append --out ../../Levels/chapter_02.json

# Re-solve every level of every file and print difficulty tables, sorted by score, plus the
# score curve in file order; exits with status 2 on a minMoves mismatch or a chapter mechanic (seal, rune, glass, ice, bubbling, twins, pipe, cauldron, switch) that doesn't matter
swift run -c release levelgen --report ../../Levels

# Time the solver on random 8-color puzzles (also takes --locks, --essence, --essence-empty, --narrow, --funnel, --tap, --frozen, --bubbling,
# --twins, --overflow, --link-placement, --cauldron, --ingredients, --mix-pairs, --scramble, --switch, --switch-placement)
swift run -c release levelgen --bench --colors 8 --count 10

# Time the recipes of one Rush run (R6): spec, phase, minMoves and generation time per recipe
# (--mechanics all by default; or a list such as sealed,frozen; "" = classic only)
swift run -c release levelgen --rush 42 --count 25
```

Optional generator flags: `--min-score/--max-score`, `--id-prefix`, `--easiest` (keep the easiest of the pool) and
the pack metadata `--kind chapter|challenge --chapter N --location NAME`. Generation is fully deterministic:
the same flags and seed always produce the same file. Chapter presets put a tiny tutorial recipe first, then sort
the rest by score inside sections (e.g. one seal before two).

Level files are JSON. Layers are listed bottom → top. A color layer is an integer and a key layer is
`{"key": n}`. A locked bottle has `"lockedBy": n`, and `"hidden": true` turns on hidden layers for a level.
Pack fields besides `version` and `levels` are optional: `name`, `subtitle`, `kind` (`"chapter"` or
`"challenge"`), `chapter` (1-based, required for a chapter), `location` and `introduces` (mechanics a
first-time tutorial explains: `"basic"`, `"sealed"`, `"murky"`, `"essence"`, `"narrowNeck"`, `"funnel"`, `"tap"`, `"frozen"`, `"bubbling"`,
`"twins"`, `"overflow"`, `"cauldron"`, `"switch"`;
unknown names still load):

```json
{ "version": 1, "name": "Rune Vault", "kind": "chapter", "chapter": 2, "location": "Rune Vault",
  "introduces": ["sealed"], "levels": [ { "id": "c2_001", "capacity": 4,
  "bottles": [ { "layers": [0, 1, 1, 2] }, { "layers": [3, 3, 3, 3], "lockedBy": 1 },
               { "layers": [2, {"key": 1}, 0] }, { "layers": [] } ],
  "meta": { "seed": 12345, "minMoves": 11, "score": 23.4 } } ] }
```

Every lock needs exactly one matching key and vice versa; the loader rejects files that break this.

**Format version 2** adds flask `modifiers` (`[{"type": "essence", "color": 3}, {"type": "narrowNeck"}, …]`; the
seal stays `lockedBy`), level `links` (`{"type": "twins", "between": [0, 4]}`, `{"type": "overflow", "from": 1,
"to": 2}`, `{"type": "switchGate", "switch": 3, "gate": 5}`) and a `goal` (`{"type": "order", "targets": [{"bottle":
2, "layers": [5, 5, 5, 5]}]}`, `{"type": "pattern", "targets": [{"bottle": 0, "layers": [0, 2, 2, 2]}]}`; layers
bottom → top, exactly the flask's capacity). `levelgen` and `LevelLoader.encode` write version 2 only when a level uses
one of these, so chapter 1 and the challenges stay version 1; chapters 2 and 3 became version 2 with their order
recipes (R7), and `chapter_04` (essence runes), `chapter_05` (`{"type": "narrowNeck"}`,
`{"type": "funnel"}`, `{"type": "tap"}`) and `chapter_06` (`{"type": "frozen", "layer": 2, "turns": 5}`, layer 0 =
bottom), `chapter_07` (`{"type": "bubbling", "every": 3, "phase": 1}`, phase 0 when omitted) and `chapter_08`
(`links`: twins and pressure pipes), `chapter_09` (`{"type": "cauldron", "recipes": [{"a": 0, "b": 1, "result": 4}]}`,
recipes stored sorted) and `chapter_10` (`links`: `{"type": "switchGate", "switch": 1, "gate": 0}`) are version 2.
Essence, glass, frozen layers, bubbling flasks, twins, pressure pipes, cauldrons, switches, orders and layered recipes
are playable; the other R5 mechanics and the dropped rescue goal are defined but not playable: such levels decode, but
fail validation.

To ship a new file, put the JSON file in `Levels/` (a synchronized folder, so no project edit is needed).

## How it works

- **Rules** (`Rules.swift`): one turn is `Rules.resolve(_:afterAction:)`, which applies the pour and then the turn order
  of MECHANICS.md §4 (immediate effects such as unsealing, move counter, timed effects, goal check). A pour runs
  through one modifier pipeline (`Rules.apply`, a switch where each flask modifier can veto or change it) and then the
  base rule (a color run moves, or a key opens its seal). The game, the solver and the generator all go through it.
- **Customer orders** (R7, `Goal.order` / `Goal.pattern`, rules in `Rules.isMet`): an order flask must end full of
  its potion, the rest standard; a layered-recipe flask must end with its exact layers, every other flask holds one
  potion or nothing, and the rest of each potion is gathered in one flask. Target flasks are marked by index (they
  follow shuffles), `StateKey` writes them as canonical ranks, and the solver treats a marked flask like a linked one
  in its pruning (a finished flask may still have to move into the flask that ordered it). `OrderImpact` checks that
  an order changes optimal play (2+ extra moves in the chapters); a layered recipe always does.
- **Mechanics** (`Mechanics.swift`): a flask carries `modifiers` (`.sealed`, `.essence`, `.narrowNeck`, `.funnel`,
  `.tap`, `.frozen(layer:turns:)`, `.bubbling(every:phase:)` and `.cauldron([Recipe])` are implemented), the level has `links`
  (twins, pressure pipes and switch → gate implemented) and a `goal` (`.standard`; order, pattern, rescue for R7). A new mechanic is one
  case plus its arms in the `Rules` switches; key, JSON and validation already handle every case.
  `Bottle.lockedBy` remains as the seal's accessor, `Bottle.essenceColor` gives a flask's rune color,
  `hasNarrowNeck` / `isFunnel` / `hasTap` the glass, `frozenLayers` / `thawTurns(atLayer:)` / `holdsIce` /
  `isIcedOver` the ice, `bubbling` (`Bubbling.every` / `phase` / `movesUntilRise`) / `isBubbling` a bubbling flask,
  `isCauldron` / `recipes` a cauldron (`Rules.recipe(mixing:into:)` previews a mix, `Rules.mixed(_:pouring:amount:recipe:)`
  and `Rules.beforeMixing(_:poured:amount:recipe:pairs:)` give a cauldron's layers after and before a mix), `GameState.twin(of:)` / `overflowTarget(of:)` / `overflowSource(of:)` / `link(at:)`
  the links, `GameState.gate(of:)` / `switchFlask(of:)` / `isGateClosed(_:)`, `Rules.isSwitchOn(_:)` and
  `Rules.isGateClosed(_:in:)` the switches (the gate's state is derived, never stored), `Rules.linkRefusal(of:in:)` names a twin chain, a pressure pipe or a closed gate that refuses a pour, and `Rules.refusal(of:in:)` names the modifier that refuses a pour
  (a rune, a funnel, a tap, ice; a funnel, tap or ice is named even when the base rule refuses too, e.g. a full tap).
  Automatic effects after the pour are `Turn.events` (`TurnEvent.mixed(bottle:recipe:pairs:)` first, then
  `TurnEvent.thawed(bottle:layer:)`, then `TurnEvent.bubbled(bottle:)`, with `TurnEvent.gateOpened(switch:gate:)` /
  `.gateClosed(switch:gate:)` after the step that caused them; `GameSession.lastEvents`; `Rules.sunk(_:)` gives a risen flask's layers before the rise). Every turn reports what it poured (`Turn.pour`, a `PourEvent` with amount, layer and
  whether it left from the bottom, plus `landings` when part of it landed in a twin and `push` when it pushed the
  target's bottom through a pressure pipe; `Rules.push(of:in:)` previews a push, `Rules.pushed(from:into:count:)`
  moves layers or masks the same way); `Rules.outlet(of:)` says which layers a flask would pour. `MechanicImpact` is the
  "must matter" check for any mechanic (`LockImpact`, `EssenceImpact`, `GlassImpact`, `FrozenImpact` and `BubblingImpact` are its
  seal, rune, glass, ice and bubbling cases, `LinkImpact` the twins and pipes, `CauldronImpact` the cauldron,
  `SwitchImpact` the switches (one-sided: a gate only refuses pours, so the check is how many moves it adds); a
  funnel matters by the trap it sets, a pressure pipe only by saving moves (`isHelper`), a cauldron by counting:
  without mixing the colors can't end in full flasks, so every solution mixes; necks, taps, bubbling and twins count
  either way).
- **Solver**: breadth-first search for the fewest moves. Each state gets a compact key that ignores
  bottle order (`StateKey`: one word per classic or sealed bottle; v2 adds variable-length words for other
  modifiers and a global section where links refer to bottles by canonical rank), and three pruning rules skip
  moves that can't change the outcome (on states whose flasks carry only seals, runes and glass, which have no state of
  their own; whole-content relocations are judged by the amount the pour really moves; an empty flask is only
  interchangeable with an empty flask carrying the same modifiers). While ice remains a relocation is a real
  "wait" move (the counters tick), so only the empty-flask rule stays; while a flask bubbles, likewise, but all
  relocations of a state are the same wait, so only the first one is tried. A linked flask (twin, pipe end) is never
  interchangeable with another flask, and a pour into either twin of a pair is the same move, so only one is tried.
  With a cauldron the "skip a finished flask" rule is off (mixing changes color counts, and a cauldron can take a
  mixing pour). A switch and its gate are linked flasks like twins and pipe ends, so the same rules keep them safe:
  a complete switch is never skipped as a source (emptying it closes its gate, a real choice). An 8-color level solves in about 10–40 ms in a release build.
- **Difficulty score** = `minMoves + 1.5·log2(statesExplored) + 40·deadEndRatio + 0.5·branchingFactor`.
- **Generator**: shuffles random layers with a seed, then rejects levels that are already sorted, unsolvable, or outside the target difficulty.
  Cauldron levels are the exception: they are built backwards from a solved board by a seeded walk of reverse pours
  and un-mixes, each checked by replaying the forward pour, then measured by the solver like any other level.
- **Daily puzzle (core)**: `DailyDate` is a UTC calendar day (the puzzle changes at UTC midnight for everyone).
  `DailyPlan.spec(for:)` picks the weekday's recipe (Mon Gentle 4 colors → Sun Grand Brew, 7 colors murky + seal),
  and `DailyPuzzle.level(for:)` generates it on device from a seed hashed from the date and `algorithmVersion`
  (`daily-v2`), so every device gets the same level, offline. `DailyResult` / `DailyHistory` / `DailyStreaks` give
  the current and best streak, solved days and perfect solves (solver minimum, no hint; undo allowed). See DECISIONS 105–112, 119.
- **Daily puzzle (app)**: `DailyModel` (injected at the root) holds today's `DailyDate`, re-read when the app
  becomes active and by a timer at the next UTC midnight; it generates today's level in a detached task (cached per
  date) and keeps the `DailyHistory` behind `DailyStore` (`UserDefaults` key `daily.history.v1`, JSON) plus the dates whose
  puzzle showed a hint (`daily.hinted.v1`, so reopening the puzzle doesn't clear it). The game
  screen plays the daily with `GameViewModel(dailyLevel:date:daily:)`, which records the win (moves, minMoves, hint
  used) instead of stars. See DECISIONS 113–118.
- **App**: `GameViewModel` wraps `GameSession`. After every move it solves the new state in the background
  to detect dead ends ("Stuck — undo or restart?") and to keep the next hint ready instantly.
  It applies each move first and then publishes a `PourEvent`; the view only animates it.
  Hidden layers come from `GameSession.isHidden` / `hiddenDepths`; views contain no rule logic.
- **Feedback**: the view model publishes `FeedbackEvent`s (select, illegal, pour, flask completed, level won);
  `FeedbackPlayer` turns them into sound and haptics, timed to the pour animation. "Flask completed" is
  `Rules.completedBottles(before:after:)` in the core and fires when the pour lands.
- **Sound**: `SoundEngine` synthesizes every sound at launch, off the main thread (glass clinks, bubbly gurgles,
  cork pop + chime, success arpeggio, muted tap, key click, rune hum, valve, brass knock, a cold tink when ice refuses
  a pour, and a soft crackle with drips when ice thaws), and plays the PCM buffers with `AVAudioEngine`; no
  audio files. Sounds and haptics scheduled for later in a pour are dropped when that pour is cancelled (Undo,
  Restart, new level), when you leave the game, or when Sound is turned off.
- **Flask look**: a completed flask gets a cork that drops in with a bounce and a sparkle burst in the potion's
  color; glass sheen and a soft potion glow on every flask. With *Color Runes* on, every layer shows one of 12
  runes (one per color) so colors can be told apart without hue. A frozen layer is covered by a frosted ice slab
  with a hexagonal crystal showing its thaw counter (moved aside when runes are on or the layer is murky); a flask
  holding ice gets a frost crust with icicles on its lip, frost along the glass and a pale blue outline. The
  counters tick when a pour lands; a thawing layer cracks, its crystal pops and the slab melts into the potion
  with a few drips and a breath of mist (Reduce Motion: it fades).
- **Settings** (gear in the toolbar of the map, chapter and Challenges screens, or ⌘, on the Mac): sound, haptics (iOS), color runes, reduce motion
  (system / on / off). Stored behind `SettingsStore` (`UserDefaults` keys `settings.*`).

## Known limitations

- Random levels can take a few seconds for the largest settings (up to ~2.5 s per level in a release build on an
  M-series Mac, longer on a phone or in a debug build; a hard attempt can take ~5 s). Leaving the screen, Replay or Undo
  cancels a running generation.
- Pour animation: a pour between rows makes the flying bottle cover the upper row; near the top of a short screen
  the tilted bottle can overlap the header.
- Progress is keyed by level id, so regenerating a pack with different content keeps old stars on the new levels.
- The chapter map's button positions are hand-placed for this painting; new map art needs new `ChapterArt.mapSpots`.
- One empty bottle makes almost every puzzle with 6+ colors (bottle size 4) unsolvable, so one-empty levels stay at
  5 colors, or 6 colors with size-5 bottles.
- Progress, gold seals, Rush bests and daily results live in `UserDefaults` on each device, with no iCloud sync.
- Rush's clock pauses whenever the app is inactive (on the Mac: another app in front), so a run can't be timed
  across a break; leaving the Rush screen mid-run drops the run.
- The daily calendar and countdown use UTC days, so for players far from UTC the puzzle changes during their
  day (by design, same puzzle for everyone).
- No full accessibility pass beyond labels and VoiceOver flask contents (color runes are available in Settings).
- The difficulty score's weights are hand-picked and haven't been calibrated with playtest data.
- The solver's packed state key supports capacity ≤ 9, color ids 0–46 and key ids 0–15.
- Layered recipes score high (42–53) for their length (8–10 moves): most positions are dead ends once the
  pattern's bottom is poured away, and the score weighs dead ends heavily.
- The app has no UI tests. Gameplay was checked with screenshots taken via the debug launch arguments.

## Next steps

1. Playtest the pack and tune the score weights and tier ranges with real solve times.
2. More chapters as their mechanics land (R5: chapter 10).
3. A full accessibility pass (VoiceOver already reads flask contents).
4. Optional iCloud progress sync.
