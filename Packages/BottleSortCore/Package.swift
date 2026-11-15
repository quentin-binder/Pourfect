// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BottleSortCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BottleSortCore", targets: ["BottleSortCore"]),
        .executable(name: "levelgen", targets: ["levelgen"]),
    ],
    targets: [
        .target(name: "BottleSortCore"),
        .executableTarget(name: "levelgen", dependencies: ["BottleSortCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),  // simple top-level script
        .testTarget(name: "BottleSortCoreTests", dependencies: ["BottleSortCore"]),
    ]
)
