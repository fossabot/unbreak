import Testing

@testable import CCFixCore

@Suite("Watch-mode gate pipeline (PRD v2 §7)")
struct WatchGateTests {
    // A bundle id that is in the default allowlist.
    let term = "com.apple.Terminal"

    /// A repaired-and-shell-like clipboard that, with a good terminal, passes all
    /// six gates. `git pull && make test` is a strong-signal command (operator +
    /// known tool) with no structure-risk veto.
    private func passingDecision(
        clipboard: String = "git pull && make test",
        isPlainText: Bool = true,
        frontmostBundleID: String? = "com.apple.Terminal",
        changed: Bool = true,
        config: WatchGate.Config = .init()
    ) -> WatchGate.Decision {
        WatchGate.decide(
            clipboard: clipboard,
            isPlainText: isPlainText,
            frontmostBundleID: frontmostBundleID,
            report: RepairReport(changed: changed),
            config: config
        )
    }

    // MARK: - The happy path

    @Test("All six gates pass → mutate")
    func allGatesPass() {
        let d = passingDecision()
        #expect(d.shouldMutate)
        #expect(d.blockingGate == nil)
        #expect(d.outcomes.allSatisfy { $0.passed })
        #expect(d.outcomes.count == WatchGate.Gate.allCases.count)
    }

    @Test("The decision evaluates every gate, even past a failure (for logging)")
    func evaluatesAllGates() {
        // Non-allowlisted terminal AND no change — two failures, both recorded.
        let d = WatchGate.decide(
            clipboard: "git status",
            isPlainText: true,
            frontmostBundleID: "com.example.NotATerminal",
            report: RepairReport(changed: false)
        )
        #expect(!d.shouldMutate)
        #expect(d.outcomes.count == WatchGate.Gate.allCases.count)
        let failed = d.outcomes.filter { !$0.passed }.map(\.gate)
        #expect(failed.contains(.terminalAllowlisted))
        #expect(failed.contains(.repairChangedContent))
        // blockingGate is the first failure in §7 order.
        #expect(d.blockingGate == .terminalAllowlisted)
    }

    // MARK: - Gate 1: frontmost terminal (§7.1)

    @Test("A non-allowlisted frontmost app blocks the mutation")
    func nonAllowlistedTerminalBlocks() {
        let d = passingDecision(frontmostBundleID: "com.brave.Browser")
        #expect(!d.shouldMutate)
        #expect(d.blockingGate == .terminalAllowlisted)
    }

    @Test("A nil frontmost bundle id blocks the mutation")
    func nilFrontmostBlocks() {
        let d = passingDecision(frontmostBundleID: nil)
        #expect(!d.shouldMutate)
        #expect(d.blockingGate == .terminalAllowlisted)
    }

    @Test("Each default-allowlist terminal is accepted")
    func defaultAllowlistAccepted() {
        for bundleID in WatchGate.Config.defaultTerminalAllowlist {
            let d = passingDecision(frontmostBundleID: bundleID)
            #expect(d.shouldMutate, "expected \(bundleID) to pass")
        }
    }

    @Test("A user-extended allowlist is honored")
    func userExtendedAllowlist() {
        var config = WatchGate.Config()
        config.terminalAllowlist.insert("com.example.MyTerm")
        let d = passingDecision(frontmostBundleID: "com.example.MyTerm", config: config)
        #expect(d.shouldMutate)
    }

    // MARK: - Gate 2: plain text (§7.2)

    @Test("A non-plain-text item is left untouched")
    func nonPlainTextBlocks() {
        let d = passingDecision(isPlainText: false)
        #expect(!d.shouldMutate)
        #expect(d.blockingGate == .plainText)
    }

    // MARK: - Gate 3: size bound (§7.3)

    @Test("A payload over the byte bound is skipped")
    func oversizedBlocks() {
        var config = WatchGate.Config()
        config.maxClipboardBytes = 8
        let d = passingDecision(clipboard: "git pull && make test", config: config)
        #expect(!d.shouldMutate)
        #expect(d.blockingGate == .sizeWithinBound)
    }

    @Test("A payload exactly at the bound passes (inclusive)")
    func sizeBoundIsInclusive() {
        let clip = "git x"  // 5 bytes
        var config = WatchGate.Config()
        config.maxClipboardBytes = clip.utf8.count
        let d = passingDecision(clipboard: clip, config: config)
        let sizeOutcome = d.outcomes.first { $0.gate == .sizeWithinBound }
        #expect(sizeOutcome?.passed == true)
    }

    @Test("The size bound counts UTF-8 bytes, not characters")
    func sizeBoundCountsBytes() {
        // A multi-byte command: each `é` is 2 UTF-8 bytes, each emoji 4.
        let clip = "echo 'café 🚀'"
        let d = passingDecision(clipboard: clip)
        let expectedBytes = clip.utf8.count
        #expect(d.byteCount == expectedBytes)
        #expect(d.byteCount > clip.count)
    }

