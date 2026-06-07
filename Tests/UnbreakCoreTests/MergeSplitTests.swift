import Testing

@testable import UnbreakCore

@Suite("Merge-artifact split (PRD v2 §6.5, lossy / off by default)")
struct MergeSplitTests {
    private let w = 42

    @Test("Off by default: a padded merge is left merged")
    func offByDefault() {
        let merged = String(repeating: "x", count: 42) + "   git push origin"
        // No --split-padding-artifacts → unchanged even though it looks merged.
        #expect(Repair.repair(merged, options: .init(forcedWidth: w)).text == merged)
    }

    @Test("Opt-in splits a long line at the padding run before a fresh statement")
    func optInSplits() {
        let left = String(repeating: "x", count: 42)
        let merged = left + "   git push origin"
        let out = Repair.repair(
            merged,
            options: .init(forcedWidth: w, splitPaddingArtifacts: true)
        ).text
        #expect(out == left + "\ngit push origin")
    }

    @Test("A shell keyword tail (fi) qualifies as a statement start")
    func keywordTailSplits() {
        let left = String(repeating: "y", count: 44)
        let merged = left + "   fi"
        let out = Repair.repair(
            merged,
            options: .init(forcedWidth: w, splitPaddingArtifacts: true)
        ).text
        #expect(out == left + "\nfi")
    }

    @Test("Never splits inside a heredoc body, even when opted in")
    func neverInsideHeredoc() {
        let body = String(repeating: "y", count: 44) + "   git push"
        let input = "cat <<EOF\n" + body + "\nEOF"
        let out = Repair.repair(
            input,
            options: .init(forcedWidth: w, splitPaddingArtifacts: true)
        ).text
        #expect(out == input)
    }

    @Test("Does not split when the tail is not statement-like (intentional alignment)")
    func keepsAlignment() {
        let line = String(repeating: "z", count: 44) + "   aligned prose follows"
        let out = Repair.repair(
            line,
            options: .init(forcedWidth: w, splitPaddingArtifacts: true)
        ).text
        #expect(out == line)
    }

    @Test("Does not split at a padding run that sits before the wrap column W")
    func respectsPastWidthGuard() {
        // The qualifying run (4 spaces before a `git` tail) is at column 7, well
        // short of W=42, so the guard suppresses the split.
        let line = "echo hi    git push" + String(repeating: "!", count: 40)
        let out = Repair.repair(
            line,
            options: .init(forcedWidth: w, splitPaddingArtifacts: true)
        ).text
        #expect(out == line)
    }

    @Test("With no detectable wrap column, nothing is split")
    func noWidthNoSplit() {
        let merged = String(repeating: "x", count: 50) + "   git push"
        // Single line → no width detected and none forced → split is a no-op.
        let out = Repair.repair(merged, options: .init(splitPaddingArtifacts: true)).text
        #expect(out == merged)
    }

    // MARK: Direct unit checks

    @Test("looksLikeStatementStart accepts commands and keywords, rejects prose")
    func statementStartClassification() {
        #expect(MergeSplit.looksLikeStatementStart("git commit -m x"))
        #expect(MergeSplit.looksLikeStatementStart("done"))
        #expect(!MergeSplit.looksLikeStatementStart("the rest of a sentence"))
        #expect(!MergeSplit.looksLikeStatementStart(""))
    }
}
