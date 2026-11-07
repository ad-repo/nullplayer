import AppKit
import os

/// Casts what a Visualizations window shows, with the music, live to a Chromecast or a DLNA TV.
///
/// The local engine keeps playing and is the source: a process tap takes the app's audio (and mutes
/// the Mac), `VisualizationCastEncoder` turns it and the GL view's frames into MPEG-TS, and
/// `LocalMediaServer` serves that under `/viscast/`. While this owns the Chromecast/UPnP managers,
/// `CastManager.activeSession` reads nil, so transport, volume and the cast menus stay local.
@MainActor
final class VisualizationCast {
    static let shared = VisualizationCast()

    /// The encoder a receiver plays, from just before the LOAD until the receiver is stopped: what
    /// `/viscast/*` serves (`VisualizationCast+HTTP`), and while set `CastManager` hides its session.
    nonisolated static let serving = OSAllocatedUnfairLock<VisualizationCastEncoder?>(initialState: nil)

    /// True while a visualization cast holds a manager's session; `CastManager` hides it.
    nonisolated static var ownsCastManagers: Bool { serving.withLockUnchecked { $0 != nil } }

    private(set) var activeDevice: CastDevice?
    private weak var sourceView: VisualizationGLView?
    private var encoder: VisualizationCastEncoder?
    private var stopTap: (() -> Void)?   // `ProcessAudioTap.stop`, which unmutes the Mac
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    private var hasSeenPlayback = false

    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    func start(device: CastDevice, view: VisualizationGLView) {
        Task { await run(device: device, view: view) }
    }

    /// A Resolution or Frame Rate change restarts a running cast on the same device.
    func qualityDidChange() {
        guard let device = activeDevice, let view = sourceView else { return }
        Task {
            await stop()
            await run(device: device, view: view)
        }
    }

    private func run(device: CastDevice, view: VisualizationGLView) async {
        if CastManager.shared.activeSession != nil { await CastManager.shared.stopCasting() }
        await stop()
        generation += 1
        let myGeneration = generation
        activeDevice = device
        sourceView = view
        NSLog("VisualizationCast: starting to %@ at %@", device.name, String(describing: VisualizationCastQuality.saved))
        do {
            guard #available(macOS 14.2, *) else { throw VisualizationCastError.unsupportedSystem }
            try await LocalMediaServer.shared.start()
            let quality = VisualizationCastQuality.saved
            let (encoder, stopTap) = try await Task.detached { () throws -> (VisualizationCastEncoder, () -> Void) in
                let tap = try ProcessAudioTap()
                do {
                    let encoder = try VisualizationCastEncoder(quality: quality, inputSampleRate: tap.sampleRate)
                    let ring = encoder.audio
                    try tap.start { buffers, frames in ring.write(buffers, frames: frames) }
                    return (encoder, tap.stop)
                } catch {
                    tap.stop()
                    throw error
                }
            }.value
            guard generation == myGeneration else { await Self.tearDown(encoder, stopTap); return }
            self.encoder = encoder
            self.stopTap = stopTap
            encoder.start()
            view.castEncoder = encoder
            observeEnd(of: device, window: view.window)

            // The playlist starts a Chromecast 6 s back (`VisualizationCastEncoder.playlist`).
            let startupSegments = 6
            let deadline = Date().addingTimeInterval(12)
            while encoder.segmentCount < startupSegments, Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard generation == myGeneration else { return }
            guard encoder.segmentCount >= startupSegments else { throw VisualizationCastError.noStream }

            Self.serving.withLockUnchecked { $0 = encoder }
            try await load(device: device, quality: quality)
            guard generation == myGeneration else { return }
            NSLog("VisualizationCast: casting to %@", device.name)
        } catch {
            guard generation == myGeneration else { return }
            NSLog("VisualizationCast: start failed — %@", error.localizedDescription)
            await stop()
            Self.showAlert(error.localizedDescription)
        }
    }

    private func load(device: CastDevice, quality: VisualizationCastQuality) async throws {
        guard let ip = LocalMediaServer.shared.localIPAddress else { throw LocalServerError.noNetworkInterface }
        let base = "http://\(ip):\(LocalMediaServer.httpPort)/viscast/"
        hasSeenPlayback = false
        switch device.type {
        case .chromecast:
            let metadata = CastMetadata(title: "NullPlayer Visualization", contentType: "application/x-mpegurl",
                                        mediaType: .video, resolution: "\(quality.width)x\(quality.height)", isLive: true)
            try await ChromecastManager.shared.connect(to: device)
            try await ChromecastManager.shared.cast(url: URL(string: base + "live.m3u8")!, metadata: metadata)
        case .dlnaTV:
            let metadata = CastMetadata(title: "NullPlayer Visualization", contentType: "video/mp2t",
                                        mediaType: .video, resolution: "\(quality.width)x\(quality.height)", isLive: true)
            try await UPnPManager.shared.connect(to: device)
            try await UPnPManager.shared.cast(url: URL(string: base + "live.ts")!, metadata: metadata)
        case .sonos:
            throw CastError.unsupportedDevice
        }
    }

