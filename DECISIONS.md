# Decisions

Short entries, newest at the bottom.

1. **Repo layout.** The repo root is `LiquidPour/` (not `BottleSort/`). The existing Xcode project `LiquidPour.xcodeproj` and its folder `LiquidPour/` play the role of the spec's `App/`. `Packages/BottleSortCore` and `Levels/` sit at the repo root as specified.
2. **No XcodeGen.** XcodeGen isn't installed and the user already created the Xcode project, so we keep it and make small targeted edits to `project.pbxproj` (user-approved) instead of generating one.
3. **Platforms.** App target supports iOS/iPadOS and native macOS (arm64 + x86_64 universal, via SwiftUI multiplatform — not Catalyst, not "Designed for iPad"). visionOS removed. Minimum iOS 17 / macOS 14 (matches the package platforms and `@Observable`).
4. **Git.** Commits go directly on `main` (user choice). Per-user Xcode state (`xcuserdata`) is ignored.
5. **Tooling.** Package uses swift-tools-version 6.0 (Swift 6 language mode, strict concurrency; all model types are `Sendable` value types). Tests use Swift Testing (`import Testing`), which ships with the toolchain — no third-party deps.
6. **Rules in one place.** `Rules.pourAmount(from:to:)` is the single legality + amount check (returns 0 = illegal); `Rules.movableRunCount` and `Rules.isSolved` are the other hooks. `GameState.canPour/pouring/legalMoves/isSolved` all delegate to it. Locked bottles are already rejected there (cheap, and the field exists now).
7. **Move counter.** `GameSession.moveCount` = number of moves currently applied, so Undo decreases it. Stars compare this with `minMoves`.
8. **Validation scope.** `validate()` checks: at least one bottle, capacity ≥ 1 and identical across bottles, no overfilled bottle, every color exactly `capacity` times. It does not check solvability (that's the solver's job).
