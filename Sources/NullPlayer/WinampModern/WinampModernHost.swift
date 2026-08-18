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
    /// What a song ticker shows — Winamp's playlist display title, i.e. "Artist - Title".
    var trackDisplayTitle: String { get }
    /// Stream properties the skin's `songinfo` script parses out of `getSongInfoText()`.
    /// Zero means "unknown", which renders as the skin's own placeholder.
    var bitrateKbps: Int { get }
    var sampleRateHz: Int { get }
    var channelCount: Int { get }
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
    var trackDisplayTitle: String { trackTitle }
    var bitrateKbps: Int { 0 }
    var sampleRateHz: Int { 0 }
    var channelCount: Int { 0 }
    func revealInFinder(_ path: String) {}
    func openExternally(_ path: String) {}

    /// Winamp's `System.getSongInfoText()` string. Skins do not read bitrate/sample rate through
    /// dedicated APIs — `songinfo.maki` lowercases this string and pulls the values out around the
    /// literals "kbps", "khz" and the channel words, so the shape matters more than the wording.
    var songInfoText: String {
        var parts: [String] = []
        if bitrateKbps > 0 { parts.append("\(bitrateKbps)kbps") }
        switch channelCount {
        case 1: parts.append("mono")
        case 2: parts.append("stereo")
        case let count where count > 2: parts.append("surround")
        default: break
        }
        if sampleRateHz > 0 { parts.append("\(sampleRateHz / 1_000)khz") }
        return parts.joined(separator: " ")
    }
}

final class WinampModernAudioEngineHost: WinampModernHost {
    private let engine: AudioEngine
    private let consumerID: String
    private var isConsumingVisualization = false
    var spectrumLevels: [Float] = []

    /// The current track's cover, decoded once per track rather than per frame — `albumArtwork` is
    /// read inside `draw`, so converting an `NSImage` there would re-rasterise the art every repaint.
    private var artworkCache: (trackID: UUID, image: CGImage?)?
    private var artworkObserver: NSObjectProtocol?

    init(engine: AudioEngine, consumerID: String = "winampModernMain") {
        self.engine = engine
        self.consumerID = consumerID
        // `NowPlayingManager` already fetches cover art for every source (local tags, Plex, Subsonic,
        // Jellyfin, Emby) to feed the system Now Playing panel. A skin's `<AlbumArt>` wants exactly
        // that image, so this listens rather than fetching a second copy of it.
        artworkObserver = NotificationCenter.default.addObserver(
            forName: NowPlayingManager.artworkDidLoadNotification,
            object: nil, queue: .main) { [weak self] _ in self?.artworkCache = nil }
    }

    /// The playing track's cover, or `nil` — which is what makes an `<AlbumArt>` fall back to the
    /// `notfoundImage` the skin ships. Until this existed the protocol's default `nil` applied to
    /// every `.wal` skin, so every `<AlbumArt>` in every skin permanently showed "no cover art".
    ///
    /// Keyed by track id: the cache has to be dropped when the track changes, or the previous
    /// track's cover stays on screen over the new one's title.
    var albumArtwork: CGImage? {
        guard let trackID = engine.currentTrack?.id else { return nil }
        if let artworkCache, artworkCache.trackID == trackID { return artworkCache.image }
        let manager = NowPlayingManager.shared
        // Only the art that belongs to *this* track. A load in flight for a track that has already
        // changed would otherwise be shown against the wrong one.
        let image = manager.currentTrackId == trackID
            ? manager.currentArtwork?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            : nil
        artworkCache = (trackID, image)
        return image
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
    var trackDisplayTitle: String {
        guard let track = engine.currentTrack else { return "" }
        guard let artist = track.artist, !artist.isEmpty else { return track.title }
        return "\(artist) - \(track.title)"
    }
    var bitrateKbps: Int { engine.currentTrack?.bitrate ?? 0 }
    var sampleRateHz: Int { engine.currentTrack?.sampleRate ?? 0 }
    var channelCount: Int { engine.currentTrack?.channels ?? 0 }
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

    deinit {
        if let artworkObserver { NotificationCenter.default.removeObserver(artworkObserver) }
        endVisualizationConsumption()
    }
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
