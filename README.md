# LiquidPour

A liquid-sorting puzzle game for **iPhone, iPad and Mac** (native Apple silicon), built with SwiftUI.
Pour colored layers between bottles until every bottle is empty or full with one color.

The app is shown to players as **Pourfect**, a potion-lab game: in the UI bottles are *flasks*, levels are *recipes*
and packs are *chapters*. Code, module and target names stay neutral (`LiquidPour`, `BottleSortCore`) until the
release rename (R8).

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
| `chapter_08` | 8 Twin Towers | `c8_001…` | 32 | 8–25 | 20–56 | Twin flasks (every one needs a split), then overflow pipes (6 colors, size 3), then murky layers, seals and 7 colors; the last two recipes have both links |
| `chapter_09` | 9 Alchemist's Hall | `c9_001…` | 30 | 4–19 | 15–52 | Mixing cauldron: one recipe with ingredients that must all be brewed, then ingredients that are potions of their own (one pair to brew for the shortest win), then two recipes; at the end murky layers, a seal and 8 colors. Built backwards from a solved board |
| `chapter_10` | 10 Dragon's Hoard | `c10_001…` | 30 | 6–32 | 14–63 | Switch flasks and gates: one switch (gate full of potion, empty gate, empty switch), then two; then one earlier mechanic each (murky, seal, rune, narrow neck, ice, bubbling, twins); the finale (8–9 colors, 58–63) is the hardest of the main path |

All ten chapters of `ChapterOutline.plan` ship.
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
  A **Daily Brew** card sits at the top of the panel (and as a row in the bottom bar on iPhone): today's weekday
  and difficulty, mode, solved / perfect state, the streak flame and "New brew in 3 h 12 m" (UTC midnight).
- **Daily Brew:** today's puzzle (weekday · difficulty, mode, difficulty pips, **Play** / **Replay**), current and
  best streak, brews solved and perfect count, and a month calendar (Monday first, navigable back to your first
  result) with solved days in amber, perfect days in gold with a seal, today ringed and future days dimmed. All
  days are UTC dates ("Resets at midnight UTC"). Playing uses the normal game screen; the win card shows
  "Daily solved!", the **Perfect** badge (fewest moves, no hint), the streak and a **Share Result** button with
  spoiler-free text such as `Pourfect Daily 2026-11-15 · 22 moves (perfect) · 🔥 6`. Daily results never touch
  chapter stars.
