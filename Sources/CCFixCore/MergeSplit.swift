import Foundation

/// Merge-artifact split (PRD v2 §6.5) — **lossy and off by default**.
///
/// A renderer can drop a newline and hide the seam behind a run of padding
/// spaces, leaving one over-long line where two statements were merged (§5 Case
/// 5). This pass splits such a line at the padding run. It is heuristic and
/// indistinguishable in general from intentional alignment, and the original
/// indent is unrecoverable — so it runs **only** when the caller opts in
/// (`RepairOptions.splitPaddingArtifacts`), and **never** inside a heredoc body
/// (§6.4). It is the one artifact the tool does not promise to fix cleanly, and
/// it is not guaranteed idempotent (rejoin and split are partial inverses).
enum MergeSplit {
    /// Split over-long lines at qualifying padding runs. `width` is the detected
    /// wrap column `W`; with no `W` there is nothing to be "past", so the text is
    /// returned untouched. Returns the rewritten text and the number of splits.
    static func split(
        _ text: String,
        profile: WrapProfile,
        width: Int?
    ) -> (text: String, splits: Int) {
        guard let w = width else { return (text, 0) }
        let lines = Repair.splitLines(text)
        // Re-detect heredocs against *this* text: rejoin may have merged earlier
        // lines and shifted indices, so a set computed pre-rejoin no longer maps.
        let protected = Heredoc.detect(lines).protectedLines

        var out: [String] = []
        var splits = 0
        for (idx, line) in lines.enumerated() {
            let lineWidth = DisplayWidth.width(of: line, tabWidth: profile.tabWidth)
            let eligible = !protected.contains(idx) && lineWidth > w
            let pieces = eligible ? splitLine(line, profile: profile, width: w) : nil
            if let pieces {
                out.append(contentsOf: pieces)
                splits += pieces.count - 1
            } else {
                out.append(line)
            }
        }
        return (out.joined(separator: "\n"), splits)
    }

    /// Split a single line at the first padding run that (a) is at least
    /// `profile.minPaddingRun` spaces, (b) sits past the wrap column `W` (the
    /// content before it is already a full line), and (c) is followed by something
    /// that looks like a fresh statement. Recurses on the tail so a triple-merge
    /// splits fully. Returns `nil` when no run qualifies.
    static func splitLine(_ line: String, profile: WrapProfile, width w: Int) -> [String]? {
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            guard chars[i] == " " else {
                i += 1
                continue
            }
            var j = i
            while j < chars.count, chars[j] == " " { j += 1 }
            if j - i >= profile.minPaddingRun {
                let leftWidth = DisplayWidth.width(
                    of: String(chars[0..<i]),
                    tabWidth: profile.tabWidth
                )
                if leftWidth >= w {
                    let tail = String(chars[j...])
                    if looksLikeStatementStart(tail) {
                        let rest = splitLine(tail, profile: profile, width: w) ?? [tail]
                        return [String(chars[0..<i])] + rest
                    }
                }
            }
            i = j
        }
        return nil
    }

    /// Shell keywords that legitimately begin a statement but are not commands, so
    /// `Signals.shell` would miss them (a lone `fi` is not "command-shaped").
    static let statementKeywords: Set<String> = [
        "fi", "done", "then", "else", "elif", "do", "esac", "case", "while",
        "for", "if", "until", "return", "function",
    ]

    /// The tail after a padding run looks like a separate statement when it starts
    /// with a shell keyword or clears the §7 gate-5 shell-signal bar.
    static func looksLikeStatementStart(_ tail: String) -> Bool {
        let trimmed = tail.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let firstWord = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .first.map(String.init)
        if let firstWord, statementKeywords.contains(firstWord) {
            return true
        }
        return Signals.shell(trimmed).passesGate
    }
}
