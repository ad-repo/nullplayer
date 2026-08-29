import AppKit
import Foundation

/// The playing item's tag fields beyond the three (`title` / `artist` / `album`) a `Track` carries —
/// what a file-info panel prints once it has asked `System.getPlayItemMetaDataString` for each one.
///
/// Every field is already the string a skin draws, so "we do not know" is `""`: a panel reads an
/// empty field as "nothing to show" and hides that whole line, which is exactly the right outcome
/// for a value we cannot answer honestly. Nothing here is ever faked to fill a line.
struct WinampModernTrackMetadata {
    var albumArtist = ""
    var composer = ""
    var genre = ""
    var comment = ""
    var year = ""
    var trackNumber = ""
    var discNumber = ""
    var bpm = ""
    /// Radio only. A station is what Winamp calls the "stream", and `streamTitle` is the ICY
    /// now-playing line, which changes *within* one track — see `trackMetadata`'s caching note.
    var streamName = ""
    var streamURL = ""
    var streamTitle = ""
    var streamGenre = ""

    static let empty = WinampModernTrackMetadata()
}

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
    /// The rest of the playing item's tags — see `WinampModernTrackMetadata`. Read through
    /// `playItemMetadata(forKey:)`, which is what maps a skin's key onto a field.
    var trackMetadata: WinampModernTrackMetadata { get }
    /// The playing track's rating in **stars, 0–5** — Winamp's own unit for
    /// `getCurrentTrackRating`/`setCurrentTrackRating`, and the same field NullPlayer's Library
    /// Browser draws in ART mode. `TrackRatingService` owns the conversion to the app's internal
    /// 0–10 scale and to each server's; nothing here should do arithmetic on it.
    ///
    /// 0 is "unrated", because that is what a star widget draws as an empty row — Winamp has no
    /// separate unrated value. Writing is a no-op for a source with nowhere to store it.
    var currentTrackRating: Int { get set }
    /// What a song ticker shows — Winamp's playlist display title, i.e. "Artist - Title".
    var trackDisplayTitle: String { get }
    /// Stream properties the skin's `songinfo` script parses out of `getSongInfoText()`.
    /// Zero means "unknown", which renders as the skin's own placeholder.
    var bitrateKbps: Int { get }
    var sampleRateHz: Int { get }
    var channelCount: Int { get }
    /// What `System.getDecoderName()` answers — Winamp names the input plugin that is decoding the
    /// current track ("Nullsoft MPEG Audio Decoder"), and skins print it as a *Decoder* readout. The
    /// honest equivalent here is the format NullPlayer is decoding, so the string is a codec name.
    /// Empty when nothing is loaded, which renders as the skin's own placeholder.
    var decoderName: String { get }
    /// The playing item's own location — what `getPlayItemMetaDataString("filename")` answers, and
    /// the string skins then hand to `getPath()`/`getExtension()` for a *File path* or *Format*
    /// readout. Display only: nothing in the seam opens a path a script hands back.
    var trackPath: String { get }
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

    /// The 576-sample waveform per channel a `<vis mode="2">` oscilloscope draws — Winamp's
    /// `visdata` format, `UInt8` centred on 128. **Not the spectrum**: a scope shows the wave itself,
    /// which is the whole point of the mode, and the band levels beside it cannot be reshaped into
    /// one. A host with no tap (the render harness, a test double) reads a flat centre line, so a
    /// scope still draws — as a straight line, which is what silence looks like.
    var waveformSamples: (left: [UInt8], right: [UInt8]) { get }

    /// Whether anything on screen is asking for that waveform. The tap is real-time audio work, so it
    /// stays off unless a skin actually declares a scope: the renderer recomputes this whenever the
    /// graph changes and pushes it here only when the answer moves. Idempotent.
    func setWaveformNeeded(_ needed: Bool)

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
    var waveformSamples: (left: [UInt8], right: [UInt8]) {
        (WinampModernWaveformTap.silence, WinampModernWaveformTap.silence)
    }
    func setWaveformNeeded(_ needed: Bool) {}
    var trackArtist: String { "" }
    var trackAlbum: String { "" }
    var trackMetadata: WinampModernTrackMetadata { .empty }
    // A host with nothing to rate (the render harness, a test double) reads unrated and swallows the
    // write, the way `balance` does — a star widget still draws, empty.
    var currentTrackRating: Int {
        get { 0 }
        set {}
    }
    var trackDisplayTitle: String { trackTitle }
    var bitrateKbps: Int { 0 }
    var sampleRateHz: Int { 0 }
    var channelCount: Int { 0 }
    var decoderName: String { "" }
    var trackPath: String { "" }
    func revealInFinder(_ path: String) {}
    func openExternally(_ path: String) {}

    /// `System.getPlayItemMetaDataString(key)` — one field of the playing item, as a string.
    ///
    /// Winamp's key set is open-ended and skins spell the same field several ways, so this is a
    /// table rather than four cases: Big Bento's file-info panel alone asks for eighteen keys and
    /// hides the line for every one that comes back `""`. It lives on the protocol so the render
    /// harness and any test double answer identically to the live host.
    ///
    /// The rule for an unanswerable key is `""`, never a placeholder — the panel then hides the
    /// line, which is what Winamp itself does with a field a file has no tag for.
    func playItemMetadata(forKey key: String) -> String {
        let metadata = trackMetadata
        switch key.lowercased() {
        case "title": return trackTitle
        case "artist": return trackArtist
        case "album": return trackAlbum
        case "albumartist", "album artist": return metadata.albumArtist
        case "composer": return metadata.composer
        case "genre": return metadata.genre
        case "comment": return metadata.comment
        case "year": return metadata.year
        // Winamp answers "-1" for an untagged track number and skins test for both that and `""`
        // (`if (l != "" && l != "-1")`). `""` satisfies every one of those tests; "-1" satisfies
        // only the skins that remember to check for it.
        case "track", "tracknumber": return metadata.trackNumber
        case "disc", "discnumber": return metadata.discNumber
        case "bpm": return metadata.bpm
        // The item's own location. `filepath` is the same field under Big Bento's spelling; the
        // panels split whichever they get with `getPath`/`getExtension`.
        case "filename", "filepath": return trackPath
        // Both readouts name the codec, which is the one thing we actually know about the format —
        // deliberately the same answer as `System.getDecoderName()` rather than a second, differently
        // derived string that could disagree with it on the same panel.
        case "format", "decoder": return decoderName
        // **Milliseconds**, which is the unit every caller pins: each one wraps this in
        // `integerToTime(stringToInteger(...))`, and `integerToTime` takes the same milliseconds
        // `System.getPosition()` and `System.getPlayItemLength()` answer in. The playlist-side
        // `getMetaData("length")` answers in the same unit.
        case "length": return duration > 0 ? String(WinampModernScriptRuntime.milliseconds(duration)) : ""
        case "bitrate": return bitrateKbps > 0 ? String(bitrateKbps) : ""
        case "srate", "samplerate": return sampleRateHz > 0 ? String(sampleRateHz) : ""
        // A flag, not a count — skins compare it to the literal "1" and print "Stereo"/"Mono".
        // Unknown stays `""`, which takes the same branch as mono but claims nothing.
        case "stereo": return channelCount > 0 ? (channelCount >= 2 ? "1" : "0") : ""
        // Written straight into a text object, so these are formatted rather than numeric.
        case "timeelapsed": return Self.clockString(currentTime)
        case "timeremaining": return duration > 0 ? Self.clockString(duration - currentTime) : ""
        case "streamname": return metadata.streamName
        case "streamurl": return metadata.streamURL
        case "streamtitle": return metadata.streamTitle
        case "streamgenre": return metadata.streamGenre
        // Stars, matching `getCurrentTrackRating()` — the same field under its other name, so a panel
        // that prints the number and a star row that draws it cannot disagree. Unrated is `""`, which
        // hides the line, rather than "0", which would read as a deliberate zero-star rating.
        case "rating": return currentTrackRating > 0 ? String(currentTrackRating) : ""
        // Answered empty on purpose, and listed rather than left to the default so the next reader
        // knows it was decided: NullPlayer stores no publisher tag, and `vbr` and `streamtype` are
        // things the engine never learns.
        case "publisher", "vbr", "streamtype": return ""
        default: return ""
        }
    }

    /// `m:ss`, or `h:mm:ss` past an hour — the shape `integerToTime` produces, since these strings
    /// go into a text object without passing through it.
    private static func clockString(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3_600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", total / 60, seconds)
    }

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

