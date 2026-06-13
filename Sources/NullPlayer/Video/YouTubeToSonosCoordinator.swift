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
    private var liveStreamURL: URL?            // set for the live (ffmpeg transcode) audio path
    private var proxyUpstreamURL: URL?         // set for the proxied-file audio path (AAC)
    private var syncController: SonosVideoSyncController?
    private var castDevice: CastDevice?
    private weak var videoController: VideoPlayerWindowController?
    private var didStartManagedCast = false

    // Transport state
    private(set) var isPlaying: Bool = true    // Session starts playing
    private var completionPollTimer: Timer?

    private init() {}

    // MARK: - Public API

    /// Start YouTube → Sonos streaming
    /// - Parameters:
    ///   - youtubeURL: The YouTube URL to stream
    ///   - device: The Sonos device to cast to. If nil, the first discovered Sonos device is used.
    func start(youtubeURL: URL, device requestedDevice: CastDevice? = nil) async {
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

            // 2. Resolve the Sonos device (explicit user selection wins; else first discovered)
            let device: CastDevice
            if let requestedDevice {
                device = requestedDevice
            } else if let first = CastManager.shared.sonosDevices.first {
                device = first
            } else {
                throw CastError.deviceNotFound
            }
            self.castDevice = device
            NSLog("YouTubeToSonosCoordinator: Selected Sonos device: %@", device.name)

            // 3 + 4. Set up the Sonos audio. For AAC (itag 140 — the common case) proxy the real
            //   m4a file through the SAME path Navidrome/local files use: real Content-Length +
            //   Range passthrough, cast as a normal durationed track. That is the reliable Sonos
            //   path. Only fall back to live ffmpeg transcoding when the audio isn't already AAC
            //   (e.g. opus/webm, which Sonos can't play directly).
            if isAACAudio(codec: resolved.audioCodec, ext: resolved.audioExtension) {
                guard let proxyURL = LocalMediaServer.shared.registerStreamURL(
                    resolved.audioURL,
                    contentType: "audio/mp4",
                    debugLabel: "YouTube audio (AAC proxy)",
                    requestHeaders: resolved.audioHeaders
                ) else {
                    throw CastError.localServerError("Failed to register audio proxy")
                }
                self.proxyUpstreamURL = resolved.audioURL
                NSLog("YouTubeToSonosCoordinator: Proxying AAC audio via %@", proxyURL.absoluteString)
                let metadata = CastMetadata(
                    title: resolved.title,
                    duration: resolved.duration,
                    contentType: "audio/mp4",
                    mediaType: .audio
                )
                try await CastManager.shared.cast(to: device, url: proxyURL, metadata: metadata)
            } else {
                let liveURL = try await setupLiveAudioStream(resolved)
                self.liveStreamURL = liveURL
                let metadata = CastMetadata(
                    title: resolved.title,
                    duration: resolved.duration,
                    contentType: "audio/aac",
                    mediaType: .audio
                )
                try await CastManager.shared.castLiveAudioStream(liveURL, to: device, metadata: metadata)
            }
            didStartManagedCast = true
            NSLog("YouTubeToSonosCoordinator: Cast started to %@", device.name)

            // 5. Play video locally, MUTED, with headers (stays local; audio goes to Sonos)
            let videoController = WindowManager.shared.showLocalMutedVideo(
                url: resolved.videoURL,
                title: resolved.title,
                httpHeaders: resolved.videoHeaders
            )
            self.videoController = videoController
            videoController.isYouTubeToSonosCompanion = true
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
            videoController.onAVOffsetResync = { [weak syncController] in
                syncController?.realignToCurrentOffset()
            }
            videoController.setAVOffsetVisible(true)
            DispatchQueue.main.async { [weak videoController] in
                videoController?.showAVOffsetPopover()
            }
            syncController.start()

            // Start completion poll: check periodically if playback has finished
            startCompletionPoll()

        } catch {
            NSLog("YouTubeToSonosCoordinator: Error during start - %@", error.localizedDescription)
            stop()
            showError(error.localizedDescription)
        }
    }

    /// Stop YouTube → Sonos streaming
    func stop() {
        completionPollTimer?.invalidate()
        completionPollTimer = nil

        syncController?.stop()
        syncController = nil

        if let liveURL = liveStreamURL {
            LocalMediaServer.shared.unregisterLiveStream(liveURL)
            liveStreamURL = nil
        }

        if let upstream = proxyUpstreamURL {
            LocalMediaServer.shared.unregisterStreamURL(upstream)
            proxyUpstreamURL = nil
        }

        terminateFFmpeg()

        if let videoController = videoController {
            videoController.onAVOffsetChanged = nil
            videoController.onAVOffsetResync = nil
            videoController.setAVOffsetVisible(false)
            videoController.isYouTubeToSonosCompanion = false
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

    /// Whether a YouTube → Sonos session is currently active (used to enable the Stop menu item
    /// and to suppress the video-start audio-pause). True for both the proxied and live paths.
    var isActive: Bool { liveStreamURL != nil || proxyUpstreamURL != nil }

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
            // NOTE: do NOT add `-re` here. Pacing the read at realtime starves Sonos's initial
            // format probe (it delays the first bytes), so Sonos gives up and stays STOPPED.
            // Letting ffmpeg run ahead lets Sonos buffer enough to start playback.
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
                // Capture stderr so a genuine transcode failure can be surfaced (see terminationHandler).
                let errPipe = Pipe()
                process.standardError = errPipe
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

                process.terminationHandler = { proc in
                    readHandle.readabilityHandler = nil
                    // Only log on a real ffmpeg failure, not our own SIGTERM teardown on stop().
                    if proc.terminationReason == .exit && proc.terminationStatus != 0 {
                        let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        NSLog("YouTubeToSonosCoordinator: ffmpeg exited %d: %@",
                              proc.terminationStatus, String(errText.suffix(500)))
                    }
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

    // MARK: - Transport Control

    /// Resume playback: video first, then Sonos, then re-align video if Sonos confirms.
    func resume() {
        NSLog("YouTubeToSonosCoordinator: resume()")
        videoController?.setPaused(false)

        Task {
            try? await CastManager.shared.resume()

            // Retry re-align briefly if Sonos confirmation hasn't landed yet
            var attempts = 0
            let maxAttempts = 20 // ~2 seconds with 100ms delays
            while attempts < maxAttempts && !CastManager.shared.isSonosPlaybackConfirmed {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                attempts += 1
            }

            if CastManager.shared.isSonosPlaybackConfirmed {
                await MainActor.run {
                    self.syncController?.realignToCurrentOffset()
                }
            }
        }

        isPlaying = true
    }

    /// Pause playback on both video and Sonos.
    func pause() {
        NSLog("YouTubeToSonosCoordinator: pause()")
        videoController?.setPaused(true)

        Task {
            try? await CastManager.shared.pause()
        }

        isPlaying = false
    }

    /// Toggle between resume and pause based on current state.
    func togglePlayPause() {
        NSLog("YouTubeToSonosCoordinator: togglePlayPause()")
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// Seek both video and Sonos to the given time.
    /// - Parameter time: Target position in seconds (from Sonos/audio reference)
    func seek(to time: TimeInterval) {
        NSLog("YouTubeToSonosCoordinator: seek(to: %.1f)", time)

        Task {
            try? await CastManager.shared.seek(to: time)
        }

        // Video target = audio time + offset. Use seekLocalVideo (not seek) to bypass the
        // companion-forwarding branch in VideoPlayerWindowController.seek, which would recurse here.
        let videoTarget = max(0, time + (syncController?.userOffset ?? 0))
        videoController?.seekLocalVideo(to: videoTarget)
    }

    /// Skip relative to current position (e.g. +10 or -10 seconds). Used by Next/Prev.
    /// - Parameter seconds: Relative offset in seconds (may be negative)
    func skipRelative(_ seconds: TimeInterval) {
        NSLog("YouTubeToSonosCoordinator: skipRelative(%.1f)", seconds)
        let target = max(0, min(currentPosition + seconds, duration))
        seek(to: target)
    }

    /// Current Sonos playback position in seconds.
    var currentPosition: TimeInterval {
        CastManager.shared.currentCastPosition() ?? 0
    }

    /// Total duration of the stream in seconds.
    var duration: TimeInterval {
        resolved?.duration ?? 0
    }

    /// Called when playback reaches end-of-item. Stops and closes the session.
    private func handlePlaybackFinished() {
        NSLog("YouTubeToSonosCoordinator: handlePlaybackFinished()")
        stop()
    }

    /// Lightweight completion poll: fires when position >= duration - 0.5 or on error.
    private func startCompletionPoll() {
        completionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.isActive else { return }

                // Don't fire until Sonos has confirmed playback
                guard CastManager.shared.isSonosPlaybackConfirmed else { return }

                let dur = self.duration
                guard dur > 0 else { return }

                let pos = self.currentPosition
                if pos >= dur - 0.5 {
                    NSLog("YouTubeToSonosCoordinator: Position %.1f >= duration %.1f, finishing playback", pos, dur)
                    self.handlePlaybackFinished()
                }
            }
        }
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
