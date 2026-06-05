import Foundation

/// Terminal display-cell width (PRD v2 §6.1).
///
/// This is the single source of truth for gutter math (§6.2) and wrap detection
/// (§6.3). `String.count`, UTF-16 count, and byte count all differ from what a
/// terminal actually renders, so the repair pipeline must never use them for
/// column comparisons.
///
/// TODO(§6.1): grapheme-cluster awareness for emoji-ZWJ sequences and full
/// East-Asian-Width tables; this is a conservative first pass.
public enum DisplayWidth {
    public static let defaultTabWidth = 8

    /// Width of a single scalar in terminal cells (0 for combining/zero-width,
    /// 2 for wide CJK/emoji, 1 otherwise).
    static func width(of scalar: Unicode.Scalar) -> Int {
        switch scalar.value {
        case 0x0300...0x036F, // combining diacritical marks
             0x200B...0x200F, // zero-width space / joiners / marks
             0xFE00...0xFE0F, // variation selectors
             0xFEFF:          // zero-width no-break space / BOM
            return 0
        default:
            break
        }
        if scalar.properties.generalCategory == .nonspacingMark { return 0 }
        return isWide(scalar) ? 2 : 1
    }

    static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,    // Hangul Jamo
             0x2E80...0xA4CF,    // CJK radicals … Yi
             0xAC00...0xD7A3,    // Hangul syllables
             0xF900...0xFAFF,    // CJK compatibility ideographs
             0xFE30...0xFE4F,    // CJK compatibility forms
             0xFF00...0xFF60,    // fullwidth forms
             0xFFE0...0xFFE6,    // fullwidth signs
             0x1F300...0x1FAFF,  // emoji & pictographs
             0x20000...0x3FFFD:  // CJK extension B+
            return true
        default:
            return false
        }
    }

    /// Display width of a substring, expanding tabs to the next tab stop.
    public static func width(of string: Substring, tabWidth: Int = defaultTabWidth) -> Int {
        var col = 0
        for scalar in string.unicodeScalars {
            if scalar == "\t" {
                col += tabWidth - (col % tabWidth)
            } else {
                col += width(of: scalar)
            }
        }
        return col
    }

    public static func width(of string: String, tabWidth: Int = defaultTabWidth) -> Int {
        width(of: string[...], tabWidth: tabWidth)
    }

    /// Display width of the leading whitespace (spaces and tabs) of a line.
    public static func leadingWidth(of line: String, tabWidth: Int = defaultTabWidth) -> Int {
        var col = 0
        for ch in line {
            if ch == " " {
                col += 1
            } else if ch == "\t" {
                col += tabWidth - (col % tabWidth)
            } else {
                break
            }
        }
        return col
    }
}