/// What a running video session answers for the readouts a `.wal` skin drives from playback: the
/// transport state, the clock and the title. Injected as a closure so the host can be exercised
/// without a `WindowManager`.
struct WinampModernVideoSession {
    var state: PlaybackState
    var currentTime: TimeInterval
    var duration: TimeInterval
    var title: String
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

    /// The oscilloscope's PCM. Lazy beside `levelMeter`, but unlike it **not** started with the rest
    /// of the visualization consumption: the waveform tap costs real-time audio work in
    /// `AudioEngine.processAudioBuffer`, and most skins draw an analyzer and never ask for it.
    /// `setWaveformNeeded` is what turns it on, from the renderer that found a `mode="2"` box.
    private lazy var waveformTap = WinampModernWaveformTap(consumerId: consumerID + ".waveform")
    private var isWaveformNeeded = false
    var waveformSamples: (left: [UInt8], right: [UInt8]) {
        isWaveformNeeded ? waveformTap.samples
            : (WinampModernWaveformTap.silence, WinampModernWaveformTap.silence)
    }

    func setWaveformNeeded(_ needed: Bool) {
        guard needed != isWaveformNeeded else { return }
        isWaveformNeeded = needed
        if needed { waveformTap.start() } else { waveformTap.stop() }
    }

    /// What the skin's window installs to hear that the audio went quiet — the one clock that can
    /// get a paused analyzer's bars and a scope's flat line actually *painted*
    /// (`WinampModernLevelMeter.onSilence`). On the host because the meter is the host's.
    var visualizationSilenceHandler: (() -> Void)? {
        get { levelMeter.onSilence }
        set { levelMeter.onSilence = newValue }
    }

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

