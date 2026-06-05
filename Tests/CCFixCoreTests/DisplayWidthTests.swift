import Testing
@testable import CCFixCore

@Suite("Display-cell width (PRD v2 §6.1, §13)")
struct DisplayWidthTests {
    @Test("ASCII counts one cell per character")
    func ascii() {
        #expect(DisplayWidth.width(of: "git status") == 10)
    }

    @Test("Wide CJK characters count two cells each")
    func cjk() {
        #expect(DisplayWidth.width(of: "你好") == 4)
    }

    @Test("Emoji counts as a wide character")
    func emoji() {
        #expect(DisplayWidth.width(of: "🚀") == 2)
    }

    @Test("Combining marks contribute zero width")
    func combiningMark() {
        // "e" + combining acute accent renders in one cell.
        #expect(DisplayWidth.width(of: "e\u{0301}") == 1)
    }

    @Test("Tabs expand to the next tab stop")
    func tabs() {
        #expect(DisplayWidth.width(of: "\t", tabWidth: 8) == 8)
        #expect(DisplayWidth.width(of: "ab\t", tabWidth: 8) == 8)
    }

    @Test("Leading whitespace width is display-aware")
    func leading() {
        #expect(DisplayWidth.leadingWidth(of: "    x", tabWidth: 8) == 4)
        #expect(DisplayWidth.leadingWidth(of: "\tx", tabWidth: 8) == 8)
    }
}
