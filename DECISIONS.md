# Decisions

Short entries, newest at the bottom.

1. **Repo layout.** The repo root is `LiquidPour/` (not `BottleSort/`). The existing Xcode project `LiquidPour.xcodeproj` and its folder `LiquidPour/` play the role of the spec's `App/`. `Packages/BottleSortCore` and `Levels/` sit at the repo root as specified.
2. **No XcodeGen.** XcodeGen isn't installed and the user already created the Xcode project, so we keep it and make small targeted edits to `project.pbxproj` (user-approved) instead of generating one.
3. **Platforms.** App target supports iOS/iPadOS and native macOS (arm64 + x86_64 universal, via SwiftUI multiplatform — not Catalyst, not "Designed for iPad"). visionOS removed. Minimum iOS 17 / macOS 14 (matches the package platforms and `@Observable`).
4. **Git.** Commits go directly on `main` (user choice). Per-user Xcode state (`xcuserdata`) is ignored.
