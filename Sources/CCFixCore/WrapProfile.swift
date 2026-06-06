/// Per-tool wrap behavior as data, not a framework (PRD v2 §6.6).
///
/// Adding Gemini/Codex support should be a new value here plus fixtures, not new
/// code paths. v1 ships `claudeCode` only.
public struct WrapProfile: Sendable {
    public var name: String
    /// Tokens that, when a line ends with one, mark an *intentional* line break
    /// (heredoc/`\` layout/one-operator-per-line) that must be preserved (§6.3).
    public var continuationTokens: [String]
    public var tabWidth: Int
    /// Minimum wrap-column confidence before rejoin is attempted (§6.3).
    public var minWrapConfidence: Double
    /// Minimum run of spaces that can mark a merge artifact's hidden newline (§6.5).
    public var minPaddingRun: Int

    public init(
        name: String,
        continuationTokens: [String],
        tabWidth: Int = DisplayWidth.defaultTabWidth,
        minWrapConfidence: Double = 0.5,
        minPaddingRun: Int = 3
    ) {
        self.name = name
        self.continuationTokens = continuationTokens
        self.tabWidth = tabWidth
        self.minWrapConfidence = minWrapConfidence
        self.minPaddingRun = minPaddingRun
    }

    public static let claudeCode = WrapProfile(
        name: "claude-code",
        continuationTokens: ["\\", "&&", "||", "|", "(", ","]
    )
}

/// One-shot CLI options (PRD v2 §8.1).
public struct RepairOptions: Sendable, Equatable {
    public var forcedWidth: Int?
    public var joinAll: Bool
    /// Lossy merge-artifact split — off by default (§6.5).
    public var splitPaddingArtifacts: Bool

    public init(
        forcedWidth: Int? = nil,
        joinAll: Bool = false,
        splitPaddingArtifacts: Bool = false
    ) {
        self.forcedWidth = forcedWidth
        self.joinAll = joinAll
        self.splitPaddingArtifacts = splitPaddingArtifacts
    }
}
