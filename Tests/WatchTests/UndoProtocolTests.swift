import Foundation
import Testing

@testable import Watch

/// An in-memory `UndoConnection` for driving `UndoServer.serve` without a socket.
private final class FakeConnection: UndoConnection {
    private let request: Data
    private(set) var written = Data()
    private(set) var closed = false

    init(request: Data) {
        self.request = request
    }

    func readFrame(maxBytes: Int) -> Data {
        Data(request.prefix(maxBytes))
    }

    func writeFrame(_ data: Data) {
        written.append(data)
    }

    func close() {
        closed = true
    }
}

@Suite("Undo wire protocol + server (PRD v2 §7.1)")
struct UndoProtocolTests {
    @Test("request round-trips through the codec")
    func requestRoundTrip() throws {
        let frame = try UndoProtocol.encode(UndoRequest())
        // Newline-delimited: exactly one trailing newline, within the size cap.
        #expect(frame.last == UndoProtocol.newline)
        #expect(frame.count <= UndoProtocol.maxFrameBytes)
        let decoded = try UndoProtocol.decode(UndoRequest.self, from: frame)
        #expect(decoded == UndoRequest(command: .undo))
    }

    @Test("response round-trips for every status")
    func responseRoundTrip() throws {
        for status in [UndoResponse.Status.restored, .empty, .error] {
            let frame = try UndoProtocol.encode(UndoResponse(status: status))
            let decoded = try UndoProtocol.decode(UndoResponse.self, from: frame)
            #expect(decoded.status == status)
        }
    }

    @Test("decode tolerates a missing trailing newline")
    func decodeNoNewline() throws {
        let raw = Data(#"{"command":"undo"}"#.utf8)
        let decoded = try UndoProtocol.decode(UndoRequest.self, from: raw)
        #expect(decoded.command == .undo)
    }

    @Test("decode rejects an empty frame")
    func decodeEmpty() {
        #expect(throws: UndoProtocol.CodecError.emptyFrame) {
            _ = try UndoProtocol.decode(UndoRequest.self, from: Data("\n".utf8))
        }
    }

    @Test("decode rejects an unknown command")
    func decodeUnknownCommand() {
        let raw = Data(#"{"command":"nuke"}"#.utf8)
        #expect(throws: UndoProtocol.CodecError.malformed) {
            _ = try UndoProtocol.decode(UndoRequest.self, from: raw)
        }
    }

    @Test("no clipboard content ever crosses the wire")
    func contentFree() throws {
        // The request/response types carry no text field by construction; assert the
        // encoded bytes never include arbitrary payload, only the fixed vocabulary.
        let request = try UndoProtocol.encode(UndoRequest())
        let text = String(bytes: request, encoding: .utf8) ?? ""
        #expect(text.contains("command"))
        #expect(text.contains("undo"))
        #expect(!text.contains("clipboard"))
    }

    @Test("server restores via the service and replies restored")
    func serverRestores() throws {
        let store = RollbackStore()
        store.record("recovered")
        let server = UndoServer(
            service: RollbackService(store: store, restore: { _ in })
        )
        let connection = FakeConnection(request: try UndoProtocol.encode(UndoRequest()))

        server.serve(connection)

        let response = try UndoProtocol.decode(UndoResponse.self, from: connection.written)
        #expect(response.status == .restored)
        #expect(connection.closed)
    }

    @Test("server replies empty when the buffer holds nothing")
    func serverEmpty() throws {
        let server = UndoServer(
            service: RollbackService(store: RollbackStore(), restore: { _ in })
        )
        let connection = FakeConnection(request: try UndoProtocol.encode(UndoRequest()))

        server.serve(connection)

        let response = try UndoProtocol.decode(UndoResponse.self, from: connection.written)
        #expect(response.status == .empty)
    }

    @Test("server replies error for a malformed request frame")
    func serverMalformed() throws {
        let server = UndoServer(
            service: RollbackService(store: RollbackStore(), restore: { _ in })
        )
        let connection = FakeConnection(request: Data("garbage\n".utf8))

        server.serve(connection)

        let response = try UndoProtocol.decode(UndoResponse.self, from: connection.written)
        #expect(response.status == .error)
    }
}