- **Chapter screen:** vignette header with name, subtitle, stars and what they open ("Earn 12 more stars to open
  Misty Marsh"), then the recipe grid (recipes open in order).
- **Challenges:** Random Brew plus the Challenger, Expert and Master books, all open (recipes inside still open in order).
- **Tips:** the first time a recipe uses a mechanic (basic pouring, rune seals, murky potions, essence flasks, narrow
  necks, funnels, taps, frozen layers, bubbling flasks, twin flasks, overflow pipes, the mixing cauldron) the game shows a
  short illustrated tip drawn with the real flasks (2–3 steps, **Got it**). The **?** in the game's top bar (⌘/)
  shows the tips for the current recipe again. Seen tips are stored per mechanic (`TutorialStore`, UserDefaults).

## Layout

```
LiquidPour.xcodeproj         Xcode project (one multiplatform app target: iOS 17+ / macOS 14+)
LiquidPour/                  SwiftUI app
  Model/                     GameViewModel, LevelCatalog, ProgressStore, Tutorials, AppSettings, Palette, RandomLevelMaker
  Views/                     RootView, ChapterMapView (home), PackView (chapter / challenge recipes), ChallengesView,
                             GameView, TutorialOverlay, BottleView, RandomLevelView, PourAnimationView,
                             TiltedLiquid, FlaskDecor, GlassDecor, FrostDecor, BubbleDecor, LinkDecor, CauldronDecor,
                             WorkbenchBackground, SettingsView
  Assets.xcassets            Optimized painted art (workbench backgrounds, chapter map, chapter vignettes)
  Localizable.xcstrings      English String catalog for all UI text; InfoPlist.xcstrings names the app
  Feedback/                  SoundEngine (synthesized sounds), Haptics, FeedbackPlayer
Packages/BottleSortCore/     Swift package — pure game logic, no UI imports
  Sources/BottleSortCore/    Model, Mechanics, Rules, StateKey, Solver, Difficulty, Generator, LevelFile, GameSession,
                             RandomLevel, Settings
  Sources/levelgen/          Command-line level generator
  Tests/BottleSortCoreTests/ Swift Testing suite
Levels/chapter_0N.json       Main-path chapters 1–3; challenge_*.json: optional challenges (synchronized folder: every JSON file is bundled)
```

No third-party dependencies, only Apple frameworks.

## Run the app

**In Xcode:** open `LiquidPour.xcodeproj`, choose the **LiquidPour** scheme, then pick a destination:

- **My Mac** for the native macOS app, or
- any **iPhone / iPad simulator**,

and press **⌘R**. If Xcode reports a signing error, open the target's *Signing & Capabilities* tab
and pick your team (or *Sign to Run Locally* on the Mac).

**From the command line:**

```sh
# macOS
xcodebuild -project LiquidPour.xcodeproj -scheme LiquidPour -destination 'platform=macOS' build
# iOS Simulator
xcodebuild -project LiquidPour.xcodeproj -scheme LiquidPour -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

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
- **Overflow pipes** (chapter 8). A brass pipe runs from flask A's rim to flask B. A pour into A works as usual,
  except that when A is full before the run has all gone in, the rest flows on through the pipe into B, as much
  as B legally takes (empty or the same top, no veto, free space); anything left stays in the source. A full A with
  the poured color on top passes the whole pour on. One hop only, nothing flows back into the source, a pour into B
  is an ordinary pour. A flask is an end of at most one link (twin chain or pipe).
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
  `Art/README.md`); about 6 MB in total.
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
| `-LPMapAnchor Y` | Opens the chapter map scrolled to height Y (0 = top / dragon, 1 = bottom / cellar). |
| `-LPDemoMoves K` | Auto-plays the first K optimal moves through the normal tap path (with the pour animation). A demo win saves no stars and no daily result. |
| `-LPDemoUndo N` | After `-LPDemoMoves`: undoes N moves, one per second. |
| `-LPDemoRefuse S` | After `-LPDemoMoves` (or at once), waits S seconds and tries a pour a flask refuses: an essence, tap or frozen-over flask (flare, message, sound), else picks up a filled funnel flask, else a pour a twin chain refuses. |
| `-LPDemoIcePour S` | After `-LPDemoMoves` (or at once), waits S seconds and plays a legal pour out of a flask that holds ice (the potion above the ice pours, the ice stays pinned). |
| `-LPDemoLinkPour S` | After `-LPDemoMoves` (or at once), waits S seconds and plays a pour that uses a link: one that runs through an overflow pipe if any (e.g. chapter 8 recipe 17), else one split between twins. |
| `-LPSlowMotion F` | Plays the pour, thaw, bubble-up and cauldron mix animations F times slower (F ≥ 1), to look at single frames. Sounds keep their normal timing. |
| `-LPRandomSettings 1` | Opens the Random Brew screen (inside Challenges). |
| `-LPRandomGenerate 1` | With `-LPRandomSettings 1`: presses *Generate* once. |
| `-LPRandomMode classic\|locks\|hidden` | Generates a random level with the saved settings and opens it. |
| `-LPRandomSeed S` | Seed for `-LPRandomMode` (default 1), so the same level comes back every time. |
| `-LPOpenDaily 1` | Opens the Daily Brew screen. |
| `-LPPlayDaily 1` | Opens the Daily Brew screen and starts today's puzzle (once it is generated). |
| `-LPDailyDate YYYY-MM-DD` | Pretends today is that UTC date (the clock is shifted by whole days, so the countdown and "solved today" still work). Results stay in memory only. |
| `-LPDailySeedResults N` | Adds fake results for the N days before today (a few gaps, mostly perfect, a 5-day run ending yesterday), for calendar screenshots. Results stay in memory only: nothing is saved and the real history is untouched. |
| `-LPOpenSettings 1` | macOS: opens the Settings window at launch. |
| `-LPExportSounds DIR` | Writes every synthesized sound to `DIR` as WAV files (to listen to or inspect them). |
| `-settings.colorRunes 1`, `-settings.sound 0`, `-settings.reduceMotion always\|never\|system` | Override a setting for this run (not saved unless changed in Settings). |
| `-random.colors N`, `-random.capacity N`, `-random.empty N`, `-random.locks N`, `-random.mode M` | Override the saved Random Brew settings for this run (`M` = `classic`, `locksAndKeys`, `hidden`). |

Example: `xcrun simctl launch <device> <bundle id> -LPRandomMode locks -LPRandomSeed 5 -random.colors 6 -random.locks 2`.
Daily win card: `open -n LiquidPour.app --args -LPDailySeedResults 40 -LPPlayDaily 1 -LPSkipTutorials 1 -LPDemoMoves 99`.
On the Mac, if a killed debug run left no window to restore, add `-ApplePersistenceIgnoreState YES`.

## Run the tests

```sh
scripts/test-fast.sh                     # optimized build, the suite runs in ~2-3 s (plus ~15-50 s to compile)
scripts/test-fast.sh --filter Cauldron   # only matching tests
cd Packages/BottleSortCore && swift test # debug build, ~80 s — run once before committing
LP_SLOW_TESTS=1 scripts/test-fast.sh     # also the slow performance tests (60 days of Daily generation)
```

Debug builds make the solver 30–40× slower, so iterate with `scripts/test-fast.sh` and do one debug `swift test` at the end.
The 60-day Daily performance test is opt-in (`LP_SLOW_TESTS=1`); run it when Daily, generator or solver code changes.

This runs 454 tests covering the rules (including every key and lock rule), undo/restart, hidden layers,
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
checks, and chapter 7 (every bubbling flask changes the optimum by 2+ moves). Twins and overflow pipes
(`LinkTests.swift`): every rule case (even split, free space and per-twin limits, refusals, keys, taps, runes and
ice on a twin, overflow through a full flask, the far end's veto, one hop, no backflow, seals), a hand-made puzzle
that needs a split, a spill trap, the solver against the naive BFS on ~400 random linked levels (also with
modifiers on linked flasks), pruning that keeps every distinct child, the linked key fast path against the general
encoding, JSON, validation, undo/restart, murky masks for every landing, the generator options and tutorial
checks, and chapter 8 (every link matters). Cauldrons (`CauldronTests.swift`): every rule case (pairs, leftover,
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
murky masks, the generator options and placements, and chapter 10 (every switch adds 2+ moves, an optimal solution
opens a gate, the finale is the hardest of the main path).
You can also run them in Xcode by opening `Packages/BottleSortCore/Package.swift` and pressing ⌘U.

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
# filled flask into an empty one); --link-cost C rejects levels where a link changes the optimum by fewer than C
# moves either way, except that a pipe also counts when it sets a spill trap (LinkImpact, DECISIONS 181;
# --links-matter = cost 1, the chapter uses 2). Pipes only matter in roomy 6-color size-3 boards (~1 in 150)
# --needs-split also rejects twins an optimal solution never pours into (the chain would only restrict; DECISIONS 191)
swift run -c release levelgen --colors 4 --empty 2 --twins 1 --link-placement filled --link-cost 2 --needs-split --count 5 --seed 1 --out twins.json

# Mixing cauldron: --cauldron R adds one cauldron with R (1–2) natural recipes (red + blue → purple, …) and builds
# the level BACKWARDS from a solved board: --scramble STEPS reverse moves (verified forward pours), --mix-pairs N
# un-mixed pairs per recipe; --ingredients fresh (the ingredients are extra colors that must all be brewed away) or
# sorted (they are potions of their own: the shortest win brews exactly N pairs). --mixing-matter rejects levels that could be won
# without mixing (CauldronImpact); --teaches-mixing keeps tutorial-friendly ones (empty cauldron, no parked flask,
# no dead-end first move). --locks N seals flasks after the walk, --hidden makes it murky
swift run -c release levelgen --colors 4 --empty 1 --cauldron 1 --mix-pairs 2 --scramble 80 --mixing-matter --count 5 --seed 1 --out brew.json
swift run -c release levelgen --colors 6 --capacity 3 --empty 2 --overflow 1 --link-placement mixed --link-cost 2 --count 2 --seed 1 --out pipes.json

# Switches: --switch N joins N pairs of plain, unlinked flasks with a lever (switch → gate);
# --switch-placement closed|empty|emptySwitch|any picks them (closed: both start with potion, the gate's is locked
# away; empty: the gate is an empty flask; emptySwitch: the switch is an empty flask to fill with one color).
# --switch-cost C rejects levels where a switch adds fewer than C moves to the optimal solution (SwitchImpact;
# --switch-matter = cost 1, the chapter uses 2); --teaches-switch keeps tutorial-friendly ones (every gate starts
# closed with potion, every star without a pure wait, no dead-end first move)
swift run -c release levelgen --colors 5 --empty 2 --switch 1 --switch-placement closed --switch-cost 2 --count 5 --seed 1 --out hoard.json

# Re-solve every level of every file and print difficulty tables, sorted by score, plus the
# score curve in file order; exits with status 2 on a minMoves mismatch or a chapter mechanic (seal, rune, glass, ice, bubbling, twins, pipe, cauldron, switch) that doesn't matter
swift run -c release levelgen --report ../../Levels

# Time the solver on random 8-color puzzles (also takes --locks, --essence, --essence-empty, --narrow, --funnel, --tap, --frozen, --bubbling,
# --twins, --overflow, --link-placement, --cauldron, --ingredients, --mix-pairs, --scramble, --switch, --switch-placement)
swift run -c release levelgen --bench --colors 8 --count 10
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
"to": 2}`, `{"type": "switchGate", "switch": 3, "gate": 5}`) and a `goal` (`{"type": "order", "targets": […]}`, …).
`levelgen` and `LevelLoader.encode` write version 2 only when a level uses one of these, so chapters 1–3 and the
challenges stay version 1 and `chapter_04` (essence runes), `chapter_05` (`{"type": "narrowNeck"}`,
`{"type": "funnel"}`, `{"type": "tap"}`) and `chapter_06` (`{"type": "frozen", "layer": 2, "turns": 5}`, layer 0 =
bottom), `chapter_07` (`{"type": "bubbling", "every": 3, "phase": 1}`, phase 0 when omitted) and `chapter_08`
(`links`: twins and overflow pipes), `chapter_09` (`{"type": "cauldron", "recipes": [{"a": 0, "b": 1, "result": 4}]}`,
recipes stored sorted) and `chapter_10` (`links`: `{"type": "switchGate", "switch": 1, "gate": 0}`) are version 2.
Essence, glass, frozen layers, bubbling flasks, twins, overflow pipes, cauldrons and switches are playable; the other
R5/R7 mechanics are defined but not yet: such levels decode, but fail validation.

