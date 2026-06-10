import Foundation

/// Locates and loads the on-disk fixture corpus bundled with this test target
/// (`Fixtures/` is copied verbatim via `resources: [.copy(...)]` in Package.swift).
///
/// Keeping fixtures as real files — not string literals — means a capture pasted
/// from a terminal lands byte-for-byte in the corpus, control bytes and all
/// (ANSI/OSC/tabs survive a text editor where a Swift string literal would not).
enum FixtureLoader {
    /// Root of the copied `Fixtures/` resource directory.
    static var root: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures", isDirectory: true)
    }

    /// One loaded fixture: its corpus-relative name and decoded UTF-8 contents.
    struct Fixture {
        let name: String
        let text: String
    }

    /// Every file directly under `Fixtures/<subdir>`, sorted by name for a stable
    /// test order. Decoded as UTF-8 (the only representation the watcher ever acts
    /// on — §7.2).
    static func load(_ subdir: String) -> [Fixture] {
        let dir = root.appendingPathComponent(subdir, isDirectory: true)
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            )) ?? []
        return
            urls
            .filter { !$0.hasDirectoryPath }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                    let text = String(data: data, encoding: .utf8)
                else { return nil }
                return Fixture(name: url.lastPathComponent, text: text)
            }
    }

    /// A golden repair pair under `Fixtures/repair/<tool>`: the raw mangled capture
    /// (`<case>.in`) and its expected repaired form (`<case>.expected`).
    struct GoldenPair {
        let caseName: String
        let input: String
        let expected: String
    }

    static func goldenPairs(tool: String) -> [GoldenPair] {
        pairs(
            in:
                root
                .appendingPathComponent("repair", isDirectory: true)
                .appendingPathComponent(tool, isDirectory: true)
        )
    }

    /// Known-gap pairs under `Fixtures/known-issues/`: a real capture (`<case>.in`)
    /// and the form repair *should* produce once the linked CLAU issue is fixed
    /// (`<case>.expected`). Asserted inside `withKnownIssue` so CI stays green today
    /// and fails loudly the moment a gap is fixed (prompting the wrapper's removal).
    static func knownIssues() -> [GoldenPair] {
        pairs(in: root.appendingPathComponent("known-issues", isDirectory: true))
    }

    /// Load every `<case>.in` / `<case>.expected` pair directly under `dir`.
    private static func pairs(in dir: URL) -> [GoldenPair] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            )) ?? []
        return
            urls
            .filter { $0.pathExtension == "in" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { inURL in
                let expectedURL = inURL.deletingPathExtension().appendingPathExtension("expected")
                guard let input = try? String(contentsOf: inURL, encoding: .utf8),
                    let expected = try? String(contentsOf: expectedURL, encoding: .utf8)
                else { return nil }
                return GoldenPair(
                    caseName: inURL.deletingPathExtension().lastPathComponent,
                    input: input,
                    expected: expected
                )
            }
    }
}