    // MARK: - Gate 4: repair changed content (§7.4)

    @Test("An unchanged repair blocks the mutation")
    func unchangedBlocks() {
        let d = passingDecision(changed: false)
        #expect(!d.shouldMutate)
        #expect(d.blockingGate == .repairChangedContent)
    }

    // MARK: - Gate 5: shell-signal tiers (§7.5)

    @Test("Prose that changed but lacks shell signals is blocked at gate 5")
    func proseWithoutShellSignalBlocks() {
        // A single weak signal at most; no strong → gate 5 fails (and structure
        // may also veto, but gate 5 comes first in §7 order).
        let d = WatchGate.decide(
            clipboard: "the quick brown fox",
            isPlainText: true,
            frontmostBundleID: term,
            report: RepairReport(changed: true)
        )
        #expect(!d.shouldMutate)
        #expect(d.blockingGate == .shellSignal)
    }

    // MARK: - Gate 6: structure-risk veto (§7.6)

    @Test("A prose paragraph vetoes even with a stray operator-free command shape")
    func proseVetoes() {
        let prose = """
            This is a sentence about software.
            It explains how the system works in detail.
            Every line reads like ordinary prose here.
            """
        let d = WatchGate.decide(
            clipboard: prose,
            isPlainText: true,
            frontmostBundleID: term,
            report: RepairReport(changed: true)
        )
        #expect(!d.shouldMutate)
        // No shell signal AND prose veto; gate 5 is first in order.
        #expect(d.blockingGate == .shellSignal)
    }

    @Test("A markdown list with a shell signal is still vetoed by structure risk")
    func markdownVetoesDespiteShellSignal() {
        // Markers dominate (gate 6 vetoes) but `git`/operator gives a strong signal
        // (gate 5 passes) — proves the structure veto is independent of gate 5.
        let md = """
            - run git status first
            - then pipe it: cat x | wc -l
            - finally && commit
            """
        let analysis = Signals.analyze(md)
        #expect(analysis.shell.passesGate)  // operators + git → strong
        #expect(analysis.structure.vetoes)  // markdown markers dominate
        let d = WatchGate.decide(
            clipboard: md,
            isPlainText: true,
            frontmostBundleID: term,
            report: RepairReport(changed: true),
            analysis: analysis
        )
        #expect(!d.shouldMutate)
        #expect(d.blockingGate == .structureRiskClear)
    }

    @Test("A stack trace is vetoed by structure risk")
    func stackTraceVetoes() {
        let trace = """
            at Object.<anonymous> (/app/index.js:12:9)
            at Module._compile (node:internal/modules:1, line 1)
            at require (/app/lib/run.js:44:3)
            """
        let d = WatchGate.decide(
            clipboard: trace,
            isPlainText: true,
            frontmostBundleID: term,
            report: RepairReport(changed: true)
        )
        #expect(!d.shouldMutate)
        #expect(d.blockingGate == .structureRiskClear)
    }

    // MARK: - Observability surface (§7.2 / §7.3)

    @Test("byteCount and lineCount are reported for logging")
    func reportsCounts() {
        let clip = "git pull\nmake test\n"
        let d = passingDecision(clipboard: clip)
        #expect(d.byteCount == clip.utf8.count)
        // Trailing newline does not add a phantom line: "git pull", "make test", "".
        #expect(d.lineCount == 3)
    }

    @Test("An empty clipboard reports zero lines")
    func emptyClipboardZeroLines() {
        let d = passingDecision(clipboard: "", changed: false)
        #expect(d.byteCount == 0)
        #expect(d.lineCount == 0)
    }

    @Test("logSummary is content-safe and names the blocking gate")
    func logSummaryShape() {
        let d = passingDecision(frontmostBundleID: "com.brave.Browser")
        #expect(d.logSummary.contains("decision=skip"))
        #expect(d.logSummary.contains("blocked=terminal-allowlisted"))
        #expect(d.logSummary.contains("bytes="))
        #expect(d.logSummary.contains("lines="))
        // The raw clipboard content never appears in the summary.
        #expect(!d.logSummary.contains("git"))
    }

    @Test("logSummary reports a mutate verdict with no blocked gate")
    func logSummaryMutate() {
        let d = passingDecision()
        #expect(d.logSummary.contains("decision=mutate"))
        #expect(!d.logSummary.contains("blocked="))
    }

    @Test("Every gate outcome carries a non-empty, content-safe detail")
    func gateDetailsPresent() {
        let d = passingDecision()
        for outcome in d.outcomes {
            #expect(!outcome.detail.isEmpty, "\(outcome.gate) detail should not be empty")
        }
    }
}
