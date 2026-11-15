# LiquidPour

A liquid-sorting puzzle game for **iPhone, iPad and Mac** (native Apple silicon), built with SwiftUI.
Pour colored layers between bottles until every bottle is empty or full with one color.

This is the prototype described in [`BOTTLE_SORT_PROTOTYPE_SPEC.md`](BOTTLE_SORT_PROTOTYPE_SPEC.md).
Progress is tracked in [`PLAN.md`](PLAN.md); design choices are in [`DECISIONS.md`](DECISIONS.md).

## Layout

```
LiquidPour.xcodeproj         Xcode project (one multiplatform app target: iOS 17+ / macOS 14+)
LiquidPour/                  SwiftUI app
  Model/                     GameViewModel, LevelCatalog, ProgressStore, Palette, RandomLevelMaker
  Views/                     RootView, LevelSelectView, GameView, BottleView, RandomLevelView,
                             PourAnimationView, TiltedLiquid
Packages/BottleSortCore/     Swift package — pure game logic, no UI imports
  Sources/BottleSortCore/    Model, Rules, Solver, Difficulty, Generator, LevelFile, GameSession, RandomLevel
  Sources/levelgen/          Command-line level generator
  Tests/BottleSortCoreTests/ Swift Testing suite
Levels/pack_01.json          The 40 levels bundled into the app
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

### Random Level

Tap **Random Level** (dice) at the top of the level list, or the dice in the toolbar. Pick a mode, the number of
colors (2–12), the bottle size (2–6), empty bottles (0–4) and, in Locks & Keys, the number of locks (1–2), then
**Generate**. The settings are remembered.

The level is generated off the main thread with a fresh random seed. Up to 6 candidates are tried ("Attempt k of 6");
a candidate is rejected if a bottle is already sorted or the solver can't prove it solvable within 1M states
(no time limit, so a seed gives the same level on every device).
If all 6 fail you get "Couldn't find a solvable level in 6 tries — try more empty bottles or fewer colors".
Boards with no empty bottle are almost always unsolvable. Random levels are played in the normal game screen
(Hint and stuck detection included). They don't change saved progress, and the win card offers
**New Random Level** with the same settings instead of *Next*.

### Debug launch arguments

DEBUG builds accept these (set them in *Edit Scheme ▸ Run ▸ Arguments*, or pass them to `simctl launch` / `open --args`):

| Argument | Effect |
|---|---|
| `-LPOpenLevel N` | Opens pack level N (1-based) directly, ignoring locks. |
| `-LPDemoMoves K` | Auto-plays the first K optimal moves through the normal tap path (with the pour animation). |
| `-LPRandomSettings 1` | Opens the Random Level screen. |
| `-LPRandomGenerate 1` | With `-LPRandomSettings 1`: presses *Generate* once. |
| `-LPRandomMode classic\|locks\|hidden` | Generates a random level with the saved settings and opens it. |
| `-LPRandomSeed S` | Seed for `-LPRandomMode` (default 1), so the same level comes back every time. |
| `-random.colors N`, `-random.capacity N`, `-random.empty N`, `-random.locks N`, `-random.mode M` | Override the saved Random Level settings for this run (`M` = `classic`, `locksAndKeys`, `hidden`). |

Example: `xcrun simctl launch <device> <bundle id> -LPRandomMode locks -LPRandomSeed 5 -random.colors 6 -random.locks 2`.

## Run the tests

```sh
cd Packages/BottleSortCore
swift test
```

This runs 95 tests covering the rules (including every key and lock rule), undo/restart, hidden layers,
validation, the solver (cross-checked against a naive BFS on 125 random puzzles and 175 random lock levels),
hints, canonical keys, difficulty metrics, the generator's determinism, random levels, the JSON format, and the
shipped pack (every level loads, validates and solves in its recorded `minMoves`).
You can also run them in Xcode by opening `Packages/BottleSortCore/Package.swift` and pressing ⌘U.

## Generate levels

```sh
cd Packages/BottleSortCore

# One configuration (spec example)
swift run -c release levelgen --colors 4 --capacity 4 --empty 2 --count 20 \
    --min-moves 8 --max-moves 15 --seed 1 --out ../../Levels/pack_02.json

# Lock levels: N locked full bottles, their keys buried in the other bottles (0 ≤ N < colors)
swift run -c release levelgen --colors 5 --empty 2 --locks 1 --count 5 --seed 1 --out locks.json

# The starter pack (tiers from 3 to 8 colors, sorted by difficulty score)
swift run -c release levelgen --preset starter --seed 1 --out ../../Levels/pack_01.json

# Re-solve every level in a pack and print a difficulty table, sorted by score
swift run -c release levelgen --report ../../Levels/pack_01.json

# Time the solver on random 8-color puzzles
swift run -c release levelgen --bench --colors 8 --count 10
```

Optional generator flags: `--min-score/--max-score` and `--id-prefix`. Generation is fully deterministic:
the same flags and seed always produce the same pack.

Level files are JSON. Layers are listed bottom → top. A color layer is an integer and a key layer is
`{"key": n}`. A locked bottle has `"lockedBy": n`, and `"hidden": true` turns on hidden layers for a level:

```json
{ "version": 1, "levels": [ { "id": "p1_001", "capacity": 4,
  "bottles": [ { "layers": [0, 1, 1, 2] }, { "layers": [3, 3, 3, 3], "lockedBy": 1 },
               { "layers": [2, {"key": 1}, 0] }, { "layers": [] } ],
  "meta": { "seed": 12345, "minMoves": 11, "score": 23.4 } } ] }
```

Every lock needs exactly one matching key and vice versa; the loader rejects files that break this.

To ship a new pack, add the JSON file to the `Levels` group in Xcode (target *LiquidPour*), then load it
with `LevelCatalog.loadBundled(named:)`.

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

## Known limitations

- Locks & Keys and Hidden layers exist only as random levels. There's no hand-curated pack for them.
- Random levels can take a few seconds for the largest settings (up to ~2.5 s per level in a release build on an
  M-series Mac, longer on a phone or in a debug build; a hard attempt can take ~5 s). Leaving the screen, Replay or Undo
  cancels a running generation.
- Pour animation: a pour between rows makes the flying bottle cover the upper row; near the top of a short screen
  the tilted bottle can overlap the header.
- Only one level pack. There's no menu for choosing packs, and progress is keyed by level id.
- Progress lives in `UserDefaults` on each device, with no iCloud sync.
- No sound, settings screen, tutorial overlay or accessibility pass beyond basic labels. Colors alone tell
  layers apart, which is hard for color-blind players.
- The difficulty score's weights are hand-picked and haven't been calibrated with playtest data.
- The solver's packed state key supports capacity ≤ 9, color ids 0–46 and key ids 0–15.
- The app has no UI tests. Gameplay was checked with screenshots taken via the debug launch arguments.

## Next steps

1. Playtest the pack and tune the score weights and tier ranges with real solve times.
2. Curated Locks & Keys and Hidden-layer packs (`levelgen --locks` already generates lock levels).
3. Color-blind support (patterns or symbols per color) and VoiceOver descriptions of bottle contents.
4. Sound and haptic polish.
5. More packs and a pack picker; optional iCloud progress sync.
