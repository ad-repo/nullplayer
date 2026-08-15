import AppKit
import Foundation

protocol WinampModernHost: AnyObject {
    var playbackState: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var volume: Double { get set }
    var shuffleEnabled: Bool { get set }
    var repeatEnabled: Bool { get set }
    var trackTitle: String { get }
    var trackInfo: String { get }
    var albumArtwork: CGImage? { get }
    var spectrumLevels: [Float] { get set }

    func play()
    func pause()
    func stop()
    func previous()
    func next()
    func seek(to seconds: TimeInterval)
    func openFiles()
    func beginVisualizationConsumption()
    func endVisualizationConsumption()

    /// ClassicPro `ClassicProFile` shell adapters (P0B §1). All are gated by an intentional
    /// reveal/open policy: only existing on-disk files are acted on; skins can never navigate URLs,
    /// launch executables, or reach arbitrary paths.
    func revealInFinder(_ path: String)
    func openExternally(_ path: String)
}

extension WinampModernHost {
    var albumArtwork: CGImage? { nil }
    func revealInFinder(_ path: String) {}
    func openExternally(_ path: String) {}
}

final class WinampModernAudioEngineHost: WinampModernHost {
    private let engine: AudioEngine
    private let consumerID: String
    private var isConsumingVisualization = false
    var spectrumLevels: [Float] = []

    init(engine: AudioEngine, consumerID: String = "winampModernMain") {
        self.engine = engine
        self.consumerID = consumerID
    }

    var playbackState: PlaybackState { engine.state }
    var currentTime: TimeInterval { engine.currentTime }
    var duration: TimeInterval { engine.duration }
    var volume: Double {
        get { Double(engine.volume) }
        set { engine.volume = Float(max(0, min(1, newValue))) }
    }
    var shuffleEnabled: Bool {
        get { engine.shuffleEnabled }
        set { engine.shuffleEnabled = newValue }
    }
    var repeatEnabled: Bool {
        get { engine.repeatEnabled }
        set { engine.repeatEnabled = newValue }
    }
    var trackTitle: String { engine.currentTrack?.title ?? "" }
    var trackInfo: String {
        guard let track = engine.currentTrack else { return "" }
        return [track.artist, track.album].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " - ")
    }

    func play() { engine.play() }
    func pause() { engine.pause() }
    func stop() { engine.stop() }
    func previous() { engine.previous() }
    func next() { engine.next() }
    func seek(to seconds: TimeInterval) { engine.seek(to: seconds) }
    func openFiles() { MenuActions.shared.openFile() }

    func revealInFinder(_ path: String) {
        guard let url = Self.existingFileURL(for: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openExternally(_ path: String) {
        // Reveal/open policy: only open a real, existing document with its default app. Non-existent
        // paths (e.g. a Windows uninstaller) and URLs are intentionally ignored — no navigation, no
        // executable launch.
        guard let url = Self.existingFileURL(for: path) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func existingFileURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("://"),
              !trimmed.hasPrefix("~") else { return nil }
        let url = URL(fileURLWithPath: trimmed)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return url
    }

    func beginVisualizationConsumption() {
        guard !isConsumingVisualization else { return }
        isConsumingVisualization = true
        engine.addSpectrumConsumer(consumerID)
    }

    func endVisualizationConsumption() {
        guard isConsumingVisualization else { return }
        isConsumingVisualization = false
        engine.removeSpectrumConsumer(consumerID)
        spectrumLevels.removeAll(keepingCapacity: false)
    }

    deinit { endVisualizationConsumption() }
}

final class MakiTimerService {
    let maximumActiveTimers: Int
    let minimumPeriod: TimeInterval
    let maximumFrequency: Double

    private var timers: [UInt64: DispatchSourceTimer] = [:]
    private(set) var isTornDown = false

    init(maximumActiveTimers: Int = 256, minimumPeriod: TimeInterval = 0.008,
         maximumFrequency: Double = 120) {
        self.maximumActiveTimers = maximumActiveTimers
        self.minimumPeriod = minimumPeriod
        self.maximumFrequency = maximumFrequency
    }

    var activeTimerCount: Int { timers.count }
    func contains(id: UInt64) -> Bool { timers[id] != nil }

    @discardableResult
    func schedule(id: UInt64, period: TimeInterval, handler: @escaping () -> Void) throws -> TimeInterval {
        guard !isTornDown else { return 0 }
        guard timers[id] != nil || timers.count < maximumActiveTimers else {
            throw WalFailure(WalDiagnostic(.scriptBudgetExceeded,
                                           "MAKI skin exceeds \(maximumActiveTimers) active timers."))
        }
        cancel(id: id)
        let effective = max(minimumPeriod, 1 / maximumFrequency, period)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + effective, repeating: effective,
                       leeway: .milliseconds(1))
        timer.setEventHandler(handler: handler)
        timers[id] = timer
        timer.resume()
        return effective
    }

    func cancel(id: UInt64) {
        guard let timer = timers.removeValue(forKey: id) else { return }
        timer.setEventHandler {}
        timer.cancel()
    }

    func teardown() {
        guard !isTornDown else { return }
        for timer in timers.values {
            timer.setEventHandler {}
            timer.cancel()
        }
        timers.removeAll()
        isTornDown = true
    }

    deinit { teardown() }
}
