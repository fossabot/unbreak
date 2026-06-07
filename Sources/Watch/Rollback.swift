import Foundation

/// The in-memory, single-slot rollback buffer for watch mode (PRD v2 §7.1).
///
/// Watch mode rewrites the clipboard in place, which would otherwise be
/// destructive: a misfire loses the user's original copy. `RollbackStore` keeps
/// the **one** most recent pre-mutation original so `unbreak undo` can put it back.
/// It is deliberately tiny and dumb — one slot, no persistence, no history:
///
///  - `record(_:)` stashes the original *before* a mutation overwrites it.
///  - `clear()` drops the slot when a copy goes by that we did **not** mutate —
///    that copy is now the clipboard's truth, so the older original is no longer
///    the thing an undo should restore ("cleared on next user copy", §7.1).
///  - `take()` hands the original back for an undo and empties the slot, so a
///    second `undo` in a row reports "nothing to undo" rather than re-restoring.
///
/// The slot lives only in the daemon's memory, so a daemon restart clears it for
/// free (§7.1: "not persistent"). Pure: no clipboard, no socket — unit-testable
/// in isolation.
///
/// `@unchecked Sendable`: the store is confined to the daemon's main run loop —
/// both the poll/mutate path (`WatchSession.handle`, on the poll timer) and the
/// undo path (the `DispatchSource` read source, on the `.main` queue) touch it
/// only from the main thread. There is no concurrent access.
public final class RollbackStore: @unchecked Sendable {
    private var slot: String?

    public init() {}

    /// Stash the original clipboard text about to be overwritten by a mutation.
    /// Overwrites any previous slot — only the most recent mutation is undoable.
    public func record(_ original: String) {
        slot = original
    }

    /// Drop the slot. Called when a copy the watcher did *not* mutate goes by, so
    /// a stale original can never be restored over newer clipboard content (§7.1).
    public func clear() {
        slot = nil
    }

    /// Hand back the stored original for an undo and empty the slot, or `nil` if
    /// there is nothing to undo.
    public func take() -> String? {
        defer { slot = nil }
        return slot
    }

    /// Whether an original is currently held (for tests/diagnostics).
    public var hasValue: Bool { slot != nil }
}

/// Maps a decoded undo request to a response over a `RollbackStore` and an
/// injected restore action (PRD v2 §7.1).
///
/// This is the seam between the wire protocol and the actual clipboard write. The
/// restore **must** be performed by the daemon (through its own `Clipboard`, via
/// the injected closure) rather than by the `unbreak undo` process: the daemon's
/// self-write suppression (`Clipboard.isSelfWrite` / `Watcher.poll`) would treat
/// an undo-process write as a fresh external copy and immediately re-repair it,
/// reverting the undo. Routing the write back through the daemon records it as a
/// self-write, so the restored original survives.
///
/// Pure over its injected dependencies — no socket, no real clipboard — so the
/// restored/empty branching is unit-testable on its own.
public struct RollbackService: Sendable {
    private let store: RollbackStore
    private let restore: @Sendable (String) -> Void

    /// - Parameters:
    ///   - store: the single-slot buffer to undo from.
    ///   - restore: writes the recovered original back to the clipboard. In the
    ///     daemon this routes through the watcher so the write is self-write
    ///     suppressed and not re-repaired.
    public init(store: RollbackStore, restore: @escaping @Sendable (String) -> Void) {
        self.store = store
        self.restore = restore
    }

    /// Handle one decoded request: restore the buffered original if there is one,
    /// else report the buffer empty. Never errors — protocol/transport failures
    /// are surfaced as `.error` by the codec/server layer, not here.
    public func handle(_ request: UndoRequest) -> UndoResponse {
        switch request.command {
        case .undo:
            guard let original = store.take() else {
                return UndoResponse(status: .empty)
            }
            restore(original)
            return UndoResponse(status: .restored)
        }
    }
}
