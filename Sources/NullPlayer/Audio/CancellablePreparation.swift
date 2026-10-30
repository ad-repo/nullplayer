import Foundation

/// Main-queue ownership of one background operation. `start` runs the work detached and
/// publishes its result back on main; a reset or a newer `start` cancels it, and a cancelled
/// task that still finishes can no longer publish into the replacement slot.
// AudioEngine is a legacy, nonisolated main-queue owner, so this cannot be `@MainActor`.
// The preconditions enforce that contract; the detached work only captures what it is handed.
final class CancellablePreparation<Payload>: @unchecked Sendable {
    private var generation: UInt64 = 0
    private(set) var payload: Payload?
    private var task: Task<Void, Never>?

    func reset() {
        generation &+= 1
        task?.cancel()
        task = nil
        payload = nil
    }

    func start<Value>(_ payload: Payload, priority: TaskPriority,
                      work: @escaping @Sendable () async throws -> Value,
                      publish: @escaping (Payload, Result<Value, Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        reset()
        self.payload = payload
        let generation = generation
        task = Task.detached(priority: priority) { [weak self] in
            let result: Result<Value, Error>
            do {
                let value = try await work()
                try Task.checkCancellation()
                result = .success(value)
            } catch is CancellationError {
                return
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { [weak self] in
                guard let payload = self?.take(ifCurrent: generation) else { return }
                publish(payload, result)
            }
        }
    }

    @discardableResult
    func update(_ change: (inout Payload) -> Void) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard var payload else { return false }
        change(&payload)
        self.payload = payload
        return true
    }

    private func take(ifCurrent generation: UInt64) -> Payload? {
        guard self.generation == generation else { return nil }
        let value = payload
        payload = nil
        task = nil
        return value
    }

    deinit { task?.cancel() }
}
