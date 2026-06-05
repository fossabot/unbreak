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

    @Test("Emoji-ZWJ sequence counts as a single wide cluster (§6.1, §13)")
    func emojiZWJ() {
        // Family: man + ZWJ + woman + ZWJ + girl + ZWJ + boy — one glyph, 2 cells.
        #expect(DisplayWidth.width(of: "👨‍👩‍👧‍👦") == 2)
    }

    @Test("Regional-indicator flag counts as a single wide cluster (§6.1, §13)")
    func flag() {
        #expect(DisplayWidth.width(of: "🇯🇵") == 2)
    }

    @Test("Emoji + variation selector (VS16) counts as wide (§6.1, §13)")
    func emojiVariationSelector() {
        // U+2764 (heart, default text presentation) + U+FE0F → 2-cell emoji.
        #expect(DisplayWidth.width(of: "\u{2764}\u{FE0F}") == 2)
    }

    @Test("Width sums correctly across a mixed CJK + emoji-ZWJ string")
    func mixedClusters() {
        // "你" (2) + space (1) + family (2) + "x" (1) = 6.
        #expect(DisplayWidth.width(of: "你 👨‍👩‍👧‍👦x") == 6)
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
