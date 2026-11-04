import Foundation
import os

/// Values a skin makes once and draws many times (a blurred cover, a key's mask, a restyled
/// control), kept behind a lock: frames are laid out and drawn off the main thread, every window's
/// on the same skin. A value is made outside the lock, so a window drawing beside the one making it
/// waits only for a lookup, never for a blur; two that both miss both make it, and the first stored
/// is kept (as `AIMPSkinPixels` decodes). At most `limit` are kept, the oldest stored let go first.
final class AIMPSkinCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private let limit: Int
    private let stored = OSAllocatedUnfairLock(initialState: Stored())

    private struct Stored: Sendable {
        var values: [Key: Value] = [:]
        /// Keys in the order they were stored, the next to let go first.
        var order: [Key] = []
    }

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// The value for `key`, as `make` makes it, made once while it is kept.
    func value(_ key: Key, making make: () -> Value) -> Value {
        if let found = stored.withLock({ $0.values[key] }) { return found }
        let made = make()
        return stored.withLock { [limit] stored in
            if let found = stored.values[key] { return found }
            stored.values[key] = made
            stored.order.append(key)
            if stored.order.count > limit { stored.values[stored.order.removeFirst()] = nil }
            return made
        }
    }

    /// How many values are kept.
    var count: Int { stored.withLock { $0.values.count } }
}
