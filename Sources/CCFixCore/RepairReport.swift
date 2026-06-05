/// Confidence signals returned alongside a repair (PRD v2 §6.7).
///
/// The one-shot CLI acts whenever `changed` is true (permissive — the user
/// asked). Watch mode instead applies the discrete shell-signal tiers and the
/// structure-risk veto (§7 gates 5/6); these float fields exist for logging and
/// optional power-user overrides.
public struct RepairReport: Sendable, Equatable {
    public var changed: Bool
    public var dedentChanged: Bool
    public var wrapColumnConfidence: Double
    public var shellSignalScore: Double
    public var structureRisk: Double
    public var heredocDetected: Bool
    public var detectedWidth: Int?

    public init(
        changed: Bool = false,
        dedentChanged: Bool = false,
        wrapColumnConfidence: Double = 0,
        shellSignalScore: Double = 0,
        structureRisk: Double = 0,
        heredocDetected: Bool = false,
        detectedWidth: Int? = nil
    ) {
        self.changed = changed
        self.dedentChanged = dedentChanged
        self.wrapColumnConfidence = wrapColumnConfidence
        self.shellSignalScore = shellSignalScore
        self.structureRisk = structureRisk
        self.heredocDetected = heredocDetected
        self.detectedWidth = detectedWidth
    }
}

/// Output of the pure repair pipeline (PRD v2 §6).
public struct RepairResult: Sendable, Equatable {
    public let text: String
    public let report: RepairReport

    public init(text: String, report: RepairReport) {
        self.text = text
        self.report = report
    }
}
