import Testing

@testable import CCFixCore

@Suite("Repair pipeline (PRD v2 §6)")
struct RepairTests {
    // MARK: §6.1 Normalize

    @Test("CRLF and CR collapse to LF")
    func normalizesNewlines() {
        #expect(Repair.normalize("a\r\nb\rc") == "a\nb\nc")
    }

    @Test("Strips ANSI SGR color sequences (§6.1)")
    func stripsSGR() {
        // Red "git status" reset — the escapes must not survive or count as width.
        #expect(Repair.normalize("\u{1B}[31mgit status\u{1B}[0m") == "git status")
    }

    @Test("Strips a multi-parameter CSI sequence (§6.1)")
    func stripsCSI() {
        #expect(Repair.normalize("a\u{1B}[1;32;40mb") == "ab")
    }

    @Test("Strips an OSC52 clipboard sequence terminated by BEL (§6.1, §13)")
    func stripsOSC52BEL() {
        #expect(Repair.normalize("\u{1B}]52;c;Zm9v\u{07}echo hi") == "echo hi")
    }

    @Test("Strips an OSC sequence terminated by ST (ESC backslash) (§6.1)")
    func stripsOSCWithST() {
        #expect(Repair.normalize("\u{1B}]0;title\u{1B}\\ls") == "ls")
    }

    @Test("Escape bytes do not count as display columns after normalize (§6.1)")
    func escapesDoNotCountAsWidth() {
        let colored = "\u{1B}[32m" + String(repeating: "x", count: 42) + "\u{1B}[0m"
        #expect(DisplayWidth.width(of: Repair.normalize(colored)) == 42)
    }

    // MARK: §6.2 De-gutter

    @Test("Removes the common gutter, preserving relative indent among lines 2..n (§5 cases 2/6)")
    func dedentRemovesGutterKeepsRelativeIndent() {
        // Gutter = minimum indent of the continuation lines (4). Stripping it
        // keeps the 4-space nesting difference between the two of them.
        let input = "git clone foo\n    && cd foo\n        && nested"
        let (out, changed) = Repair.degutter(input, tabWidth: 8)
        #expect(changed)
        #expect(out == "git clone foo\n&& cd foo\n    && nested")
    }

    @Test("Excludes a partially selected first line from gutter detection (§5 case 3)")
    func dedentExcludesPartialFirstLine() {
        // Line 1 has only 1 leading space (partial selection); the gutter (4) is
        // computed from lines 2..n, and line 1 loses only min(1, 4) = 1 space.
        let input = " git push\n    --force\n    origin"
        let (out, _) = Repair.degutter(input, tabWidth: 8)
        #expect(out == "git push\n--force\norigin")
    }

    // MARK: §6.3 Rejoin

    @Test("Rejoins a word-boundary wrap with a single space (§5 case 1)")
    func rejoinSingleSpace() {
        // First line is full (width 42 == W) and ends in a normal character, not
        // a continuation token, so the next line is rejoined with one space.
        let head = String(repeating: "x", count: 42)
        let (out, _, _) = Repair.rejoin(
            head + "\n/tmp/out.json",
            profile: .claudeCode,
            options: .init(forcedWidth: 42)
        )
        #expect(out == head + " /tmp/out.json")
    }

    @Test("Leaves explicit `\\` continuations as separate lines (§5 case 6)")
    func preservesBackslashContinuation() {
        let input = String(repeating: "y", count: 42) + " \\\nnext line"
        let (out, _, _) = Repair.rejoin(
            input,
            profile: .claudeCode,
            options: .init(forcedWidth: 44)
        )
        #expect(out == input)
    }

    // MARK: §6.8 Guarantees

    @Test("Clean single-line input is returned unchanged")
    func cleanSingleLineUnchanged() {
        let input = "git status"
        #expect(Repair.repair(input).text == input)
    }

    @Test("Clean short multi-line input is returned unchanged")
    func cleanMultiLineUnchanged() {
        let input = "line one\nline two\nline three"
        #expect(Repair.repair(input).text == input)
    }

    @Test("Idempotent: repairing twice equals repairing once")
    func idempotent() {
        let wrapped = [
            String(repeating: "a", count: 42),
            String(repeating: "b", count: 42),
            "tail",
        ].joined(separator: "\n")
        let once = Repair.repair(wrapped, options: .init(forcedWidth: 42)).text
        let twice = Repair.repair(once, options: .init(forcedWidth: 42)).text
        #expect(once == twice)
    }
}
