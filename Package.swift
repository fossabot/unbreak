// swift-tools-version: 6.3
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
        // NSPasteboard-backed clipboard, behind a testable protocol (PRD v2 §7.2).
        .target(name: "Clipboard"),
        // Watch-mode event loop + app-context detection (PRD v2 §7.4).
        .target(
            name: "Watch",
            dependencies: ["CCFixCore", "Clipboard"]
        ),
        // Thin CLI shell around CCFixCore (PRD v2 §8.1).
        .executableTarget(
            name: "ccfix",
            dependencies: ["CCFixCore"]
        ),
        .testTarget(
            name: "CCFixCoreTests",
            dependencies: ["CCFixCore"]
        ),
        .testTarget(
            name: "ClipboardTests",
            dependencies: ["Clipboard"]
        ),
        .testTarget(
            name: "WatchTests",
            dependencies: ["Watch", "Clipboard", "CCFixCore"]
        ),
    ]
)
