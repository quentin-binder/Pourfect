# Plan — LiquidPour (Bottle Sort prototype)

Source of truth: `BOTTLE_SORT_PROTOTYPE_SPEC.md`. Decisions: `DECISIONS.md`.

## Setup
- [x] Move spec to repo root, add `.gitignore`
- [x] App target: iOS/iPadOS + native macOS (no visionOS, no Catalyst), min iOS 17 / macOS 14
- [x] Verify app builds for macOS (arm64) and iOS Simulator

## Phase 1 — Core model & rules
- [x] Swift package `Packages/BottleSortCore` (library + `levelgen` executable + tests)
- [x] `ColorID`, `KeyID`, `Layer`, `Bottle`, `Move`, `GameState`
- [x] Rules in one place (`Rules.swift`): canPour / pouring / legalMoves / isSolved
- [x] `validate()` → `[ValidationError]`
- [x] `GameSession`: apply / undo / restart / moveCount
- [x] Tests: pour cases, partial pour, full-run pour, win detection, undo/restart, validation
- [x] Checkpoint (awaiting "continue")

## Phase 2 — Solver, difficulty, generator
- [ ] Canonical state key (bottle-order independent, includes `lockedBy`)
- [ ] BFS `Solver` with safe pruning + `SolverLimits` / `SolverResult`
- [ ] `hint(for:)`
- [ ] `DifficultyReport` (minMoves, statesExplored, deadEndRatio, branchingFactor, score)
- [ ] SplitMix64 RNG + `GeneratorConfig` + rejection-sampling generator
- [ ] Level JSON format + `LevelLoader` (validates)
- [ ] `levelgen` CLI (generate + `--report`)
- [ ] `Levels/pack_01.json` (~40 levels, rising difficulty)
- [ ] Tests: known optimal puzzles, unsolvable, replay, canonicalization, determinism, pack loads/solves
- [ ] Perf: 8 colors / cap 4 / 2 empty < ~2 s release
- [ ] Checkpoint

## Phase 3 — SwiftUI app (iOS + macOS)
- [ ] Link local package into `LiquidPour.xcodeproj`; bundle `Levels/pack_01.json`
- [ ] 12-color palette, bottle view, game screen, HUD, win overlay, stuck banner
- [ ] Level select + `ProgressStore` (UserDefaults)
- [ ] `GameViewModel` (@Observable), solver off main thread
- [ ] Builds & runs on iOS Simulator and macOS
- [ ] Checkpoint

## Phase 4 — Verification & cleanup
- [ ] All tests, `levelgen --report` table
- [ ] README.md
- [ ] Review pass, limitations & next steps
- [ ] Checkpoint

## Phase 5 — Locks & keys (only on request)
