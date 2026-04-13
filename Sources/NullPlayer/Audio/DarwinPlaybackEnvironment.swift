import Foundation
import AppKit
import NullPlayerPlayback

final class DarwinPlaybackEnvironment: PlaybackEnvironmentProviding {
    private var sleepObserverTokens: [NSObjectProtocol] = []
    private let observerLock = NSLock()

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        observerLock.lock()
        let tokens = sleepObserverTokens
        sleepObserverTokens.removeAll()
        observerLock.unlock()

        for token in tokens {
            center.removeObserver(token)
        }
    }

    func reportNonFatalPlaybackError(_ message: String) {
        let presentAlert = {
            let alert = NSAlert()
            alert.messageText = "Playback Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }

        if Thread.isMainThread {
            presentAlert()
        } else {
            DispatchQueue.main.async(execute: presentAlert)
        }
    }

    func makeTemporaryPlaybackURLIfNeeded(for originalURL: URL) throws -> URL {
        guard originalURL.isFileURL else { return originalURL }

        let isLocalVolume = (try? originalURL.resourceValues(
            forKeys: [.volumeIsLocalKey]
        ))?.volumeIsLocal ?? true

        guard !isLocalVolume else { return originalURL }

        let fileSize = (try? originalURL.resourceValues(
            forKeys: [.fileSizeKey]
        ))?.fileSize ?? 0
        let maxCopySize = 300 * 1024 * 1024
        guard fileSize <= maxCopySize else {
            NSLog(
                "DarwinPlaybackEnvironment: Skipping NAS copy for large file '%@' (%lld MB)",
                originalURL.lastPathComponent,
                Int64(fileSize) / (1024 * 1024)
            )
            return originalURL
        }

        let ext = originalURL.pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let candidate = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nullplayer-\(UUID().uuidString)\(suffix)")
        let copyStart = CFAbsoluteTimeGetCurrent()
        try FileManager.default.copyItem(at: originalURL, to: candidate)

        NSLog(
            "DarwinPlaybackEnvironment: Copied NAS '%@' to temp in %.3fs",
            originalURL.lastPathComponent,
            CFAbsoluteTimeGetCurrent() - copyStart
        )

        return candidate
    }

    func beginSleepObservation(_ handler: @escaping @Sendable (PlaybackSleepEvent) -> Void) {
        let center = NSWorkspace.shared.notificationCenter

        let willSleep = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            handler(.willSleep)
        }

        let didWake = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            handler(.didWake)
        }

        observerLock.lock()
        sleepObserverTokens.append(willSleep)
        sleepObserverTokens.append(didWake)
        observerLock.unlock()
    }
}
