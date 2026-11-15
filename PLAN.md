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
- [x] Canonical state key (bottle-order independent, includes `lockedBy`)
- [x] BFS `Solver` with safe pruning + `SolverLimits` / `SolverResult`
- [x] `hint(for:)`
- [x] `DifficultyReport` (minMoves, statesExplored, deadEndRatio, branchingFactor, score)
- [x] SplitMix64 RNG + `GeneratorConfig` + rejection-sampling generator
- [x] Level JSON format + `LevelLoader` (validates)
- [x] `levelgen` CLI (generate + `--report`)
- [x] `Levels/pack_01.json` (~40 levels, rising difficulty)
- [x] Tests: known optimal puzzles, unsolvable, replay, canonicalization, determinism, pack loads/solves
- [x] Perf: 8 colors / cap 4 / 2 empty < ~2 s release
- [x] Checkpoint (awaiting "continue")

## Phase 3 — SwiftUI app (iOS + macOS)
- [x] Link local package into `LiquidPour.xcodeproj`; bundle `Levels/pack_01.json`
- [x] 12-color palette, bottle view, game screen, HUD, win overlay, stuck banner
- [x] Level select + `ProgressStore` (UserDefaults)
- [x] `GameViewModel` (@Observable), solver off main thread
- [x] Builds & runs on iOS Simulator and macOS
- [x] Verified: iOS Simulator screenshots (level select, game, win, persistence after relaunch); native arm64 macOS app launches

## Phase 4 — Verification & cleanup
- [x] All tests, `levelgen --report` table
- [x] README.md
- [x] Review pass, limitations & next steps
- [x] Checkpoint

## Phase 5 — Locks & keys, hidden layers, random levels (core)
- [x] `Layer.key(KeyID)`, JSON `{"key": n}`, `Layer.colorID` nil for keys, description `k1`
- [x] `Rules.pour(from:to:)` — single function for all move effects (color run, key → unlock + consume)
- [x] Win requires no keys and no locks
- [x] Validation: duplicate key / duplicate lock / lock without key / key without lock
- [x] `StateKey` key tokens (colors 0…46, keys 0…15)
- [x] Solver pruning re-checked for keys (rule 3 skips only unlocked empties)
- [x] Generator `locks` option + `levelgen --locks N` (pack_01 unchanged)
- [x] Tests: every key/lock rule, JSON round-trip, validation, canonical key, puzzle that needs the key, solver vs reference BFS on lock levels, generator determinism
- [x] Hidden layers: `LevelDefinition.hidden`, `GameSession(_:hidden:)`, `isHidden(bottle:layer:)`, undo/restart restore
- [x] `RandomLevel.generate` (6-attempt cap, progress callback, `GameMode` classic / locks & keys / hidden) + tests
- [ ] App: lock icon on bottles, key layer, "?" for hidden layers, Random Level button (separate task)
