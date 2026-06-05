// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ccfix",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ccfix", targets: ["ccfix"]),
        .library(name: "CCFixCore", targets: ["CCFixCore"]),
    ],
    targets: [
        // Pure, deterministic repair pipeline (PRD v2 §6). No I/O, no globals.
        .target(name: "CCFixCore"),
        // Thin CLI shell around CCFixCore (PRD v2 §8.1).
        .executableTarget(
            name: "ccfix",
            dependencies: ["CCFixCore"]
        ),
        .testTarget(
            name: "CCFixCoreTests",
            dependencies: ["CCFixCore"]
        ),
    ]
)
