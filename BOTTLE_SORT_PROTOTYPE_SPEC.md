# Bottle Sort — Prototype & Solver Spec (for Claude Code)

> **How to use this file:** Put it in the root of an empty project folder on your Mac, open Claude Code there, and say:
> *"Read BOTTLE_SORT_PROTOTYPE_SPEC.md and carry out the workflow it describes, phase by phase."*

---

## 0. Instructions for Claude Code

You are building the first playable prototype of an iOS liquid-sorting puzzle game, plus the solver and level generator behind it. Work through this autonomously, following these rules:

1. **Read this whole spec first.** Then write `PLAN.md` with a checklist of every phase and task below. Keep it updated as you go.
2. **Work one phase at a time, in order.** Don't start a phase until the previous one's acceptance criteria pass.
3. **Test-driven for the core.** Everything in `BottleSortCore` must have unit tests. Run `swift test` after every meaningful change, and never leave a phase with failing tests.
4. **Commit after each completed task.** Use `git init` if needed, with small commits and clear messages (e.g. `core: add pour rules`).
5. **Record decisions.** When this spec is ambiguous, make a reasonable choice, write it in `DECISIONS.md` (one short entry per decision) and continue. Only stop to ask me if a choice would be expensive to undo.
6. **Checkpoints.** At the end of each phase, stop and give me a short summary: what was built, test results, anything I should try by hand, and open questions. Wait for my "continue" before the next phase.
7. **Keep the game logic pure.** `BottleSortCore` must not import SwiftUI, UIKit or SpriteKit. It must build and test with `swift test` on the command line.
8. **No third-party dependencies** in the core or the app. Apple frameworks only. Command-line dev tools like XcodeGen are fine (see Phase 3).
9. **Keep it simple.** This is a prototype: favor clear code over clever code, and don't build features beyond this spec.

---

## 1. Game rules (the source of truth)

### Basics
- There are **N bottles**. Each has a **capacity** (number of layer slots, e.g. 4).
- Each bottle holds a stack of **layers**, bottom → top. A layer is one unit of one color.
- In a level, each color has exactly `capacity` layers in total.
- **Move:** choose a source bottle and a target bottle.
  - The source must be non-empty.
  - The source's **top run** is the contiguous block of same-colored layers at the top.
  - The target must be **empty**, or its **top layer has the same color** as the source's top run.
  - The target must have at least one free slot.
  - Layers move one by one from the top run until the run is used up or the target is full (partial pours are allowed).
  - Source and target must be different bottles.
- **Win:** every bottle is either empty or full with a single color.

### Extensibility (design for it now, implement in Phase 5)
The model must make it easy to add bottle and layer modifiers later without rewriting the rules. Plan for:
- **Locked bottles:** `lockedBy: KeyID?`. A locked bottle can't be poured from or into.
- **Key layers:** a layer can be `.key(KeyID)` instead of `.color(ColorID)`. It takes up one slot.
- **Hidden layers** (later): a layer is shown as "?" until it is the top layer or above. This is a display-only rule, but the solver must ignore it.

Put the rules in one place (e.g. a `Rules` type or `GameState` methods) so new mechanics add a case there instead of scattering `if` checks.

---

## 2. Project structure

```
BottleSort/
├── BOTTLE_SORT_PROTOTYPE_SPEC.md
├── PLAN.md
├── DECISIONS.md
├── Packages/
│   └── BottleSortCore/            # Swift package: pure logic, testable via `swift test`
│       ├── Package.swift
│       ├── Sources/
│       │   ├── BottleSortCore/    # model, rules, solver, generator, level I/O
│       │   └── levelgen/          # command-line tool target
│       └── Tests/BottleSortCoreTests/
├── App/                           # iOS SwiftUI app (Phase 3)
│   ├── project.yml                # if XcodeGen is used
│   └── BottleSort/...
└── Levels/
    └── pack_01.json               # generated + curated levels
```

- Swift 5.9+ (or whatever the installed toolchain supports). Package platforms: iOS 17, macOS 14.

---

## 3. Phases

### Phase 1 — Core model & rules

**Build**
- `ColorID` (Int-backed), `KeyID` (Int-backed).
- `enum Layer: Hashable, Codable { case color(ColorID) /* case key(KeyID) added in Phase 5 */ }`
- `struct Bottle: Hashable, Codable { var layers: [Layer]; let capacity: Int; var lockedBy: KeyID? }`
  - Computed: `isEmpty`, `isFull`, `freeSpace`, `topLayer`, `topRunCount`, `isSolved` (empty, or full with one color).
