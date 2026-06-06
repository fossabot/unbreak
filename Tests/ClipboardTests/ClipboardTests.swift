import Testing

@testable import Clipboard

#if canImport(AppKit)
import AppKit
#endif

/// In-memory `PasteboardBackend` for testing the `Clipboard` facade without a
/// real `NSPasteboard`.
final class FakePasteboard: PasteboardBackend {
    var changeCount = 0
    var string: String?
    /// Toggle to simulate a rich/file/image item we must leave untouched.
    var plainTextAvailable = true

    func plainText() -> String? { plainTextAvailable ? string : nil }
    func hasPlainText() -> Bool { plainTextAvailable }

    @discardableResult
    func writePlainText(_ string: String) -> Int {
        self.string = string
        plainTextAvailable = true
        changeCount += 1
        return changeCount
    }
}

@Suite("Clipboard facade (PRD v2 §7.4)")
struct ClipboardFacadeTests {
    @Test("Reads the plain-text payload through the backend")
    func reads() {
        let fake = FakePasteboard()
        fake.string = "hello"
        let clip = Clipboard(backend: fake)
        #expect(clip.plainText() == "hello")
        #expect(clip.hasPlainText())
    }

    @Test("Non-plain-text item is reported as such and reads nil")
    func nonPlainText() {
        let fake = FakePasteboard()
        fake.string = "ignored"
        fake.plainTextAvailable = false
        let clip = Clipboard(backend: fake)
        #expect(!clip.hasPlainText())
        #expect(clip.plainText() == nil)
    }

    @Test("write records the resulting changeCount as a self-write")
    func recordsSelfWrite() {
        let fake = FakePasteboard()
        fake.changeCount = 7
        let clip = Clipboard(backend: fake)
        #expect(clip.lastSelfWriteChangeCount == nil)

        clip.write("fixed")
        #expect(clip.changeCount == 8)
        #expect(clip.lastSelfWriteChangeCount == 8)
        #expect(clip.isSelfWrite(8))
        #expect(!clip.isSelfWrite(9))
    }

    @Test("A later external change is not mistaken for our self-write")
    func externalAfterSelfWrite() {
        let fake = FakePasteboard()
        let clip = Clipboard(backend: fake)
        clip.write("ours")  // changeCount -> 1, recorded
        fake.changeCount += 1  // simulate a user copy -> 2
        #expect(!clip.isSelfWrite(fake.changeCount))
    }
}

#if canImport(AppKit)
@Suite("SystemPasteboard rich-content guard (PRD v2 §7.2)")
struct SystemPasteboardTests {
    /// A private, uniquely-named pasteboard per test, so tests never touch the
    /// user's real clipboard and never race each other (swift-testing runs tests
    /// in parallel — a shared named pasteboard corrupts under concurrent writes).
    private func scratch(_ name: String) -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("net.tidio.ccfix.tests.\(name)"))
        pb.clearContents()
        return pb
    }

    @Test("Plain-text item is readable and writable")
    func plainText() {
        let pb = scratch("plain")
        pb.declareTypes([.string], owner: nil)
        pb.setString("git status", forType: .string)
        let sys = SystemPasteboard(pb)
        #expect(sys.hasPlainText())
        #expect(sys.plainText() == "git status")
    }

    @Test("A file-URL item is left untouched (not treated as plain text)")
    func fileItemProtected() {
        let pb = scratch("file")
        pb.declareTypes([.fileURL, .string], owner: nil)
        pb.setString("file:///tmp/x", forType: .fileURL)
        pb.setString("/tmp/x", forType: .string)
        let sys = SystemPasteboard(pb)
        #expect(!sys.hasPlainText())
        #expect(sys.plainText() == nil)
    }

    @Test("An RTF (rich) item is left untouched even with a string rep")
    func richItemProtected() {
        let pb = scratch("rtf")
        pb.declareTypes([.rtf, .string], owner: nil)
        pb.setData(Data("{\\rtf1}".utf8), forType: .rtf)
        pb.setString("plain fallback", forType: .string)
        let sys = SystemPasteboard(pb)
        #expect(!sys.hasPlainText())
    }

    @Test("writePlainText advances changeCount and round-trips")
    func writeRoundTrips() {
        let pb = scratch("write")
        let sys = SystemPasteboard(pb)
        let before = sys.changeCount
        let after = sys.writePlainText("echo hi")
        #expect(after > before)
        #expect(after == sys.changeCount)
        #expect(sys.plainText() == "echo hi")
    }
}
#endif
