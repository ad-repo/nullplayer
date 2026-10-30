import AVFoundation

/// The asynchronous part of a local selection. AudioEngine owns the in-flight `Request` in a
/// `CancellablePreparation`; staging, decoding and the failure filesystem checks run in `prepare`,
/// off main.
enum LocalTrackPreparation {
    /// A transport load's skip bound and Play Now rollback, carried through any failed-file skip.
    struct Transport {
        var lastSkippable: Int? = nil
        var playNow: PlayNowRequest? = nil
        var firstFailure: TrackLoadFailure? = nil
    }

    enum Policy {
        case transport(Transport)
        case immediate(userInitiated: Bool)
    }

    struct Request {
        let track: Track
        let index: Int
        let playbackGeneration: Int
        var policy: Policy
        /// The only copy of the selection's Play/Pause intent; Play and Pause update it in place.
        var intent: PlaybackState
    }

    struct Failure: Error {
        let underlying: Error
        let folderIsPresent: Bool
        let fileIsMissing: Bool
    }

    static func prepare(_ url: URL) async throws -> AVAudioFile {
        do {
            return try await LocalAudioFile.prepareForPlayback(url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure(underlying: error,
                          folderIsPresent: AudioEngine.containingFolderIsPresent(url),
                          fileIsMissing: !FileManager.default.fileExists(atPath: url.path))
        }
    }
}
