import Foundation

/// Content classification for the confidence model (PRD v2 §6.7) and the watch-mode
/// gates (§7 gates 5 and 6).
///
/// `shell(_:)` implements the discrete shell-signal tiers (gate 5): the gate passes
/// iff there is ≥1 strong signal OR ≥2 weak signals. `structure(_:)` implements the
/// structure-risk veto (gate 6): markdown dominance, stack traces, or a prose ratio.
///
/// The pure repair pipeline records the derived 0…1 floats (`shellSignalScore`,
/// `structureRisk`) in the `RepairReport` for logging and power-user thresholds; the
/// watcher consults the discrete `passesGate` / `vetoes` booleans directly so the
/// tier rule, not a float, is the source of truth.
public enum Signals {
    // MARK: - Shell signal (§7 gate 5)

    public struct Shell: Sendable, Equatable {
        /// Number of distinct strong-signal categories present (0…4).
        public let strongCount: Int
        /// Number of distinct weak-signal categories present (0…3).
        public let weakCount: Int

        /// Discrete tier rule (§7 gate 5): ≥1 strong, OR ≥2 weak. A lone weak
        /// signal never passes — that is the prose trap.
        public var passesGate: Bool { strongCount >= 1 || weakCount >= 2 }

        /// 0…1 projection of the tiers for logging/overrides. Calibrated so the
        /// gate's pass boundary lands at exactly 0.5 (one strong = two weak = 0.5).
        public var score: Double {
            min(1.0, 0.5 * Double(strongCount) + 0.25 * Double(weakCount))
        }
    }

    public static func shell(_ text: String) -> Shell {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let nonBlank = lines.filter { !$0.allSatisfy { $0 == " " || $0 == "\t" } }

        // Strong categories (presence anywhere in the fragment).
        var strong = 0
        if nonBlank.contains(where: hasTopLevelOperator) { strong += 1 }
        if text.contains("$(") || text.contains("`") { strong += 1 }
        if nonBlank.contains(where: hasEnvAssignmentPrefix) { strong += 1 }
        if nonBlank.contains(where: startsWithKnownTool) { strong += 1 }

        // Weak categories (presence anywhere; need ≥2 distinct to count).
        var weak = 0
        if nonBlank.contains(where: looksLikeCommandShape) { weak += 1 }
        if nonBlank.contains(where: hasFlagCluster) { weak += 1 }
        if nonBlank.contains(where: hasPathLikeToken) { weak += 1 }

        return Shell(strongCount: strong, weakCount: weak)
    }

    // MARK: - Structure risk (§7 gate 6)

    public struct Structure: Sendable, Equatable {
        public let markdownDominant: Bool
        public let stackTrace: Bool
        public let prose: Bool
        /// 0…1 risk estimate for logging/overrides; ≥0.5 whenever a veto fires.
        public let risk: Double

        /// Any one of the three patterns vetoes a watch-mode mutation (§7 gate 6).
        public var vetoes: Bool { markdownDominant || stackTrace || prose }
    }

    public static func structure(_ text: String) -> Structure {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let nonBlank = lines.filter { !$0.allSatisfy { $0 == " " || $0 == "\t" } }
        guard !nonBlank.isEmpty else {
            return Structure(markdownDominant: false, stackTrace: false, prose: false, risk: 0)
        }
        let total = Double(nonBlank.count)

        // Markdown: list/heading markers at multiple line starts that dominate.
        let mdCount = nonBlank.filter(startsWithMarkdownMarker).count
        let mdFraction = Double(mdCount) / total
        let markdownDominant = mdCount >= 2 && mdFraction >= 0.5

        // Stack trace: ≥2 `at …(file:line)` frames, or any Python `File "…", line N`.
        let atFrames = nonBlank.filter(looksLikeAtFrame).count
        let pyFrames = nonBlank.filter(looksLikePythonFrame).count
        let stackTrace = atFrames >= 2 || pyFrames >= 1
        let stackFraction = Double(atFrames + pyFrames) / total

        // Prose: most lines end in sentence punctuation, letters dominate symbols,
        // and there are no shell operators.
        let sentenceLines = nonBlank.filter(endsWithSentencePunctuation).count
        let sentenceFraction = Double(sentenceLines) / total
        let noOperators =
            !nonBlank.contains(where: hasTopLevelOperator) && !text.contains("$(")
            && !text.contains("`")
        let prose = sentenceFraction >= 0.5 && alphaRatio(text) >= 0.7 && noOperators

        let mdScore = markdownDominant ? max(0.6, mdFraction) : mdFraction
        let stackScore = stackTrace ? max(0.6, stackFraction) : stackFraction * 0.5
        let proseScore = prose ? max(0.6, sentenceFraction) : sentenceFraction * 0.4
        let risk = min(1.0, max(mdScore, max(stackScore, proseScore)))

        return Structure(
            markdownDominant: markdownDominant,
            stackTrace: stackTrace,
            prose: prose,
            risk: risk
        )
    }

    // MARK: - Shell-signal helpers

