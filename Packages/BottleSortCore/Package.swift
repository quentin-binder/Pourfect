// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BottleSortCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BottleSortCore", targets: ["BottleSortCore"]),
        .executable(name: "levelgen", targets: ["levelgen"]),
        .library(name: "Match3Core", targets: ["Match3Core"]),
        .executable(name: "m3gen", targets: ["m3gen"]),
        .library(name: "DistilleryCore", targets: ["DistilleryCore"]),
        .executable(name: "distillgen", targets: ["distillgen"]),
        .executable(name: "hiddengen", targets: ["hiddengen"]),
        .library(name: "SecretRecipeCore", targets: ["SecretRecipeCore"]),
        .library(name: "HiddenCore", targets: ["HiddenCore"]),
    ],
    targets: [
        .target(name: "BottleSortCore"),
        .executableTarget(name: "levelgen", dependencies: ["BottleSortCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),  // simple top-level script
        .testTarget(name: "BottleSortCoreTests", dependencies: ["BottleSortCore"]),
        // R9 ingredient gathering (match-3): pure rules, bot, level files, daily generator.
        .target(name: "Match3Core", dependencies: ["BottleSortCore"]),
        .executableTarget(name: "m3gen", dependencies: ["Match3Core", "BottleSortCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "Match3CoreTests", dependencies: ["Match3Core", "BottleSortCore"]),
        // R10 distillery (pipe rotation): pure rules, exact solver, generator, level files, daily.
        .target(name: "DistilleryCore", dependencies: ["BottleSortCore"]),
        .executableTarget(name: "distillgen", dependencies: ["DistilleryCore", "BottleSortCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DistilleryCoreTests", dependencies: ["DistilleryCore", "BottleSortCore"]),
        // R10b Secret Recipe (code-breaking deduction): pure rules, candidates, daily generator, stats.
        .target(name: "SecretRecipeCore", dependencies: ["BottleSortCore"]),
        .testTarget(name: "SecretRecipeCoreTests", dependencies: ["SecretRecipeCore", "BottleSortCore"]),
        // R11 hidden-object rooms: scene files, placement + blending rules (ported from the art pipeline), round
        // generator with decoys, hit testing, round state, progression. Goldens come from poc/hidden-object/tools.
        .target(name: "HiddenCore"),
        // Proposes and checks the fixed rounds (`HiddenScenes/<room>/rounds.json`).
        .executableTarget(name: "hiddengen", dependencies: ["HiddenCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "HiddenCoreTests", dependencies: ["HiddenCore"], exclude: ["Goldens"]),
    ]
)
