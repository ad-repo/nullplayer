import Foundation

/// The one skin load a window runs at a time: starting one cancels the one before, and a cancelled
/// load never finishes.
final class SkinLoadTask {
    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }

    func run<Value>(_ work: @escaping () async throws -> Value, done: @escaping @MainActor (Value) -> Void,
                    failed: @escaping @MainActor (Error) -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            do {
                let value = try await work()
                try Task.checkCancellation()
                done(value)
            } catch is CancellationError {
                return
            } catch {
                failed(error)
            }
        }
    }
}
