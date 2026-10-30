import AVFoundation

/// Only MPEG-4 inputs needing a full fallback decode are prepared early. Native formats
/// still open at the fade boundary. Refreshed by track/queue/option changes, never a timer.
/// Main-queue owned, like the `CancellablePreparation` it drives.
final class LocalCrossfadePreparation {
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
        guard LocalAudioFile.mayNeedFallbackDecode(next.url) else { return }
        let url = next.url
        slot.start(nextBoundary, priority: .utility) { () async throws -> AVAudioFile? in
            // A native AAC/ALAC/Opus reader keeps the existing just-in-time fade path.
            guard try LocalAudioFile.openNatively(url) == nil else { return nil }
            return try await LocalAudioFile.prepareForPlayback(url)
        } publish: { [weak self] _, result in
            switch result {
            case .success(let file):
                self?.prepared = file
                if file != nil { NSLog("Sweet Fades: Prepared next track: %@", next.title) }
            case .failure(let error):
                NSLog("Sweet Fades: Next track preparation failed: %@",
                      error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
    }

    /// Native formats retain their existing off-main, just-in-time open. At the boundary
    /// a fallback may only use an already prepared handle; it never begins a full decode.
    func openForFade(current: UUID, next: Track,
                     completion: @escaping (Result<AVAudioFile?, Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let fadeBoundary = Boundary(current: current, next: next.id)
        if boundary == fadeBoundary, let prepared {
            completion(.success(prepared))
            return
        }
        let url = next.url
        slot.start(fadeBoundary, priority: .utility) {
            try LocalAudioFile.openNatively(url)
        } publish: { _, result in
            completion(result)
        }
    }
}
