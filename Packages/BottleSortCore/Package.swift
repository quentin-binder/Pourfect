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
        .library(name: "SecretRecipeCore", targets: ["SecretRecipeCore"]),
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
        // R10b Secret Recipe (code-breaking deduction): pure rules, candidates, daily generator, stats.
        .target(name: "SecretRecipeCore", dependencies: ["BottleSortCore"]),
        .testTarget(name: "SecretRecipeCoreTests", dependencies: ["SecretRecipeCore", "BottleSortCore"]),
    ]
)