- `struct Move: Hashable, Codable { let from: Int; let to: Int }`
- `struct GameState: Hashable, Codable { var bottles: [Bottle] }`
  - `func canPour(_ move: Move) -> Bool`
  - `func pouring(_ move: Move) -> GameState?` (returns a new state, or nil if illegal)
  - `func legalMoves() -> [Move]`
  - `var isSolved: Bool`
  - `func validate() -> [ValidationError]`: checks each color has exactly `capacity` layers, no bottle is overfilled, and the capacity is consistent.
- `GameSession` (or similar): holds the current state and the undo stack (`[GameState]`). Methods: `apply(move)`, `undo()`, `restart()`, `moveCount`.

**Tests (minimum)**
- Pouring onto an empty bottle; onto a matching color; rejected onto a mismatched color; rejected when the target is full; rejected from an empty source; rejected when source == target.
- A partial pour leaves the remainder in the source.
- A pour moves the whole top run when there is room.
- Win detection: true / false cases, including "full but mixed" = false.
- Undo restores the exact previous state; restart restores the initial state.
- `validate()` catches a bad color count.

**Acceptance:** `swift test` is green. The rules match Section 1 exactly.

---

### Phase 2 — Solver, difficulty metrics, level generator

**Solver**
- `struct Solver` with `func solve(_ state: GameState, limits: SolverLimits) -> SolverResult`.
- **Breadth-first search** for the minimum number of moves (add A* later only if BFS is too slow).
- **Canonicalization:** two states that differ only in the order of bottles count as the same state. Build a canonical key by sorting bottles. Bottles with locks/keys must keep their lock identity in the key, so include `lockedBy` in each bottle's sort key.
- **Pruning (must be safe, i.e. never removes the only optimal path; explain each rule in a comment):**
  - Never pour out of a bottle that is already solved and full.
  - Never pour a bottle whose layers are all one color into an empty bottle (pointless).
  - When several empty bottles are possible targets, only try one of them (they're interchangeable).
- `SolverLimits`: `maxStates` (e.g. 2,000,000) and an optional timeout. If a limit is hit, return `.unknown` rather than `.unsolvable`.
- `SolverResult`: `.solved(moves: [Move], statesExplored: Int)`, `.unsolvable(statesExplored: Int)`, `.unknown(reason)`.

**Hint**
- `func hint(for state: GameState) -> Move?`: the first move of the optimal solution from the current state. If the player's current state is unsolvable, report that instead (useful UI feedback: "No solution from here — undo?").

**Difficulty metrics** (`struct DifficultyReport`)
- `minMoves`: optimal solution length.
- `statesExplored`: search effort.
- `deadEndRatio`: share of reachable states (within the explored set) from which the puzzle can't be solved. Estimate it if computing it exactly is too expensive, and note the method in DECISIONS.md.
- `branchingFactor`: average number of legal moves along the optimal path.
- `score`: a single number combining the above (e.g. a weighted sum). Document the formula. It will be tuned later.

**Level generator**
- Seeded, reproducible RNG (implement SplitMix64 or similar; don't use `SystemRandomNumberGenerator`).
- `GeneratorConfig`: `colors`, `capacity`, `emptyBottles`, `seed`, plus target difficulty bounds (`minMoves` range or `score` range).
- Algorithm: shuffle all `colors × capacity` layers into `colors` full bottles, add `emptyBottles` empty ones, then **reject** the level if:
  - any bottle is already solved,
  - the solver says unsolvable / unknown,
  - its difficulty is outside the target range.
  Retry with the next seed until it passes, up to a maximum number of attempts.
- Do **not** generate levels by scrambling backwards from a solved state.

**Level file format** (`Levels/*.json`)
```json
{
  "version": 1,
  "levels": [
    {
      "id": "p1_001",
      "capacity": 4,
      "bottles": [
        { "layers": [0, 1, 1, 2] },
        { "layers": [2, 0, 1, 0] },
        { "layers": [1, 2, 2, 0] },
        { "layers": [] },
        { "layers": [] }
      ],
      "meta": { "seed": 12345, "minMoves": 11, "score": 23.4 }
    }
  ]
}
```
- Layers are listed bottom → top. Plain integers are color layers. Leave the format open for later layer types, e.g. `{"key": 1}`, and bottle fields such as `"lockedBy": 1`.
- `LevelLoader` decodes the file and runs `validate()` on every level.

**`levelgen` command-line tool**
```
swift run levelgen --colors 4 --capacity 4 --empty 2 --count 20 \
    --min-moves 8 --max-moves 15 --seed 1 --out Levels/pack_01.json
```
- Also: `swift run levelgen --report Levels/pack_01.json` re-solves every level and prints a table (id, minMoves, statesExplored, score), sorted by score.
- Produce a starter pack of **~40 levels** with a rising difficulty curve, e.g.:
  - 1–5: 3 colors, capacity 3–4, 2 empty bottles (tutorial-easy)
  - 6–20: 4–5 colors, capacity 4, 2 empty bottles
  - 21–40: 6–8 colors, capacity 4, 2 empty → occasionally 1 empty

**Tests (minimum)**
- The solver finds a known optimal solution for 3–4 hand-made small puzzles (hard-code their expected `minMoves`).
- The solver reports a hand-made unsolvable puzzle as unsolvable.
- Replaying the solver's move list on the start state reaches `isSolved == true`.
- Canonicalization: permuted bottle orders produce equal keys.
- The generator is deterministic: same config + seed → identical level.
- Every level in `Levels/pack_01.json` loads, validates and solves.

**Performance target:** an 8-color, capacity-4, 2-empty-bottle puzzle solves in under ~2 s on a Mac in release mode (`swift run -c release`). If it doesn't, profile and improve: compact state encoding (e.g. pack layers into a `[UInt8]` or an integer key), better pruning, or A* with an admissible heuristic. Note the results in DECISIONS.md.

**Acceptance:** tests green; `pack_01.json` exists with ~40 validated levels; the `--report` output shows rising difficulty.

---

### Phase 3 — Playable SwiftUI prototype

**Project setup**
- If `xcodegen` is installed (`which xcodegen`), create `App/project.yml` and generate the project, with the local `BottleSortCore` package as a dependency.
- If it isn't installed, stop and ask me to either install it (`brew install xcodegen`) or create an iOS App project manually in Xcode, which you will then fill in. Don't hand-write a `.pbxproj`.
- Bundle `Levels/pack_01.json` into the app.

**Gameplay screen**
- Bottles drawn with plain SwiftUI shapes: a rounded-rectangle outline with stacked colored rectangles for the layers. Up to 7 bottles per row, wrapping to a second row.
- Use a fixed, distinct palette of 12 colors, defined in one place.
- **Interaction:** tap a source bottle (it lifts / highlights), then tap a target.
  - Legal move → animate the layers moving (a simple animated transition is enough for now).
  - Illegal move → small shake + light haptic, then deselect.
  - Tapping the same bottle again deselects it.
- HUD: level number, move counter, **Undo**, **Restart**, **Hint** (highlights the suggested source and target briefly).
- Win: overlay with move count vs. `minMoves` (e.g. 3 stars if equal, 2 if within +3, otherwise 1), with **Next** / **Replay** buttons.
- If the player reaches a state with no legal moves, or the solver says it's unsolvable, show "Stuck — undo or restart?".

**Level select**
- Grid of level numbers. Locked/unlocked state and best stars per level, saved with `UserDefaults` (wrap it in a small `ProgressStore` so it can be swapped out later).

**Architecture**
- An `@Observable` (or `ObservableObject`) `GameViewModel` wraps `GameSession`. Views contain no rule logic.
- Run hint/solver calls off the main thread so the UI never freezes.

**Acceptance:** the app builds and runs in the iOS Simulator; I can play through levels 1–10, using undo, restart and hint; progress survives an app relaunch. Tell me exactly how to build and run it.

---

### Phase 4 — Verification & cleanup

- Re-run all tests. Run `levelgen --report` and include the table in the checkpoint summary.
- Add `README.md`: what the project is, how to run the tests, how to generate levels, how to run the app.
- Quick review pass: remove dead code, make sure the core has no UI imports, and check that the rules exist in exactly one place.
- List known limitations and suggested next steps.

**Acceptance:** green tests, clean build, README accurate.

---

### Phase 5 — (Optional, only when I say so) Locks & keys

Rules to implement:
- `Layer.key(KeyID)` occupies one slot. It can only move when it is the top layer, and it moves alone (a key never forms a run with other layers).
- A key can only be poured onto a bottle with `lockedBy == thatKeyID`. When this happens, the bottle becomes unlocked and the key is consumed (removed from the game).
- Keys can't be poured onto unlocked bottles, and colors can't be poured onto keys. If a key is the top layer of a bottle, nothing can be poured into that bottle.
- Locked bottles can't be poured from or into. They may contain layers, which become reachable once unlocked.
- Win: no key layers remain, no bottle is locked, and the normal win condition holds.

Update together: the rules, the solver (canonical key and pruning must stay correct), the generator (option: `--locks 1`, which places the key in a random non-top position in a non-locked bottle and puts some of the colors inside the locked bottle), the JSON format, the UI (a lock icon on the bottle, a key icon as a layer) and the tests (including a puzzle that *requires* using the key to be solvable).

---

## 4. Definition of done (prototype)

- [ ] `swift test` green, with good coverage of rules, solver and generator
- [ ] `levelgen` produces validated, solvable, difficulty-sorted packs
- [ ] A ~40-level pack ships in the app
- [ ] The app is playable in the Simulator: pour, undo, restart, hint, win, level select, saved progress
- [ ] `README.md`, `PLAN.md` and `DECISIONS.md` are up to date
