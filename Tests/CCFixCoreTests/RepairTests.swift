import Testing
@testable import CCFixCore

@Suite("Repair pipeline (PRD v2 §6)")
struct RepairTests {
    // MARK: §6.1 Normalize

    @Test("CRLF and CR collapse to LF")
    func normalizesNewlines() {
        #expect(Repair.normalize("a\r\nb\rc") == "a\nb\nc")
    }

    // MARK: §6.2 De-gutter

    @Test("Strips a uniform +2 gutter, preserving relative indent (§5 case 2)")
    func dedentUniformGutter() {
        let input = "  git clone foo\n    && cd foo"
        let (out, changed) = Repair.degutter(input, tabWidth: 8)
        #expect(changed)
        #expect(out == "git clone foo\n  && cd foo")
    }

    @Test("Computes gutter from lines 2..n when line 1 is partial (§5 case 3)")
    func dedentPartialFirstLine() {
        let input = "git clone foo\n    && cd foo"
        let (out, _) = Repair.degutter(input, tabWidth: 8)
        #expect(out == "git clone foo\n  && cd foo")
    }

    // MARK: §6.3 Rejoin

    @Test("Rejoins a word-boundary wrap with a single space (§5 case 1)")
    func rejoinSingleSpace() {
        let lines = [
            String(repeating: "x", count: 40) + " |",
            "/tmp/out.json",
        ]
        let (out, _, _) = Repair.rejoin(
            lines.joined(separator: "\n"),
            profile: .claudeCode,
            options: .init(forcedWidth: 42)
        )
        #expect(out == String(repeating: "x", count: 40) + " | /tmp/out.json")
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
