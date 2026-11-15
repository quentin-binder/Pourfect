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

Chapters 4–10 (Glyph Library … Dragon's Hoard, `ChapterOutline.plan`) show as "coming soon".
Optional **Challenges** (never gated):

| File | Pack | Ids | Levels | Moves | Score | What makes it hard |
|---|---|---|---|---|---|---|
| `challenge_challenger` | Challenger | `p2_…` | 30 | 15–34 | 43–72 | 8–10 colors, taller flasks, one-empty-flask levels |
| `challenge_expert` | Expert | `p3_…` | 30 | 20–41 | 50–84 | 10–12 colors, flask size 5, one empty flask |
| `challenge_master` | Master | `p6_…` | 20 | 22–43 | 53–96 | 12 colors, size-5 flasks, 2 locks, hidden 10-color boards |

Each chapter starts with a tiny tutorial recipe and then rises in difficulty score; challenges keep only the
highest-scoring levels from a larger generated pool. Level ids of the original packs are unchanged, so saved
stars keep counting. (The old Locks & Keys and Hidden Depths packs were replaced by chapters 2 and 3.)

## Layout

```
LiquidPour.xcodeproj         Xcode project (one multiplatform app target: iOS 17+ / macOS 14+)
LiquidPour/                  SwiftUI app
  Model/                     GameViewModel, LevelCatalog, ProgressStore, AppSettings, Palette, RandomLevelMaker
  Views/                     RootView, LevelSelectView, GameView, BottleView, RandomLevelView,
                             PourAnimationView, TiltedLiquid, FlaskDecor, WorkbenchBackground, SettingsView
  Assets.xcassets            Optimized painted art (workbench backgrounds, chapter map, chapter vignettes)
  Localizable.xcstrings      English String catalog for all UI text; InfoPlist.xcstrings names the app
  Feedback/                  SoundEngine (synthesized sounds), Haptics, FeedbackPlayer
Packages/BottleSortCore/     Swift package — pure game logic, no UI imports
  Sources/BottleSortCore/    Model, Rules, Solver, Difficulty, Generator, LevelFile, GameSession, RandomLevel, Settings
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
  Clearing a level unlocks the next one. Progress is saved on the device.
- A pour is animated: the bottle flies over the target, tilts, and a stream fills the target. Taps made during
  a pour are queued. With *Reduce Motion* on, the levels just change in place.

### Modes

- **Classic**: the 40 levels of the starter pack, and random levels.
- **Locks & Keys** (random levels): a locked bottle shows a lock in its key's color and its contents are dimmed.
  It can't be poured from or into. A key is a dark layer with a key icon. It always moves alone, and only into the
  bottle with the matching lock. That bottle unlocks (the key drops into the lock and the lock pops off) and the key
  disappears. You win when every bottle is sorted, so all keys must be used.
- **Hidden layers** (random levels): every layer below a bottle's top run is shown as a grey "?". A layer flips over
  to its real color once it becomes part of the top run, and stays revealed. Undo and restart restore the "?" layers.
  This is display-only; the rules and the solver see every layer.

### Random Brew (random levels)

Tap **Random Brew** (dice) at the top of the level list, or the dice in the toolbar. Pick a mode, the number of
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
  `bg_workbench_portrait` for tall ones), dimmed in the middle so the flasks read clearly; the level list has a
  blurred, washed copy. Both come from `WorkbenchBackground(style: .game / .menu)`. The chapter map
  (`chapter_map`) and chapter vignettes (`chapter_01`…`chapter_10`) are in the catalog for the chapter screens.
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
| `-LPOpenLevel N` | Opens level N (1-based) directly, ignoring locks. |
| `-LPOpenPack P` | With `-LPOpenLevel`: which pack (1-based, default 1 = Starter). |
| `-LPUnlockAll 1` | Makes every pack level playable in the grid (saved stars are untouched). |
| `-LPDemoMoves K` | Auto-plays the first K optimal moves through the normal tap path (with the pour animation). |
| `-LPDemoUndo N` | After `-LPDemoMoves`: undoes N moves, one per second. |
| `-LPRandomSettings 1` | Opens the Random Level screen. |
| `-LPRandomGenerate 1` | With `-LPRandomSettings 1`: presses *Generate* once. |
| `-LPRandomMode classic\|locks\|hidden` | Generates a random level with the saved settings and opens it. |
| `-LPRandomSeed S` | Seed for `-LPRandomMode` (default 1), so the same level comes back every time. |
| `-LPOpenSettings 1` | macOS: opens the Settings window at launch. |
| `-LPExportSounds DIR` | Writes every synthesized sound to `DIR` as WAV files (to listen to or inspect them). |
| `-settings.colorRunes 1`, `-settings.sound 0`, `-settings.reduceMotion always\|never\|system` | Override a setting for this run (not saved unless changed in Settings). |
| `-random.colors N`, `-random.capacity N`, `-random.empty N`, `-random.locks N`, `-random.mode M` | Override the saved Random Level settings for this run (`M` = `classic`, `locksAndKeys`, `hidden`). |

Example: `xcrun simctl launch <device> <bundle id> -LPRandomMode locks -LPRandomSeed 5 -random.colors 6 -random.locks 2`.

## Run the tests

```sh
cd Packages/BottleSortCore
swift test
```

This runs 143 tests covering the rules (including every key and lock rule), undo/restart, hidden layers,
validation, the solver (cross-checked against a naive BFS on 125 random puzzles and 175 random lock levels),
hints, canonical keys, difficulty metrics, the generator's determinism, random levels, the JSON format and pack metadata,
the chapter gate (including the exact-50 % boundary), the lock-impact check, and the shipped files (every level
loads and validates, ids are unique across files, chapter 1 keeps the Starter ids, chapters have the expected
shape, every lock in a chapter matters, and every level whose recorded search is small solves in its recorded
`minMoves` — the larger ones are re-solved by `levelgen --report` in release).
You can also run them in Xcode by opening `Packages/BottleSortCore/Package.swift` and pressing ⌘U.

## Generate levels

```sh
cd Packages/BottleSortCore

# Regenerate all six shipped files (about 90 s; output is deterministic)
swift run -c release levelgen --preset all --out-dir ../../Levels

# One file: chapter1 | chapter2 | chapter3 | challenger | expert | master
swift run -c release levelgen --preset chapter2 --out ../../Levels/chapter_02.json

# One configuration; --pool 3 keeps the hardest 20 of 60 passing levels, --hidden makes "?" levels
swift run -c release levelgen --colors 9 --capacity 4 --empty 2 --count 20 --pool 3 \
    --min-moves 26 --max-moves 40 --seed 1 --name "My Pack" --out my_pack.json

# Lock levels: N locked full flasks, their keys buried in the others (0 ≤ N < colors);
# --locks-matter rejects levels where a lock only adds the key pour (LockImpact)
swift run -c release levelgen --colors 5 --empty 2 --locks 1 --locks-matter --count 5 --seed 1 --out locks.json

# Re-solve every level of every file and print difficulty tables, sorted by score, plus the
# score curve in file order; exits with status 2 on a minMoves mismatch or a chapter lock that doesn't matter
swift run -c release levelgen --report ../../Levels

# Time the solver on random 8-color puzzles
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
first-time tutorial explains: `"basic"`, `"sealed"`, `"murky"`; unknown names still load):

