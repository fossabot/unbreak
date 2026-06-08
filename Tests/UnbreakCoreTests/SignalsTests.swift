import Testing

@testable import UnbreakCore

@Suite("Confidence signals (PRD v2 §6.7, §7 gates 5/6)")
struct SignalsTests {
    // MARK: §7 gate 5 — shell-signal tiers

    @Test("A single strong signal (known tool) passes the gate")
    func strongToolPasses() {
        let s = Signals.shell("git status")
        #expect(s.strongCount >= 1)
        #expect(s.passesGate)
        #expect(s.score >= 0.5)
    }

    @Test("A top-level pipe operator is a strong signal")
    func pipeIsStrong() {
        #expect(Signals.shell("cat file | wc -l").passesGate)
    }

    @Test("An env-assignment prefix is a strong signal")
    func envAssignmentIsStrong() {
        let s = Signals.shell("FOO=bar ./run.sh")
        #expect(s.strongCount >= 1)
        #expect(s.passesGate)
    }

    @Test("Command substitution $(...) is a strong signal")
    func commandSubstitutionIsStrong() {
        #expect(Signals.shell("echo $(date)").strongCount >= 1)
    }

    @Test("An operator inside quotes does not count; a bare one does")
    func quotedOperatorIgnored() {
        #expect(!Signals.hasTopLevelOperator("printf 'a | b'"))
        #expect(Signals.hasTopLevelOperator("printf a | b"))
    }

    @Test("A single weak signal alone does not pass (the prose trap)")
    func singleWeakDoesNotPass() {
        // "the quick brown fox" — command-shaped but no flags/paths/strong signals.
        let s = Signals.shell("the quick brown fox")
        #expect(s.strongCount == 0)
        #expect(s.weakCount == 1)
        #expect(!s.passesGate)
    }

    @Test("Two weak signals pass (command shape + flag cluster)")
    func twoWeakPass() {
        // Not a known tool, but command-shaped, with a flag and a path.
        let s = Signals.shell("./mytool --verbose ./out")
        #expect(s.strongCount == 0)
        #expect(s.weakCount >= 2)
        #expect(s.passesGate)
    }

    @Test("Score is calibrated so the pass boundary is 0.5")
    func scoreBoundary() {
        #expect(Signals.Shell(strongCount: 1, weakCount: 0).score == 0.5)
        #expect(Signals.Shell(strongCount: 0, weakCount: 2).score == 0.5)
        #expect(Signals.Shell(strongCount: 0, weakCount: 1).score == 0.25)
        #expect(Signals.Shell(strongCount: 3, weakCount: 3).score == 1.0)  // capped
    }

    // MARK: §7 gate 6 — structure-risk veto

    @Test("Prose vetoes: sentence endings, letter-dominant, no operators")
    func proseVetoes() {
        let text = "The quick brown fox jumped.\nIt landed softly.\nThen it slept."
        let s = Signals.structure(text)
        #expect(s.prose)
        #expect(s.vetoes)
        #expect(s.risk >= 0.5)
    }

    @Test("A dominant markdown list vetoes")
    func markdownVetoes() {
        let s = Signals.structure("- first item\n- second item\n- third item")
        #expect(s.markdownDominant)
        #expect(s.vetoes)
    }

    @Test("Markdown headings and ordered lists are recognized")
    func markdownForms() {
        #expect(Signals.startsWithMarkdownMarker("## Heading"))
        #expect(Signals.startsWithMarkdownMarker("1. first"))
        #expect(Signals.startsWithMarkdownMarker("* bullet"))
        #expect(!Signals.startsWithMarkdownMarker("#nospace"))
    }

    @Test("A Python traceback vetoes")
    func pythonStackVetoes() {
        let text = """
            Traceback (most recent call last):
              File "/app/main.py", line 42, in <module>
                run()
            """
        let s = Signals.structure(text)
        #expect(s.stackTrace)
        #expect(s.vetoes)
    }

    @Test("A JS-style `at file:line` stack trace vetoes")
    func atFrameStackVetoes() {
        let text = """
            at Object.<anonymous> (/app/index.js:12:5)
            at Module._compile (node:internal/modules:1:1)
            """
        #expect(Signals.structure(text).stackTrace)
    }

    @Test("A real shell command is not vetoed")
    func shellCommandNotVetoed() {
        let s = Signals.structure("git commit -m 'wip'\nnpm run build")
        #expect(!s.vetoes)
        #expect(s.risk < 0.5)
    }

    @Test("One list item among commands is not dominant")
    func lonelyListItemNotDominant() {
        #expect(!Signals.structure("git status\n- a stray dash").markdownDominant)
    }

    @Test("A box-drawing table vetoes (§11 borked-table regression)")
    func boxTableVetoes() {
        let text = """
            ┌────────┬──────────────────────────────────────┐
            │ Job ID │ 612e7dd2-cf2f-4d78-83e1-18b6f0b1edf2 │
            ├────────┼──────────────────────────────────────┤
            │ URL    │ https://www.tidio.com/               │
            └────────┴──────────────────────────────────────┘
            """
        let s = Signals.structure(text)
        #expect(s.tabular)
        #expect(s.vetoes)
        #expect(s.risk >= 0.5)
    }

    @Test("A lone box-drawing glyph is not tabular (needs ≥2 rows to smush)")
    func loneBoxGlyphNotTabular() {
        // A single border line can't be rejoined into anything (needs ≥2 same-width
        // lines), so one stray glyph must not trip the veto.
        #expect(!Signals.structure("echo ───\nrm -rf build").tabular)
    }

    // MARK: Integration with the RepairReport (§6.7)

    @Test("Report carries shell-signal score and structure risk")
    func reportCarriesSignals() {
        let report = Repair.repair("git push origin main").report
        #expect(report.shellSignalScore >= 0.5)
        #expect(report.structureRisk < 0.5)
    }

    @Test("Report flags prose as high structure risk")
    func reportFlagsProse() {
        let report = Repair.repair("This is a normal sentence. And another one.").report
        #expect(report.structureRisk >= 0.5)
    }
}
