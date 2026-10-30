import AVFoundation

/// Only MPEG-4 inputs needing a full fallback decode are prepared early. Native formats
/// still open at the fade boundary. Refreshed by track/queue/option changes, never a timer.
// AudioEngine is a legacy, nonisolated main-queue owner. Runtime preconditions below
// enforce that every mutable access is on main; detached tasks only capture weak self
// to enqueue publication there. No mutable state is read by the worker itself.
final class LocalCrossfadePreparation: @unchecked Sendable {
    struct Boundary: Equatable {
        let current: UUID
        let next: UUID
    }

    private let slot = CancellablePreparation<Boundary>()
    private var boundary: Boundary?
    private var prepared: AVAudioFile?
    var preparedTrackID: UUID? {
        dispatchPrecondition(condition: .onQueue(.main))
        return prepared == nil ? nil : boundary?.next
    }

    func reset() {
        dispatchPrecondition(condition: .onQueue(.main))
        slot.reset()
        boundary = nil
        prepared = nil
    }

    func prepare(current: UUID, next: Track) {
        dispatchPrecondition(condition: .onQueue(.main))
        let nextBoundary = Boundary(current: current, next: next.id)
        guard boundary != nextBoundary else { return }
        reset()
        boundary = nextBoundary
        guard ["m4a", "mp4", "m4b"].contains(next.url.pathExtension.lowercased()) else { return }
        slot.start(nextBoundary) { generation in
            Task.detached(priority: .utility) { [weak self] in
                do {
                    // A native AAC/ALAC/Opus reader keeps the existing just-in-time fade path.
                    guard try LocalAudioFile.openNatively(next.url) == nil else { return }
                    try Task.checkCancellation()
                    let file = try await LocalAudioFile.prepareForPlayback(next.url)
                    try Task.checkCancellation()
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.slot.take(ifCurrent: generation) == nextBoundary else { return }
                        self.prepared = file
                        NSLog("Sweet Fades: Prepared next track: %@", next.title)
                    }
                } catch is CancellationError {
                    // The replacement boundary owns the fade now.
                } catch {
                    NSLog("Sweet Fades: Next track preparation failed: %@",
                          error.localizedDescription.redactingSensitiveURLQueryItems)
                }
            }
        }
    }

    func file(current: UUID?, next: UUID) -> AVAudioFile? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let current, boundary == Boundary(current: current, next: next) else { return nil }
        return prepared
    }

    /// Native formats retain their existing off-main, just-in-time open. At the boundary
    /// a fallback may only use an already prepared handle; it never begins a full decode.
    func openForFade(current: UUID, next: Track,
                     completion: @escaping (Result<AVAudioFile?, Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let prepared = file(current: current, next: next.id) {
            completion(.success(prepared))
            return
        }
        let fadeBoundary = Boundary(current: current, next: next.id)
        slot.start(fadeBoundary) { generation in
            Task.detached(priority: .utility) { [weak self] in
                let result = Result { try LocalAudioFile.openNatively(next.url) }
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async { [weak self] in
                    guard self?.slot.take(ifCurrent: generation) == fadeBoundary else { return }
                    completion(result)
                }
            }
        }
    }
}
