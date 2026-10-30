import AVFoundation

/// A prepared handle owns its complete backing lifetime, including any NAS staging copy.
struct PreparedLocalFile {
    let file: AVAudioFile
}

/// Owns the asynchronous part of a local selection. All control/publication is on main;
/// staging, decoding and failure filesystem checks run in the independent worker task.
// AudioEngine is a legacy, nonisolated main-queue owner. Runtime preconditions below
// enforce that every mutable access is on main; detached tasks only capture weak self
// to enqueue publication there. No mutable state is read by the worker itself.
final class LocalTrackPreparation: @unchecked Sendable {
    struct Transport {
        var lastSkippable: Int? = nil
        var playNow: PlayNowRequest? = nil
        var firstFailure: TrackLoadFailure? = nil
        var intent: PlaybackState = .stopped
    }

    enum Policy {
        case transport(Transport)
        case immediate(userInitiated: Bool)
    }

    struct Request {
        let track: Track
        let index: Int
        let playbackGeneration: Int
        let policy: Policy
        var intent: PlaybackState
    }

    struct Failure: Error {
        let underlying: Error
        let folderIsPresent: Bool
        let fileIsMissing: Bool
    }

    private let slot = CancellablePreparation<Request>()
    var intent: PlaybackState? {
        dispatchPrecondition(condition: .onQueue(.main))
        return slot.payload?.intent
    }
    var isPending: Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return slot.payload != nil
    }

    @discardableResult
    func record(_ intent: PlaybackState) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return slot.update { $0.intent = intent }
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        slot.reset()
    }

    func start(_ request: Request,
               completion: @escaping (Request, Result<PreparedLocalFile, Error>) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        slot.start(request) { generation in
            Task.detached(priority: .userInitiated) { [weak self] in
                let result: Result<PreparedLocalFile, Error>
                do {
                    let file = try await LocalAudioFile.prepareForPlayback(request.track.url)
                    try Task.checkCancellation()
                    result = .success(PreparedLocalFile(file: file))
                } catch is CancellationError {
                    return
                } catch {
                    result = .failure(Failure(underlying: error,
                        folderIsPresent: AudioEngine.containingFolderIsPresent(request.track.url),
                        fileIsMissing: !FileManager.default.fileExists(atPath: request.track.url.path)))
                }
                DispatchQueue.main.async { [weak self] in
                    guard let request = self?.slot.take(ifCurrent: generation) else { return }
                    completion(request, result)
                }
            }
        }
    }
}