    /// **A film is not the audio engine's clock.** `AudioEngine` is *paused* for the whole of a
    /// video session (`WindowManager.videoPlaybackDidStart`), so a host that answers only from it
    /// reports a `.wal` skin's transport as paused and its readout as 0:00 while the picture plays
    /// in plain sight — in cPro-Bento's own Video tab, where the film is the thing on screen.
    /// Classic and Original never had this because their views substitute
    /// `WindowManager.isVideoActivePlayback` at every draw; this is the same substitution, made once
    /// at the seam every `.wal` readout, script and `getPlayItemMetaDataString` key already goes
    /// through.
    ///
    /// Keyed on the video's **title**, not on `isVideoActivePlayback`: that property's
    /// `isVideoOutputVisible` term goes false the moment the picture is unparked, which is precisely
    /// the state a film left running behind another tab is in.
    var videoSession: () -> WinampModernVideoSession? = {
        let manager = WindowManager.shared
        guard let title = manager.currentVideoTitle else { return nil }
        return WinampModernVideoSession(state: manager.videoPlaybackState,
                                        currentTime: manager.videoCurrentTime,
                                        duration: manager.videoDuration,
                                        title: title)
    }

    var playbackState: PlaybackState { videoSession()?.state ?? engine.state }
    var currentTime: TimeInterval { videoSession()?.currentTime ?? engine.currentTime }
    var duration: TimeInterval { videoSession()?.duration ?? engine.duration }
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
    var trackTitle: String { videoSession()?.title ?? engine.currentTrack?.title ?? "" }
    var trackArtist: String { engine.currentTrack?.artist ?? "" }
    var trackAlbum: String { engine.currentTrack?.album ?? "" }
    /// The library row for the playing track, looked up once per track rather than once per key —
    /// a file-info panel asks for a dozen fields in a row, and each one would otherwise take the
    /// library's queue. Keyed by track id, so it drops when the track changes.
    private var libraryRowCache: (trackID: UUID, row: LibraryTrack?)?

    /// Everything a file-info panel prints beyond title/artist/album. `Track` carries only `genre`
    /// of these, so the tags come from the library row for the same file; a track with no row —
    /// a Plex/Jellyfin/Emby/Subsonic stream, a radio station, a file outside every watch folder —
    /// answers with what the `Track` itself knows and leaves the rest empty, which hides those
    /// lines instead of filling them with something invented.
    var trackMetadata: WinampModernTrackMetadata {
        guard let track = engine.currentTrack else { return .empty }
        let row = libraryRow(for: track)
        var metadata = WinampModernTrackMetadata()
        metadata.albumArtist = row?.albumArtist ?? ""
        metadata.composer = row?.composer ?? ""
        metadata.genre = row?.genre ?? track.genre ?? ""
        metadata.comment = row?.comment ?? ""
        metadata.year = row?.year.map(String.init) ?? ""
        metadata.trackNumber = row?.trackNumber.map(String.init) ?? ""
        metadata.discNumber = row?.discNumber.map(String.init) ?? ""
        metadata.bpm = row?.bpm.map(String.init) ?? ""
        // Read live, not cached with the row: the ICY now-playing line changes *during* a station's
        // playback, and the whole point of the `streamtitle` field is to follow it.
        if track.isRadioOrigin, let station = RadioManager.shared.currentStation {
            metadata.streamName = station.name
            metadata.streamURL = station.url.absoluteString
            metadata.streamGenre = station.genre ?? ""
            metadata.streamTitle = RadioManager.shared.currentMetadataTitle ?? ""
        }
        return metadata
    }

