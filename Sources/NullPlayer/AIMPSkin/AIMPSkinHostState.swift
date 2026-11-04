import CoreGraphics
import CoreText
import Foundation

/// What a frame and the skin's scripts read beyond the skin's own state, in three parts by owner:
/// the player (`player`, the engine's snapshot), what the window drawing the frame adds of its own
/// (`feedback`: its clock, meters and pointer, and what its last frame measured), and the quick
/// search's matches (`playlistMatches`, the runtime's cache).
struct AIMPSkinHostState: Sendable {
    var player = AIMPSkinPlayerSnapshot()
    var feedback = AIMPSkinFrameFeedback()
    /// The quick search's matches, worked out once by the runtime when the playlist or the search
    /// changes: the window asks every frame.
    var playlistMatches: PlaylistMatches?

    struct PlaylistMatches: Equatable, Sendable {
        let search: String
        let indices: [Int]
    }

    /// The rows a quick search leaves, as indices into the playlist: those holding every word of
    /// it, any case; all of them with no search.
    func playlistIndices(matching search: String) -> [Int] {
        let rows = player.playlist.rows
        let words = search.lowercased().split(separator: " ")
        guard !words.isEmpty else { return Array(rows.indices) }
        if let playlistMatches, playlistMatches.search == search { return playlistMatches.indices }
        return rows.indices.filter { index in
            let title = rows[index].title.lowercased()
            return words.allSatisfy { title.contains($0) }
        }
    }

    /// A player provider's pin (`AIMPSkinSource.PlayerPin`), nil for anything else (the skin's own
    /// providers are `AIMPSkinDataflow`'s).
    func pin(_ source: String, _ pin: String) -> Double? {
        AIMPSkinSource.PlayerPin(source, pin).map(value)
    }

    /// A player pin's value: 0–100 for the volume, balance and progress as bindings read them,
    /// seconds for times, 1 or 0 for switches.
    func value(_ pin: AIMPSkinSource.PlayerPin) -> Double {
        let player = self.player
        switch pin {
        case .volumeFraction: return player.volume
        case .volume: return player.volume * 100
        case .balance: return player.balance * 100
        case .playState: return Double(player.playState.rawValue)
        case .timeOfDay: return Double(player.timeOfDay)
        case .duration: return Double(player.durationSeconds)
        case .elapsed: return Double(player.elapsedSeconds)
        case .progress: return player.position * 100
        case .hasCoverArt: return player.coverArt == nil ? 0 : 1
        case .playlistCount: return Double(player.playlist.rows.count)
        case .playlistDuration: return Double(player.playlist.rows.reduce(0) { $0 + $1.seconds })
        case .playlistSize: return Double(player.playlist.rows.reduce(Int64(0)) { $0 + $1.bytes })
        case .bitrate: return Double(player.bitrate)
        // In kHz: Sony Media Tower labels it so.
        case .sampleRate: return Double(player.sampleRate / 1_000)
        case .channels: return Double(player.channels)
        case .rating: return Double(player.rating ?? 0)
        case .ratingAvailable: return player.rating == nil ? 0 : 1
        case .clockFlash: return Double(player.timeOfDay % 2)
        case .tracksStarted: return Double(player.tracksStarted)
        case .tracksFinished: return Double(player.tracksFinished)
        case .remaining: return Double(max(0, player.durationSeconds - player.elapsedSeconds))
        case .sleepTimer: return 0
        // AIMP's level runs to about 145 (Cassette-3D scales it by 0.69 to its 0–100 gauge).
        case .levelL: return feedback.levelL * 145
        case .levelR: return feedback.levelR * 145
        case .nightMode: return player.nightMode ? 1 : 0
        case .shuffle: return player.shuffle ? 1 : 0
        case .repeatAll: return player.repeatAll ? 1 : 0
        case .stayOnTop: return player.stayOnTop ? 1 : 0
        case .muted: return player.muted ? 1 : 0
        case .equalizerOn: return player.eqEnabled ? 1 : 0
        case .window(let role): return role.isOpen(in: player) ? 1 : 0
        }
    }
}

/// The player, as the window fills it from `AudioEngine` (`AIMPSkinAudioEngineHost.snapshot`): an
/// idle one by default, nothing loaded and every control at rest. The probe fills its own.
struct AIMPSkinPlayerSnapshot: Equatable, Sendable {
    enum PlayState: Int, Sendable {
        case stopped = 0, playing = 1, paused = 2
    }

