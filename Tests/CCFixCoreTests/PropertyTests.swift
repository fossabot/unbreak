import Testing
@testable import CCFixCore

/// Lightweight property tests (PRD v2 §6.8, §13) — no external dependency, to
/// keep the build self-contained. A seeded generator makes failures reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Repair properties (PRD v2 §6.8)")
struct PropertyTests {
    private func randomCleanFragment(_ rng: inout SeededGenerator) -> String {
        // Short tokens joined by single spaces / newlines — no wrap artifacts,
        // so a correct repair must leave them untouched.
        let tokens = ["git", "ls", "-la", "cd", "src", "make", "test", "echo", "ok", "&&"]
        let count = Int.random(in: 1...6, using: &rng)
        let words = (0..<count).map { _ in tokens.randomElement(using: &rng)! }
        let sep = Bool.random(using: &rng) ? " " : "\n"
        return words.joined(separator: sep)
    }

    @Test("Clean input is returned unchanged", arguments: 0..<200)
    func cleanInputUnchanged(seed: Int) {
        var rng = SeededGenerator(seed: UInt64(seed))
        let input = randomCleanFragment(&rng)
        #expect(Repair.repair(input).text == input)
    }

    @Test("Repair is idempotent", arguments: 0..<200)
    func idempotent(seed: Int) {
        var rng = SeededGenerator(seed: UInt64(seed) &+ 1000)
        let input = randomCleanFragment(&rng)
        let once = Repair.repair(input).text
        let twice = Repair.repair(once).text
        #expect(once == twice)
    }
}
