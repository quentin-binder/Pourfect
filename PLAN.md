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
- [x] Haptics: light tap on select, soft thud on pour, success pattern on a completed flask (iOS; no-op on Mac)
- [x] Sound, synthesized with AVAudioEngine (no files): glass clink, pour gurgle (length follows the pour), cork pop + sparkle chime
- [x] Completed flask: cork drops in + small particle burst (SwiftUI Canvas)
- [x] Glass highlight and a soft glow on potions
- [x] Colorblind runes: one simple vector rune per color (12), drawn on every layer when enabled
- [x] Settings screen: sound, haptics, colorblind runes, reduce-motion override; stored behind a `SettingsStore` protocol
- [x] Tests: settings persistence; "flask completed" detection lives in core
- [x] Review fixes: cork no longer dips into the liquid, Reduce Motion toggle doesn't replay drops, sound synthesis off the main thread, cancelled pours drop their delayed sounds/haptics
- Not covered in R1: light-mode and iOS-device screenshots were not checked (iOS builds only); haptics are untested on hardware

## R2 — Pourfect theme & chapters (Milestone 2)
- [x] Rename to **Pourfect**: display name, window title, in-app titles. Code/module names stay neutral; the target/bundle id rename waits for R8
- [x] UI wording: bottles → flasks, levels → recipes, packs → chapters (strings only)
- [x] Art: painted workbench backgrounds, chapter map and chapter vignettes (generated, optimized copies in the asset catalog); flask rim, smoky glass; 12-color potion palette with names. (Only one flask silhouette so far: the bottle shape is unchanged.)
- [x] String catalog (English only for now, ready for more languages)
- [x] Chapter map (main path), star-gated: Ch. 1 Apprentice Cellar (basic), Ch. 2 Rune Vault (A1), Ch. 3 Misty Marsh (B1). Later chapters show as "coming soon" until their mechanic lands. Map buttons sit on the painted path; chapter screen with vignette header, stars and what they open
- [x] Current Challenger / Expert / Master packs move to an optional **Challenges** area (no gating), together with Random Brew; Locks & Keys and Hidden Depths content is regenerated as chapters 2–3
- [x] Tutorial overlay: one illustrated hint the first time a mechanic appears (seen-state stored per mechanic); "?" in the game re-opens it
- [x] `levelgen` chapter presets with a tuned curve and a tutorial level first (`chapter1|chapter2|chapter3|challenger|expert|master`; every lock in a chapter must matter)
- [x] Core: pack metadata (`kind`, `chapter`, `location`, `introduces`), `ChapterGate` / `ChapterProgress` (50 % star gate, recipes in order), `ChapterOutline.plan`; files renamed to `chapter_0N.json` / `challenge_*.json`; chapters 2 Rune Vault and 3 Misty Marsh generated (30 recipes each)
- [x] Progress migration: existing stars keep counting (level ids stay unique; chapter 1 and the challenges keep their `p1/p2/p3/p6` ids); stars of the removed `p4_`/`p5_` recipes are ignored
- Review fixes: cleared recipes stay open (stars never hidden behind a lock), readable locked cells in light mode, consistent rune-seal tip wording, themed Random Brew screen (DECISIONS 100–102)
- Not covered in R2: iPad layouts were not checked; tutorial steps were checked by screenshots only (no UI tests); light mode was checked on the Mac chapter screen only
- Open design question: chapter locks only have to add more than one move (DECISIONS 91, 103); most add exactly one. A stricter threshold would mean regenerating chapters 2–3

