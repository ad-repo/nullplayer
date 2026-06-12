import Foundation
import AppKit

/// Orchestrates YouTube → Sonos streaming with local video sync
@MainActor
final class YouTubeToSonosCoordinator {

    // MARK: - Singleton

    static let shared = YouTubeToSonosCoordinator()

    // MARK: - Properties

    private var resolved: ResolvedStreams?
    private var ffmpegProcess: Process?
    private var liveStreamURL: URL?
    private var syncController: SonosVideoSyncController?
    private var castDevice: CastDevice?
    private weak var videoController: VideoPlayerWindowController?
    private var didStartManagedCast = false

    private init() {}

    // MARK: - Public API

    /// Start YouTube → Sonos streaming
    /// - Parameter youtubeURL: The YouTube URL to stream
    func start(youtubeURL: URL) async {
        guard HelperBinaries.isAvailable else {
            NSLog("YouTubeToSonosCoordinator: Helper binaries not available; aborting")
            showError("YouTube → Sonos streaming requires yt-dlp and ffmpeg binaries.")
            return
        }

        do {
            // 1. Resolve streams
            NSLog("YouTubeToSonosCoordinator: Resolving %@", youtubeURL.absoluteString)
            let resolved = try await YouTubeStreamResolver.resolve(youtubeURL)
            self.resolved = resolved

            // 2. Find first available Sonos device
            let sonosDevices = CastManager.shared.sonosDevices
            guard let device = sonosDevices.first else {
                throw CastError.deviceNotFound
            }
            self.castDevice = device
            NSLog("YouTubeToSonosCoordinator: Selected Sonos device: %@", device.name)

            // 3. Start ffmpeg producer and register live stream
            let liveURL = try await setupLiveAudioStream(resolved)
            self.liveStreamURL = liveURL

            // 4. Cast live audio to Sonos
            let metadata = CastMetadata(
                title: resolved.title,
                contentType: "audio/aac",
                mediaType: .audio
            )
            try await CastManager.shared.castLiveAudioStream(liveURL, to: device, metadata: metadata)
            didStartManagedCast = true
            NSLog("YouTubeToSonosCoordinator: Cast started to %@", device.name)

            // 5. Play video locally, MUTED, with headers (stays local; audio goes to Sonos)
            let videoController = WindowManager.shared.showLocalMutedVideo(
                url: resolved.videoURL,
                title: resolved.title,
                httpHeaders: resolved.videoHeaders
            )
            self.videoController = videoController
            NSLog("YouTubeToSonosCoordinator: Video playing MUTED with %d headers", resolved.videoHeaders.count)

            // 6. Start sync controller and connect the user-facing A/V offset slider (the
            //    primary calibration mechanism: Sonos position is only ~1s granular).
            let syncController = SonosVideoSyncController(
                positionProvider: {
                    CastManager.shared.currentCastPosition()
                },
                videoController: videoController
            )
            self.syncController = syncController
            videoController.avOffset = syncController.userOffset // reflect the persisted value
            videoController.onAVOffsetChanged = { [weak syncController] value in
                syncController?.userOffset = value
            }
            videoController.setAVOffsetVisible(true)
            syncController.start()

        } catch {
            NSLog("YouTubeToSonosCoordinator: Error during start - %@", error.localizedDescription)
            stop()
            showError(error.localizedDescription)
        }
    }

    /// Stop YouTube → Sonos streaming
    func stop() {
        syncController?.stop()
        syncController = nil

        if let liveURL = liveStreamURL {
            LocalMediaServer.shared.unregisterLiveStream(liveURL)
            liveStreamURL = nil
        }

        terminateFFmpeg()

        if let videoController = videoController {
            videoController.onAVOffsetChanged = nil
            videoController.setAVOffsetVisible(false)
            videoController.stop()
            videoController.volume = 1.0 // Restore volume
            self.videoController = nil
        }

        if didStartManagedCast {
            Task {
                await CastManager.shared.stopCasting()
            }
        }

        resolved = nil
        castDevice = nil
        didStartManagedCast = false

        NSLog("YouTubeToSonosCoordinator: Stopped")
    }

