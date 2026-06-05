import Testing

@testable import CCFixCore

@Suite("Heredoc detection / protected regions (PRD v2 §6.4)")
struct HeredocTests {
    // MARK: Opener parsing

    @Test("Parses a plain <<EOF opener")
    func parsesPlainOpener() {
        let delim = Heredoc.opener(in: "cat <<EOF")
        #expect(delim == Heredoc.Delimiter(word: "EOF", allowLeadingTabs: false))
    }

    @Test("Parses the <<- tab-stripping variant")
    func parsesDashVariant() {
        let delim = Heredoc.opener(in: "cat <<-END")
        #expect(delim == Heredoc.Delimiter(word: "END", allowLeadingTabs: true))
    }

    @Test("Parses a single-quoted delimiter (<<'EOF')")
    func parsesQuotedDelimiter() {
        let delim = Heredoc.opener(in: "cat <<'EOF'")
        #expect(delim == Heredoc.Delimiter(word: "EOF", allowLeadingTabs: false))
    }

    @Test("Parses a double-quoted delimiter (<<\"EOF\")")
    func parsesDoubleQuotedDelimiter() {
        let delim = Heredoc.opener(in: "cat <<\"BLOCK\"")
        #expect(delim == Heredoc.Delimiter(word: "BLOCK", allowLeadingTabs: false))
    }

    @Test("Parses a backslash-escaped delimiter (<<\\EOF)")
    func parsesEscapedDelimiter() {
        let delim = Heredoc.opener(in: "cat <<\\EOF")
        #expect(delim == Heredoc.Delimiter(word: "EOF", allowLeadingTabs: false))
    }

    @Test("Tolerates whitespace between << and the delimiter")
    func parsesWithSpace() {
        let delim = Heredoc.opener(in: "cat << EOF > out")
        #expect(delim == Heredoc.Delimiter(word: "EOF", allowLeadingTabs: false))
    }

    @Test("A redirect after the delimiter does not bleed into the word")
    func delimiterStopsAtRedirect() {
        let delim = Heredoc.opener(in: "cat <<EOF >file.txt")
        #expect(delim == Heredoc.Delimiter(word: "EOF", allowLeadingTabs: false))
    }

    @Test("<<< here-string is not a heredoc")
    func herestringIgnored() {
        #expect(Heredoc.opener(in: "grep foo <<< \"$var\"") == nil)
    }

    @Test("A line with no heredoc operator has no opener")
    func noOpener() {
        #expect(Heredoc.opener(in: "echo a < b > c") == nil)
    }

    // MARK: Body region marking

    @Test("Marks the body and terminator, leaving the opener and tail free")
    func marksBodyRegion() {
        let lines = [
            "cat <<EOF",  // 0 opener — not protected
            "line one",  // 1 body
            "line two",  // 2 body
            "EOF",  // 3 terminator — protected
            "echo done",  // 4 tail — not protected
        ]
        let result = Heredoc.detect(lines)
        #expect(result.detected)
        #expect(result.protectedLines == [1, 2, 3])
    }

    @Test("An unterminated heredoc protects through end of input")
    func unterminatedProtectsToEnd() {
        let lines = ["cat <<EOF", "body still going", "more body"]
        let result = Heredoc.detect(lines)
        #expect(result.detected)
        #expect(result.protectedLines == [1, 2])
    }

    @Test("Terminator matches despite a leading gutter (copied TUI text)")
    func terminatorMatchesThroughGutter() {
        let lines = ["  cat <<EOF", "  body", "  EOF", "  echo done"]
        let result = Heredoc.detect(lines)
        #expect(result.protectedLines == [1, 2])
    }

    @Test("Openers inside a body are not re-parsed as nested heredocs")
    func nestedOpenerInsideBodyIgnored() {
        let lines = [
            "cat <<OUTER",
            "cat <<INNER",  // literal body content, not a real opener
            "still body",
            "OUTER",
            "echo done",
        ]
        let result = Heredoc.detect(lines)
        #expect(result.protectedLines == [1, 2, 3])
    }

    @Test("No heredoc → nothing detected, nothing protected")
    func noHeredoc() {
        let result = Heredoc.detect(["git status", "echo hi"])
        #expect(!result.detected)
        #expect(result.protectedLines.isEmpty)
    }

    // MARK: Integration with the repair pipeline

    @Test("heredocDetected surfaces in the RepairReport")
    func reportFlag() {
        let input = "cat <<EOF\nbody\nEOF"
        #expect(Repair.repair(input).report.heredocDetected)
        #expect(!Repair.repair("git status").report.heredocDetected)
    }

    @Test("De-gutter leaves the heredoc body untouched but still dedents commands")
    func degutterSkipsBody() {
        // Every line carries a +2 gutter. The command lines (opener + tail) are
        // dedented; the heredoc body keeps its raw indentation (§6.4 / §5 case 6).
        let input = "  cat <<EOF\n      indented body\n  EOF\n  echo done"
        let out = Repair.repair(input).text
        #expect(out == "cat <<EOF\n      indented body\n  EOF\necho done")
    }

    @Test("Rejoin never merges the opener into the body or merges body lines")
    func rejoinSkipsBody() {
        // The opener line is exactly the wrap width, which would normally absorb
        // the next line — but it is the first body line, so the join is vetoed.
        let opener = "cat " + String(repeating: "x", count: 38) + " <<EOF"
        let bodyA = String(repeating: "a", count: 42)
        let bodyB = "EOF"
        let input = [opener, bodyA, bodyB].joined(separator: "\n")
        let result = Repair.repair(input, options: .init(forcedWidth: 42))
        #expect(result.text == input)
        #expect(result.report.heredocDetected)
    }

    @Test("join-all still cannot collapse a heredoc body")
    func joinAllRespectsHeredoc() {
        let input = "cat <<EOF\nfirst\nsecond\nEOF\necho tail"
        let out = Repair.repair(input, options: .init(joinAll: true)).text
        // Body newlines survive; only the free tail could ever be joined (here it
        // follows the protected terminator, so it stays put too).
        #expect(out.contains("first\nsecond\nEOF"))
    }
}
