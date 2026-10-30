import AVFoundation

/// The asynchronous part of a local selection. AudioEngine owns the in-flight `Request` in a
/// `CancellablePreparation`; staging, decoding and the failure filesystem checks run in `prepare`,
/// off main.
enum LocalTrackPreparation {
    enum Policy {
        case transport(TrackLoadTransport)
        case immediate(userInitiated: Bool)
    }

    struct Request {
        let track: Track
        var index: Int
        let playbackGeneration: Int
        var policy: Policy
        /// The only copy of the selection's Play/Pause intent; Play and Pause update it in place.
        var intent: PlaybackState
    }

    /// A local file that would not open, with the filesystem checks its skip/stop policy needs.
    /// Building one stats the file's volume, so build it on the thread that just touched it.
    struct Failure: Error {
        let underlying: Error
        let folderIsPresent: Bool
        let fileIsMissing: Bool

        init(_ underlying: Error, url: URL) {
            self.underlying = underlying
            folderIsPresent = AudioEngine.containingFolderIsPresent(url)
            fileIsMissing = !FileManager.default.fileExists(atPath: url.path)
        }
    }

    /// Throws only `CancellationError`, which `CancellablePreparation` never publishes.
    static func prepare(_ url: URL) async throws -> Result<AVAudioFile, Failure> {
        do {
            return .success(try await LocalAudioFile.prepareForPlayback(url))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failure(Failure(error, url: url))
        }
    }
}