    /// Ends the cast: the receiver first (while the managers are still hidden), then the stream and
    /// the tap, which unmutes the Mac. Safe to call when nothing is running. The session's state is
    /// cleared before the first await, so a cast started meanwhile is not wiped by this one.
    func stop() async {
        generation += 1
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        let device = activeDevice, encoder = self.encoder, stopTap = self.stopTap
        sourceView?.castEncoder = nil
        activeDevice = nil
        sourceView = nil
        self.encoder = nil
        self.stopTap = nil
        if Self.ownsCastManagers, let device {
            switch device.type {
            case .chromecast:
                ChromecastManager.shared.stop()
                try? await Task.sleep(nanoseconds: 200_000_000)   // let STOP flush (`chromecast-casting`)
                ChromecastManager.shared.disconnect()
            case .dlnaTV, .sonos:
                try? await UPnPManager.shared.stop()
                await UPnPManager.shared.disconnect()
            }
        }
        Self.serving.withLockUnchecked { $0 = nil }
        await Self.tearDown(encoder, stopTap)
        if device != nil { NSLog("VisualizationCast: stopped") }
    }

    /// Off the main thread: the encoder waits out a tick in flight, and Core Audio's teardown blocks.
    private static func tearDown(_ encoder: VisualizationCastEncoder?, _ stopTap: (() -> Void)?) async {
        await Task.detached {
            encoder?.stop()
            stopTap?()
            if let encoder { NSLog("VisualizationCast: %d tap frames dropped", encoder.audio.droppedFrames) }
        }.value
    }

    /// The cast ends when its window closes, when the TV drops the session, or when a Chromecast
    /// rejects the stream (IDLE/ERROR, e.g. 4K on a 1080p device).
    private func observeEnd(of device: CastDevice, window: NSWindow?) {
        let center = NotificationCenter.default
        if let window {
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.endFromObserver(nil) }
            })
        }
        guard device.type == .chromecast else { return }
        observers.append(center.addObserver(forName: ChromecastManager.mediaStatusDidUpdateNotification, object: nil, queue: .main) { [weak self] note in
            guard let status = note.userInfo?["status"] as? CastMediaStatus else { return }
            MainActor.assumeIsolated { self?.chromecastStatus(status) }
        })
        observers.append(center.addObserver(forName: CastManager.sessionDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard Self.ownsCastManagers else { return }
                let session = ChromecastManager.shared.activeSession
                if session == nil || session?.state == .idle { self?.endFromObserver(nil) }
            }
        })
    }

    private func chromecastStatus(_ status: CastMediaStatus) {
        guard Self.ownsCastManagers else { return }
        switch status.playerState {
        case .playing, .buffering:
            hasSeenPlayback = true
        case .idle where status.idleReason == "ERROR":
            endFromObserver("The TV rejected the stream — try a lower resolution.")
        case .idle where hasSeenPlayback:
            endFromObserver(nil)
        default:
            break
        }
    }

    private func endFromObserver(_ message: String?) {
        NSLog("VisualizationCast: ending — %@", message ?? "window closed or TV ended the session")
        let view = sourceView
        Task {
            await stop()
            // A closed or hidden window was kept rendering only for the cast.
            if view?.window?.isVisible != true || view?.window?.isMiniaturized == true { view?.stopRendering() }
            if let message { Self.showAlert(message) }
        }
    }

    private static func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Cast Visualization"
        alert.informativeText = message
        alert.runModal()
    }
}

enum VisualizationCastError: LocalizedError {
    case encoder(String)
    case audioTap(String, OSStatus)
    case noStream
    case unsupportedSystem

    var errorDescription: String? {
        switch self {
        case .encoder(let part): return "Could not start the \(part)."
        case .audioTap(let step, let status): return "Could not capture the app's audio (\(step), \(status))."
        case .noStream: return "The visualization stream did not start."
        case .unsupportedSystem: return "Casting the visualization needs macOS 14.2 or later."
        }
    }
}
