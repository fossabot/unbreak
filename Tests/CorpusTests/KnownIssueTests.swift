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

    /// Fixtures whose gap has been **fixed**: they assert with a plain `#expect`
    /// (a permanent regression lock) instead of `withKnownIssue`. A case moves here
    /// from the open set the moment its fix lands. The fixture pair stays put under
    /// `Fixtures/known-issues/` so `corpusWired` keeps covering the whole corpus.
    static let fixed: Set<String> = [
        "F2-twoline-wrap",  // CLAU-umzcppan: two-line wraps rejoin (tolerance-based detection)
        "F3-uneven-multiline-wrap",  // CLAU-rtzoinwb: uneven-width wraps rejoin (±2 band)
        "F4-url-token-corruption",  // CLAU-ajqigmcx: mid-token rejoin no longer injects spaces
        "F6-degutter-flatten",  // CLAU-vqcljzus: de-gutter preserves structural code indentation
    ]

    /// Still-open gaps — asserted inside `withKnownIssue` so CI stays green until the
    /// fix lands, then fails ("known issue was not recorded") to prompt promotion.
    static var open: [String: String] {
        trackingIssue.filter { !fixed.contains($0.key) }
    }

    @Test("Every known gap has a tracking issue and a fixture pair")
    func corpusWired() {
        let names = Set(FixtureLoader.knownIssues().map(\.caseName))
        #expect(
            names == Set(Self.trackingIssue.keys),
            "known-issue corpus drifted from the issue map"
        )
    }

    @Test(
        "Each open gap repairs to its desired form once fixed",
        arguments: FixtureLoader.knownIssues().filter { Self.open.keys.contains($0.caseName) }
    )
    func knownGap(_ pair: FixtureLoader.GoldenPair) {
        let issue = Self.trackingIssue[pair.caseName] ?? "UNTRACKED"
        withKnownIssue("\(issue): repair gap (\(pair.caseName)) — promote to #expect when fixed") {
            #expect(Repair.repair(pair.input).text == pair.expected)
        }
    }

    @Test(
        "Each fixed gap stays repaired (regression lock)",
        arguments: FixtureLoader.knownIssues().filter { Self.fixed.contains($0.caseName) }
    )
    func fixedGap(_ pair: FixtureLoader.GoldenPair) {
        #expect(Repair.repair(pair.input).text == pair.expected)
    }
}
