import Config
import Foundation

/// `unbreak uninstall` — the counterpart to `setup`/`install-agent` (PRD v2 §8.2,
/// §9). It removes everything unbreak *writes* to the user's machine and then tells
/// the user how to remove the binary itself.
///
/// The binary is reported rather than deleted on purpose: the process doing the
/// uninstall *is* that binary, and a Homebrew-managed copy must be removed with
/// `brew uninstall` so brew's own bookkeeping stays consistent (§9). Deleting it
/// from under either would be surprising — so we hand the last step back to the
/// user with the exact command for their install method.
extension SetupCommand {
    /// Tear down unbreak state: the login LaunchAgent, the watch logs, the undo
    /// socket, and (unless `keepConfig`) the config file. Reports each path
    /// touched and finishes with binary-removal guidance. Returns a non-zero exit
    /// code only if a removal that should have succeeded failed.
    static func runUninstall(keepConfig: Bool, environment: Environment) -> Int32 {
        var removed: [String] = []
        var failures: [String] = []

        // 1. LaunchAgent: bootout + plist removal. The manager already reports a
        //    missing agent as a clean no-op, so its message stands on its own.
        let agent = environment.agentManager.uninstall()
        environment.writeStdout(agent.message + "\n")
        if agent.exitCode != 0 {
            failures.append(agent.message)
        }

        // 2. State files the daemon creates: ~/Library/Logs/unbreak*.log and the
        //    undo socket. Absent files are skipped, not reported as work.
        for url in environment.stateFiles where environment.fileExists(url) {
            remove(url, environment: environment, removed: &removed, failures: &failures)
        }

        // 3. The config file, unless the user asked to keep it for a reinstall.
        if keepConfig {
            environment.writeStdout("Keeping config at \(environment.configURL.path).\n")
        } else if environment.fileExists(environment.configURL) {
            remove(
                environment.configURL,
                environment: environment,
                removed: &removed,
                failures: &failures
            )
        }

        report(removed: removed, failures: failures, environment: environment)
        environment.writeStdout(binaryGuidance(environment: environment))
        return failures.isEmpty ? 0 : 1
    }

    private static func remove(
        _ url: URL,
        environment: Environment,
        removed: inout [String],
        failures: inout [String]
    ) {
        do {
            try environment.removeFile(url)
            removed.append(url.path)
        } catch {
            failures.append("could not remove \(url.path): \(error)")
        }
    }

    private static func report(
        removed: [String],
        failures: [String],
        environment: Environment
    ) {
        if removed.isEmpty {
            environment.writeStdout("No unbreak state files were present.\n")
        } else {
            let lines = removed.map { "  • \($0)" }.joined(separator: "\n")
            environment.writeStdout("Removed:\n\(lines)\n")
        }
        for failure in failures {
            environment.writeStderr("unbreak: \(failure)\n")
        }
    }

    /// The closing instruction: how to remove the `unbreak` binary itself. We can't
    /// do it for the user (see the type doc), so we resolve the running binary's
    /// path and print the right command for how it was installed.
    static func binaryGuidance(environment: Environment) -> String {
        guard let path = environment.agentManager.binaryPath(), !path.isEmpty else {
            return """

                The binary itself was left in place. Remove it with `brew uninstall unbreak`
                (Homebrew) or by deleting the `unbreak` executable on your PATH.

                """
        }
        // Homebrew binaries live under `<prefix>/Cellar/...` but reach us as the
        // `<prefix>/bin/unbreak` symlink on PATH — the running process's own path.
        // The keg only shows in the *resolved* path, so dereference before testing:
        // classifying on the raw symlink mislabels every tap install as a manual one
        // and tells the user to `rm` the symlink, which desyncs brew (the keg and its
        // receipt survive, so `brew install` then reports "already installed").
        let resolved = environment.resolveSymlinks(path)
        if resolved.contains("/Cellar/") || resolved.contains("/Homebrew/") {
            return """

                The binary is Homebrew-managed (\(path)). Finish removing it with:
                    brew uninstall unbreak

                """
        }
        return """

            One step left — remove the binary itself:
                rm \(path)

            """
    }
}

/// The well-known locations of unbreak-created state, mirrored here so the Setup
/// module can clean them up without depending on the Watch module that writes
/// them. Keep in sync with `WatchLog.defaultLog` and `UndoSocketPath.defaultURL`
/// (both §7); the config path defers to `ConfigLoader.defaultConfigURL` (§8.3).
public enum StatePaths {
    /// Logs + undo socket to remove on uninstall (the config is handled
    /// separately so `--keep-config` can spare it).
    public static func all(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let logs = home.appendingPathComponent("Library/Logs", isDirectory: true)
        return [
            // The daemon's structured decision log (§7.3) …
            logs.appendingPathComponent("unbreak.log"),
            // … and the LaunchAgent's stdout/stderr redirect (§7.4).
            logs.appendingPathComponent("unbreak.watch.log"),
            // The undo control socket (§7.1).
            home.appendingPathComponent("Library/Application Support/unbreak/undo.sock"),
        ]
    }
}
