import Testing

@testable import UnbreakCore

/// The optional float-threshold overrides for gates 5/6 (PRD v2 §8.3). These use
/// the explicit-`analysis` overload so `Shell.score` / `Structure.risk` can be
/// pinned exactly, isolating the gate's threshold logic from signal derivation.
@Suite("Watch-mode gate float thresholds (PRD v2 §8.3)")
struct WatchGateThresholdTests {
    private let term = "com.apple.Terminal"

    private func decide(
        shell: Signals.Shell,
        structure: Signals.Structure,
        config: WatchGate.Config
    ) -> WatchGate.Decision {
        WatchGate.decide(
            clipboard: "x",
            isPlainText: true,
            frontmostBundleID: term,
            report: RepairReport(changed: true),
            analysis: Signals.Analysis(shell: shell, structure: structure),
            config: config
        )
    }

    private let noStructureRisk = Signals.Structure(
        markdownDominant: false,
        stackTrace: false,
        prose: false,
        risk: 0
    )

    private func shellOutcome(_ d: WatchGate.Decision) -> WatchGate.GateOutcome {
        d.outcomes.first { $0.gate == .shellSignal }!
    }

    private func structureOutcome(_ d: WatchGate.Decision) -> WatchGate.GateOutcome {
        d.outcomes.first { $0.gate == .structureRiskClear }!
    }

    @Test("Shell threshold can pass a signal the discrete tier rejects")
    func shellThresholdRescuesWeakSignal() {
        // One weak signal: discrete rule fails (needs ≥1 strong or ≥2 weak), but
        // its 0.25 score clears a 0.2 threshold.
        let shell = Signals.Shell(strongCount: 0, weakCount: 1)
        #expect(!shell.passesGate)

        let d = decide(
            shell: shell,
            structure: noStructureRisk,
            config: .init(shellSignalScoreThreshold: 0.2)
        )
        #expect(shellOutcome(d).passed)
        #expect(d.shouldMutate)
    }

    @Test("Shell threshold can fail a signal the discrete tier accepts")
    func shellThresholdRejectsStrongSignal() {
        // One strong signal: discrete passes; its 0.5 score is below a 0.6 bar.
        let shell = Signals.Shell(strongCount: 1, weakCount: 0)
        #expect(shell.passesGate)

        let d = decide(
            shell: shell,
            structure: noStructureRisk,
            config: .init(shellSignalScoreThreshold: 0.6)
        )
        #expect(!shellOutcome(d).passed)
        #expect(d.blockingGate == .shellSignal)
    }

    @Test("Structure threshold vetoes on risk even without a discrete pattern")
    func structureThresholdVetoesOnRisk() {
        let passingShell = Signals.Shell(strongCount: 1, weakCount: 0)
        // No discrete veto fires, but the risk float sits at/above the threshold.
        let risky = Signals.Structure(
            markdownDominant: false,
            stackTrace: false,
            prose: false,
            risk: 0.5
        )
        #expect(!risky.vetoes)

        let d = decide(
            shell: passingShell,
            structure: risky,
            config: .init(structureRiskThreshold: 0.4)
        )
        #expect(!structureOutcome(d).passed)
        #expect(d.blockingGate == .structureRiskClear)
    }

    @Test("With no thresholds set, the discrete rules are unchanged")
    func nilThresholdsKeepDiscreteRule() {
        let weak = Signals.Shell(strongCount: 0, weakCount: 1)  // discrete: fail
        let d = decide(shell: weak, structure: noStructureRisk, config: .init())
        #expect(!shellOutcome(d).passed)  // still fails — discrete rule intact
        #expect(structureOutcome(d).passed)  // no veto
    }
}