```json
{ "version": 1, "name": "Rune Vault", "kind": "chapter", "chapter": 2, "location": "Rune Vault",
  "introduces": ["sealed"], "levels": [ { "id": "c2_001", "capacity": 4,
  "bottles": [ { "layers": [0, 1, 1, 2] }, { "layers": [3, 3, 3, 3], "lockedBy": 1 },
               { "layers": [2, {"key": 1}, 0] }, { "layers": [] } ],
  "meta": { "seed": 12345, "minMoves": 11, "score": 23.4 } } ] }
```

Every lock needs exactly one matching key and vice versa; the loader rejects files that break this.

To ship a new file, put the JSON file in `Levels/` (a synchronized folder, so no project edit is needed).

## How it works

- **Rules** (`Rules.swift`): a single function, `Rules.pour(from:to:)`, decides whether a pour is legal and what it does
  (a color run moves, or a key opens its lock). The game, the solver and the generator all go through it.
- **Solver**: breadth-first search for the fewest moves. Each state gets a compact key that ignores
  bottle order, and three pruning rules skip moves that can't change the outcome.
  An 8-color level solves in about 10–40 ms in a release build.
- **Difficulty score** = `minMoves + 1.5·log2(statesExplored) + 40·deadEndRatio + 0.5·branchingFactor`.
- **Generator**: shuffles random layers with a seed, then rejects levels that are already sorted, unsolvable, or outside the target difficulty.
- **App**: `GameViewModel` wraps `GameSession`. After every move it solves the new state in the background
  to detect dead ends ("Stuck — undo or restart?") and to keep the next hint ready instantly.
  It applies each move first and then publishes a `PourEvent`; the view only animates it.
  Hidden layers come from `GameSession.isHidden` / `hiddenDepths`; views contain no rule logic.