    /// The playing track's rating in stars, cached per track id.
    ///
    /// The cache is the whole mechanism, not an optimisation: a script reads this from a repaint, and
    /// only a local file can answer synchronously — every server source needs a request. So a miss
    /// answers with the local rating (0 for a server track), starts one fetch, and the arriving value
    /// both fills the cache and is announced to the skin through `currentTrackRatingChanged`, which is
    /// how a star row lights up a moment after a Plex track starts.
    private var ratingCache: (trackID: UUID, stars: Int)?
    private var ratingFetchTrackID: UUID?

    /// Raised when the rating for the playing track becomes known or is changed, so the runtime can
    /// fire `onCurrentTrackRated`. Set by the controller that owns the runtime.
    var currentTrackRatingChanged: ((Int) -> Void)?

    var currentTrackRating: Int {
        get {
            guard let track = engine.currentTrack else { return 0 }
            if let ratingCache, ratingCache.trackID == track.id { return ratingCache.stars }
            let stars = TrackRatingService.shared.localRating(for: track)
                .map(TrackRatingService.stars(fromRating:)) ?? 0
            ratingCache = (track.id, stars)
            fetchRatingIfNeeded(for: track)
            return stars
        }
        set {
            guard let track = engine.currentTrack else { return }
            let stars = max(0, min(5, newValue))
            // Store first: the widget that just wrote this expects to read it back immediately, and
            // the round trip to a server would otherwise let it snap back to its old position.
            ratingCache = (track.id, stars)
            let rating = TrackRatingService.rating(fromStars: stars)
            Task { try? await TrackRatingService.shared.setRating(stars > 0 ? rating : nil, for: track) }
            currentTrackRatingChanged?(stars)
        }
    }

    private func fetchRatingIfNeeded(for track: Track) {
        // Only a source that has to be asked, and only once per track — the local answer above is
        // already final for a file.
        guard track.plexRatingKey != nil || track.subsonicId != nil
            || track.jellyfinId != nil || track.embyId != nil else { return }
        guard ratingFetchTrackID != track.id else { return }
        ratingFetchTrackID = track.id
        Task { @MainActor [weak self] in
            let rating = await TrackRatingService.shared.rating(for: track)
            guard let self, self.engine.currentTrack?.id == track.id else { return }
            let stars = rating.map(TrackRatingService.stars(fromRating:)) ?? 0
            guard self.ratingCache?.stars != stars else { return }
            self.ratingCache = (track.id, stars)
            self.currentTrackRatingChanged?(stars)
        }
    }

    private func libraryRow(for track: Track) -> LibraryTrack? {
        if let libraryRowCache, libraryRowCache.trackID == track.id { return libraryRowCache.row }
        // Only a local file can have one — the library is keyed by path, and a server or stream URL
        // never matches. The miss is cached too, so a stream does not re-ask on every field.
        let row = track.url.isFileURL ? MediaLibrary.shared.findTrack(byURL: track.url) : nil
        libraryRowCache = (track.id, row)
        return row
    }

    var trackDisplayTitle: String {
        guard let track = engine.currentTrack else { return "" }
        guard let artist = track.artist, !artist.isEmpty else { return track.title }
        return "\(artist) - \(track.title)"
    }
    var bitrateKbps: Int { engine.currentTrack?.bitrate ?? 0 }
    var sampleRateHz: Int { engine.currentTrack?.sampleRate ?? 0 }
    var channelCount: Int { engine.currentTrack?.channels ?? 0 }

    /// The codec, from the track's own extension — the only thing available without opening the file
    /// again, and the same thing Winamp's readout is really telling the user. A stream with no
    /// recognisable extension answers with its scheme's transport ("HTTP Stream"), which is what the
    /// Decoder line says in Winamp for a radio station.
    var decoderName: String {
        guard let url = engine.currentTrack?.url else { return "" }
        let named = Self.codecNames[url.pathExtension.lowercased()]
        if let named { return named }
        return url.isFileURL ? url.pathExtension.uppercased() : "HTTP Stream"
    }

    var trackPath: String {
        guard let url = engine.currentTrack?.url else { return "" }
        return url.isFileURL ? url.path : url.absoluteString
    }

    private static let codecNames: [String: String] = [
        "mp3": "MPEG Audio", "m4a": "AAC", "aac": "AAC", "mp4": "AAC", "m4b": "AAC",
        "flac": "FLAC", "ogg": "Vorbis", "oga": "Vorbis", "opus": "Opus",
        "wav": "PCM Wave", "aiff": "AIFF", "aif": "AIFF", "caf": "Core Audio",
        "wma": "Windows Media", "ape": "Monkey's Audio", "wv": "WavPack", "alac": "ALAC",
    ]

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
        setWaveformNeeded(false)
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
