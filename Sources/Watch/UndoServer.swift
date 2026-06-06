import Foundation

/// One accepted, one-shot undo connection: read the request frame, write the
/// response frame, then it is closed (PRD v2 §7.1).
///
/// Abstracting the accepted stream behind this protocol keeps the server's
/// frame-handling logic (`UndoServer.serve`) testable with an in-memory pair,
/// while the production transport (`FileDescriptorConnection`) wraps a real
/// socket file descriptor.
public protocol UndoConnection {
    /// Read one request frame: bytes up to and including the first newline, or
    /// until EOF / `maxBytes`, whichever comes first.
    func readFrame(maxBytes: Int) -> Data
    /// Write the full response frame.
    func writeFrame(_ data: Data)
    /// Close the connection (idempotent).
    func close()
}

/// The protocol-level undo server: turns a request frame into a response frame
/// over an injected `RollbackService` (PRD v2 §7.1).
///
/// Pure with respect to I/O — it never touches a socket — so the full
/// request→service→response path, including malformed/oversized frames mapping to
/// a `.error` status, is unit-testable against fake connections.
public struct UndoServer: Sendable {
    private let service: RollbackService

    public init(service: RollbackService) {
        self.service = service
    }

    /// Decode a request frame, run it through the rollback service, and encode the
    /// response. A frame that does not decode into a valid `UndoRequest` yields a
    /// `.error` response rather than throwing — the client always gets an answer.
    public func respond(to frame: Data) -> Data {
        let response: UndoResponse
        if let request = try? UndoProtocol.decode(UndoRequest.self, from: frame) {
            response = service.handle(request)
        } else {
            response = UndoResponse(status: .error)
        }
        // Encoding a fixed two-field struct cannot exceed the frame cap; fall back
        // to a hand-written minimal error frame rather than crashing if it ever does.
        return (try? UndoProtocol.encode(response)) ?? Data("{\"status\":\"error\"}\n".utf8)
    }

    /// Service one accepted connection end-to-end: read the request, respond, and
    /// close. The single entry point the socket server drives per connection.
    public func serve(_ connection: UndoConnection) {
        let frame = connection.readFrame(maxBytes: UndoProtocol.maxFrameBytes)
        connection.writeFrame(respond(to: frame))
        connection.close()
    }
}
