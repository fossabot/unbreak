import Foundation
import Testing

@testable import UnbreakCore

/// Repair gaps surfaced by the CLAU-vmpxtwus QA pass, locked as regression tests.
///
/// Each fixture under `Fixtures/known-issues/` pairs a real capture (`.in`) with the
/// form repair *should* produce once the linked issue is fixed (`.expected`). The
/// assertion runs inside `withKnownIssue`, so:
///   - today the suite stays **green** (the gap is an expected, recorded failure), and
///   - the day someone fixes the gap, `withKnownIssue` reports "known issue was not
///     recorded" and the test **fails** — a deliberate nudge to delete the wrapper
///     and promote it to a plain `#expect`.
///
/// See `docs/qa/CLAU-vmpxtwus-runthrough.md` for the full write-up.
@Suite("Known repair gaps — locked via withKnownIssue (CLAU-vmpxtwus)")
struct KnownIssueTests {
    /// fixture case name → the follow-up issue that tracks the fix.
    static let trackingIssue: [String: String] = [
        "F1-quotebar-overjoin-commands": "CLAU-jelhxutz",  // §6.2 reflow over-joins commands
        "F2-twoline-wrap": "CLAU-umzcppan",  // 2-line wraps never rejoin
        "F3-uneven-multiline-wrap": "CLAU-rtzoinwb",  // uneven-width wraps don't rejoin
        "F4-url-token-corruption": "CLAU-ajqigmcx",  // mid-token wrap → injected spaces
        "F5-table-smush": "CLAU-fplzfldz",  // one-shot smushes box-drawing tables
        "F6-degutter-flatten": "CLAU-vqcljzus",  // de-gutter flattens code indentation
    ]

    @Test("Every known gap has a tracking issue and a fixture pair")
    func corpusWired() {
        let names = Set(FixtureLoader.knownIssues().map(\.caseName))
        #expect(names == Set(Self.trackingIssue.keys), "known-issue corpus drifted from the issue map")
    }

    @Test(
        "Each known gap repairs to its desired form once fixed",
        arguments: FixtureLoader.knownIssues()
    )
    func knownGap(_ pair: FixtureLoader.GoldenPair) {
        let issue = Self.trackingIssue[pair.caseName] ?? "UNTRACKED"
        withKnownIssue("\(issue): repair gap (\(pair.caseName)) — promote to #expect when fixed") {
            #expect(Repair.repair(pair.input).text == pair.expected)
        }
    }
}
