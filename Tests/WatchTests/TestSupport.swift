/// A mutable reference cell so a `@Sendable` closure can record what it was handed
/// (a plain `var` can't be captured mutably by a `@Sendable` closure). Shared
/// across the watch-mode test suites.
final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
