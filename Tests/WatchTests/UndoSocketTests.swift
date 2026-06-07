import Foundation
import Testing

@testable import Watch

@Suite("Undo socket integration (real UDS, PRD v2 §7.1)")
struct UndoSocketTests {
    /// A unique socket path inside a dedicated temp subdirectory — short enough to
    /// stay under the 104-byte `sun_path` limit, and a directory the server may
    /// safely chmod to 0700 (mirroring production's owned `unbreak/` dir, rather than
    /// the shared `$TMPDIR` itself).
    private func tempSocketURL() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "unbreak-undo-\(UInt32.random(in: 0..<UInt32.max))",
                isDirectory: true
            )
        return dir.appendingPathComponent("u.sock")
    }

    @Test("end-to-end: client undo over a real socket restores via the daemon")
    func endToEndRestore() throws {
        let url = tempSocketURL()
        let store = RollbackStore()
        store.record("before the fix")
        let restored = Box<[String]>([])
        let socketServer = UndoSocketServer(
            socketURL: url,
            server: UndoServer(
                service: RollbackService(store: store, restore: { restored.value.append($0) })
            )
        )
        try socketServer.start()
        defer { socketServer.stop() }

        // The server accepts on the main queue; the client call blocks this thread,
        // so the round-trip is driven from a background thread while the main run
        // loop services the accept.
        let outcome = runClientOffMain { UndoClient(socketURL: url).requestUndo() }

        #expect(outcome == .restored)
        #expect(restored.value == ["before the fix"])
    }

    @Test("end-to-end: empty buffer reports empty")
    func endToEndEmpty() throws {
        let url = tempSocketURL()
        let socketServer = UndoSocketServer(
            socketURL: url,
            server: UndoServer(service: RollbackService(store: RollbackStore(), restore: { _ in }))
        )
        try socketServer.start()
        defer { socketServer.stop() }

        let outcome = runClientOffMain { UndoClient(socketURL: url).requestUndo() }

        #expect(outcome == .empty)
    }

    @Test("no server listening → noDaemon")
    func noDaemon() {
        let outcome = UndoClient(socketURL: tempSocketURL()).requestUndo()
        #expect(outcome == .noDaemon)
    }

    /// Run `body` on a background queue and pump the main run loop until it returns,
    /// so the server's `.main`-queue accept handler gets a chance to run.
    private func runClientOffMain(_ body: @escaping @Sendable () -> UndoOutcome) -> UndoOutcome {
        let result = Box<UndoOutcome?>(nil)
        DispatchQueue.global().async {
            result.value = body()
        }
        let deadline = Date().addingTimeInterval(5)
        while result.value == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return result.value ?? .error("timed out")
    }
}
