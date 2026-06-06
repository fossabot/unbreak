import Testing

@testable import Watch

@Suite("Rollback buffer + service (PRD v2 §7.1)")
struct RollbackTests {
    @Test("record then take returns the original and empties the slot")
    func recordTake() {
        let store = RollbackStore()
        #expect(store.hasValue == false)

        store.record("original text")
        #expect(store.hasValue == true)
        #expect(store.take() == "original text")
        // The slot is single-use: a second take finds nothing.
        #expect(store.hasValue == false)
        #expect(store.take() == nil)
    }

    @Test("record overwrites — only the most recent original is undoable")
    func singleSlot() {
        let store = RollbackStore()
        store.record("first")
        store.record("second")
        #expect(store.take() == "second")
    }

    @Test("clear drops the slot (cleared on next user copy)")
    func clear() {
        let store = RollbackStore()
        store.record("original")
        store.clear()
        #expect(store.hasValue == false)
        #expect(store.take() == nil)
    }

    @Test("service restores the buffered original and reports restored")
    func serviceRestores() {
        let store = RollbackStore()
        store.record("the original")
        let restored = Box<[String]>([])
        let service = RollbackService(store: store, restore: { restored.value.append($0) })

        let response = service.handle(UndoRequest())

        #expect(response.status == .restored)
        #expect(restored.value == ["the original"])
        // The slot was consumed — a second undo finds nothing.
        #expect(store.hasValue == false)
    }

    @Test("service reports empty and never restores when the buffer is empty")
    func serviceEmpty() {
        let store = RollbackStore()
        let restoreCalls = Box(0)
        let service = RollbackService(store: store, restore: { _ in restoreCalls.value += 1 })

        let response = service.handle(UndoRequest())

        #expect(response.status == .empty)
        #expect(restoreCalls.value == 0)
    }
}