To ship a new file, put the JSON file in `Levels/` (a synchronized folder, so no project edit is needed).

## How it works

- **Rules** (`Rules.swift`): one turn is `Rules.resolve(_:afterAction:)`, which applies the pour and then the turn order
  of MECHANICS.md §4 (immediate effects such as unsealing, move counter, timed effects, goal check). A pour runs
  through one modifier pipeline (`Rules.apply`, a switch where each flask modifier can veto or change it) and then the
  base rule (a color run moves, or a key opens its seal). The game, the solver and the generator all go through it.
- **Mechanics** (`Mechanics.swift`): a flask carries `modifiers` (`.sealed`, `.essence`, `.narrowNeck`, `.funnel`,
  `.tap`, `.frozen(layer:turns:)`, `.bubbling(every:phase:)` and `.cauldron([Recipe])` are implemented), the level has `links`
  (twins, overflow pipes and switch → gate implemented) and a `goal` (`.standard`; order, pattern, rescue for R7). A new mechanic is one
  case plus its arms in the `Rules` switches; key, JSON and validation already handle every case.
  `Bottle.lockedBy` remains as the seal's accessor, `Bottle.essenceColor` gives a flask's rune color,
  `hasNarrowNeck` / `isFunnel` / `hasTap` the glass, `frozenLayers` / `thawTurns(atLayer:)` / `holdsIce` /
  `isIcedOver` the ice, `bubbling` (`Bubbling.every` / `phase` / `movesUntilRise`) / `isBubbling` a bubbling flask,
  `isCauldron` / `recipes` a cauldron (`Rules.recipe(mixing:into:)` previews a mix, `Rules.mixed(_:pouring:amount:recipe:)`
  and `Rules.beforeMixing(_:poured:amount:recipe:pairs:)` give a cauldron's layers after and before a mix), `GameState.twin(of:)` / `overflowTarget(of:)` / `overflowSource(of:)` / `link(at:)`
  the links, `GameState.gate(of:)` / `switchFlask(of:)` / `isGateClosed(_:)`, `Rules.isSwitchOn(_:)` and
  `Rules.isGateClosed(_:in:)` the switches (the gate's state is derived, never stored), `Rules.linkRefusal(of:in:)` names a twin chain or a closed gate that refuses a pour, and `Rules.refusal(of:in:)` names the modifier that refuses a pour
  (a rune, a funnel, a tap, ice; a funnel, tap or ice is named even when the base rule refuses too, e.g. a full tap).
  Automatic effects after the pour are `Turn.events` (`TurnEvent.mixed(bottle:recipe:pairs:)` first, then
  `TurnEvent.thawed(bottle:layer:)`, then `TurnEvent.bubbled(bottle:)`, with `TurnEvent.gateOpened(switch:gate:)` /
  `.gateClosed(switch:gate:)` after the step that caused them; `GameSession.lastEvents`; `Rules.sunk(_:)` gives a risen flask's layers before the rise). Every turn reports what it poured (`Turn.pour`, a `PourEvent` with amount, layer and
  whether it left from the bottom, plus `shares` / `landings` when part of it landed in a twin or ran through a
  pipe); `Rules.outlet(of:)` says which layers a flask would pour. `MechanicImpact` is the
  "must matter" check for any mechanic (`LockImpact`, `EssenceImpact`, `GlassImpact`, `FrozenImpact` and `BubblingImpact` are its
  seal, rune, glass, ice and bubbling cases, `LinkImpact` the twins and pipes, `CauldronImpact` the cauldron,
  `SwitchImpact` the switches (one-sided: a gate only refuses pours, so the check is how many moves it adds); a
  funnel matters by the trap it sets, a pipe by the spill it can force, a cauldron by counting: without mixing the
  colors can't end in full flasks, so every solution mixes; necks, taps, bubbling and links count either way).
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
- Progress and daily results live in `UserDefaults` on each device, with no iCloud sync.
- The daily calendar and countdown use UTC days, so for players far from UTC the puzzle changes during their
  day (by design, same puzzle for everyone).
- No full accessibility pass beyond labels and VoiceOver flask contents (color runes are available in Settings).
- The difficulty score's weights are hand-picked and haven't been calibrated with playtest data.
- The solver's packed state key supports capacity ≤ 9, color ids 0–46 and key ids 0–15.
- The app has no UI tests. Gameplay was checked with screenshots taken via the debug launch arguments.

## Next steps

1. Playtest the pack and tune the score weights and tier ranges with real solve times.
2. More chapters as their mechanics land (R5: chapters 9–10); chapter 8 needs its app part (chain, pipe, split stream).
3. A full accessibility pass (VoiceOver already reads flask contents).
4. Optional iCloud progress sync.
