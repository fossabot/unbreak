import Foundation
import Testing

@testable import Setup

@Suite("LaunchAgent plist generation (PRD v2 §7.4)")
struct LaunchAgentPlistTests {
    @Test("Plist embeds the binary path, --watch, and a generic label")
    func plistContents() {
        let xml = LaunchAgent.plist(
            binaryPath: "/opt/homebrew/bin/ccfix",
            standardOutPath: "/Users/x/Library/Logs/ccfix.watch.log"
        )
        #expect(xml.contains("<string>io.ccfix.watch</string>"))
        #expect(xml.contains("<string>/opt/homebrew/bin/ccfix</string>"))
        #expect(xml.contains("<string>--watch</string>"))
        #expect(xml.contains("<key>RunAtLoad</key>"))
        #expect(xml.contains("<key>KeepAlive</key>"))
        #expect(xml.contains("<string>/Users/x/Library/Logs/ccfix.watch.log</string>"))
    }

    @Test("Label carries no personal identifier (fixes the original plist)")
    func genericLabel() {
        #expect(LaunchAgent.label == "io.ccfix.watch")
        #expect(!LaunchAgent.label.contains("/Users/"))
        let xml = LaunchAgent.plist(binaryPath: "/usr/local/bin/ccfix", standardOutPath: "/tmp/o")
        #expect(!xml.lowercased().contains("bartturczynski"))
    }

    @Test("XML special characters in paths are escaped")
    func escaping() {
        let xml = LaunchAgent.plist(
            binaryPath: "/Apps/A & B/ccfix",
            standardOutPath: "/logs/<weird>.log"
        )
        #expect(xml.contains("/Apps/A &amp; B/ccfix"))
        #expect(xml.contains("/logs/&lt;weird&gt;.log"))
        #expect(!xml.contains("A & B"))
    }
}

/// Records every side effect a `LaunchAgentManager` performs so install/uninstall
/// can be asserted without touching launchd or the filesystem.
final class FakeAgentBackend {
    var launchctlCalls: [[String]] = []
    var written: [(String, URL)] = []
    var removed: [URL] = []
    var present: Set<String> = []
    var bootstrapStatus: Int32 = 0
    var binary: String? = "/opt/homebrew/bin/ccfix"
    var writeError: Error?

    func manager() -> LaunchAgentManager {
        LaunchAgentManager(
            launchAgentsDirectory: URL(fileURLWithPath: "/Users/x/Library/LaunchAgents"),
            standardOutPath: "/Users/x/Library/Logs/ccfix.watch.log",
            binaryPath: { self.binary },
            writeFile: { contents, url in
                if let writeError = self.writeError { throw writeError }
                self.written.append((contents, url))
                self.present.insert(url.path)
            },
            removeFile: { url in
                self.removed.append(url)
                self.present.remove(url.path)
            },
            fileExists: { self.present.contains($0.path) },
            runLaunchctl: { args in
                self.launchctlCalls.append(args)
                return args.first == "bootstrap" ? self.bootstrapStatus : 0
            }
        )
    }
}

@Suite("LaunchAgentManager install/uninstall (PRD v2 §8.2)")
struct LaunchAgentManagerTests {
    @Test("Install writes the plist then bootstraps after a defensive bootout")
    func installHappyPath() {
        let backend = FakeAgentBackend()
        let outcome = backend.manager().install()

        #expect(outcome.exitCode == 0)
        #expect(backend.written.count == 1)
        #expect(backend.written[0].1.lastPathComponent == "io.ccfix.watch.plist")
        #expect(backend.written[0].0.contains("/opt/homebrew/bin/ccfix"))
        // bootout (idempotent re-install) precedes bootstrap.
        #expect(backend.launchctlCalls[0][0] == "bootout")
        #expect(backend.launchctlCalls[1][0] == "bootstrap")
    }

    @Test("Install refuses when the binary path cannot be resolved")
    func installNoBinary() {
        let backend = FakeAgentBackend()
        backend.binary = nil
        let outcome = backend.manager().install()
        #expect(outcome.exitCode == 1)
        #expect(backend.written.isEmpty)
        #expect(backend.launchctlCalls.isEmpty)
    }

    @Test("A failed bootstrap surfaces a non-zero outcome but keeps the plist")
    func installBootstrapFails() {
        let backend = FakeAgentBackend()
        backend.bootstrapStatus = 5
        let outcome = backend.manager().install()
        #expect(outcome.exitCode == 1)
        #expect(backend.written.count == 1)
        #expect(outcome.message.contains("bootstrap"))
    }

    @Test("Uninstall of an installed agent boots it out and removes the plist")
    func uninstallExisting() {
        let backend = FakeAgentBackend()
        _ = backend.manager().install()
        let outcome = backend.manager().uninstall()
        #expect(outcome.exitCode == 0)
        #expect(backend.removed.count == 1)
        #expect(outcome.message.contains("removed"))
        #expect(backend.launchctlCalls.last?[0] == "bootout")
    }

    @Test("Uninstall with nothing installed is a clean no-op")
    func uninstallMissing() {
        let backend = FakeAgentBackend()
        let outcome = backend.manager().uninstall()
        #expect(outcome.exitCode == 0)
        #expect(outcome.message.contains("nothing to do"))
    }
}
