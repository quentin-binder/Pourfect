# Plan — LiquidPour (Bottle Sort prototype)

Decisions: `DECISIONS.md`. (The original prototype spec was removed from the repo after Phase 5.)

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
- [x] Merged into `main`; `swift test` green (95 tests)

## Phase 5 — App: new mechanics
- [x] Key layer (dark layer, `key.fill` in the key's color; key/lock colors in `Palette`)
- [x] Locked bottle: `lock.fill` badge in the key's color, contents dimmed, outline tinted
- [x] Key pour uses the pour animation: key drops into the lock, lock pops away
- [x] Hidden layers: grey "?" from `GameSession.hiddenDepths`; flip reveal; flying bottle keeps them grey
- [x] `GameViewModel` creates `GameSession(_:hidden:)` from the level's flag
- [x] Hint and stuck detection on lock and hidden levels (same solver path)

## Random level
- [x] "Random Level" card (dice) on the level list + toolbar button
- [x] Settings: mode, colors 2–12, bottle size 2–6, empty 0–4, locks 1–2 (Locks & Keys only); clamped by core; remembered
- [x] Generate off the main thread with a fresh seed, "Attempt k of 6", failure message after 6 tries
- [x] Played in `GameView`; no effect on progress; win card offers "New Random Level"
- [x] DEBUG launch args `-LPRandomSettings`, `-LPRandomGenerate`, `-LPRandomMode`, `-LPRandomSeed`
- [x] Verified: iOS Simulator screenshots (settings, progress, failure, lock level, key pour, hidden level, random win) + macOS lock level

## Pour animation
- [x] `PourEvent` published by the view model after the move is applied; taps queued (≤ 2) during a pour
- [x] Tilt + stream + continuous fill (`PourPose` timeline, `TiltedLiquid` level surface), 1.1 s
- [x] Undo / restart / level change cancel the pour; win & stuck cards wait for it
- [x] Reduce Motion: in-place level change
- [x] Verified on iOS Simulator and macOS (burst screenshots)
- [ ] Not hand-tested: undo during a pour, macOS window resize during a pour

## Level packs
- [x] Remove the prototype spec file
- [x] Pack name/subtitle in the JSON format; levelgen `--hidden`, `--pool`, `--name`, presets and `--preset all`
- [x] Five new harder packs (Challenger, Expert, Locks & Keys, Hidden Depths, Master) — 140 new levels
- [x] App: loads every bundled `pack_*.json`, pack picker with star totals, pack-aware routing, `-LPOpenPack`
- [x] Tests: every shipped pack loads/validates, unique ids, solvable levels checked; all 180 re-solved by `--report`
