// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BottleSortCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BottleSortCore", targets: ["BottleSortCore"]),
    ],
    targets: [
        .target(name: "BottleSortCore"),
        .testTarget(name: "BottleSortCoreTests", dependencies: ["BottleSortCore"]),
    ]
)