    /// Whether a YouTube → Sonos session is currently active (used to enable the Stop menu item).
    var isActive: Bool { liveStreamURL != nil }

    // MARK: - Private Helpers

    private func setupLiveAudioStream(_ resolved: ResolvedStreams, startOffset: TimeInterval = 0) async throws -> URL {
        guard let ffmpegURL = HelperBinaries.ffmpegURL else {
            throw CastError.localServerError("ffmpeg not found")
        }

        // Build ffmpeg command
        // Format: ffmpeg -headers "K: V\r\nK2: V2\r\n" -i <audioURL> -vn -c:a copy -f adts pipe:1
        // Strip CR/LF from header keys and values so a malicious resolved header cannot inject
        // additional ffmpeg `-headers` lines.
        func sanitize(_ s: String) -> String {
            s.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        }
        var headers = ""
        for (key, value) in resolved.audioHeaders {
            headers += "\(sanitize(key)): \(sanitize(value))\r\n"
        }

        let canCopyToADTS = isAACAudio(codec: resolved.audioCodec, ext: resolved.audioExtension)
        var args: [String] = []
        if !headers.isEmpty {
            args = ["-headers", headers]
        }
        args += [
            "-ss", String(format: "%.3f", startOffset),
            "-i", resolved.audioURL.absoluteString,
            "-vn"
        ]
        if canCopyToADTS {
            args += ["-c:a", "copy"]
        } else {
            args += ["-c:a", "aac", "-b:a", "192k"]
        }
        args += [
            "-f", "adts",
            "pipe:1"
        ]

        let argsSnapshot = args // Capture args for the closure
        let producer: @Sendable () -> AsyncThrowingStream<Data, Error> = {
            AsyncThrowingStream { continuation in
                let process = Process()
                process.executableURL = ffmpegURL
                process.arguments = argsSnapshot

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                let readHandle = pipe.fileHandleForReading

                // Drive the stream from pipe readability events (no busy-wait). EOF -> finish.
                readHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        continuation.finish()
                    } else {
                        continuation.yield(data)
                    }
                }

                process.terminationHandler = { _ in
                    readHandle.readabilityHandler = nil
                    continuation.finish()
                }

                // Client disconnect or cancellation tears down ffmpeg so it cannot leak.
                continuation.onTermination = { _ in
                    readHandle.readabilityHandler = nil
                    if process.isRunning { process.terminate() }
                    try? readHandle.close()
                }

                do {
                    try process.run()
                    // Record the live process so stop()/terminateFFmpeg() can kill it.
                    Task { @MainActor in YouTubeToSonosCoordinator.shared.ffmpegProcess = process }
                } catch {
                    readHandle.readabilityHandler = nil
                    continuation.finish(throwing: error)
                }
            }
        }

        guard let liveURL = LocalMediaServer.shared.registerLiveStream(
            contentType: "audio/aac",
            debugLabel: "YouTube audio",
            producer: producer
        ) else {
            throw CastError.localServerError("Failed to register live stream")
        }

        NSLog("YouTubeToSonosCoordinator: Live stream registered at %@", liveURL.absoluteString)
        return liveURL
    }

    private func terminateFFmpeg() {
        guard let process = ffmpegProcess else { return }
        ffmpegProcess = nil
        guard process.isRunning else { return }
        process.terminate() // SIGTERM
        let pid = process.processIdentifier
        // Escalate to SIGKILL if ffmpeg ignores SIGTERM (e.g. blocked reading a stalled stream).
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func isAACAudio(codec: String?, ext: String?) -> Bool {
        let normalizedCodec = codec?.lowercased() ?? ""
        let normalizedExt = ext?.lowercased() ?? ""
        return normalizedExt == "m4a" ||
            normalizedExt == "aac" ||
            normalizedCodec.contains("aac") ||
            normalizedCodec.contains("mp4a")
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "YouTube → Sonos Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
