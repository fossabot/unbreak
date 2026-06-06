import CCFixCore
import CLI
import Clipboard
import Config
import Foundation
import Watch

#if canImport(AppKit)
import AppKit
#endif

// Thin shim over the `CLI` surface (PRD v2 §8.1): load user config (§8.3), parse
// argv, then either hand off to the watch daemon (§7) — which owns the run loop —
// or run a one-shot repair through the shared `Clipboard` backend. The setup
// wizard and LaunchAgent management (§8.2) are not wired up yet.

let loaded = ConfigLoader.load()
for warning in loaded.warnings {
    FileHandle.standardError.write(Data("ccfix: \(warning)\n".utf8))
}
let config = loaded.config

switch CLI.parse(Array(CommandLine.arguments.dropFirst())) {
case .help:
    print(CLI.helpText)
    exit(0)

case .error(let message):
    FileHandle.standardError.write(Data("ccfix: \(message)\n".utf8))
    exit(2)

case .run(let arguments):
    if arguments.watch || arguments.dryRunWatch {
        runWatchDaemon(dryRun: arguments.dryRunWatch, options: arguments.options, config: config)
    }
    exit(CLI.runOneShot(arguments, profile: config.wrapProfile, environment: .system()))
}

/// Start the opt-in fix-on-copy daemon (§7) and block on the run loop until the
/// process is terminated. Never returns. The `config` (§8.3) supplies the gate
/// allowlist/size bound/thresholds, the wrap profile, and the poll interval.
func runWatchDaemon(dryRun: Bool, options: RepairOptions, config: CCFixConfig) -> Never {
    #if canImport(AppKit)
    let watcher = Watcher.system()
    let session = WatchSession(
        watcher: watcher,
        log: FileLog.defaultLog(),
        options: .init(
            dryRun: dryRun,
            profile: config.wrapProfile,
            repair: options,
            gate: config.gateConfig
        )
    )
    _ = session  // retained for the lifetime of the process
    watcher.start(pollInterval: config.pollInterval)
    let mode = dryRun ? "dry-run (log-only)" : "active (mutating)"
    FileHandle.standardError.write(
        Data("ccfix: watch mode \(mode); logging to ~/Library/Logs/ccfix.log\n".utf8)
    )
    RunLoop.main.run()
    exit(0)
    #else
    FileHandle.standardError.write(Data("ccfix: watch mode requires macOS\n".utf8))
    exit(1)
    #endif
}
