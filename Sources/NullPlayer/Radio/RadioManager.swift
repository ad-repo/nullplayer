import Foundation
import AppKit

/// Singleton managing internet radio station connections and state
class RadioManager {
    static weak var cliAudioEngine: AudioEngine?

    private var resolvedAudioEngine: AudioEngine {
        if AudioEngine.isHeadless, let cliEngine = RadioManager.cliAudioEngine {
            return cliEngine
        }
        return WindowManager.shared.audioEngine
    }

    private struct SomaChannelsResponse: Decodable {
        let channels: [SomaChannel]
    }

    private struct SomaChannel: Decodable {
        let id: String
        let lastPlaying: String?
    }
    
    // MARK: - Singleton
    
    static let shared = RadioManager()
    
    // MARK: - Notifications
    
    static let stationsDidChangeNotification = Notification.Name("RadioStationsDidChange")
    static let streamMetadataDidChangeNotification = Notification.Name("RadioStreamMetadataDidChange")
    static let connectionStateDidChangeNotification = Notification.Name("RadioConnectionStateDidChange")
    
    // MARK: - Station State
    
    /// All saved radio stations
    private(set) var stations: [RadioStation] = [] {
        didSet {
            saveStations()
            NotificationCenter.default.post(name: Self.stationsDidChangeNotification, object: self)
        }
    }
    
    /// Currently playing radio station (nil if not playing radio)
    private(set) var currentStation: RadioStation? {
        didSet {
            if oldValue?.id != currentStation?.id {
                currentStreamTitle = nil
                currentSomaLastPlaying = nil
                stopSomaMetadataPolling()
                reconnectAttempts = 0
            }
        }
    }
    
    // MARK: - Stream Metadata
    
    /// Current stream title from ICY metadata (e.g., "Artist - Song")
    private(set) var currentStreamTitle: String? {
        didSet {
            if oldValue != currentStreamTitle {
                publishStreamMetadataChangeIfNeeded()
                if currentStreamTitle != nil {
                    stopSomaMetadataPolling()
                }
            }
        }
    }

    /// The current stream metadata title (song name / show info); ICY metadata first, then SomaFM fallback.
    var currentMetadataTitle: String? { currentStreamTitle ?? currentSomaLastPlaying }

    /// Fallback title from SomaFM channels API (`lastPlaying`) when ICY metadata is missing.
    private(set) var currentSomaLastPlaying: String? {
        didSet {
            if oldValue != currentSomaLastPlaying {
                publishStreamMetadataChangeIfNeeded()
            }
        }
    }
    