    var title = ""
    var artist = ""
    var album = ""
    /// The playing file's details, for info pages (`%Y`, `%B`, `%H`, `%C`, `%S`, `%G`) and its
    /// rating (0–5; nil when the library has none for it).
    var year = 0
    var bitrate = 0
    var sampleRate = 0
    var channels = 0
    var fileSize: Int64 = 0
    var genre = ""
    var rating: Int?
    /// The file's type, as AIMP's `%E` gives it (`MP3`, `FLAC`).
    var fileType = ""
    var playState = PlayState.stopped
    /// 0…1.
    var volume = 0.7
    /// 0…1, the playback position seek bars show.
    var position = 0.0
    var elapsedSeconds = 0
    var durationSeconds = 0
    /// Seconds since local midnight, for clock displays.
    var timeOfDay = 0
    /// 0…1, left to right.
    var balance = 0.5
    /// 0…1, for every other bound value (effects): the middle, unless a knob has been turned
    /// (`otherValues`: NullPlayer has no TrueBass or flanger, so the knob only keeps its place).
    var otherValue = 0.5
    var otherValues: [String: Double] = [:]
    /// The system's dark appearance, as AIMP's `NightMode` reads Windows': the theme a modern skin
    /// picks when left on automatic (Tascam Fireone's, Soot's).
    var nightMode = false
    var shuffle = false
    var repeatAll = false
    var stayOnTop = false
    var muted = false
    var eqEnabled = false
    var playlistVisible = false
    var libraryVisible = false
    /// How many tracks have started and finished, for `OnTrackStarted`/`OnTrackFinished` handlers.
    var tracksStarted = 0
    var tracksFinished = 0
    var equalizerVisible = false
    var visualizationVisible = false
    /// The equalizer: each NullPlayer band's gain and the preamp, 0…1 over −12…+12 dB. AIMP's band
    /// sliders are spread over the bands (`eqBand`).
    var eqGains = Array(repeating: 0.5, count: 10)
    var preamp = 0.5
    /// The playback speed, 0…1 over 0.5×…1.5×: the middle is normal speed.
    var speed = 0.5
    /// The playing track's artwork, for cover-art displays (SL-1200's record label).
    var coverArt: CGImage?
    /// NullPlayer's playlist, for a skin's own playlist (Akai GX-F90's screen), and the playing row.
    var playlist = Playlist()
    var playlistIndex = -1
    /// NullPlayer's music library, for a skin's own library window, and whether it is scanning.
    var library: AIMPSkinLibrary?
    var libraryScanning = false

    /// The playlist's rows, and which build of them they are: a snapshot is taken about ten times
    /// a second and compared with the last, so two playlists are the same when their builds are,
    /// not row by row.
    struct Playlist: Equatable, Sendable {
        struct Row: Equatable, Sendable {
            var title: String
            var seconds: Int
            var bytes: Int64 = 0
        }

        var rows: [Row] = []
        /// Moves whenever the rows do.
        var generation = 0

        static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs.generation == rhs.generation }
    }

    /// The NullPlayer band at the same place along the scale as AIMP band `n`: AIMP 4 has 18
    /// (`Band1`–`Band18`), AIMP 5 has 20 (`Band0`–`Band19`); a ten-band NullPlayer EQ takes them in pairs.
    func eqBand(aimp n: Int, aimp5: Bool) -> Int? {
        guard eqGains.count > 1 else { return nil }
        let (first, count) = aimp5 ? (0, 20) : (1, 18)
        let fraction = Double(min(max(n - first, 0), count - 1)) / Double(count - 1)
        return Int((fraction * Double(eqGains.count - 1)).rounded())
    }

    /// The value a control bound to this data provider shows.
    func value(for provider: AIMPSkinProvider?) -> Double {
        switch provider {
        case .volume: return volume
        case .balance: return balance
        case .position: return position
        case .preamp: return preamp
        case .speed: return speed
        case .equalizerBand(let band): return eqGains.indices.contains(band) ? eqGains[band] : 0.5
        case .named(let name): return otherValues[name] ?? otherValue
        case nil: return otherValue
        }
    }
}

/// What the window drawing a frame adds to the player's snapshot: the clock it draws at, its meters,
/// and what its last frame showed (`AIMPSkinRuntime.host(drawnBy:clock:)`). Empty for a script run outside a
/// frame (a click's handler); the probe's still renders set meters and a spectrum of their own.
struct AIMPSkinFrameFeedback: Sendable {
    /// Seconds on a free-running clock, for animators and timers.
    var clock = 0.0
    /// 0…1 output level per channel, for meters, and the spectrum, 0…1 per band, for
    /// visualization handlers and spectrum displays.
    var levelL = 0.0
    var levelR = 0.0
    var spectrum: [Double] = []
    /// Where the pointer is, in skin pixels, and where each named item and control was last drawn:
    /// `IsActive` is the pointer over one (Cassette-3D's keys show while it is over the cassette).
    var pointer = Pointer.anywhere

    enum Pointer: Sendable, Equatable {
        /// No pointer to go by (the probe, a measure of everything it reveals): everything reads active.
        case anywhere
        /// Outside the window: nothing is under it.
        case outside
        case at(CGPoint)
    }
    var hoverRects: [String: CGRect] = [:]
    /// How many rows the skin's playlist showed in the last frame, for `Playlist.Scrolling`: nil
    /// before it has been drawn.
    var playlistRowsShown: Int?
    /// Where each gauge's needle or bar stands, 0–100, as the window eases it after its value
    /// (`ReactionSpeedLevelUp`/`Down`); a gauge not here shows its value as it is.
    var gaugeLevels: [AIMPSkinControl.ID: Double] = [:]
}
