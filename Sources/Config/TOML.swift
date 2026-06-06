import Foundation

/// A scalar or array value read from a config file.
public enum TOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case array([TOMLValue])
}

/// A deliberately small TOML reader covering exactly the slice `ccfix`'s config
/// schema needs (PRD v2 §8.3): `# comments`, `[table]` headers, and one
/// `key = value` per line where a value is a string, integer, float, boolean, or
/// a single-line array of those. It is **not** a general TOML implementation —
/// no multi-line strings/arrays, dotted keys, inline tables, or datetimes.
///
/// Keys are returned flattened: a top-level `key` stays `key`; a `key` under
/// `[thresholds]` becomes `thresholds.key`. This keeps the loader a flat lookup.
public enum TOML {
    public enum ParseError: Error, Equatable {
        /// Line numbers are 1-based, for a message the user can act on.
        case syntax(line: Int, message: String)
    }

    /// Parse `text` into a flat `[dotted-key: value]` map. Throws on the first
    /// malformed line.
    public static func parse(_ text: String) throws -> [String: TOMLValue] {
        var result: [String: TOMLValue] = [:]
        var section = ""  // current table prefix ("" = top level)

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[") {
                section = try parseSectionHeader(line, lineNumber: lineNumber)
                continue
            }

            let (key, value) = try parseKeyValue(line, lineNumber: lineNumber)
            let fullKey = section.isEmpty ? key : "\(section).\(key)"
            result[fullKey] = value
        }
        return result
    }

    // MARK: - Line parsing

    /// Drop an inline `#` comment, respecting `#` characters inside a quoted
    /// string so a bundle id or path with a `#` survives.
    private static func stripComment(_ line: String) -> String {
        var inString = false
        var escaped = false
        var result = ""
        for char in line {
            if escaped {
                result.append(char)
                escaped = false
                continue
            }
            switch char {
            case "\\" where inString:
                escaped = true
                result.append(char)
            case "\"":
                inString.toggle()
                result.append(char)
            case "#" where !inString:
                return result
            default:
                result.append(char)
            }
        }
        return result
    }

    private static func parseSectionHeader(_ line: String, lineNumber: Int) throws -> String {
        guard line.hasSuffix("]") else {
            throw ParseError.syntax(line: lineNumber, message: "unterminated table header")
        }
        let name = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            throw ParseError.syntax(line: lineNumber, message: "empty table header")
        }
        return name
    }

    private static func parseKeyValue(_ line: String, lineNumber: Int) throws -> (
        String, TOMLValue
    ) {
        guard let equals = line.firstIndex(of: "=") else {
            throw ParseError.syntax(line: lineNumber, message: "expected 'key = value'")
        }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let rawValue = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            throw ParseError.syntax(line: lineNumber, message: "missing key before '='")
        }
        return (key, try parseValue(rawValue, lineNumber: lineNumber))
    }

    // MARK: - Value parsing

    private static func parseValue(_ raw: String, lineNumber: Int) throws -> TOMLValue {
        guard !raw.isEmpty else {
            throw ParseError.syntax(line: lineNumber, message: "missing value after '='")
        }
        if raw.hasPrefix("[") { return try parseArray(raw, lineNumber: lineNumber) }
        if raw.hasPrefix("\"") { return .string(try parseString(raw, lineNumber: lineNumber)) }
        if raw == "true" { return .boolean(true) }
        if raw == "false" { return .boolean(false) }

        // A numeric literal: integers may use `_` group separators (TOML), floats
        // carry a `.` or exponent.
        let digits = raw.replacingOccurrences(of: "_", with: "")
        if digits.contains(".") || digits.contains("e") || digits.contains("E") {
            guard let value = Double(digits) else {
                throw ParseError.syntax(line: lineNumber, message: "invalid float '\(raw)'")
            }
            return .double(value)
        }
        guard let value = Int(digits) else {
            throw ParseError.syntax(line: lineNumber, message: "unrecognized value '\(raw)'")
        }
        return .integer(value)
    }

    private static func parseString(_ raw: String, lineNumber: Int) throws -> String {
        guard raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") else {
            throw ParseError.syntax(line: lineNumber, message: "unterminated string \(raw)")
        }
        let body = raw.dropFirst().dropLast()
        var result = ""
        var escaped = false
        for char in body {
            if escaped {
                switch char {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                default: result.append(char)
                }
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else {
                result.append(char)
            }
        }
        if escaped {
            throw ParseError.syntax(line: lineNumber, message: "dangling escape in string")
        }
        return result
    }

    private static func parseArray(_ raw: String, lineNumber: Int) throws -> TOMLValue {
        guard raw.hasSuffix("]") else {
            throw ParseError.syntax(line: lineNumber, message: "unterminated array")
        }
        let body = raw.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        if body.isEmpty { return .array([]) }
        let elements = try splitTopLevel(String(body), lineNumber: lineNumber)
        return .array(try elements.map { try parseValue($0, lineNumber: lineNumber) })
    }

    /// Split an array body on commas that are not inside a quoted string, so
    /// `"a,b", "c"` yields two elements rather than three.
    private static func splitTopLevel(_ body: String, lineNumber: Int) throws -> [String] {
        var elements: [String] = []
        var current = ""
        var inString = false
        var escaped = false
        for char in body {
            if escaped {
                current.append(char)
                escaped = false
                continue
            }
            switch char {
            case "\\" where inString:
                escaped = true
                current.append(char)
            case "\"":
                inString.toggle()
                current.append(char)
            case "," where !inString:
                elements.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default:
                current.append(char)
            }
        }
        if inString {
            throw ParseError.syntax(line: lineNumber, message: "unterminated string in array")
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        // A trailing comma leaves an empty tail; TOML allows it, so drop it.
        if !last.isEmpty { elements.append(last) }
        return elements
    }
}