- **Feedback**: the view model publishes `FeedbackEvent`s (select, illegal, pour, flask completed, level won);
  `FeedbackPlayer` turns them into sound and haptics, timed to the pour animation. "Flask completed" is
  `Rules.completedBottles(before:after:)` in the core and fires when the pour lands.
- **Sound**: `SoundEngine` synthesizes every sound at launch, off the main thread (glass clinks, bubbly gurgles,
  cork pop + chime, success arpeggio, muted tap, key click), and plays the PCM buffers with `AVAudioEngine`; no
  audio files. Sounds and haptics scheduled for later in a pour are dropped when that pour is cancelled (Undo,
  Restart, new level), when you leave the game, or when Sound is turned off.
- **Flask look**: a completed flask gets a cork that drops in with a bounce and a sparkle burst in the potion's
  color; glass sheen and a soft potion glow on every flask. With *Color Runes* on, every layer shows one of 12
  runes (one per color) so colors can be told apart without hue.
- **Settings** (gear in the level list, or ⌘, on the Mac): sound, haptics (iOS), color runes, reduce motion
  (system / on / off). Stored behind `SettingsStore` (`UserDefaults` keys `settings.*`).

## Known limitations

- Random levels can take a few seconds for the largest settings (up to ~2.5 s per level in a release build on an
  M-series Mac, longer on a phone or in a debug build; a hard attempt can take ~5 s). Leaving the screen, Replay or Undo
  cancels a running generation.
- Pour animation: a pour between rows makes the flying bottle cover the upper row; near the top of a short screen
  the tilted bottle can overlap the header.
- All packs are open from the start (levels unlock only within a pack). Progress is keyed by level id, so
  regenerating a pack with different content keeps old stars on the new levels.
- One empty bottle makes almost every puzzle with 6+ colors (bottle size 4) unsolvable, so one-empty levels stay at
  5 colors, or 6 colors with size-5 bottles.
- Progress lives in `UserDefaults` on each device, with no iCloud sync.
- No tutorial overlay or accessibility pass beyond basic labels (color runes are available in Settings).
- The difficulty score's weights are hand-picked and haven't been calibrated with playtest data.
- The solver's packed state key supports capacity ≤ 9, color ids 0–46 and key ids 0–15.
- The app has no UI tests. Gameplay was checked with screenshots taken via the debug launch arguments.

## Next steps

1. Playtest the pack and tune the score weights and tier ranges with real solve times.
2. More chapters as their mechanics land (R5).
3. VoiceOver descriptions of bottle contents.
4. More packs and a pack picker; optional iCloud progress sync.