    // MARK: - Connection State
    
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case failed(message: String)
        
        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected): return true
            case (.connecting, .connecting): return true
            case (.connected, .connected): return true
            case (.reconnecting(let a), .reconnecting(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }
    
    private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            NotificationCenter.default.post(name: Self.connectionStateDidChangeNotification, object: self)
        }
    }
    
    // MARK: - Auto-Reconnect
    
    /// Whether auto-reconnect is enabled (default: true)
    var autoReconnectEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "RadioAutoReconnect") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "RadioAutoReconnect") }
    }
    
    /// Maximum number of reconnect attempts
    let maxReconnectAttempts = 5
    
    /// Current reconnect attempt count
    private var reconnectAttempts = 0
    
    /// Timer for reconnect delay
    private var reconnectTimer: Timer?

    /// Poll timer for SomaFM metadata fallback when stream ICY metadata is unavailable.
    private var somaMetadataTimer: Timer?

    private var somaMetadataRequestInFlight = false
    private var lastPublishedStreamTitle: String?

    private let somaChannelsURL = URL(string: "https://somafm.com/channels.json")!
    private let somaMetadataPollInterval: TimeInterval = 45
    
    /// Whether a manual stop was requested (don't auto-reconnect)
    private var manualStopRequested = false
    
    // MARK: - UserDefaults Keys
    
    private let stationsKey = "RadioStations"
    private let deletedDefaultsKey = "RadioDeletedDefaults"
    private let smartGenreOverridesKey = "RadioSmartGenreOverrides"
    private let smartRegionOverridesKey = "RadioSmartRegionOverrides"
    private let defaultGenreMigrationVersionKey = "RadioDefaultGenreMigrationVersion"
    private let defaultURLMigrationVersionKey = "RadioDefaultURLMigrationVersion"
    private static let defaultURLAliases: [String: String] = [
        "https://wgbh-live.streamguys1.com/wgbh": "https://wgbh-live.streamguys1.com/wgbh.mp3",
        "https://wgbh-live.streamguys1.com/wgbh.mp3": "https://wgbh-live.streamguys1.com/wgbh"
    ]
    private static let channelSourceURLs: [String: Set<String>] = [
        "Audiophile.fm": Set([
            "https://admin.biasradio.com/listen/bias_radio/flac",
            "https://admin.biasradio.com/listen/bias_radio/live",
            "https://amp.cesnet.cz:8443/cro3.flac",
            "https://amp1.cesnet.cz:8443/cro-d-dur.flac",
            "https://amp1.cesnet.cz:8443/cro-jazz.flac",
            "https://amp1.cesnet.cz:8443/cro-radio-wave.flac",
            "https://audio-edge-cmc51.fra.h.radiomast.io/radioblues-flac",
            "https://audio.opensky.radio:8082/flac",
            "https://audio.opensky.radio:8082/oise",
            "https://azura.wbor.org/listen/wbor/flac",
            "https://azura.wbor.org/listen/wbor/stream",
            "https://bcast.vigormultimedia.com:48888/sjcompl320mp3",
            "https://bcast.vigormultimedia.com:48888/sjcomplflac",
            "https://blueswave.radio:8002/blues320",
            "https://blueswave.radio:8100/FlacBlues",
            "https://cdn05.radio.cloud:8128/AIDA-OMNIA-GAI",
            "https://cdn06-us-east.radio.cloud/80ba63862a97bd69c593cc7a2ccaab1c_hq",
            "https://cdn1.zetcast.net/flac",
            "https://cdn1.zetcast.net/stream",
            "https://dancewave.online/dance.flac.ogg",
            "https://dancewave.online/dance.mp3",
            "https://edge2.sr.se/p2-flac",
            "https://edge62.streamonkey.net/aidaradio-meergefuehl",
            "https://futura.fm/stream.ogg",
            "https://gmusto.radioca.st/mp3",
            "https://http-live.sr.se/p2musik-aac-320",
            "https://ice.radiorandom.org/WBJM",
            "https://ice.radiorandom.org/WBJM-FLAC",
            "https://icecast.centaury.cl:7550/SuperStereo1",
            "https://icecast.centaury.cl:7550/SuperStereo1Plus",
            "https://icecast.centaury.cl:7550/SuperStereo2",
            "https://icecast.centaury.cl:7550/SuperStereo3",
            "https://icecast.centaury.cl:7550/SuperStereo3Plus",
            "https://icecast.centaury.cl:7550/SuperStereo4",
            "https://icecast.centaury.cl:7550/SuperStereo4Plus",
            "https://icecast.centaury.cl:7550/SuperStereo5",
            "https://icecast.centaury.cl:7550/SuperStereo6",
            "https://icecast.centaury.cl:7550/SuperStereo7",
            "https://icecast.centaury.cl:7570/SuperStereoHiRes1",
            "https://icecast.centaury.cl:7570/SuperStereoHiRes1Plus",
            "https://icecast.centaury.cl:7570/SuperStereoHiRes2",
            "https://icecast.centaury.cl:7570/SuperStereoHiRes3",
            "https://icecast.centaury.cl:7570/SuperStereoHiRes3Plus",
            "https://icecast.centaury.cl:7570/SuperStereoHiRes4",
            "https://icecast.centaury.cl:7570/SuperStereoHiRes4Plus",
            "https://icecast.centaury.cl:7570/SuperStereoHiRes5",
            "https://icecast.centaury.cl:7570/SuperStereoHiRes6",
            "https://icecast.centaury.cl:7570/SuperStereoHiRes7",
            "https://icecast.radiosega.net/live",
            "https://icecast.radiosega.net/rs-flac.ogg",
            "https://iradio.fi/klasu-hi.mp3",
            "https://iradio.fi/klasu.flac",
            "https://iradio.fi/klasupro-hi.mp3",
            "https://iradio.fi/klasupro.flac",
            "https://listen.teknivalradio.com/listen/teknivalradio/radio.flac",
            "https://listen.teknivalradio.com/listen/teknivalradio/radio.mp3",
            "https://live.easyradio.bg/aac?type=.mp3",
            "https://live.easyradio.bg/flac",
            "https://manager.dhectar.fr:1065/stream",
            "https://manager.dhectar.fr:1080/stream",
            "https://mediacp.jb-radio.net:8001/aac",
            "https://mediacp.jb-radio.net:8001/flac",
            "https://mp3.magic-radio.net/320",
            "https://mp3.magic-radio.net/flac",
            "https://mscp3.live-streams.nl:8252/class-flac.flac",
            "https://mscp3.live-streams.nl:8252/class-high.aac",
            "https://mscp3.live-streams.nl:8342/jazz-flac.flac",
            "https://mscp3.live-streams.nl:8342/jazz-high.aac",
            "https://mscp3.live-streams.nl:8362/flac.flac",
            "https://mscp3.live-streams.nl:8362/high.aac",
            "https://mscp4.live-streams.nl:8142/flac.ogg",
            "https://mscp4.live-streams.nl:8142/live.mp3",
            "https://mscp4.live-streams.nl:8142/lounge.mp3",
            "https://mscp4.live-streams.nl:8142/lounge.ogg",
            "https://online.jamminvibezradio.com/listen/caribbean/live.flac",
            "https://online.jamminvibezradio.com/listen/caribbean/stream",
            "https://online.jamminvibezradio.com/listen/christmas/live.flac",
            "https://online.jamminvibezradio.com/listen/christmas/stream",
            "https://online.jamminvibezradio.com/listen/oldies/live.flac",
            "https://online.jamminvibezradio.com/listen/oldies/stream",
            "https://online.jamminvibezradio.com/listen/reggae/live.flac",
            "https://online.jamminvibezradio.com/listen/reggae/stream",
            "https://radio.lapfoxradio.com/radio/8000/stream-flac.flac",
            "https://radio.lapfoxradio.com/radio/8000/stream-mp3-320.mp3",
            "https://radio3.radio-calico.com:8443/calico",
            "https://radio3.radio-calico.com:8443/calico.mp3",
            "https://radioemisoras.cl/distorsion.flac",
            "https://radioemisoras.cl/distorsion.mp3",
            "https://radiosputnik.nl:8443",
            "https://radiosputnik.nl:8443/flac",
            "https://radiotalas.dckrov.rs/listen/dckrov/aac",
            "https://radiotalas.dckrov.rs/listen/dckrov/flac",
            "https://retro.dancewave.online/retrodance.flac.ogg",
            "https://retro.dancewave.online/retrodance.mp3",
            "https://rozhlas.stream/ddur.mp3",
            "https://rozhlas.stream/jazz.mp3",
            "https://rozhlas.stream/radio_wave.mp3",
            "https://rozhlas.stream/vltava.mp3",
            "https://s2.audiostream.hu/bdpstrock_320k",
            "https://s2.audiostream.hu/bdpstrock_FLAC",
            "https://s2.audiostream.hu/juventus_320k",
            "https://s2.audiostream.hu/juventus_FLAC",
            "https://s2.audiostream.hu/roxy_320k",
            "https://s2.audiostream.hu/roxy_FLAC",
            "https://secure.live-streams.nl/flac.ogg",
            "https://secure.live-streams.nl/live",
            "https://station.thecheese.co.nz/listen/the_cheese/aac",
            "https://station.thecheese.co.nz/listen/the_cheese/flac",
            "https://stream.and-stuff.nl:8443/riverside",
            "https://stream.and-stuff.nl:8443/riversideMp3",
            "https://stream.danubiusradio.hu/danubius_320k",
            "https://stream.danubiusradio.hu/danubius_HiFi",
            "https://stream.motherearthradio.de/listen/motherearth/motherearth",
            "https://stream.motherearthradio.de/listen/motherearth/motherearth.aac",
            "https://stream.motherearthradio.de/listen/motherearth_instrumental/motherearth.instrumental",
            "https://stream.motherearthradio.de/listen/motherearth_instrumental/motherearth.instrumental.aac",
            "https://stream.motherearthradio.de/listen/motherearth_jazz/motherearth.jazz",
            "https://stream.motherearthradio.de/listen/motherearth_jazz/motherearth.jazz.mp4",
            "https://stream.motherearthradio.de/listen/motherearth_klassik/motherearth.klassik",
            "https://stream.motherearthradio.de/listen/motherearth_klassik/motherearth.klassik.aac",
            "https://stream.openbroadcast.ch/16bit.flac",
            "https://stream.openbroadcast.ch/320.mp3",
            "https://stream.p-node.org/piano.flac",
            "https://stream.p-node.org/piano.mp3",
            "https://stream.radio90.fm:2002/stream",
            "https://stream.radio90.fm:2002/web",
            "https://stream.radiobergeijk.nl/listen/radio_bergeijk/flac",
            "https://stream.radiobergeijk.nl/listen/radio_bergeijk/mp3",
            "https://stream.radioclub80.cl:8002/clasicos80.flac",
            "https://stream.radioclub80.cl:8002/clasicos80.mp3",
            "https://stream.radioclub80.cl:8012/espanol80.flac",
            "https://stream.radioclub80.cl:8012/live.mp3",
            "https://stream.radioclub80.cl:8022/retro80.flac",
            "https://stream.radioclub80.cl:8022/retro80.mp3",
            "https://stream.radioclub80.cl:8032/stream.euro80flac",
            "https://stream.radioclub80.cl:8032/stream.euro80mp3",
            "https://stream.radioclub80.cl:8042/baladas80.flac",
            "https://stream.radioclub80.cl:8042/baladas80.mp3",
            "https://stream.radioclub80.cl:8052/trance80.flac",
            "https://stream.radioclub80.cl:8052/trancelive80.mp3",
            "https://stream.radioenergy.to/stream",
            "https://stream.radioparadise.com/aac-320",
            "https://stream.radioparadise.com/beyond-320",
            "https://stream.radioparadise.com/beyond-flac",
            "https://stream.radioparadise.com/flac",
            "https://stream.radioparadise.com/global-320",
            "https://stream.radioparadise.com/global-flac",
            "https://stream.radioparadise.com/mellow-320",
            "https://stream.radioparadise.com/mellow-flac",
            "https://stream.radioparadise.com/radio2050-320",
            "https://stream.radioparadise.com/radio2050-flac",
            "https://stream.radioparadise.com/rock-320",
            "https://stream.radioparadise.com/rock-flac",
            "https://stream.rcs.revma.com/vbp5ag77xs3vv",
            "https://stream.rjrradio.fr/rjr-dab.flac",
            "https://stream.rjrradio.fr/rjr.mp3",
            "https://stream.trance.ie/stream",
            "https://stream.trance.ie/tpmixes",
            "https://stream10.xdevel.com/audio13s976748-2017/stream/icecast.audio",
            "https://stream10.xdevel.com/audio15s976748-2280/stream/icecast.audio",
            "https://stream10.xdevel.com/audio17s976748-2218/stream/icecast.audio",
            "https://stream9.xdevel.com/audio1s976748-1515/stream/icecast.audio",
            "https://streams.95bfm.com/stream112",
            "https://streams.95bfm.com/stream95",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_dance_channel/flac",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_dance_channel/ultra",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_dj_r.i.ps_podcast/flac",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_dj_r.i.ps_podcast/ultra",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_downtempo_channel/flac",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_downtempo_channel/ultra",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_hardcore_channel/flac",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_hardcore_channel/ultra",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_live-party_channel/flac",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_live-party_channel/ultra",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_rap__hip-hop_channel/flac",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_rap__hip-hop_channel/ultra",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_trance-electro_channel/flac",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_trance-electro_channel/ultra",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_various_channel/flac",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_-_various_channel/ultra",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_the_underground_channel/flac",
            "https://streamserver.pure-isp.eu/listen/pure_radio_holland_the_underground_channel/ultra",
            "https://tuneintoradio1.com/listen/vfr_80s/radio.mp3",
            "https://tuneintoradio1.com/listen/vfr_80s/stream.flac",
            "https://tuneintoradio1.com/listen/violent_forces_radio/radio.mp3",
            "https://tuneintoradio1.com/listen/violent_forces_radio/stream.flac",
            "https://www.streamvortex.com:8444/s/10280",
        ])
    ]
    private static let channelHostAliases: [String: String] = [
        "somafm.com": "SomaFM",
        "radioparadise.com": "Radio Paradise",
        "nightride.fm": "Nightride FM",
        "ntslive.net": "NTS",
        "kcrw.com": "KCRW",
        "wfmu.org": "WFMU",
        "streamguys1.com": "StreamGuys",
        "1.fm": "1.FM"
    ]
    private let ratingsStore = RadioStationRatingsStore.shared
    private let foldersStore = RadioStationFoldersStore.shared
    private static let defaultURLMigrationCurrentVersion = 2
    private static let removedDefaultStationURLs: Set<String> = [
        "https://stream.radioparadise.com/rock-flac",
        "https://audio-edge-cmc51.fra.h.radiomast.io/radioblues-flac"
    ]
    
    /// URLs of default stations the user has intentionally deleted (won't be re-added)
    private var deletedDefaultURLs: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: deletedDefaultsKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: deletedDefaultsKey)
        }
    }
    
    /// Check if a URL is a default station URL
    private func isDefaultStationURL(_ url: URL) -> Bool {
        Self.defaultStations.contains { areEquivalentStationURLs($0.url, url) }
    }

    private func areEquivalentStationURLs(_ lhs: URL, _ rhs: URL) -> Bool {
        if lhs == rhs { return true }
        let left = lhs.absoluteString
        let right = rhs.absoluteString
        return Self.defaultURLAliases[left] == right || Self.defaultURLAliases[right] == left
    }

    private var smartGenreOverrides: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: smartGenreOverridesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: smartGenreOverridesKey) }
    }

    private var smartRegionOverrides: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: smartRegionOverridesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: smartRegionOverridesKey) }
    }

    private func equivalentURLKeys(for url: URL) -> Set<String> {
        var keys: Set<String> = [url.absoluteString]
        if let alias = Self.defaultURLAliases[url.absoluteString] {
            keys.insert(alias)
        }
        for (key, value) in Self.defaultURLAliases where value == url.absoluteString {
            keys.insert(key)
        }
        return keys
    }

    private func normalizedOverrideLabel(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func overrideValue(for url: URL, in map: [String: String]) -> String? {
        for key in equivalentURLKeys(for: url) {
            if let value = normalizedOverrideLabel(map[key]) {
                return value
            }
        }
        return nil
    }

    private func setOverrideValue(_ value: String?, for url: URL, in map: inout [String: String]) -> Bool {
        let normalized = normalizedOverrideLabel(value)
        let keys = equivalentURLKeys(for: url)
        var changed = false
        for key in keys {
            let old = map[key]
            if let normalized {
                if old != normalized {
                    map[key] = normalized
                    changed = true
                }
            } else if map.removeValue(forKey: key) != nil {
                changed = true
            }
        }
        return changed
    }

    private func clearSmartFolderOverrides(for url: URL) {
        var genres = smartGenreOverrides
        var regions = smartRegionOverrides
        let genreChanged = setOverrideValue(nil, for: url, in: &genres)
        let regionChanged = setOverrideValue(nil, for: url, in: &regions)
        if genreChanged { smartGenreOverrides = genres }
        if regionChanged { smartRegionOverrides = regions }
    }

    private func moveSmartFolderOverrides(from oldURL: URL, to newURL: URL) {
        guard oldURL != newURL else { return }
        let oldGenre = overrideValue(for: oldURL, in: smartGenreOverrides)
        let oldRegion = overrideValue(for: oldURL, in: smartRegionOverrides)

        var genres = smartGenreOverrides
        var regions = smartRegionOverrides
        _ = setOverrideValue(nil, for: oldURL, in: &genres)
        _ = setOverrideValue(nil, for: oldURL, in: &regions)
        _ = setOverrideValue(oldGenre, for: newURL, in: &genres)
        _ = setOverrideValue(oldRegion, for: newURL, in: &regions)

        smartGenreOverrides = genres
        smartRegionOverrides = regions
    }

    /// Combined stream title used by UI: ICY metadata first, then Soma fallback.
    private var effectiveStreamTitle: String? {
        currentStreamTitle ?? currentSomaLastPlaying
    }

    private func publishStreamMetadataChangeIfNeeded() {
        let streamTitle = effectiveStreamTitle
        guard streamTitle != lastPublishedStreamTitle else { return }
        lastPublishedStreamTitle = streamTitle
        NotificationCenter.default.post(
            name: Self.streamMetadataDidChangeNotification,
            object: self,
            userInfo: streamTitle.map { ["streamTitle": $0] }
        )
    }
    
    // MARK: - Initialization
    
    private init() {
        loadStations()
    }
    
    // MARK: - Station Persistence
    
    private func loadStations() {
        guard let data = UserDefaults.standard.data(forKey: stationsKey),
              let decoded = try? JSONDecoder().decode([RadioStation].self, from: data) else {
            // Add some default stations for first-time users
            UserDefaults.standard.set(Self.defaultGenreMigrationCurrentVersion, forKey: defaultGenreMigrationVersionKey)
            UserDefaults.standard.set(Self.defaultURLMigrationCurrentVersion, forKey: defaultURLMigrationVersionKey)
            stations = Self.defaultStations
            return
        }
        var migrated = decoded
        let changedByURLMigration = applyDefaultURLMigrationIfNeeded(to: &migrated)
        let changedByMigration = applyDefaultGenreMigrationIfNeeded(to: &migrated)
        stations = migrated
        NSLog("RadioManager: Loaded %d saved stations", stations.count)
        if changedByURLMigration > 0 {
            NSLog("RadioManager: Migrated %d saved station URLs to latest defaults", changedByURLMigration)
        }
        if changedByMigration > 0 {
            NSLog("RadioManager: Migrated %d saved station genres to latest defaults", changedByMigration)
        }

        // Ensure existing users receive newly added defaults while still honoring
        // deleted-default tracking.
        addMissingDefaults()
    }
    
    private func saveStations() {
        guard let data = try? JSONEncoder().encode(stations) else { return }
        UserDefaults.standard.set(data, forKey: stationsKey)
    }

    @discardableResult
    private func applyDefaultURLMigrationIfNeeded(to stations: inout [RadioStation]) -> Int {
        let defaults = UserDefaults.standard
        let appliedVersion = defaults.integer(forKey: defaultURLMigrationVersionKey)
        guard appliedVersion < Self.defaultURLMigrationCurrentVersion else { return 0 }

        let migration = Self.applyingDefaultURLCorrections(to: stations)
        if migration.changedCount > 0 {
            stations = migration.stations
        }

        defaults.set(Self.defaultURLMigrationCurrentVersion, forKey: defaultURLMigrationVersionKey)
        return migration.changedCount
    }

    @discardableResult
    private func applyDefaultGenreMigrationIfNeeded(to stations: inout [RadioStation]) -> Int {
        let defaults = UserDefaults.standard
        let appliedVersion = defaults.integer(forKey: defaultGenreMigrationVersionKey)
        guard appliedVersion < Self.defaultGenreMigrationCurrentVersion else { return 0 }

        let migration = Self.applyingDefaultGenreCorrections(to: stations)
        if migration.changedCount > 0 {
            stations = migration.stations
        }

        defaults.set(Self.defaultGenreMigrationCurrentVersion, forKey: defaultGenreMigrationVersionKey)
        return migration.changedCount
    }

    private func postStationsDidChange() {
        NotificationCenter.default.post(name: Self.stationsDidChangeNotification, object: self)
    }
    /// Seed model for bundled default stations JSON.
    private struct DefaultStationSeed: Decodable {
        let name: String
        let url: String
        let genre: String?
        let iconURL: String?
    }

    private struct DefaultGenreCorrection {
        let from: String
        let to: String
    }

    static let defaultGenreMigrationCurrentVersion = 1

    private static let defaultGenreCorrections: [String: DefaultGenreCorrection] = [
        "https://ice5.somafm.com/bossa-128-mp3": DefaultGenreCorrection(from: "Classical", to: "Bossa Nova"),
        "https://radio11.plathong.net/7138/;stream.mp3": DefaultGenreCorrection(from: "Thai", to: "News"),
        "https://breakz-2012-high.rautemusik.fm/?ref=radiobrowser-top100-clubcharts": DefaultGenreCorrection(from: "Rap/Hip Hop", to: "Dance/EDM"),
        "https://0n-indie.radionetz.de/0n-indie.mp3": DefaultGenreCorrection(from: "Rap/Hip Hop", to: "Alternative Rock"),
        "https://www.radioking.com/play/alternative-radio-1": DefaultGenreCorrection(from: "Rap/Hip Hop", to: "Alternative Rock"),
        "http://ice.stream101.com:9016/stream": DefaultGenreCorrection(from: "Rap/Hip Hop", to: "Country"),
        "https://stream.zeno.fm/muzrp86994zuv": DefaultGenreCorrection(from: "Rap/Hip Hop", to: "Afrobeats"),
        "https://workout-high.rautemusik.fm/?ref=radiobrowser": DefaultGenreCorrection(from: "Nature Sounds", to: "Workout"),
        "http://bayerwaldradio.deg.net:8000/allesoberkrain": DefaultGenreCorrection(from: "Nature Sounds", to: "Polka/Folk"),
        "http://fluxfm.streamabc.net/flx-70er-mp3-320-4383769?sABC=6202qr25%230%237osorqnn86p8nnp979o1124290qqo247%23fgernzf.syhksz.qr&amsparams=playerid:streams.fluxfm.de;skey:1644355109": DefaultGenreCorrection(from: "Nature Sounds", to: "Classic Rock"),
        "https://fluxfm.streamabc.net/flx-80er-mp3-320-9596107?sABC=6202qrr6%230%23sorr1p583723p06268o324o2ps5n399q%23fgernzf.syhksz.qr&amsparams=playerid:streams.fluxfm.de;skey:1644355302": DefaultGenreCorrection(from: "Nature Sounds", to: "Classic Rock"),
        "http://streams.radiobob.de/bob-90srock/mp3-192/mediaplayer": DefaultGenreCorrection(from: "Nature Sounds", to: "Classic Rock"),
        "http://streams.radiobob.de/gothic/mp3-192/mediaplayer": DefaultGenreCorrection(from: "Nature Sounds", to: "Gothic Rock"),
        "http://streams.radiobob.de/bob-metal/mp3-192/mediaplayer": DefaultGenreCorrection(from: "Nature Sounds", to: "Metal"),
        "http://streams.radiobob.de/metalcore/mp3-192/mediaplayer": DefaultGenreCorrection(from: "Nature Sounds", to: "Metal"),
        "http://streams.radiobob.de/metallica/mp3-192/mediaplayer/": DefaultGenreCorrection(from: "Nature Sounds", to: "Metal"),
        "http://streams.radiobob.de/rockparty/mp3-192/mediaplayer/": DefaultGenreCorrection(from: "Nature Sounds", to: "Rock"),
        "http://streams.radiobob.de/bob-wacken/mp3-192/mediaplayer": DefaultGenreCorrection(from: "Nature Sounds", to: "Metal"),
        "http://lux.radio.tvstitch.com/kyiv/lux_adv_sd": DefaultGenreCorrection(from: "Nature Sounds", to: "Top 40"),
        "http://streams.radio.co/s79fbbb432/listen": DefaultGenreCorrection(from: "Nature Sounds", to: "World"),
        "https://streaming.radiostreamlive.com/miamibeachradio_devices": DefaultGenreCorrection(from: "Nature Sounds", to: "Dance"),
        "http://streams.radiobob.de/bob-wacken/mp3-192/streams.radiobob.de/": DefaultGenreCorrection(from: "Nature Sounds", to: "Metal"),
        "http://213.141.131.10:8004/forestpsytrance": DefaultGenreCorrection(from: "Nature Sounds", to: "Psytrance"),
        "http://195.95.206.13:8000/RadioROKS": DefaultGenreCorrection(from: "Nature Sounds", to: "Rock"),
        "http://online.radioroks.ua/RadioROKS_Ukr_HD": DefaultGenreCorrection(from: "Nature Sounds", to: "Rock"),
        "http://www.segenswelle.de:8000/ukrainisch": DefaultGenreCorrection(from: "Nature Sounds", to: "World"),
        "https://listen9.myradio24.com/6262": DefaultGenreCorrection(from: "Nature Sounds", to: "Easy Listening"),
        "http://online.hitfm.ua/HitFM_Ukr": DefaultGenreCorrection(from: "Nature Sounds", to: "Top 40"),
        "https://online-news.radioplayer.ua/RadioNews": DefaultGenreCorrection(from: "Nature Sounds", to: "News"),
        "https://stream.antiradio.net/radio/8000/mp3": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "http://stream.laut.fm/deep-house-sounds": DefaultGenreCorrection(from: "College Indie", to: "Deep House"),
        "https://stream.radiojar.com/cthtwxk5yvduv.mp3": DefaultGenreCorrection(from: "College Indie", to: "Easy Listening"),
        "http://streams.fluxfm.de/live/mp3-320/audio/": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "https://orf-live.ors-shoutcast.at/fm4-q1a": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "http://stream.radio.co/s1cffd7347/listen": DefaultGenreCorrection(from: "College Indie", to: "Hip Hop"),
        "http://kathy.torontocast.com:2690/stream": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "http://naxidigital-rock128.streaming.rs:8180/;stream.nsv": DefaultGenreCorrection(from: "College Indie", to: "Rock"),
        "http://mr-stream.mediaconnect.hu/4737/mr2.aac": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "http://streams.radiobob.de/bob-alternative/mp3-192/streams.radiobob.de/": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "http://streams.radiobob.de/bob-bestofrock/mp3-192/streams.radiobob.de/": DefaultGenreCorrection(from: "College Indie", to: "Rock"),
        "http://stream.zeno.fm/sri2de2qdlivv": DefaultGenreCorrection(from: "College Indie", to: "Top 40"),
        "http://f121.rndfnk.com/ard/rbb/radioeins/live/mp3/128/stream.mp3?cid=01FC1WH12KJ93TCQPDSE2E5PZ9&sid=38HoeEhwMU9ZjQaArYLcNuLu9LN&token=VXH8C52tOJ6o_G5uLXexxjt84DXyHGfH0RABfQljedk&tvf=8PpblQ7uihhmMTIxLnJuZGZuay5jb20": DefaultGenreCorrection(from: "College Indie", to: "Public Radio"),
        "http://novazz.ice.infomaniak.ch/novazz-128.mp3": DefaultGenreCorrection(from: "College Indie", to: "Jazz"),
        "http://stream.radioparadise.com/mellow-320": DefaultGenreCorrection(from: "College Indie", to: "Eclectic"),
        "http://stream.radioparadise.com/rock-320": DefaultGenreCorrection(from: "College Indie", to: "Rock"),
        "https://stream.radioparadise.com/rock-flac": DefaultGenreCorrection(from: "College Indie", to: "Rock"),
        "http://nashe1.hostingradio.ru/ultra-192.mp3": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "http://media-the.musicradio.com/RadioXUK": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "http://stream.rockantenne.de/alternative": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "https://ice5.somafm.com/folkfwd-128-aac": DefaultGenreCorrection(from: "College Indie", to: "Folk"),
        "https://ice1.somafm.com/folkfwd-128-mp3": DefaultGenreCorrection(from: "College Indie", to: "Folk"),
        "https://ice6.somafm.com/indiepop-128-aac": DefaultGenreCorrection(from: "College Indie", to: "Alternative/Pop"),
        "https://ice2.somafm.com/poptron-128-mp3": DefaultGenreCorrection(from: "College Indie", to: "Pop"),
        "http://live.slovakradio.sk:8000/FM_256.mp3": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "https://listen.radioking.com/radio/293701/stream/340084": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "http://stream.tilos.hu/tilos": DefaultGenreCorrection(from: "College Indie", to: "Eclectic"),
        "https://listen-msmn.sharp-stream.com/nme1.mp3": DefaultGenreCorrection(from: "College Indie", to: "Alternative Rock"),
        "http://stream.laut.fm/ultradarkradio": DefaultGenreCorrection(from: "College Indie", to: "Gothic Rock"),
        "https://0n-gothic.radionetz.de/0n-gothic.mp3": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Gothic Rock"),
        "https://play-radio0.jump.bg:7049/live": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Hard Rock"),
        "http://51.255.235.165:5528/stream": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Ska"),
        "http://stream.laut.fm/darkzeroradio": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Gothic Rock"),
        "https://nl4.mystreaming.net/er/greenday/icecast.audio": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Punk Rock"),
        "https://nl4.mystreaming.net/er/ramones/icecast.audio": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Punk Rock"),
        "https://audio-edge-3mayu.fra.h.radiomast.io/73055724-1141-41e2-a69b-24a6ca96c8e7": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Hard Dance"),
        "https://www.happyhardcore.com/livestreams/p/u9/": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Hard Dance"),
        "http://stream.laut.fm/hardstyle-and-hardcore": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Hard Dance"),
        "https://kniteforce.out.airtime.pro/kniteforce_a": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Hard Dance"),
        "https://playerservices.streamtheworld.com/api/livestream-redirect/Q_DANCE.mp3": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Hard Dance"),
        "http://79.120.12.130:8004/cyberpunk": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Synthwave"),
        "https://radiorecord.hostingradio.ru/teo96.aacp": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Hard Dance"),
        "http://happyhardcore-high.rautemusik.fm/": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Hard Dance"),
        "https://ice4.somafm.com/metal-128-aac": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Metal"),
        "http://lw2.mp3.tb-group.fm/tb.mp3": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Techno"),
        "http://cast1.asurahosting.com:8621/med": DefaultGenreCorrection(from: "Punk/Surf/Hardcore", to: "Rock"),
        "https://cast1.torontocast.com:4660/stream": DefaultGenreCorrection(from: "Extreme Music", to: "Metal"),
        "https://bestofrockfm.stream.vip/metallica/mp3-256/bestofrock.fm/": DefaultGenreCorrection(from: "Extreme Music", to: "Metal"),
        "http://usa17.fastcast4u.com:5508/stream": DefaultGenreCorrection(from: "Extreme Music", to: "Metalcore"),
        "http://stream.laut.fm/core-mix": DefaultGenreCorrection(from: "Extreme Music", to: "Metalcore"),
        "http://streams.radiobob.de/progrock/mp3-192/mediaplayer/": DefaultGenreCorrection(from: "Extreme Music", to: "Progressive Rock"),
        "https://securestream.us/radio/8050/radio.mp3": DefaultGenreCorrection(from: "Extreme Music", to: "Rock"),
        "https://streaming.galaxywebsolutions.com:9046/stream": DefaultGenreCorrection(from: "Extreme Music", to: "Doom Metal")
    ]

    static func correctedDefaultGenre(for stationURL: URL, currentGenre: String?) -> String? {
        guard let correction = defaultGenreCorrections[stationURL.absoluteString] else { return nil }
        let normalizedCurrent = (currentGenre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFrom = correction.from.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCurrent.compare(normalizedFrom, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else {
            return nil
        }
        return correction.to
    }

    static func applyingDefaultGenreCorrections(to stations: [RadioStation]) -> (stations: [RadioStation], changedCount: Int) {
        var changedCount = 0
        let migrated = stations.map { station -> RadioStation in
            guard let corrected = correctedDefaultGenre(for: station.url, currentGenre: station.genre) else { return station }
            var copy = station
            copy.genre = corrected
            changedCount += 1
            return copy
        }
        return (migrated, changedCount)
    }

    private static func normalizedStationNameKey(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func applyingDefaultURLCorrections(to stations: [RadioStation]) -> (stations: [RadioStation], changedCount: Int) {
        let legacyAudiophileURLs = channelSourceURLs["Audiophile.fm"] ?? []

        var canonicalURLByName: [String: URL] = [:]
        for station in defaultStations {
            let key = normalizedStationNameKey(station.name)
            if canonicalURLByName[key] == nil {
                canonicalURLByName[key] = station.url
            }
        }

        var changedCount = 0
        let filtered = stations.filter { station in
            guard !removedDefaultStationURLs.contains(station.url.absoluteString) else {
                changedCount += 1
                return false
            }
            return true
        }

        let migrated = filtered.map { station -> RadioStation in
            let key = normalizedStationNameKey(station.name)
            guard let canonicalURL = canonicalURLByName[key] else { return station }
            guard canonicalURL != station.url else { return station }
            guard legacyAudiophileURLs.contains(station.url.absoluteString) else { return station }

            var copy = station
            copy.url = canonicalURL
            changedCount += 1
            return copy
        }
        return (migrated, changedCount)
    }

    /// Default stations to show for new users
    private static let defaultStations: [RadioStation] = loadDefaultStations()

    private static func loadDefaultStations() -> [RadioStation] {
        guard let resourceURL = BundleHelper.url(forResource: "default_stations", withExtension: "json", subdirectory: "Radio") else {
            NSLog("RadioManager: Missing bundled default_stations.json")
            return []
        }

        do {
            let data = try Data(contentsOf: resourceURL)
            let decoder = JSONDecoder()
            let seeds = try decoder.decode([DefaultStationSeed].self, from: data)

            let stations = seeds.compactMap { seed -> RadioStation? in
                guard let url = URL(string: seed.url) else {
                    NSLog("RadioManager: Skipping invalid default station URL for '%@': %@", seed.name, seed.url)
                    return nil
                }
                let icon = seed.iconURL.flatMap(URL.init(string:))
                return RadioStation(name: seed.name, url: url, genre: seed.genre, iconURL: icon)
            }

            if stations.isEmpty {
                NSLog("RadioManager: Bundled default_stations.json decoded to 0 valid stations")
                return []
            }

            NSLog("RadioManager: Loaded %d bundled default stations", stations.count)
            return stations
        } catch {
            NSLog("RadioManager: Failed to load bundled default_stations.json (%@)", error.localizedDescription)
            return []
        }
    }

    // MARK: - Station Management
    
    /// Add a new radio station
    func addStation(_ station: RadioStation) {
        stations.append(station)
        NSLog("RadioManager: Added station '%@'", station.name)
    }
    
    /// Update an existing station
    func updateStation(_ station: RadioStation) {
        if let index = stations.firstIndex(where: { $0.id == station.id }) {
            let oldURL = stations[index].url
            if oldURL != station.url {
                moveRating(fromURL: oldURL, toURL: station.url)
                foldersStore.moveStationURLReferences(from: oldURL, to: station.url)
                moveSmartFolderOverrides(from: oldURL, to: station.url)
            }
            stations[index] = station
            NSLog("RadioManager: Updated station '%@'", station.name)
        }
    }
    
    /// Remove a station
    func removeStation(_ station: RadioStation) {
        // If this is a default station, track it so it won't be re-added
        if isDefaultStationURL(station.url) {
            var deleted = deletedDefaultURLs
            deleted.insert(station.url.absoluteString)
            deletedDefaultURLs = deleted
            NSLog("RadioManager: Tracking deleted default station '%@'", station.name)
        }
        removeRating(for: station)
        foldersStore.removeStationURLEverywhere(station.url)
        clearSmartFolderOverrides(for: station.url)
        stations.removeAll { $0.id == station.id }
        NSLog("RadioManager: Removed station '%@'", station.name)
    }
    
    /// Remove station by ID
    func removeStation(id: UUID) {
        if let station = stations.first(where: { $0.id == id }) {
            removeStation(station)
        }
    }
    
    /// Move station in the list
    func moveStation(from source: IndexSet, to destination: Int) {
        stations.move(fromOffsets: source, toOffset: destination)
    }
    
    /// Reset stations to defaults (removes all user stations and clears deleted tracking)
    func resetToDefaults() {
        // Clear the deleted defaults tracking so all defaults come back
        deletedDefaultURLs = []
        smartGenreOverrides = [:]
        smartRegionOverrides = [:]
        stations = Self.defaultStations
        NSLog("RadioManager: Reset to %d default stations", stations.count)
    }
    
    /// Add any default stations that aren't already in the user's list
    /// (skips stations the user has previously deleted)
    func addMissingDefaults() {
        let deleted = deletedDefaultURLs
        var added = 0
        for defaultStation in Self.defaultStations {
            // Skip if user previously deleted this default
            let wasDeleted = deleted.contains { deletedURL in
                deletedURL == defaultStation.url.absoluteString ||
                Self.defaultURLAliases[deletedURL] == defaultStation.url.absoluteString ||
                Self.defaultURLAliases[defaultStation.url.absoluteString] == deletedURL
            }
            if wasDeleted {
                continue
            }
            // Check if station with same URL already exists
            let exists = stations.contains { areEquivalentStationURLs($0.url, defaultStation.url) }
            if !exists {
                stations.append(defaultStation)
                added += 1
            }
        }
        NSLog("RadioManager: Added %d missing default stations (skipped %d deleted)", added, deleted.count)
    }

    // MARK: - Search

    /// Search internet radio stations by metadata.
    ///
    /// Matches against station name, effective genre, effective region, URL host, and full URL.
    /// Query tokens are case-insensitive and all tokens must match.
    func searchStations(query: String) -> [RadioStation] {
        searchStations(in: stations, query: query)
    }

    /// Search a provided station list by internet-radio metadata.
    func searchStations(in candidateStations: [RadioStation], query: String) -> [RadioStation] {
        let tokens = searchTokens(from: query)
        guard !tokens.isEmpty else { return [] }
        return stationsSortedBySearchName(
            candidateStations.filter { stationMatchesSearchTokens($0, tokens: tokens) }
        )
    }

    // MARK: - Station Ratings

    /// Return a station rating on a 0-5 scale (0 = unrated).
    func rating(for station: RadioStation) -> Int {
        ratingsStore.rating(for: station.url)
    }

    /// Set a station rating on a 0-5 scale (0 clears the rating).
    func setRating(_ rating: Int, for station: RadioStation) {
        ratingsStore.setRating(rating, for: station.url)
        postStationsDidChange()
    }

    /// Move an existing rating from an old stream URL to a new URL.
    func moveRating(fromURL oldURL: URL, toURL newURL: URL) {
        ratingsStore.moveRating(from: oldURL, to: newURL)
    }

    /// Remove a station's persisted rating.
    func removeRating(for station: RadioStation) {
        ratingsStore.removeRating(for: station.url)
        postStationsDidChange()
    }

    // MARK: - Smart Folder Overrides

    func smartGenreOverride(for station: RadioStation) -> String? {
        overrideValue(for: station.url, in: smartGenreOverrides)
    }

    func smartRegionOverride(for station: RadioStation) -> String? {
        overrideValue(for: station.url, in: smartRegionOverrides)
    }

    func effectiveRegion(for station: RadioStation) -> String {
        effectiveRegionLabel(for: station)
    }

    func autoRegion(for station: RadioStation) -> String {
        derivedRegion(for: station)
    }

    @discardableResult
    func setSmartGenreOverride(_ genre: String?, for station: RadioStation) -> Bool {
        let base = normalizeGenreLabel(station.genre)
        let target = normalizedOverrideLabel(genre)
        var map = smartGenreOverrides
        let changed = setOverrideValue(target == base ? nil : target, for: station.url, in: &map)
        if changed {
            smartGenreOverrides = map
            postStationsDidChange()
        }
        return changed
    }

    @discardableResult
    func setSmartRegionOverride(_ region: String?, for station: RadioStation) -> Bool {
        let base = derivedRegion(for: station)
        let target = normalizedOverrideLabel(region)
        var map = smartRegionOverrides
        let changed = setOverrideValue(target == base ? nil : target, for: station.url, in: &map)
        if changed {
            smartRegionOverrides = map
            postStationsDidChange()
        }
        return changed
    }

    func smartGenreOptions(including station: RadioStation? = nil) -> [String] {
        var labels = Set(availableGenres())
        if let station {
            labels.insert(normalizeGenreLabel(station.genre))
            labels.insert(effectiveGenreLabel(for: station))
        }
        return labels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func smartRegionOptions(including station: RadioStation? = nil) -> [String] {
        var labels = Set(availableRegions())
        if let station {
            labels.insert(derivedRegion(for: station))
            labels.insert(effectiveRegionLabel(for: station))
        }
        return labels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Folder Organization

    func userRadioFolders() -> [RadioUserFolder] {
        foldersStore.folders()
    }

    @discardableResult
    func createUserFolder(named name: String) -> RadioUserFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if userRadioFolders().contains(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return nil
        }
        let folder = foldersStore.createFolder(name: trimmed)
        if folder != nil {
            postStationsDidChange()
        }
        return folder
    }

    @discardableResult
    func renameUserFolder(id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if userRadioFolders().contains(where: { $0.id != id && $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return false
        }
        let renamed = foldersStore.renameFolder(id: id, name: trimmed)
        if renamed {
            postStationsDidChange()
        }
        return renamed
    }

    @discardableResult
    func deleteUserFolder(id: UUID) -> Bool {
        let deleted = foldersStore.deleteFolder(id: id)
        if deleted {
            postStationsDidChange()
        }
        return deleted
    }

    @discardableResult
    func addStation(_ station: RadioStation, toUserFolderID folderID: UUID) -> Bool {
        let added = foldersStore.addStationURL(station.url, toFolder: folderID)
        if added {
            postStationsDidChange()
        }
        return added
    }

    @discardableResult
    func removeStation(_ station: RadioStation, fromUserFolderID folderID: UUID) -> Bool {
        let removed = foldersStore.removeStationURL(station.url, fromFolder: folderID)
        if removed {
            postStationsDidChange()
        }
        return removed
    }

    func userFolderIDs(containing station: RadioStation) -> Set<UUID> {
        var ids = foldersStore.folderIDs(containing: station.url)
        if let alias = Self.defaultURLAliases[station.url.absoluteString],
           let aliasURL = URL(string: alias) {
            ids.formUnion(foldersStore.folderIDs(containing: aliasURL))
        }
        return ids
    }

    func isStation(_ station: RadioStation, inUserFolderID folderID: UUID) -> Bool {
        userFolderIDs(containing: station).contains(folderID)
    }

    func internetRadioFolderDescriptors() -> [RadioFolderDescriptor] {
        let channels = availableChannels()
        let genres = availableGenres()
        let regions = availableRegions()
        let userFolders = userRadioFolders()
        let hasStations: (RadioFolderKind) -> Bool = { [self] kind in
            !stations(inFolder: kind).isEmpty
        }

        var result: [RadioFolderDescriptor] = [
            RadioFolderDescriptor(
                id: RadioFolderKind.allStations.id,
                title: "All Stations",
                kind: .allStations,
                parentID: nil,
                sortOrder: 10,
                hasChildren: hasStations(.allStations)
            ),
            RadioFolderDescriptor(
                id: RadioFolderKind.favorites.id,
                title: "Favorites",
                kind: .favorites,
                parentID: nil,
                sortOrder: 20,
                hasChildren: hasStations(.favorites)
            ),
            RadioFolderDescriptor(
                id: RadioFolderKind.topRated.id,
                title: "Top Rated",
                kind: .topRated,
                parentID: nil,
                sortOrder: 30,
                hasChildren: hasStations(.topRated)
            ),
            RadioFolderDescriptor(
                id: RadioFolderKind.unrated.id,
                title: "Unrated",
                kind: .unrated,
                parentID: nil,
                sortOrder: 40,
                hasChildren: hasStations(.unrated)
            ),
            RadioFolderDescriptor(
                id: RadioFolderKind.recentlyPlayed.id,
                title: "Recently Played",
                kind: .recentlyPlayed,
                parentID: nil,
                sortOrder: 50,
                hasChildren: hasStations(.recentlyPlayed)
            ),
            RadioFolderDescriptor(
                id: RadioFolderKind.byChannel.id,
                title: "By Channel",
                kind: .byChannel,
                parentID: nil,
                sortOrder: 80,
                hasChildren: !channels.isEmpty
            ),
            RadioFolderDescriptor(
                id: RadioFolderKind.byGenre.id,
                title: "By Genre",
                kind: .byGenre,
                parentID: nil,
                sortOrder: 100,
                hasChildren: !genres.isEmpty
            ),
            RadioFolderDescriptor(
                id: RadioFolderKind.byRegion.id,
                title: "By Region",
                kind: .byRegion,
                parentID: nil,
                sortOrder: 200,
                hasChildren: !regions.isEmpty
            ),
            RadioFolderDescriptor(
                id: RadioFolderKind.userFoldersRoot.id,
                title: "My Folders",
                kind: .userFoldersRoot,
                parentID: nil,
                sortOrder: 300,
                hasChildren: !userFolders.isEmpty
            )
        ]

        for (index, channel) in channels.enumerated() {
            result.append(
                RadioFolderDescriptor(
                    id: RadioFolderKind.channel(channel).id,
                    title: channel,
                    kind: .channel(channel),
                    parentID: RadioFolderKind.byChannel.id,
                    sortOrder: 900 + index,
                    hasChildren: hasStations(.channel(channel))
                )
            )
        }

        for (index, genre) in genres.enumerated() {
            result.append(
                RadioFolderDescriptor(
                    id: RadioFolderKind.genre(genre).id,
                    title: genre,
                    kind: .genre(genre),
                    parentID: RadioFolderKind.byGenre.id,
                    sortOrder: 1000 + index,
                    hasChildren: hasStations(.genre(genre))
                )
            )
        }

        for (index, region) in regions.enumerated() {
            result.append(
                RadioFolderDescriptor(
                    id: RadioFolderKind.region(region).id,
                    title: region,
                    kind: .region(region),
                    parentID: RadioFolderKind.byRegion.id,
                    sortOrder: 2000 + index,
                    hasChildren: hasStations(.region(region))
                )
            )
        }

        for (index, folder) in userFolders.enumerated() {
            result.append(
                RadioFolderDescriptor(
                    id: RadioFolderKind.manual(folder.id).id,
                    title: folder.name,
                    kind: .manual(folder.id),
                    parentID: RadioFolderKind.userFoldersRoot.id,
                    sortOrder: 3000 + index,
                    hasChildren: hasStations(.manual(folder.id))
                )
            )
        }

        return result
    }

    func stations(inFolder kind: RadioFolderKind) -> [RadioStation] {
        switch kind {
        case .allStations:
            return stationsSortedByGenreAndName(stations)
        case .favorites:
            let filtered = stations.filter { rating(for: $0) >= 4 }
            return stationsSortedByName(filtered)
        case .topRated:
            return stations
                .map { ($0, rating(for: $0)) }
                .filter { $0.1 > 0 }
                .sorted {
                    if $0.1 != $1.1 { return $0.1 > $1.1 }
                    return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
                }
                .map(\.0)
        case .unrated:
            let filtered = stations.filter { rating(for: $0) == 0 }
            return stationsSortedByName(filtered)
        case .recentlyPlayed:
            let history = foldersStore.lastPlayedTimestampsByURL()
            return stations
                .compactMap { station -> (RadioStation, Date)? in
                    if let date = history[station.url.absoluteString] {
                        return (station, date)
                    }
                    if let alias = Self.defaultURLAliases[station.url.absoluteString], let date = history[alias] {
                        return (station, date)
                    }
                    return nil
                }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        case .channel(let channel):
            let filtered = stations.filter {
                derivedChannel(for: $0).localizedCaseInsensitiveCompare(channel) == .orderedSame
            }
            return stationsSortedByName(filtered)
        case .genre(let genre):
            let target = normalizeGenreLabel(genre)
            let filtered = stations.filter {
                effectiveGenreLabel(for: $0).localizedCaseInsensitiveCompare(target) == .orderedSame
            }
            return stationsSortedByName(filtered)
        case .region(let region):
            let filtered = stations.filter { effectiveRegionLabel(for: $0) == region }
            return stationsSortedByName(filtered)
        case .manual(let folderID):
            let urls = foldersStore.stationURLs(inFolder: folderID)
            let filtered = stations.filter { station in
                if urls.contains(station.url.absoluteString) { return true }
                if let alias = Self.defaultURLAliases[station.url.absoluteString] {
                    return urls.contains(alias)
                }
                return false
            }
            return stationsSortedByName(filtered)
        case .byChannel, .byGenre, .byRegion, .userFoldersRoot:
            return []
        }
    }

    private func stationsSortedByName(_ items: [RadioStation]) -> [RadioStation] {
        items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func stationsSortedBySearchName(_ items: [RadioStation]) -> [RadioStation] {
        items.sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            let urlOrder = lhs.url.absoluteString.localizedCaseInsensitiveCompare(rhs.url.absoluteString)
            if urlOrder != .orderedSame {
                return urlOrder == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func searchTokens(from query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map { String($0) }
            .filter { !$0.isEmpty }
            .map { normalizedSearchToken($0) }
    }

    private func normalizedSearchToken(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func stationSearchText(_ station: RadioStation) -> String {
        var fields: [String] = [
            station.name,
            effectiveGenreLabel(for: station),
            effectiveRegionLabel(for: station),
            station.url.absoluteString
        ]
        fields.append(derivedChannel(for: station))
        if let host = station.url.host {
            fields.append(host)
        }
        return normalizedSearchToken(fields.joined(separator: " "))
    }

    private func stationMatchesSearchTokens(_ station: RadioStation, tokens: [String]) -> Bool {
        let searchText = stationSearchText(station)
        return tokens.allSatisfy { searchText.contains($0) }
    }

    private func stationsSortedByGenreAndName(_ items: [RadioStation]) -> [RadioStation] {
        items.sorted { a, b in
            let ga = effectiveGenreLabel(for: a)
            let gb = effectiveGenreLabel(for: b)
            if ga.caseInsensitiveCompare(gb) != .orderedSame {
                return ga.localizedCaseInsensitiveCompare(gb) == .orderedAscending
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func normalizedGenre(for station: RadioStation) -> String {
        effectiveGenreLabel(for: station)
    }

    private func effectiveGenreLabel(for station: RadioStation) -> String {
        smartGenreOverride(for: station) ?? normalizeGenreLabel(station.genre)
    }

    private func effectiveRegionLabel(for station: RadioStation) -> String {
        smartRegionOverride(for: station) ?? derivedRegion(for: station)
    }

    private func normalizeGenreLabel(_ genre: String?) -> String {
        let trimmed = (genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    private func availableGenres() -> [String] {
        let genres = Set(stations.map { effectiveGenreLabel(for: $0) })
        return genres.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func availableRegions() -> [String] {
        let regions = Set(stations.map { effectiveRegionLabel(for: $0) })
        return regions.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func availableChannels() -> [String] {
        var counts: [String: Int] = [:]
        for station in stations {
            let channel = derivedChannel(for: station)
            counts[channel, default: 0] += 1
        }

        let labels = counts
            .filter { $0.value >= 2 || $0.key == "Audiophile.fm" }
            .map(\.key)

        return labels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func derivedChannel(for station: RadioStation) -> String {
        let keys = equivalentURLKeys(for: station.url)
        for (label, urls) in Self.channelSourceURLs where !urls.isDisjoint(with: keys) {
            return label
        }

        let host = station.url.host?.lowercased() ?? ""
        if !host.isEmpty {
            for (pattern, label) in Self.channelHostAliases where host.contains(pattern) {
                return label
            }
        }

        return normalizedChannelLabel(fromHost: host)
    }

    private func normalizedChannelLabel(fromHost host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown Source" }

        let components = trimmed.split(separator: ".")
        if components.count >= 2 {
            let label = components.suffix(2).joined(separator: ".")
            return label.lowercased()
        }
        return trimmed.lowercased()
    }

    private func derivedRegion(for station: RadioStation) -> String {
        let text = "\(station.name) \(station.genre ?? "") \(station.url.host ?? "")".lowercased()

        if containsAny(text, [
            "brazil", "argentina", "colombia", "chile", "peru", "ecuador",
            "venezuela", "bolivia", "paraguay", "uruguay", "medellin",
            "bogota", "santiago", "asuncion", "guayaquil", "la paz"
        ]) {
            return "South America"
        }

        if containsAny(text, [
            "jamaica", "barbados", "trinidad", "caribbean", "dancehall", "soca"
        ]) {
            return "Caribbean"
        }

        if containsAny(text, [
            "africa", "abidjan", "lagos", "dakar", "senegal", "ivoire", "afro"
        ]) {
            return "Africa"
        }

        if containsAny(text, [
            "india", "hindi", "tamil", "thai", "japan", "k-pop", "kpop", "asia",
            "bollywood", "bangkok", "korea", "gensokyo"
        ]) {
            return "Asia"
        }

        if containsAny(text, [
            "london", "uk", "france", "germany", "spain", "italy", "netherlands",
            "sweden", "norway", "belgium", "austria", "europe", "rtl2", "qmusic",
            "orf", "studio brussel", "los 40", "capital fm"
        ]) {
            return "Europe"
        }

        if containsAny(text, [
            "somafm", "npr", "kexp", "wgbh", "wfmu", "seattle", "new orleans", "boston", "cambridge", "massachusetts"
        ]) {
            return "North America"
        }

        return "Global"
    }

    private func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains(where: { haystack.contains($0) })
    }
    
    // MARK: - Playback
    
    /// Play a radio station
    func play(station: RadioStation) {
        manualStopRequested = false
        currentStation = station
        connectionState = .connecting
        reconnectAttempts = 0
        foldersStore.recordPlayed(station.url)
        postStationsDidChange()
        
        NSLog("RadioManager: Playing station '%@' at %@", station.name, station.url.absoluteString)
        
        startPlayback(station: station)
    }
    
    /// Internal playback start (used by play and reconnect)
    private func startPlayback(station: RadioStation) {
        // Check if URL is a playlist file that needs resolving
        let ext = station.url.pathExtension.lowercased()
        if ext == "pls" || ext == "m3u" || ext == "m3u8" {
            // Resolve playlist to get actual stream URL
            resolvePlaylistURL(station.url) { [weak self] resolvedURL in
                guard let self = self else { return }
                guard self.currentStation?.id == station.id else {
                    NSLog("RadioManager: Station changed during resolution, cancelling")
                    return
                }
                
                if let streamURL = resolvedURL {
                    NSLog("RadioManager: Resolved playlist to stream URL: %@", streamURL.absoluteString)
                    // Create a modified station with the resolved URL
                    let resolvedStation = RadioStation(
                        id: station.id,
                        name: station.name,
                        url: streamURL,
                        genre: station.genre,
                        iconURL: station.iconURL
                    )
                    // Update currentStation to use resolved URL so loadTracks check passes
                    // (loadTracks compares track.url with currentStation.url to detect radio content)
                    self.currentStation = resolvedStation
                    let track = resolvedStation.toTrack()
                    self.resolvedAudioEngine.loadTracks([track])
                    // Only call play() for local playback - casting is handled by loadTracks
                    // Check casting state fresh here, not captured before async resolution,
                    // since user may have started casting during the network request
                    if !CastManager.shared.isCasting {
                        self.resolvedAudioEngine.play()
                    }
                } else {
                    NSLog("RadioManager: Failed to resolve playlist URL")
                    self.connectionState = .failed(message: "Could not resolve playlist URL")
                }
            }
        } else {
            // Direct stream URL - play immediately
            let track = station.toTrack()
            resolvedAudioEngine.loadTracks([track])
            // Only call play() for local playback - casting is handled by loadTracks
            if !CastManager.shared.isCasting {
                resolvedAudioEngine.play()
            }
        }
    }
    
    /// Resolve a playlist URL (.pls, .m3u, .m3u8) to get the actual stream URL
    private func resolvePlaylistURL(_ url: URL, completion: @escaping (URL?) -> Void) {
        NSLog("RadioManager: Resolving playlist URL: %@", url.absoluteString)
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else {
                    NSLog("RadioManager: Failed to fetch playlist: %@", error?.localizedDescription ?? "unknown")
                    completion(nil)
                    return
                }
                
                guard let content = String(data: data, encoding: .utf8) else {
                    NSLog("RadioManager: Could not decode playlist content")
                    completion(nil)
                    return
                }
                
                // Parse the playlist content
                let streamURL = self.parsePlaylistForStreamURL(content, sourceURL: url)
                // Block SSRF: don't follow playlist redirects from public URLs to private IPs
                if let resolved = streamURL, self.isPrivateIPRedirect(from: url, to: resolved) {
                    NSLog("RadioManager: Blocked playlist redirect to private IP: %@", resolved.absoluteString)
                    completion(nil)
                    return
                }
                completion(streamURL)
            }
        }.resume()
    }
    
    /// Parse playlist content to extract the first stream URL
    private func parsePlaylistForStreamURL(_ content: String, sourceURL: URL) -> URL? {
        let lines = content.components(separatedBy: .newlines)
        let ext = sourceURL.pathExtension.lowercased()

        // HLS manifests:
        // - Master playlist: return first variant URL (can be relative path)
        // - Media playlist: keep original manifest URL (stream client follows segments)
        if ext == "m3u8" || content.contains("#EXTM3U") {
            if content.uppercased().contains("#EXT-X-STREAM-INF") {
                for (index, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.uppercased().hasPrefix("#EXT-X-STREAM-INF") else { continue }

                    var nextIndex = index + 1
                    while nextIndex < lines.count {
                        let candidate = lines[nextIndex].trimmingCharacters(in: .whitespaces)
                        if candidate.isEmpty {
                            nextIndex += 1
                            continue
                        }
                        if candidate.hasPrefix("#") {
                            break
                        }
                        return resolvedPlaylistEntryURL(candidate, sourceURL: sourceURL)
                    }
                }
            }
            return sourceURL
        }
        
        // PLS format
        if ext == "pls" || content.lowercased().contains("[playlist]") {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix("file") {
                    if let equalIndex = trimmed.firstIndex(of: "=") {
                        let urlString = String(trimmed[trimmed.index(after: equalIndex)...])
                        if let url = resolvedPlaylistEntryURL(urlString, sourceURL: sourceURL) {
                            return url
                        }
                    }
                }
            }
        }
        
        // M3U format or plain URLs
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip comments and metadata
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            if let url = resolvedPlaylistEntryURL(trimmed, sourceURL: sourceURL) {
                return url
            }
        }
        
        return nil
    }

    private func resolvedPlaylistEntryURL(_ entry: String, sourceURL: URL) -> URL? {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        if trimmed.contains("://") {
            guard let url = URL(string: trimmed),
                  ["http", "https", "rtsp", "rtmp", "mms", "icyx"].contains(url.scheme?.lowercased() ?? "") else {
                return nil
            }
            return url
        }

        if let absolute = URL(string: trimmed, relativeTo: sourceURL)?.absoluteURL {
            return absolute
        }

        let base = sourceURL.deletingLastPathComponent()
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }
    
    private func isPrivateIPRedirect(from sourceURL: URL, to resolvedURL: URL) -> Bool {
        // Allow if source is already a local/private host (user-configured LAN radio)
        guard let sourceHost = sourceURL.host, !isPrivateHost(sourceHost) else { return false }
        guard let resolvedHost = resolvedURL.host else { return false }
        return isPrivateHost(resolvedHost)
    }

    private func isPrivateHost(_ host: String) -> Bool {
        // Strip IPv6 bracket notation: [::1] → ::1
        let h = host.hasPrefix("[") ? String(host.dropFirst().dropLast()) : host

        let privateRanges = ["127.", "10.", "192.168.", "localhost"]
        if privateRanges.contains(where: { h.hasPrefix($0) }) { return true }
        // 172.16.0.0/12
        if h.hasPrefix("172."), let second = h.split(separator: ".").dropFirst().first,
           let octet = Int(second), (16...31).contains(octet) { return true }
        // IPv6 loopback, link-local, unique-local
        let lower = h.lowercased()
        if lower == "::1" || lower.hasPrefix("fe80:") ||
           lower.hasPrefix("fc") || lower.hasPrefix("fd") { return true }
        return false
    }

    /// Re-activate radio for a stream URL that is already playing (e.g. playlist replay or state restore).
    /// Used when the audio engine starts playing a radio URL without going through `play(station:)`,
    /// leaving `isActive = false` and causing ICY metadata to be silently dropped.
    /// No-op if radio is already active or the URL does not match a known station.
    func reactivateIfNeeded(for url: URL) {
        guard currentStation == nil else { return }
        guard let station = stations.first(where: { $0.url == url }) else { return }
        NSLog("RadioManager: Re-activating for station '%@' (played without RadioManager)", station.name)
        manualStopRequested = false
        currentStation = station
        connectionState = .connecting
        // connectionState will update to .connected once streamDidConnect() fires
    }

    /// Stop radio playback
    func stop() {
        manualStopRequested = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        currentStation = nil
        currentStreamTitle = nil
        connectionState = .disconnected
        reconnectAttempts = 0
        
        NSLog("RadioManager: Stopped playback")
    }
    
    // MARK: - Stream Events
    
    /// Called when stream starts playing successfully
    func streamDidConnect() {
        guard currentStation != nil else { return }
        connectionState = .connected
        reconnectAttempts = 0
        startSomaMetadataFallbackIfNeeded()
        NSLog("RadioManager: Stream connected")
    }
    
    /// Called when radio is being cast to an external device (Sonos, Chromecast, etc.)
    /// Updates the connection state since local playback won't trigger streamDidConnect
    func castDidConnect() {
        guard currentStation != nil else { return }
        
        // Cancel any pending reconnect timer - casting has taken over playback
        // Without this, a timer scheduled before casting could fire and set
        // connectionState to .connecting, but since play() is skipped during casting,
        // streamDidConnect() never fires, leaving state stuck at .connecting
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        connectionState = .connected
        reconnectAttempts = 0
        startSomaMetadataFallbackIfNeeded()
        NSLog("RadioManager: Cast connected")
    }
    
    /// Called when stream metadata is received (ICY)
    func streamDidReceiveMetadata(_ metadata: [String: String]) {
        guard let station = currentStation else { return }
        var candidates: [String] = []

        // If artist and title arrive separately, combine them first.
        if let artist = metadataValue("artist", in: metadata),
           let title = metadataValue("title", in: metadata),
           let normArtist = normalizeMetadataTitle(artist),
           let normTitle = normalizeMetadataTitle(title) {
            candidates.append("\(normArtist) - \(normTitle)")
        }

        // Prefer standard title fields.
        let preferredKeys = [
            "StreamTitle", "icy-title", "title", "song", "track",
            "now_playing", "nowplaying", "np"
        ]
        for key in preferredKeys {
            if let value = metadataValue(key, in: metadata),
               let normalized = normalizeMetadataTitle(value) {
                candidates.append(normalized)
            }
        }

        // Some streams embed StreamTitle in a larger metadata blob value.
        for (_, rawValue) in metadata {
            if let embedded = extractEmbeddedStreamTitle(from: rawValue),
               let normalized = normalizeMetadataTitle(embedded) {
                candidates.append(normalized)
            }
        }

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            guard !isLikelyStationLabel(candidate, station: station) else { continue }
            currentStreamTitle = candidate
            NSLog("RadioManager: Stream title: %@", candidate)
            return
        }

        // `icy-name` is usually a static station label. Only use it for non-Soma
        // streams when it is clearly not the station name.
        if somaChannelID(for: station) == nil,
           let icyName = metadataValue("icy-name", in: metadata)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
           !icyName.isEmpty,
           !isLikelyStationLabel(icyName, station: station) {
            currentStreamTitle = icyName
            NSLog("RadioManager: Stream title: %@", icyName)
        }
    }
    
    /// Called when stream disconnects or errors
    func streamDidDisconnect(error: Error?) {
        guard let station = currentStation else { return }
        guard !manualStopRequested else {
            NSLog("RadioManager: Manual stop - not reconnecting")
            return
        }
        
        NSLog("RadioManager: Stream disconnected: %@", error?.localizedDescription ?? "unknown")
        
        // Attempt auto-reconnect if enabled
        if autoReconnectEnabled && reconnectAttempts < maxReconnectAttempts {
            scheduleReconnect(station: station)
        } else {
            connectionState = .failed(message: error?.localizedDescription ?? "Connection lost")
        }
    }
    
    // MARK: - Auto-Reconnect
    
    private func scheduleReconnect(station: RadioStation) {
        reconnectAttempts += 1
        connectionState = .reconnecting(attempt: reconnectAttempts)
        
        // Exponential backoff: 2s, 4s, 8s, 16s, 32s
        let delay = pow(2.0, Double(reconnectAttempts))
        NSLog("RadioManager: Reconnecting in %.0fs (attempt %d/%d)", delay, reconnectAttempts, maxReconnectAttempts)
        
        // Must dispatch to main queue - streamDidDisconnect is called from AudioStreaming
        // background threads, and Timer.scheduledTimer requires an active run loop
        DispatchQueue.main.async { [weak self] in
            self?.reconnectTimer?.invalidate()
            self?.reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.attemptReconnect(station: station)
            }
        }
    }
    
    private func attemptReconnect(station: RadioStation) {
        guard currentStation?.id == station.id else {
            NSLog("RadioManager: Station changed, cancelling reconnect")
            return
        }
        
        NSLog("RadioManager: Attempting reconnect to '%@'", station.name)
        connectionState = .connecting
        
        // Use startPlayback to handle playlist URL resolution if needed
        startPlayback(station: station)
    }
    
    /// Cancel any pending reconnect
    func cancelReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: - SomaFM Metadata Fallback

    private func somaChannelID(for station: RadioStation) -> String? {
        let host = station.url.host?.lowercased() ?? ""
        guard host.contains("somafm.com") else { return nil }

        let leaf = station.url.lastPathComponent.lowercased()
        guard !leaf.isEmpty else { return nil }

        // PLS endpoints: /<id>.pls
        if station.url.pathExtension.lowercased() == "pls" {
            let channelID = station.url.deletingPathExtension().lastPathComponent.lowercased()
            return channelID.isEmpty ? nil : channelID
        }

        // Stream endpoints: /<id>-128-mp3
        if let dash = leaf.firstIndex(of: "-") {
            let channelID = String(leaf[..<dash]).trimmingCharacters(in: .whitespacesAndNewlines)
            return channelID.isEmpty ? nil : channelID
        }

        let channelID = station.url.deletingPathExtension().lastPathComponent.lowercased()
        return channelID.isEmpty ? nil : channelID
    }

    private func metadataValue(_ key: String, in metadata: [String: String]) -> String? {
        metadata.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private func extractEmbeddedStreamTitle(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Parse `StreamTitle='Artist - Song';` payloads.
        if let range = trimmed.range(of: "StreamTitle=", options: .caseInsensitive) {
            let remainder = trimmed[range.upperBound...]
            if let firstQuote = remainder.firstIndex(where: { $0 == "'" || $0 == "\"" }) {
                let quote = remainder[firstQuote]
                let contentStart = remainder.index(after: firstQuote)
                if let endQuote = remainder[contentStart...].firstIndex(of: quote) {
                    return String(remainder[contentStart..<endQuote])
                }
            }
            return String(remainder).components(separatedBy: ";").first
        }

        return nil
    }

    private func normalizeMetadataTitle(_ raw: String) -> String? {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        if let embedded = extractEmbeddedStreamTitle(from: title) {
            title = embedded.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if (title.hasPrefix("'") && title.hasSuffix("'")) ||
            (title.hasPrefix("\"") && title.hasSuffix("\"")) {
            title = String(title.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !title.isEmpty else { return nil }

        // Ignore placeholder/non-song values.
        let lower = title.lowercased()
        if lower == "unknown" || lower == "-" || lower == "n/a" {
            return nil
        }

        return title
    }

    private func isLikelyStationLabel(_ value: String, station: RadioStation?) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }

        if let stationName = station?.name,
           normalized.caseInsensitiveCompare(stationName) == .orderedSame {
            return true
        }

        let lower = normalized.lowercased()
        if lower.hasPrefix("somafm") || lower.contains("somafm.com") {
            return true
        }

        return false
    }

    private func startSomaMetadataFallbackIfNeeded() {
        guard currentStreamTitle == nil else { return }
        guard let station = currentStation, let channelID = somaChannelID(for: station) else {
            stopSomaMetadataPolling()
            currentSomaLastPlaying = nil
            return
        }

        if somaMetadataTimer == nil {
            somaMetadataTimer = Timer.scheduledTimer(withTimeInterval: somaMetadataPollInterval, repeats: true) { [weak self] _ in
                guard let self = self,
                      let station = self.currentStation,
                      let channelID = self.somaChannelID(for: station) else {
                    return
                }
                self.fetchSomaLastPlaying(channelID: channelID, stationID: station.id)
            }
        }

        fetchSomaLastPlaying(channelID: channelID, stationID: station.id)
    }

    private func stopSomaMetadataPolling() {
        somaMetadataTimer?.invalidate()
        somaMetadataTimer = nil
    }

    private func fetchSomaLastPlaying(channelID: String, stationID: UUID) {
        guard !somaMetadataRequestInFlight else { return }
        somaMetadataRequestInFlight = true

        URLSession.shared.dataTask(with: somaChannelsURL) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.somaMetadataRequestInFlight = false

                guard error == nil, let data = data else {
                    NSLog("RadioManager: Soma metadata fetch failed: %@", error?.localizedDescription ?? "unknown")
                    return
                }

                guard let response = try? JSONDecoder().decode(SomaChannelsResponse.self, from: data) else {
                    NSLog("RadioManager: Soma metadata decode failed")
                    return
                }

                guard self.currentStation?.id == stationID else { return }

                let nowPlaying = response.channels.first(where: { $0.id.caseInsensitiveCompare(channelID) == .orderedSame })?.lastPlaying?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if self.currentStreamTitle == nil {
                    self.currentSomaLastPlaying = (nowPlaying?.isEmpty == false) ? nowPlaying : nil
                }
            }
        }.resume()
    }
    
    // MARK: - Status Display
    
    /// Get display text for current state (for marquee)
    var statusText: String? {
        switch connectionState {
        case .connecting:
            return currentStation.map { "Connecting to \($0.name)..." }
        case .reconnecting(let attempt):
            return "Reconnecting... (attempt \(attempt)/\(maxReconnectAttempts))"
        case .failed(let message):
            return "Connection failed: \(message)"
        case .connected:
            // Return stream title if available, otherwise station name
            if let title = effectiveStreamTitle {
                return title
            }
            return currentStation?.name
        case .disconnected:
            return nil
        }
    }
    
    /// Whether we're currently playing or trying to play radio
    var isActive: Bool {
        currentStation != nil
    }
}
