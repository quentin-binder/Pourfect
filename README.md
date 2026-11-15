# LiquidPour

A liquid-sorting puzzle game for **iPhone, iPad and Mac** (native Apple silicon), built with SwiftUI.
Pour colored layers between bottles until every bottle is empty or full with one color.

This is the prototype described in [`BOTTLE_SORT_PROTOTYPE_SPEC.md`](BOTTLE_SORT_PROTOTYPE_SPEC.md).
Progress is tracked in [`PLAN.md`](PLAN.md); design choices are in [`DECISIONS.md`](DECISIONS.md).

## Layout

```
LiquidPour.xcodeproj         Xcode project (one multiplatform app target: iOS 17+ / macOS 14+)
LiquidPour/                  SwiftUI app
  Model/                     GameViewModel, LevelCatalog, ProgressStore, Palette
  Views/                     RootView, LevelSelectView, GameView, BottleView
Packages/BottleSortCore/     Swift package — pure game logic, no UI imports
  Sources/BottleSortCore/    Model, Rules, Solver, Difficulty, Generator, LevelFile
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

Debug builds accept two launch arguments (set them in *Edit Scheme ▸ Run ▸ Arguments*):
`-LPOpenLevel N` opens level N directly, and `-LPDemoMoves K` auto-plays the first K optimal moves.

## Run the tests

```sh
cd Packages/BottleSortCore
swift test
```

This runs 53 tests covering the rules, undo/restart, validation, the solver (cross-checked against a naive
BFS on 125 random puzzles), hints, canonical keys, difficulty metrics, the generator's determinism, the JSON
format, and the shipped pack (every level loads, validates and solves in its recorded `minMoves`).
You can also run them in Xcode by opening `Packages/BottleSortCore/Package.swift` and pressing ⌘U.

## Generate levels

```sh
cd Packages/BottleSortCore

# One configuration (spec example)
swift run -c release levelgen --colors 4 --capacity 4 --empty 2 --count 20 \
    --min-moves 8 --max-moves 15 --seed 1 --out ../../Levels/pack_02.json

# The starter pack (tiers from 3 to 8 colors, sorted by difficulty score)
swift run -c release levelgen --preset starter --seed 1 --out ../../Levels/pack_01.json

# Re-solve every level in a pack and print a difficulty table, sorted by score
swift run -c release levelgen --report ../../Levels/pack_01.json

# Time the solver on random 8-color puzzles
swift run -c release levelgen --bench --colors 8 --count 10
```

Optional generator flags: `--min-score/--max-score` and `--id-prefix`. Generation is fully deterministic:
the same flags and seed always produce the same pack.

Level files are JSON. Layers are listed bottom → top, and each color layer is an integer:

```json
{ "version": 1, "levels": [ { "id": "p1_001", "capacity": 4,
  "bottles": [ { "layers": [0, 1, 1, 2] }, { "layers": [] } ],
  "meta": { "seed": 12345, "minMoves": 11, "score": 23.4 } } ] }
```

To ship a new pack, add the JSON file to the `Levels` group in Xcode (target *LiquidPour*), then load it
with `LevelCatalog.loadBundled(named:)`.

## How it works

- **Rules** (`Rules.swift`): a single function, `Rules.pourAmount(from:to:)`, decides whether a pour is legal and how many layers move.
  The game, the solver and the generator all go through it.
- **Solver**: breadth-first search for the fewest moves. Each state gets a compact key that ignores
  bottle order, and three pruning rules skip moves that can't change the outcome.
  An 8-color level solves in about 10–40 ms in a release build.
- **Difficulty score** = `minMoves + 1.5·log2(statesExplored) + 40·deadEndRatio + 0.5·branchingFactor`.
- **Generator**: shuffles random layers with a seed, then rejects levels that are already sorted, unsolvable, or outside the target difficulty.
- **App**: `GameViewModel` wraps `GameSession`. After every move it solves the new state in the background
  to detect dead ends ("Stuck — undo or restart?") and to keep the next hint ready instantly.

## Known limitations

- Pour animation is a simple fade/slide transition, not a tilting-bottle animation.
- Only one level pack. There's no menu for choosing packs, and progress is keyed by level id.
- Progress lives in `UserDefaults` on each device, with no iCloud sync.
- No sound, settings screen, tutorial overlay or accessibility pass beyond basic labels. Colors alone tell
  layers apart, which is hard for color-blind players.
- The difficulty score's weights are hand-picked and haven't been calibrated with playtest data.
- The solver's packed state key supports capacity ≤ 9 and color ids ≤ 61.
- The app has no UI tests. Gameplay was checked with screenshots taken via the debug launch arguments.

## Next steps

1. Playtest the pack and tune the score weights and tier ranges with real solve times.
2. Phase 5: locks and keys (model fields and JSON hooks are already in place).
3. Color-blind support (patterns or symbols per color) and VoiceOver descriptions of bottle contents.
4. A pour animation (tilt + stream), sound and haptic polish.
5. More packs and a pack picker; optional iCloud progress sync.
