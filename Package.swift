// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "recap-wins",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "rw", targets: ["rw"]),
        .library(name: "RecapCore", targets: ["RecapCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Deterministic, offline core. No CLI or LLM dependencies — this is the
        // engine the standalone CLI and (Phase 3) the agent skill both consume.
        .target(
            name: "RecapCore"
        ),
        // The `rw` command-line front end over RecapCore.
        .executableTarget(
            name: "rw",
            dependencies: [
                "RecapCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "RecapCoreTests",
            dependencies: ["RecapCore"]
        ),
    ]
)