## R3 — Daily puzzle & streaks (Milestone 4, without Game Center / notifications)
- [x] Core: `DailyDate` (UTC calendar day, ISO string, day arithmetic, weekday)
- [x] Core: deterministic daily level (`DailyPuzzle`, algorithm `daily-v2`): seed hashed from the UTC date, generated on device, offline, guaranteed fallback
- [x] Core: difficulty by weekday (Mon easy → Sun hard), mode varies (classic / sealed / murky / murky + seal) — `DailyPlan`
- [x] Core: `DailyResult`, `DailyHistory`, `DailyStreaks` (current/best streak, solved days, perfect = solver minimum without a hint)
- [x] Tests: same date → same level (golden value), 60-day generation timing, streak rules across day boundaries and time zones
- [x] App: Daily screen (today's puzzle, streak, calendar of solved days, perfect badge), persistence of `DailyHistory` (`DailyStore`, UserDefaults)
- [x] App: entry point on the chapter map / side panel (Daily Brew card; row in the iPhone bottom bar), localized weekday + tier labels
- [x] App: `DailyModel` (UTC today, refresh on activation and at UTC midnight, level generated off the main thread and cached), daily win card (perfect badge, streak, Share), debug `-LPDailyDate` / `-LPDailySeedResults` / `-LPOpenDaily` / `-LPPlayDaily`
- [x] Review fixes: a hint is remembered per date (reopening the puzzle no longer restores "perfect"), a clock set back can't fill a streak gap, Gregorian month title, order-independent tie-break, Saturday / Wednesday harder (`daily-v2`), one-line game title (DECISIONS 106–111, 115, 116, 119)
- Not covered in R3: no app-level unit tests (the app has no test target; the rules are tested in the core); iPhone was checked by screenshots of the home bar and Daily screen only; light mode not checked (the Daily screen is always dark, like the map). Known limits: a device clock set forward can bank future days (DECISIONS 110); undo is allowed for "perfect" (DECISIONS 119)

## R4 — Mechanics architecture (prerequisite for R5)
- [x] `Bottle.modifiers: [BottleModifier]` (`.sealed`, `.essence`, `.narrowNeck`, `.funnel`, `.tap`, `.frozen(layer:turns:)`, `.bubbling`, `.cauldron`; switch → gate is a link); each modifier can veto or change a pour (`Rules.apply`); `lockedBy` migrates to `.sealed` (kept as a computed accessor)
- [x] Level-wide `links` (twins, overflow pipes, switch → gate) and a `Goal` (`.standard` implemented; order / pattern / rescue defined)
- [x] `Rules.resolve(afterAction:)` implements the turn order from MECHANICS.md §4 in one place (unseal is the only immediate effect; timed steps are empty hooks)
- [x] Counters in `GameState` (per-layer frozen turns and bubbling phase live in their modifiers, `moveCount` is optional and nil for classic levels)
- [x] `StateKey` v2: variable-length encoding that includes modifiers, counters and links (endpoints as canonical ranks, ties resolved by minimum); classic/sealed keys unchanged; benchmarked (DECISIONS 126)
- [x] JSON v2 (modifiers, links, goal); v1 files still load and re-encode byte for byte
- [x] "Must matter" check generalized: `MechanicImpact` (`LockImpact` is its seal case); `levelgen --report` checks every mechanic instance
- [x] All existing tests stay green (149 → 180 with the new ones; 213 after merging main and the review fixes); solver vs. naive BFS cross-check extended to lock levels and the unpruned path
- [x] Review fixes: merged main (stronger locks: `MechanicImpact` takes the lock cost; R4 decisions renumbered 120–131; golden checks re-gathered against main, DECISIONS 131); bounded move counter; one step-1 legality check for `resolve` and `isLegal`; immediate effects run in steps 2 and 5; hooks see both bottles; StateKey overflow and goal-target collision fixed (DECISIONS 121–126)
- Not covered in R4: no R5 rule is implemented (levels using them fail validation and the solver refuses them); `levelgen` has no per-mechanic flags yet; StateKey v2 is ~6× slower per key than v1 (only used by R5 states). Deferred to R5, with the mechanic that needs it (DECISIONS 130, 122): multi-bottle pours (twins, overflow, gates) and plan fields for tap / cauldron; turn events for the app's animations; murky reveal state inside the rules once bubbling or taps exist; the frozen-index rule for bubbling / tap / mixing

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
