import AppKit
import Foundation

protocol WinampModernHost: AnyObject {
    var playbackState: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var volume: Double { get set }
    /// Stereo balance, −1 hard left … 0 centre … +1 hard right — what a skin's `action="PAN"` slider
    /// drives. Winamp's own unit is the slider's 0…255 position with 127/128 at the centre; the
    /// conversion lives at the two edges (the drag and the thumb) so the host stays in the engine's
    /// unit.
    var balance: Double { get set }
    var shuffleEnabled: Bool { get set }
    var repeatEnabled: Bool { get set }
    /// Crossfading between tracks — NullPlayer's Sweet Fades. Winamp's own option, which a skin
    /// draws rather than owns, so it is reached through `WinampModernConfigBridge` from the
    /// `cfgattrib` binding and never stored in the skin's namespace.
    var crossfadeEnabled: Bool { get set }
    /// How long that crossfade runs, in whole seconds — the unit Winamp's sliders are cut in
    /// (mmd3 prints the position straight into its readout). Writes are clamped by the bridge.
    var crossfadeSeconds: Int { get set }
    var trackTitle: String { get }
    var trackArtist: String { get }
    var trackAlbum: String { get }
    var trackInfo: String { get }
    /// What a song ticker shows — Winamp's playlist display title, i.e. "Artist - Title".
    var trackDisplayTitle: String { get }
    /// Stream properties the skin's `songinfo` script parses out of `getSongInfoText()`.
    /// Zero means "unknown", which renders as the skin's own placeholder.
    var bitrateKbps: Int { get }
    var sampleRateHz: Int { get }
    var channelCount: Int { get }
    var albumArtwork: CGImage? { get }
    /// Whether the cover for the current track is still being fetched — what an `<AlbumArt>` asks
    /// with `isLoading()`. Answered truthfully rather than stubbed: a skin that polls it from a
    /// timer treats a permanent "yes" as a spinner that never stops.
    var isArtworkLoading: Bool { get }
    /// Program level per channel, 0…1, for `getLeftVUMeter`/`getRightVUMeter`.
    ///
    /// **Not the spectrum.** A VU meter reads amplitude — RMS in dB against a noise floor, with
    /// attack/decay ballistics — and the spectrum tap is a *display* signal: mono, and normalised so
    /// bars fill their window. Reading a peak band out of it and calling it a channel pinned every
    /// needle in every skin that draws one (Defix's four analog VU styles, mmd3's knobs).
    var vuLevels: (left: Double, right: Double) { get }
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
    // A host with no mixer to pan (the render harness, a test double) reads centred and swallows the
    // write, the same way `vuLevels` reads silence — a `PAN` slider still draws, at its centre.
    var balance: Double {
        get { 0 }
        set {}
    }
    var isArtworkLoading: Bool { false }
    // A host with no crossfade to drive (the render harness, a test double) reads it off and
    // swallows the write, the way `balance` does — the skin's lamp and slider still draw.
    var crossfadeEnabled: Bool {
        get { false }
        set {}
    }
    var crossfadeSeconds: Int {
        get { Int(WinampModernConfigBridge.crossfadeSecondsRange.lowerBound) }
        set {}
    }
    var vuLevels: (left: Double, right: Double) { (0, 0) }
    var trackArtist: String { "" }
    var trackAlbum: String { "" }
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
    typealias ArtworkSnapshot = (trackID: UUID?, image: NSImage?)

    private let engine: AudioEngine
    private let consumerID: String
    private let artworkSnapshot: () -> ArtworkSnapshot
    private let artworkLoading: () -> Bool
    private var isConsumingVisualization = false
    var spectrumLevels: [Float] = []

    /// Stereo program level, driven by the same RMS + ballistics model the PeppyMeter window uses so
    /// a needle behaves identically wherever it is drawn. Registered alongside the spectrum consumer
    /// and released with it, so the stereo tap is idle when no `.wal` skin is loaded.
    /// The `.wal` VU tap. Its own meter, on Winamp's linear scale — not PeppyMeter's, whose model
    /// measures the same audio for artwork calibrated differently (`WinampModernLevelMeter`).
    private lazy var levelMeter = WinampModernLevelMeter(consumerId: consumerID + ".vu")
    var vuLevels: (left: Double, right: Double) { levelMeter.levels }

    /// The current track's cover, decoded once per track rather than per frame — `albumArtwork` is
    /// read inside `draw`, so converting an `NSImage` there would re-rasterise the art every repaint.
    private var artworkCache: (trackID: UUID, image: CGImage?)?
    private var artworkObserver: NSObjectProtocol?

    // `artworkSnapshot` stays the *last* parameter: the existing call sites pass it as a trailing
    // closure, which binds to the last function-typed parameter.
    init(engine: AudioEngine, consumerID: String = "winampModernMain",
         artworkLoading: @escaping () -> Bool = { NowPlayingManager.shared.isLoadingArtwork },
         artworkSnapshot: @escaping () -> ArtworkSnapshot = {
             let manager = NowPlayingManager.shared
             return (manager.currentTrackId, manager.currentArtwork)
         }) {
        self.engine = engine
        self.consumerID = consumerID
        self.artworkSnapshot = artworkSnapshot
        self.artworkLoading = artworkLoading
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
        let snapshot = artworkSnapshot()
        // Only the art that belongs to *this* track. A load in flight for a track that has already
        // changed would otherwise be shown against the wrong one.
        let image = snapshot.trackID == trackID
            ? snapshot.image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            : nil
        artworkCache = (trackID, image)
        return image
    }

    /// True only while a fetch is actually in flight *and* this track has no cover yet — a cached
    /// cover is not "loading", and with nothing playing there is nothing to load.
    var isArtworkLoading: Bool {
        guard engine.currentTrack != nil, albumArtwork == nil else { return false }
        return artworkLoading()
    }

    var playbackState: PlaybackState { engine.state }
    var currentTime: TimeInterval { engine.currentTime }
    var duration: TimeInterval { engine.duration }
    var volume: Double {
        get { Double(engine.volume) }
        set { engine.volume = Float(max(0, min(1, newValue))) }
    }
    var balance: Double {
        get { Double(engine.balance) }
        set { engine.balance = Float(max(-1, min(1, newValue))) }
    }
    var shuffleEnabled: Bool {
        get { engine.shuffleEnabled }
        set { engine.shuffleEnabled = newValue }
    }
    var repeatEnabled: Bool {
        get { engine.repeatEnabled }
        set { engine.repeatEnabled = newValue }
    }
    var crossfadeEnabled: Bool {
        get { engine.sweetFadeEnabled }
        set { engine.sweetFadeEnabled = newValue }
    }
    /// Whole seconds, because that is the unit a skin's crossfade slider is cut in. The engine keeps
    /// a `TimeInterval`, so a fractional duration set from NullPlayer's own menu reads back rounded
    /// rather than truncated — a 2.5 s setting shows the skin 3, not 2.
    var crossfadeSeconds: Int {
        get { Int(engine.sweetFadeDuration.rounded()) }
        set { engine.sweetFadeDuration = TimeInterval(newValue) }
    }
    var trackTitle: String { engine.currentTrack?.title ?? "" }
    var trackArtist: String { engine.currentTrack?.artist ?? "" }
    var trackAlbum: String { engine.currentTrack?.album ?? "" }
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
        levelMeter.start()
    }

    func endVisualizationConsumption() {
        guard isConsumingVisualization else { return }
        isConsumingVisualization = false
        engine.removeSpectrumConsumer(consumerID)
        levelMeter.stop()
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
