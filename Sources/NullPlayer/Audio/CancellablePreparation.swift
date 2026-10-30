import Foundation

/// Main-queue ownership of one background operation. Reset is explicit at every caller;
/// a cancelled task may finish, but can no longer publish into the replacement slot.
final class CancellablePreparation<Payload> {
    private(set) var generation: UInt64 = 0
    private(set) var payload: Payload?
    private var task: Task<Void, Never>?

    func reset() {
        generation &+= 1
        task?.cancel()
        task = nil
        payload = nil
    }

    func start(_ payload: Payload, operation: (UInt64) -> Task<Void, Never>) {
        reset()
        self.payload = payload
        task = operation(generation)
    }

    func isCurrent(_ generation: UInt64) -> Bool { self.generation == generation }

    @discardableResult
    func update(_ change: (inout Payload) -> Void) -> Bool {
        guard var payload else { return false }
        change(&payload)
        self.payload = payload
        return true
    }

    func take(ifCurrent generation: UInt64) -> Payload? {
        guard isCurrent(generation) else { return nil }
        let value = payload
        payload = nil
        task = nil
        return value
    }

    deinit { task?.cancel() }
}
