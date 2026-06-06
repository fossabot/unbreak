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
        // One-shot CLI surface: arg grammar + I/O driver, testable in isolation
        // from a real terminal/NSPasteboard (PRD v2 §8.1).
        .target(
            name: "CLI",
            dependencies: ["CCFixCore", "Clipboard", "Watch"]
        ),
        // User config: config.toml reader + CCFIX_* env overrides (PRD v2 §8.3).
        .target(
            name: "Config",
            dependencies: ["CCFixCore"]
        ),
        // Setup wizard + per-user LaunchAgent lifecycle (PRD v2 §8.2, §7.4).
        .target(
            name: "Setup",
            dependencies: ["CCFixCore", "Config"]
        ),
        // Thin executable shim around CLI (§8.1) + the watch daemon (§7).
        .executableTarget(
            name: "ccfix",
            dependencies: ["CCFixCore", "Clipboard", "Watch", "CLI", "Config", "Setup"]
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
        .testTarget(
            name: "CLITests",
            dependencies: ["CLI", "CCFixCore", "Clipboard", "Watch"]
        ),
        .testTarget(
            name: "ConfigTests",
            dependencies: ["Config", "CCFixCore"]
        ),
        .testTarget(
            name: "SetupTests",
            dependencies: ["Setup", "CCFixCore", "Config"]
        ),
    ]
)
