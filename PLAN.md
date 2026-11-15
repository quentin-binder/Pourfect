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

---

# Roadmap — Pourfect: Potion Lab (post-prototype)

Sources: `FUTURE_FEATURES.md` (milestones) and `MECHANICS.md` (mechanics catalogue). Decisions behind this plan: `DECISIONS.md` #56–#63.
Every mechanic still ships as **rules + solver + generator + JSON + UI + tutorial + tests** together, and game logic stays in `BottleSortCore`.

Already done from the docs: pour animation with stream and wobble (M1), sealed flasks & keys (A1), murky/hidden layers (B1), random levels, six generated packs.

Order: **R1 Polish → R2 Pourfect theme & chapters → R3 Daily → R4 Mechanics architecture → R5 Mechanics (one chapter each) → R6 Challenges → R7 Orders & story → R8 Release.**
Each R-step is sized as one Claude Code task (or one workflow); stop for a checkpoint after each.

## R1 — Polish (finish Milestone 1)
- [ ] Haptics: light tap on select, soft thud on pour, success pattern on a completed flask (iOS; no-op on Mac)
- [ ] Sound, synthesized with AVAudioEngine (no files): glass clink, pour gurgle (length follows the pour), cork pop + sparkle chime
- [ ] Completed flask: cork drops in + small particle burst (SwiftUI Canvas)
- [ ] Glass highlight and a soft glow on potions
- [ ] Colorblind runes: one simple vector rune per color (12), drawn on every layer when enabled
- [ ] Settings screen: sound, haptics, colorblind runes, reduce-motion override; stored behind a `SettingsStore` protocol
- [ ] Tests: settings persistence; "flask completed" detection lives in core

## R2 — Pourfect theme & chapters (Milestone 2)
- [ ] Rename to **Pourfect**: display name, window title, in-app titles. Code/module names stay neutral; the target/bundle id rename waits for R8
- [ ] UI wording: bottles → flasks, levels → recipes, packs → chapters (strings only)
- [ ] Art drawn in code: wizard's workbench background, 2–3 flask silhouettes, 12-color potion palette with names
- [ ] String catalog (English only for now, ready for more languages)
- [ ] Chapter map (main path), star-gated: Ch. 1 Apprentice Cellar (basic), Ch. 2 Rune Vault (A1), Ch. 3 Misty Marsh (B1). Later chapters show as "coming soon" until their mechanic lands
- [ ] Current Challenger / Expert / Master packs move to an optional **Challenges** area (no gating); Locks & Keys and Hidden Depths content is regenerated as chapters 2–3
- [ ] Tutorial overlay: one illustrated hint the first time a mechanic appears (seen-state stored per mechanic)
- [ ] `levelgen` chapter presets with a tuned curve and a tutorial level first
- [ ] Progress migration: existing stars keep counting (level ids stay unique)

## R3 — Daily puzzle & streaks (Milestone 4, without Game Center / notifications)
- [ ] Deterministic daily level: seed = UTC date, generated on device, offline
- [ ] Difficulty by weekday (Mon easy → Sun hard), mode varies (classic / sealed / murky)
- [ ] Streak counter, calendar of solved days, "perfect solve" badge (= solver minimum)
- [ ] Tests: same date → same level on every device; streak rules across day boundaries and time zones

## R4 — Mechanics architecture (prerequisite for R5)
- [ ] `Bottle.modifiers: [BottleModifier]` (`.sealed`, `.essence`, `.narrowNeck`, `.funnel`, `.tap`, `.frozen…`, `.bubbling`, `.cauldron`, `.switch…`); each modifier can veto or change a pour; `lockedBy` migrates to `.sealed`
- [ ] Level-wide `links` (twins, overflow pipes, switch → gate) and a `Goal` (`.standard` for now)
- [ ] `Rules.resolve(afterAction:)` implements the turn order from MECHANICS.md §4 in one place
- [ ] Counters in `GameState` (per-layer frozen turns, bubbling phase, `moveCount` only while a timed rule needs it)
- [ ] `StateKey` v2: variable-length encoding that includes modifiers, counters and link state; benchmark vs. v1
- [ ] JSON v2 (modifiers, links, goal); v1 files still load
- [ ] `levelgen` "must matter" check: re-solve with the mechanic removed and reject levels where it changed nothing
- [ ] All 108 existing tests stay green; solver vs. naive BFS cross-check extended to modifiers

## R5 — New mechanics, one chapter each (Milestone 3)
For each: rules, solver/key, generator flag, JSON, art + one visual signal, tutorial level, chapter pack (~30), tests incl. naive-BFS cross-check and a "requires the mechanic" puzzle.
- [ ] **Ch. 4 Glyph Library — C1 Essence flasks** (accepts only its rune's color)
- [ ] **Ch. 5 Glass Works — C2 Narrow neck + C4 Funnels/taps** (one layer per pour; pour-in-only / pour-from-bottom)
- [ ] **Ch. 6 Frost Peak — D1 Frozen layers** (thaw counter ≤ 5, ≤ 2 per level; fire-potion variant later)
- [ ] **Ch. 7 Bubbling Bog — D2 Bubbling flask** (bottom layer rises every K moves)
- [ ] **Ch. 8 Twin Towers — F1 Twin flasks + F2 Overflow pipes**
- [ ] **Ch. 9 Alchemist's Hall — E1 Mixing cauldron** (recipes; generator builds backwards from a solved state — the one allowed exception; `validate()` allows changing color counts)
- [ ] **Ch. 10 Dragon's Hoard — A3 Switch flasks + combos**
- [ ] After each: solver timing check on the hardest preset; cap counters if needed

## R6 — Challenge modes (Milestone 5, separate from the calm main path)
- [ ] Move-limit recipes (solver minimum + slack); fail → free retry
- [ ] Rush: as many generated levels as possible in 3 minutes
- [ ] Perfect brewer: gold seal for matching the solver minimum
- [ ] Challenge results stored separately from main-path stars; the existing Random Level screen moves here

## R7 — Orders & story (Milestone 6)
- [ ] `Goal` variants in core + solver: order (specific flask = specific color), partial order, layered recipe (exact pattern), rescue (free all seals within N moves)
- [ ] Customer-order levels with villager cards; generator per goal type
- [ ] Short dialogue between chapters (apprentice + old alchemist)
- [ ] Cosmetic rewards: workbench themes, flask shapes, potion effects

## R8 — Release readiness (Milestone 7, no iCloud / Game Center / notifications)
- [ ] Final bundle id + target rename to Pourfect; app icon, launch screen, App Store screenshots
- [ ] Accessibility pass: VoiceOver labels for flasks and layers, Dynamic Type in menus, reduce-motion everywhere
- [ ] Optional: TestFlight beta (App Store Connect stats only, no third-party analytics)
- [ ] Business decision point; `HintService` and `ProgressStore` stay behind protocols
