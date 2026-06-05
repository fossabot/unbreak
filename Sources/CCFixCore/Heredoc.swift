import Foundation

/// Heredoc detection and protected-region marking (PRD v2 §6.4).
///
/// Detects `<<EOF`, `<<-EOF`, `<<'EOF'`, `<<"EOF"`, and `<<\EOF` openers and
/// their terminators, returning the set of line indices that form each heredoc
/// *body* — the lines after an opener up to and including the terminator (or the
/// end of the input if the selection was cut off before the terminator). De-gutter
/// and rejoin leave those indices untouched, and the §6.5 merge-split never fires
/// inside them. The opener line itself is a normal command line and is *not*
/// protected, so wrap/dedent repairs still apply to it.
enum Heredoc {
    /// One heredoc opener: the (unquoted) delimiter word plus whether it was the
    /// `<<-` variant (which strips leading tabs from the terminator).
    struct Delimiter: Equatable {
        let word: String
        let allowLeadingTabs: Bool
    }

    struct Result: Equatable {
        let protectedLines: Set<Int>
        let detected: Bool
    }

    /// Scan the lines (already normalized to LF) and mark heredoc body regions.
    static func detect(_ lines: [String]) -> Result {
        var protectedLines: Set<Int> = []
        var detected = false
        var i = 0
        while i < lines.count {
            guard let delim = opener(in: lines[i]) else {
                i += 1
                continue
            }
            detected = true
            // The body starts on the next line and runs until a terminator line
            // (trimmed content equals the delimiter) or the end of the input.
            // Advancing `i` past the body means openers *inside* a body are not
            // re-parsed — heredoc content is literal, not shell syntax.
            var j = i + 1
            while j < lines.count {
                protectedLines.insert(j)
                let terminated = isTerminator(lines[j], delimiter: delim)
                j += 1
                if terminated { break }
            }
            i = j
        }
        return Result(protectedLines: protectedLines, detected: detected)
    }

    /// Parse the first heredoc opener on a line, if any. Returns `nil` for plain
    /// `<<<` here-strings (no body) and for `<<` with no delimiter word.
    static func opener(in line: String) -> Delimiter? {
        let scalars = Array(line.unicodeScalars)
        let lt: UInt32 = 0x3C  // '<'
        var i = 0
        while i < scalars.count {
            guard scalars[i].value == lt, i + 1 < scalars.count, scalars[i + 1].value == lt else {
                i += 1
                continue
            }
            // `<<<` is a here-string, not a heredoc — skip the whole run of '<'.
            if i + 2 < scalars.count, scalars[i + 2].value == lt {
                i += 3
                while i < scalars.count, scalars[i].value == lt { i += 1 }
                continue
            }
            if let delim = parseDelimiter(scalars, from: i + 2) {
                return delim
            }
            i += 2
        }
        return nil
    }

    /// Parse the delimiter token that follows `<<` (or `<<-`): an optional `-`,
    /// optional spaces/tabs, then a quoted (`'`/`"`), backslash-escaped, or bare
    /// word. Returns `nil` when no delimiter word is present.
    private static func parseDelimiter(_ scalars: [Unicode.Scalar], from start: Int) -> Delimiter? {
        var i = start
        var allowLeadingTabs = false
        if i < scalars.count, scalars[i].value == 0x2D {  // '-' → <<- variant
            allowLeadingTabs = true
            i += 1
        }
        while i < scalars.count, scalars[i].value == 0x20 || scalars[i].value == 0x09 {
            i += 1  // skip spaces/tabs between the operator and the delimiter
        }
        guard i < scalars.count else { return nil }

        let quote = scalars[i].value
        if quote == 0x27 || quote == 0x22 {  // '\'' or '"' → read until the match
            i += 1
            var word = String.UnicodeScalarView()
            while i < scalars.count, scalars[i].value != quote {
                word.append(scalars[i])
                i += 1
            }
            guard i < scalars.count, !word.isEmpty else { return nil }
            return Delimiter(word: String(word), allowLeadingTabs: allowLeadingTabs)
        }

        if scalars[i].value == 0x5C { i += 1 }  // '\EOF' — escaped, same as bare
        var word = String.UnicodeScalarView()
        while i < scalars.count, !isDelimiterTerminator(scalars[i].value) {
            word.append(scalars[i])
            i += 1
        }
        guard !word.isEmpty else { return nil }
        return Delimiter(word: String(word), allowLeadingTabs: allowLeadingTabs)
    }

    /// A bare delimiter word ends at whitespace or a shell metacharacter.
    private static func isDelimiterTerminator(_ value: UInt32) -> Bool {
        switch value {
        case 0x20, 0x09:  // space, tab
            return true
        case 0x3B, 0x26, 0x7C, 0x3C, 0x3E, 0x28, 0x29, 0x60, 0x23:  // ; & | < > ( ) ` #
            return true
        default:
            return false
        }
    }

    /// A line terminates the body when its content (after trimming leading and
    /// trailing whitespace) equals the delimiter word.
    ///
    /// Leading whitespace is trimmed for two reasons: the `<<-` variant strips
    /// leading tabs from the terminator, and — more importantly here — a copied
    /// TUI line carries the render gutter on every line, so even a plain `<<EOF`
    /// terminator arrives indented. Trimming makes detection robust to that
    /// gutter, which is the whole point of this tool.
    static func isTerminator(_ line: String, delimiter: Delimiter) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == delimiter.word
    }
}