    /// A top-level (outside single/double quotes) unquoted operator: `|`, `;`, `>`,
    /// or `&&`. Quote tracking keeps operators inside string literals from counting.
    static func hasTopLevelOperator(_ line: String) -> Bool {
        var inSingle = false
        var inDouble = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inSingle {
                if c == "'" { inSingle = false }
            } else if inDouble {
                if c == "\"" { inDouble = false }
            } else {
                switch c {
                case "'": inSingle = true
                case "\"": inDouble = true
                case "|", ";", ">": return true
                case "&" where i + 1 < chars.count && chars[i + 1] == "&": return true
                default: break
                }
            }
            i += 1
        }
        return false
    }

    /// `VAR=value …` at a line start: an identifier immediately followed by `=`.
    static func hasEnvAssignmentPrefix(_ line: String) -> Bool {
        let trimmed = Substring(line).drop { $0 == " " || $0 == "\t" }
        var sawNameChar = false
        for ch in trimmed {
            if ch == "=" { return sawNameChar }
            if ch.isLetter || ch == "_" || (sawNameChar && ch.isNumber) {
                sawNameChar = true
            } else {
                return false
            }
        }
        return false
    }

    static let knownTools: Set<String> = [
        "git", "gh", "brew", "npm", "npx", "yarn", "pnpm", "node", "deno", "bun",
        "docker", "docker-compose", "kubectl", "helm", "curl", "wget", "ssh", "scp",
        "rsync", "cd", "ls", "cat", "grep", "rg", "sed", "awk", "find", "tar", "zip",
        "unzip", "python", "python3", "pip", "pip3", "ruby", "gem", "go", "cargo",
        "rustc", "rustup", "make", "cmake", "bash", "sh", "zsh", "fish", "sudo",
        "apt", "apt-get", "yum", "dnf", "pacman", "systemctl", "launchctl", "fp",
        "swift", "swiftc", "java", "javac", "mvn", "gradle", "terraform", "aws",
        "gcloud", "az", "psql", "mysql", "redis-cli", "echo", "export", "source",
        "mkdir", "rm", "cp", "mv", "touch", "chmod", "chown", "ln", "head", "tail",
        "less", "more", "open", "defaults", "codesign", "xcodebuild", "xcrun",
    ]

    static func startsWithKnownTool(_ line: String) -> Bool {
        guard let first = firstToken(of: line) else { return false }
        return knownTools.contains(first)
    }

    /// `word [more] …`: a bareword command name followed by at least one argument,
    /// and not a prose sentence (the first token must not end in `.`/`!`/`?`).
    static func looksLikeCommandShape(_ line: String) -> Bool {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard tokens.count >= 2, let first = tokens.first else { return false }
        let nameOK = first.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." || $0 == "/"
        }
        let last = first.last
        let sentenceEnd = last == "." || last == "!" || last == "?"
        return nameOK && !sentenceEnd
    }

    static func hasFlagCluster(_ line: String) -> Bool {
        line.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains { token in
            guard token.hasPrefix("-"), token.count >= 2 else { return false }
            let afterDashes = token.drop { $0 == "-" }
            return afterDashes.first?.isLetter == true
        }
    }

    static func hasPathLikeToken(_ line: String) -> Bool {
        line.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains { token in
            let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if t.hasPrefix("/") || t.hasPrefix("./") || t.hasPrefix("../") || t.hasPrefix("~/") {
                return true
            }
            // A bare token with an interior slash (e.g. src/main.swift).
            return t.dropFirst().dropLast().contains("/")
        }
    }

    // MARK: - Structure helpers

    static func startsWithMarkdownMarker(_ line: String) -> Bool {
        let t = Substring(line).drop { $0 == " " || $0 == "\t" }
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") { return true }
        // Heading: 1–6 '#' then a space.
        if t.first == "#" {
            let hashes = t.prefix { $0 == "#" }
            let rest = t.dropFirst(hashes.count)
            if (1...6).contains(hashes.count) && rest.first == " " { return true }
        }
        // Ordered list: digits, '.', space.
        let digits = t.prefix { $0.isNumber }
        if !digits.isEmpty {
            let rest = t.dropFirst(digits.count)
            if rest.hasPrefix(". ") { return true }
        }
        return false
    }

    static func looksLikeAtFrame(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("at "), let open = t.lastIndex(of: "("), t.hasSuffix(")") else {
            return false
        }
        let inside = t[t.index(after: open)..<t.index(before: t.endIndex)]
        // A frame location reads as `file:line` (and often `:col`).
        guard let colon = inside.lastIndex(of: ":") else { return false }
        return inside[inside.index(after: colon)...].contains { $0.isNumber }
    }

    static func looksLikePythonFrame(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("File \"") && t.contains("\", line ")
    }

    static func endsWithSentencePunctuation(_ line: String) -> Bool {
        guard let last = line.reversed().first(where: { $0 != " " && $0 != "\t" }) else {
            return false
        }
        return last == "." || last == "!" || last == "?"
    }

    /// Fraction of non-space characters that are letters — high for prose, low for
    /// command lines dense with flags, paths, and operators.
    static func alphaRatio(_ text: String) -> Double {
        var letters = 0
        var nonSpace = 0
        for ch in text where ch != " " && ch != "\t" && ch != "\n" {
            nonSpace += 1
            if ch.isLetter { letters += 1 }
        }
        guard nonSpace > 0 else { return 0 }
        return Double(letters) / Double(nonSpace)
    }

    static func firstToken(of line: String) -> String? {
        line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
    }
}
