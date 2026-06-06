import Testing

@testable import Config

@Suite("TOML subset reader (PRD v2 §8.3)")
struct TOMLTests {
    @Test("Parses scalars of each supported type")
    func scalars() throws {
        let table = try TOML.parse(
            """
            name = "claude-code"
            count = 1_024
            ratio = 0.5
            on = true
            off = false
            """
        )
        #expect(table["name"] == .string("claude-code"))
        #expect(table["count"] == .integer(1024))
        #expect(table["ratio"] == .double(0.5))
        #expect(table["on"] == .boolean(true))
        #expect(table["off"] == .boolean(false))
    }

    @Test("Parses a string array, ignoring a trailing comma")
    func stringArray() throws {
        let table = try TOML.parse(#"terminals = ["a", "b", "c",]"#)
        #expect(table["terminals"] == .array([.string("a"), .string("b"), .string("c")]))
    }

    @Test("Flattens keys under a table header")
    func tableHeader() throws {
        let table = try TOML.parse(
            """
            [thresholds]
            shell_signal_score = 0.5
            structure_risk = 0.7
            """
        )
        #expect(table["thresholds.shell_signal_score"] == .double(0.5))
        #expect(table["thresholds.structure_risk"] == .double(0.7))
    }

    @Test("Ignores blank lines and full-line comments")
    func commentsAndBlanks() throws {
        let table = try TOML.parse(
            """
            # a leading comment

            poll_interval_ms = 400  # an inline comment
            """
        )
        #expect(table == ["poll_interval_ms": .integer(400)])
    }

    @Test("A '#' inside a quoted string is not a comment")
    func hashInString() throws {
        let table = try TOML.parse(#"id = "com.acme.app#beta""#)
        #expect(table["id"] == .string("com.acme.app#beta"))
    }

    @Test("A comma inside a quoted array element does not split it")
    func commaInArrayString() throws {
        let table = try TOML.parse(#"xs = ["a,b", "c"]"#)
        #expect(table["xs"] == .array([.string("a,b"), .string("c")]))
    }

    @Test("Unescapes basic string escapes")
    func stringEscapes() throws {
        let table = try TOML.parse(#"s = "a\tb\nc\"d""#)
        #expect(table["s"] == .string("a\tb\nc\"d"))
    }

    @Test("A line without '=' is a syntax error with its line number")
    func missingEquals() {
        #expect(throws: TOML.ParseError.syntax(line: 2, message: "expected 'key = value'")) {
            try TOML.parse("ok = 1\ngarbage")
        }
    }

    @Test("An unterminated array is a syntax error")
    func unterminatedArray() {
        #expect(throws: (any Error).self) {
            try TOML.parse(#"xs = ["a", "b""#)
        }
    }
}
