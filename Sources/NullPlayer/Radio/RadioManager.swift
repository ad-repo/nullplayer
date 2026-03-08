import Foundation
import AppKit

/// Singleton managing internet radio station connections and state
class RadioManager {
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
    private static let defaultURLAliases: [String: String] = [
        "https://wgbh-live.streamguys1.com/wgbh": "https://wgbh-live.streamguys1.com/wgbh.mp3",
        "https://wgbh-live.streamguys1.com/wgbh.mp3": "https://wgbh-live.streamguys1.com/wgbh"
    ]
    private let ratingsStore = RadioStationRatingsStore.shared
    private let foldersStore = RadioStationFoldersStore.shared
    
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
            stations = Self.defaultStations
            return
        }
        stations = decoded
        NSLog("RadioManager: Loaded %d saved stations", stations.count)

        // Ensure existing users receive newly added defaults while still honoring
        // deleted-default tracking.
        addMissingDefaults()
    }
    
    private func saveStations() {
        guard let data = try? JSONEncoder().encode(stations) else { return }
        UserDefaults.standard.set(data, forKey: stationsKey)
    }

    private func postStationsDidChange() {
        NotificationCenter.default.post(name: Self.stationsDidChangeNotification, object: self)
    }
    
    /// Default stations to show for new users
    private static let defaultStations: [RadioStation] = [
        // MARK: - Ambient/Chill (Original defaults)
        RadioStation(
            name: "SomaFM Groove Salad",
            url: URL(string: "https://ice5.somafm.com/groovesalad-128-mp3")!,
            genre: "Ambient/Chill"
        ),
        RadioStation(
            name: "SomaFM DEF CON Radio",
            url: URL(string: "https://ice5.somafm.com/defcon-128-mp3")!,
            genre: "Electronic"
        ),
        RadioStation(
            name: "SomaFM Drone Zone",
            url: URL(string: "https://ice5.somafm.com/dronezone-128-mp3")!,
            genre: "Ambient"
        ),
        
        // MARK: - Metal
        RadioStation(
            name: "SomaFM Metal Detector",
            url: URL(string: "https://ice5.somafm.com/metal-128-mp3")!,
            genre: "Metal"
        ),
        RadioStation(
            name: "Nightride FM Darksynth",
            url: URL(string: "https://stream.nightride.fm/darksynth.mp3")!,
            genre: "Metal"
        ),
        RadioStation(
            name: "SomaFM Doomed",
            url: URL(string: "https://ice5.somafm.com/doomed-128-mp3")!,
            genre: "Metal"
        ),
        
        // MARK: - Rock
        RadioStation(
            name: "Radio Paradise Rock",
            url: URL(string: "http://stream.radioparadise.com/rock-128")!,
            genre: "Rock"
        ),
        RadioStation(
            name: "SomaFM Indie Pop Rocks",
            url: URL(string: "https://ice5.somafm.com/indiepop-128-mp3")!,
            genre: "Rock"
        ),
        RadioStation(
            name: "Nightride FM",
            url: URL(string: "https://stream.nightride.fm/nightride.mp3")!,
            genre: "Rock"
        ),
        
        // MARK: - Classic Rock
        RadioStation(
            name: "SomaFM Left Coast 70s",
            url: URL(string: "https://ice5.somafm.com/seventies-128-mp3")!,
            genre: "Classic Rock"
        ),
        RadioStation(
            name: "Radio Paradise",
            url: URL(string: "http://stream.radioparadise.com/aac-128")!,
            genre: "Classic Rock"
        ),
        RadioStation(
            name: "SomaFM Underground 80s",
            url: URL(string: "https://ice5.somafm.com/u80s-128-mp3")!,
            genre: "Classic Rock"
        ),
        
        // MARK: - Hip Hop
        RadioStation(
            name: "SomaFM Fluid",
            url: URL(string: "https://ice5.somafm.com/fluid-128-mp3")!,
            genre: "Hip Hop"
        ),
        RadioStation(
            name: "SomaFM Seven Inch Soul",
            url: URL(string: "https://ice5.somafm.com/7soul-128-mp3")!,
            genre: "Hip Hop"
        ),
        RadioStation(
            name: "SomaFM Beat Blender",
            url: URL(string: "https://ice5.somafm.com/beatblender-128-mp3")!,
            genre: "Hip Hop"
        ),
        
        // MARK: - Rap
        RadioStation(
            name: "SomaFM PopTron",
            url: URL(string: "https://ice5.somafm.com/poptron-128-mp3")!,
            genre: "Rap"
        ),
        RadioStation(
            name: "Nightride FM EBSM",
            url: URL(string: "https://stream.nightride.fm/ebsm.mp3")!,
            genre: "Rap"
        ),
        RadioStation(
            name: "SomaFM Black Rock FM",
            url: URL(string: "https://ice5.somafm.com/brfm-128-mp3")!,
            genre: "Rap"
        ),
        
        // MARK: - Jazz
        RadioStation(
            name: "SomaFM Sonic Universe",
            url: URL(string: "https://ice5.somafm.com/sonicuniverse-128-mp3")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "SomaFM Secret Agent",
            url: URL(string: "https://ice5.somafm.com/secretagent-128-mp3")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "SomaFM Illinois Street Lounge",
            url: URL(string: "https://ice5.somafm.com/illstreet-128-mp3")!,
            genre: "Jazz"
        ),
        
        // MARK: - Classical
        RadioStation(
            name: "SomaFM Bossa Beyond",
            url: URL(string: "https://ice5.somafm.com/bossa-128-mp3")!,
            genre: "Classical"
        ),
        RadioStation(
            name: "Classical KING FM",
            url: URL(string: "https://classicalking.streamguys1.com/king-fm-aac")!,
            genre: "Classical"
        ),
        RadioStation(
            name: "SomaFM ThistleRadio",
            url: URL(string: "https://ice5.somafm.com/thistle-128-mp3")!,
            genre: "Classical"
        ),
        
        // MARK: - EDM
        RadioStation(
            name: "SomaFM The Trip",
            url: URL(string: "https://ice5.somafm.com/thetrip-128-mp3")!,
            genre: "EDM"
        ),
        RadioStation(
            name: "SomaFM Dub Step Beyond",
            url: URL(string: "https://ice5.somafm.com/dubstep-128-mp3")!,
            genre: "EDM"
        ),
        RadioStation(
            name: "Nightride FM Chillsynth",
            url: URL(string: "https://stream.nightride.fm/chillsynth.mp3")!,
            genre: "EDM"
        ),
        
        // MARK: - NPR
        RadioStation(
            name: "NPR Program Stream",
            url: URL(string: "http://npr-ice.streamguys1.com/live.mp3")!,
            genre: "NPR"
        ),
        RadioStation(
            name: "WNYC 93.9 FM",
            url: URL(string: "https://fm939.wnyc.org/wnycfm")!,
            genre: "NPR"
        ),
        RadioStation(
            name: "WBUR Boston 90.9",
            url: URL(string: "http://wbur-sc.streamguys.com/wbur")!,
            genre: "NPR"
        ),
        RadioStation(
            name: "WERS Boston 88.9",
            url: URL(string: "http://marconi.emerson.edu:8000/wers")!,
            genre: "NPR"
        ),
        RadioStation(
            name: "GBH Boston 89.7",
            url: URL(string: "https://wgbh-live.streamguys1.com/wgbh.mp3")!,
            genre: "NPR"
        ),
        RadioStation(
            name: "WMBR Cambridge 88.1",
            url: URL(string: "https://wmbr.org:8002/hi")!,
            genre: "College Radio"
        ),

        // MARK: - Sports
        RadioStation(
            name: "98.5 The Sports Hub Boston",
            url: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/WBZFM.mp3")!,
            genre: "Sports"
        ),
        
        // MARK: - News
        RadioStation(
            name: "BBC World Service",
            url: URL(string: "http://stream.live.vc.bbcmedia.co.uk/bbc_world_service")!,
            genre: "News"
        ),

        // MARK: - Independent/Curated
        RadioStation(
            name: "NTS Radio 1",
            url: URL(string: "https://stream-relay-geo.ntslive.net/stream")!,
            genre: "Eclectic"
        ),
        RadioStation(
            name: "NTS Radio 2",
            url: URL(string: "https://stream-relay-geo.ntslive.net/stream2")!,
            genre: "Eclectic"
        ),
        RadioStation(
            name: "KEXP Seattle 90.3",
            url: URL(string: "https://kexp-mp3-128.streamguys1.com/kexp128.mp3")!,
            genre: "Rock"
        ),
        RadioStation(
            name: "WFMU Freeform Radio",
            url: URL(string: "https://stream0.wfmu.org/freeform-128k-primary.mp3")!,
            genre: "Freeform"
        ),
        RadioStation(
            name: "WFMU Rock 'n' Soul Radio",
            url: URL(string: "https://stream0.wfmu.org/rocknsoul-primary.mp3")!,
            genre: "Rock/Soul"
        ),
        RadioStation(
            name: "WFMU Give the Drummer Radio",
            url: URL(string: "https://stream0.wfmu.org/drummer-primary.mp3")!,
            genre: "Eclectic"
        ),
        RadioStation(
            name: "WFMU Sheena's Jungle Room",
            url: URL(string: "https://stream0.wfmu.org/sheena-primary.mp3")!,
            genre: "Exotica"
        ),
        RadioStation(
            name: "dublab Los Angeles",
            url: URL(string: "https://dublab.out.airtime.pro/dublab_a")!,
            genre: "Eclectic"
        ),
        RadioStation(
            name: "KCRW Eclectic24",
            url: URL(string: "https://streams.kcrw.com/e24_mp3")!,
            genre: "Eclectic"
        ),
        RadioStation(
            name: "KCRW Simulcast",
            url: URL(string: "https://streams.kcrw.com/kcrw_mp3")!,
            genre: "Public Radio"
        ),
        RadioStation(
            name: "KCRW News24",
            url: URL(string: "https://streams.kcrw.com/news24_mp3")!,
            genre: "News"
        ),

        // MARK: - Asian/Indian
        RadioStation(
            name: "AIR Vividh Bharati",
            url: URL(string: "https://air.pc.cdn.bitgravity.com/air/live/pbaudio001/playlist.m3u8")!,
            genre: "Indian"
        ),
        RadioStation(
            name: "AIR FM Gold Delhi",
            url: URL(string: "https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio005/hlspbaudio00564kbps.m3u8")!,
            genre: "Indian"
        ),
        RadioStation(
            name: "All India Radio News 24x7",
            url: URL(string: "https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio002/hlspbaudio002_Auto.m3u8")!,
            genre: "News"
        ),
        RadioStation(
            name: "Radio Mirchi Hindi",
            url: URL(string: "https://eu8.fastcast4u.com/proxy/clyedupq/stream")!,
            genre: "Bollywood"
        ),
        RadioStation(
            name: "Bollywood Gaane Purane",
            url: URL(string: "https://stream.zeno.fm/6n6ewddtad0uv")!,
            genre: "Bollywood"
        ),
        RadioStation(
            name: "Hindi Retro",
            url: URL(string: "https://stream.zeno.fm/v2zfmxef798uv")!,
            genre: "Bollywood"
        ),
        RadioStation(
            name: "Bombay Beats (1.FM)",
            url: URL(string: "https://strmreg.1.fm/bombaybeats_mobile_mp3")!,
            genre: "Bollywood"
        ),
        RadioStation(
            name: "Tamil 80s Radio",
            url: URL(string: "https://psrlive2.listenon.in/80?station=tamil80shitsradio")!,
            genre: "Tamil"
        ),
        RadioStation(
            name: "Mirchi Top 20",
            url: URL(string: "https://drive.uber.radio/uber/bollywoodnow/icecast.audio")!,
            genre: "Bollywood"
        ),
        RadioStation(
            name: "Radio Schizoid Psy",
            url: URL(string: "http://94.130.113.214:8000/schizoid")!,
            genre: "Psytrance"
        ),
        RadioStation(
            name: "Gensokyo Radio (JP)",
            url: URL(string: "https://stream.gensokyoradio.net/1")!,
            genre: "J-Pop/Anime"
        ),
        RadioStation(
            name: "J1 HITS (JP)",
            url: URL(string: "https://jenny.torontocast.com:2000/stream/J1HITS?_=184325")!,
            genre: "J-Pop"
        ),
        RadioStation(
            name: "J-Pop Sakura (JP)",
            url: URL(string: "https://quincy.torontocast.com:2070/stream.mp3")!,
            genre: "J-Pop"
        ),
        RadioStation(
            name: "Big B Radio K-pop",
            url: URL(string: "https://antares.dribbcast.com/proxy/kpop?mp=/s")!,
            genre: "K-Pop"
        ),

        // MARK: - Thai Music
        RadioStation(
            name: "Cool Fahrenheit",
            url: URL(string: "https://coolism-web.cdn.byteark.com/;stream/1")!,
            genre: "Thai Pop"
        ),
        RadioStation(
            name: "Flex 104.5",
            url: URL(string: "https://streaming.flexconnect.net/voiceflex/voiceflex/playlist.m3u8")!,
            genre: "Thai Pop"
        ),
        RadioStation(
            name: "Smooth 105.5",
            url: URL(string: "http://rstream.mcot.net:8000/fm1055")!,
            genre: "Easy Listening"
        ),
        RadioStation(
            name: "RequestRadio Dance",
            url: URL(string: "https://cast.requestradio.in.th:850//stream/3")!,
            genre: "Dance"
        ),
        RadioStation(
            name: "RequestRadio Inter",
            url: URL(string: "https://cast.requestradio.in.th:840//stream/3")!,
            genre: "World"
        ),
        RadioStation(
            name: "Lanna Radio",
            url: URL(string: "https://inter.lannaradio.com/radio/8000/radio.mp3")!,
            genre: "Thai"
        ),
        RadioStation(
            name: "BKK.FM",
            url: URL(string: "https://rsas.bkk.fm/radio")!,
            genre: "Alternative"
        ),
        RadioStation(
            name: "Chili Radio Thailand",
            url: URL(string: "https://stream.chiliradio.app/chiliclassics")!,
            genre: "Hits"
        ),
        RadioStation(
            name: "MCOT Radio Chiangmai FM100.75",
            url: URL(string: "https://live-org-01-cdn.mcot.net/RegionRadio/ChiangMai.stream_aac/playlist.m3u8")!,
            genre: "Thai Pop"
        ),
        RadioStation(
            name: "Talay 90.25 FM",
            url: URL(string: "https://stream.talay.asia/talay")!,
            genre: "Thai"
        ),
        RadioStation(
            name: "106 Family News Radio",
            url: URL(string: "https://radio11.plathong.net/7138/;stream.mp3")!,
            genre: "Thai"
        ),

        // MARK: - Additional SomaFM channels (alphabetical append, March 2026)
        // Genre labels map to SomaFM feed genre first token, title-cased.
        RadioStation(
            name: "SomaFM Boot Liquor",
            url: URL(string: "https://ice5.somafm.com/bootliquor-128-mp3")!,
            genre: "Americana"
        ),
        RadioStation(
            name: "SomaFM Chillits Radio",
            url: URL(string: "https://ice5.somafm.com/chillits-128-mp3")!,
            genre: "Chill"
        ),
        RadioStation(
            name: "SomaFM cliqhop idm",
            url: URL(string: "https://ice5.somafm.com/cliqhop-128-mp3")!,
            genre: "Electronic"
        ),
        RadioStation(
            name: "SomaFM Covers",
            url: URL(string: "https://ice5.somafm.com/covers-128-mp3")!,
            genre: "Eclectic"
        ),
        RadioStation(
            name: "SomaFM Deep Space One",
            url: URL(string: "https://ice5.somafm.com/deepspaceone-128-mp3")!,
            genre: "Ambient"
        ),
        RadioStation(
            name: "SomaFM Digitalis",
            url: URL(string: "https://ice5.somafm.com/digitalis-128-mp3")!,
            genre: "Electronic"
        ),
        RadioStation(
            name: "SomaFM Folk Forward",
            url: URL(string: "https://ice5.somafm.com/folkfwd-128-mp3")!,
            genre: "Folk"
        ),
        RadioStation(
            name: "SomaFM Groove Salad Classic",
            url: URL(string: "https://ice5.somafm.com/gsclassic-128-mp3")!,
            genre: "Ambient"
        ),
        RadioStation(
            name: "SomaFM Heavyweight Reggae",
            url: URL(string: "https://ice5.somafm.com/reggae-128-mp3")!,
            genre: "Reggae"
        ),
        RadioStation(
            name: "SomaFM Lush",
            url: URL(string: "https://ice5.somafm.com/lush-128-mp3")!,
            genre: "Electronic"
        ),
        RadioStation(
            name: "SomaFM Mission Control",
            url: URL(string: "https://ice5.somafm.com/missioncontrol-128-mp3")!,
            genre: "Ambient"
        ),
        RadioStation(
            name: "SomaFM n5MD Radio",
            url: URL(string: "https://ice5.somafm.com/n5md-128-mp3")!,
            genre: "Specials"
        ),
        RadioStation(
            name: "SomaFM SF 10-33",
            url: URL(string: "https://ice5.somafm.com/sf1033-128-mp3")!,
            genre: "Ambient"
        ),
        RadioStation(
            name: "SomaFM SF in SF",
            url: URL(string: "https://ice5.somafm.com/sfinsf-128-mp3")!,
            genre: "Spoken"
        ),
        RadioStation(
            name: "SomaFM SF Police Scanner",
            url: URL(string: "https://ice5.somafm.com/scanner-128-mp3")!,
            genre: "Live"
        ),
        RadioStation(
            name: "SomaFM Live",
            url: URL(string: "https://ice5.somafm.com/live-128-mp3")!,
            genre: "Live"
        ),
        RadioStation(
            name: "SomaFM Specials",
            url: URL(string: "https://ice5.somafm.com/specials-128-mp3")!,
            genre: "Specials"
        ),
        RadioStation(
            name: "SomaFM Space Station Soma",
            url: URL(string: "https://ice5.somafm.com/spacestation-128-mp3")!,
            genre: "Electronic"
        ),
        RadioStation(
            name: "SomaFM Suburbs of Goa",
            url: URL(string: "https://ice5.somafm.com/suburbsofgoa-128-mp3")!,
            genre: "World"
        ),
        RadioStation(
            name: "SomaFM Synphaera Radio",
            url: URL(string: "https://ice5.somafm.com/synphaera-128-mp3")!,
            genre: "Ambient"
        ),
        RadioStation(
            name: "SomaFM The Dark Zone",
            url: URL(string: "https://ice5.somafm.com/darkzone-128-mp3")!,
            genre: "Ambient"
        ),
        RadioStation(
            name: "SomaFM The In-Sound",
            url: URL(string: "https://ice5.somafm.com/insound-128-mp3")!,
            genre: "Pop"
        ),
        RadioStation(
            name: "SomaFM Tiki Time",
            url: URL(string: "https://ice5.somafm.com/tikitime-128-mp3")!,
            genre: "Tiki"
        ),
        RadioStation(
            name: "SomaFM Vaporwaves",
            url: URL(string: "https://ice5.somafm.com/vaporwaves-128-mp3")!,
            genre: "Electronic"
        ),

        // MARK: - Police / Scanner
        RadioStation(
            name: "Fairfax County Police, Fire and EMS",
            url: URL(string: "https://broadcastify.cdnstream1.com/28326")!,
            genre: "Scanner"
        ),
        RadioStation(
            name: "Tucson Police Dispatch",
            url: URL(string: "https://broadcastify.cdnstream1.com/22835")!,
            genre: "Scanner"
        ),
        RadioStation(
            name: "Rivercom Chelan / Douglas County Dispatch",
            url: URL(string: "https://broadcastify.cdnstream1.com/24557")!,
            genre: "Scanner"
        ),
        RadioStation(
            name: "Madison County Sheriff, Fire and EMS, Anderson Police",
            url: URL(string: "https://broadcastify.cdnstream1.com/24550")!,
            genre: "Scanner"
        ),
        RadioStation(
            name: "Jefferson County (NY) Police, Fire and EMS",
            url: URL(string: "https://broadcastify.cdnstream1.com/6007")!,
            genre: "Scanner"
        ),
        RadioStation(
            name: "Pittsburgh Police, Fire and EMS",
            url: URL(string: "https://broadcastify.cdnstream1.com/21738")!,
            genre: "Scanner"
        ),
        RadioStation(
            name: "Tillamook County Police EMS Radio",
            url: URL(string: "https://broadcastify.cdnstream1.com/16984")!,
            genre: "Scanner"
        ),
        RadioStation(
            name: "Greater New Haven Police Department",
            url: URL(string: "https://broadcastify.cdnstream1.com/8705")!,
            genre: "Scanner"
        ),
        RadioStation(
            name: "Travis County Law Enforcement",
            url: URL(string: "http://audio1.radioreference.com/907330774")!,
            genre: "Scanner"
        ),
        RadioStation(
            name: "East Coast Reflector WB2JPQ",
            url: URL(string: "https://broadcastify.cdnstream1.com/12560")!,
            genre: "Scanner"
        ),

        // MARK: - African / Caribbean
        RadioStation(
            name: "Trace FM Cote d'Ivoire",
            url: URL(string: "http://stream.trace.tv/trace_fm_ci-midfi.aac")!,
            genre: "Afrobeats"
        ),
        RadioStation(
            name: "Life Radio Cote d'Ivoire",
            url: URL(string: "https://cast4.asurahosting.com/proxy/life/stream")!,
            genre: "Afropop"
        ),
        RadioStation(
            name: "Africa Radio Abidjan",
            url: URL(string: "https://africaradio.ice.infomaniak.ch/abidjan128.mp3")!,
            genre: "African"
        ),
        RadioStation(
            name: "Dakar Musique",
            url: URL(string: "http://listen.senemultimedia.net:8090/stream")!,
            genre: "African"
        ),
        RadioStation(
            name: "Radio Thiossane",
            url: URL(string: "https://stream.radiothiossane.com/")!,
            genre: "African/Traditional"
        ),
        RadioStation(
            name: "East Africa Radio FM",
            url: URL(string: "https://eatv.radioca.st/stream")!,
            genre: "East African"
        ),
        RadioStation(
            name: "LagosJump Radio",
            url: URL(string: "https://radio.lagosjumpradio.com/listen/lagosjump_radio/radio.mp3")!,
            genre: "Afrobeats"
        ),
        RadioStation(
            name: "Softlife Afrofusion Radio",
            url: URL(string: "https://eu4.fastcast4u.com/proxy/softlife?mp=/1")!,
            genre: "Afrofusion"
        ),
        RadioStation(
            name: "Irie FM Jamaica",
            url: URL(string: "https://usa19.fastcast4u.com:7430/;")!,
            genre: "Reggae"
        ),
        RadioStation(
            name: "Jamaica Dancehall Radio",
            url: URL(string: "https://stream.jamaicadancehallradio.com/listen/jamaica_dancehall_radio/radio.mp3")!,
            genre: "Dancehall"
        ),
        RadioStation(
            name: "VOB 92.9 FM Barbados",
            url: URL(string: "https://ice66.securenetsystems.net/VOB929")!,
            genre: "Soca/Caribbean"
        ),
        RadioStation(
            name: "Q 100.7 FM Barbados",
            url: URL(string: "http://108.178.16.190:8000/1007fm.mp3")!,
            genre: "Reggae/Soca"
        ),
        RadioStation(
            name: "Scorch Radio 101.1 FM",
            url: URL(string: "https://stream.velalabs.co/scorch")!,
            genre: "Soca"
        ),
        RadioStation(
            name: "Bacchanal Radio",
            url: URL(string: "https://c13.radioboss.fm:18470/stream")!,
            genre: "Soca"
        ),
        RadioStation(
            name: "Tambrin Radio 92.7",
            url: URL(string: "https://ice42.securenetsystems.net/TAMBRIN")!,
            genre: "Caribbean"
        ),

        // MARK: - South America
        RadioStation(
            name: "Radio Saudade FM 99.7",
            url: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/SAUDADE_FMAAC.aac")!,
            genre: "Classic Hits"
        ),
        RadioStation(
            name: "Bossa Jazz Brasil",
            url: URL(string: "https://centova5.transmissaodigital.com:20104/live")!,
            genre: "Bossa Nova"
        ),
        RadioStation(
            name: "Aspen 102.3",
            url: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/ASPEN.mp3")!,
            genre: "Classic Hits"
        ),
        RadioStation(
            name: "Blue 100.7 FM",
            url: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/BLUE_FM_100_7AAC.aac")!,
            genre: "Classic Hits"
        ),
        RadioStation(
            name: "Olimpica Stereo Medellin 104.9",
            url: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/OLP_MEDELLINAAC.aac")!,
            genre: "Salsa/Vallenato"
        ),
        RadioStation(
            name: "Radioacktiva Bogota 97.9",
            url: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/RADIO_ACTIVAAAC.aac")!,
            genre: "Rock"
        ),
        RadioStation(
            name: "Concierto Chile",
            url: URL(string: "http://26643.live.streamtheworld.com/CONCIERTO_SC")!,
            genre: "Pop/Rock"
        ),
        RadioStation(
            name: "Radio Futuro Chile",
            url: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/FUTURO_SC.mp3")!,
            genre: "Rock"
        ),
        RadioStation(
            name: "Radio RPP Noticias",
            url: URL(string: "https://mdstrm.com/audio/5fab3416b5f9ef165cfab6e9/icecast.audio")!,
            genre: "News"
        ),
        RadioStation(
            name: "Canela Radio Guayaquil 90.5",
            url: URL(string: "https://canelaradio.makrodigital.com/stream/canelaradioguayaquil")!,
            genre: "Latin/Tropical"
        ),
        RadioStation(
            name: "Diblu FM 88.9",
            url: URL(string: "https://streamingecuador.net:9002/stream")!,
            genre: "Sports/Talk"
        ),
        RadioStation(
            name: "Rumba 98.1 FM Venezuela",
            url: URL(string: "https://cast20.plugstreaming.com:2020/stream/r981/;")!,
            genre: "Latin Pop"
        ),
        RadioStation(
            name: "RocaFM Clasicos Caracas",
            url: URL(string: "http://protostar.shoutca.st:8370/")!,
            genre: "Oldies"
        ),
        RadioStation(
            name: "Radio Fides La Paz",
            url: URL(string: "http://192.95.23.89:6358/stream")!,
            genre: "News"
        ),
        RadioStation(
            name: "Rock and Pop Paraguay",
            url: URL(string: "https://cp9.serverse.com/proxy/rockandpop/stream")!,
            genre: "Rock/Pop"
        ),
        RadioStation(
            name: "Radio ABC FM 98.5 Asuncion",
            url: URL(string: "https://media.streambrothers.com:8350/stream")!,
            genre: "Top 40"
        ),
        RadioStation(
            name: "Clasica 650 AM Uruguay",
            url: URL(string: "https://radios.iwstreaming.uy/8032/stream")!,
            genre: "Classical"
        ),

        // MARK: - Additional Jazz
        RadioStation(
            name: "WWOZ New Orleans",
            url: URL(string: "https://wwoz-sc.streamguys1.com/wwoz-hi.mp3")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "TSF Jazz",
            url: URL(string: "https://tsfjazz.ice.infomaniak.ch/tsfjazz-high.mp3")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "Radio Swiss Jazz",
            url: URL(string: "http://stream.srg-ssr.ch/m/rsj/mp3_128")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "ABC Jazz",
            url: URL(string: "https://abc.streamguys1.com/live/abcjazz/icecast.audio")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "Jazz Radio France",
            url: URL(string: "http://jazzradio.ice.infomaniak.ch/jazzradio-high.mp3")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "Jazz Radio Blues",
            url: URL(string: "http://jazzblues.ice.infomaniak.ch/jazzblues-high.mp3")!,
            genre: "Jazz/Blues"
        ),
        RadioStation(
            name: "Jazz Radio Classic Jazz",
            url: URL(string: "http://jazz-wr01.ice.infomaniak.ch/jazz-wr01-128.mp3")!,
            genre: "Classic Jazz"
        ),
        RadioStation(
            name: "Jazz Radio Latin Jazz",
            url: URL(string: "http://jazz-wr09.ice.infomaniak.ch/jazz-wr09-128.mp3")!,
            genre: "Latin Jazz"
        ),
        RadioStation(
            name: "Jazz Radio Electro Swing",
            url: URL(string: "http://jazz-wr04.ice.infomaniak.ch/jazz-wr04-128.mp3")!,
            genre: "Electro Swing"
        ),
        RadioStation(
            name: "Jazz Radio Manouche",
            url: URL(string: "http://jazz-wr02.ice.infomaniak.ch/jazz-wr02-128.mp3")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "Jazz Radio Piano Jazz",
            url: URL(string: "http://jzr-piano.ice.infomaniak.ch/jzr-piano.mp3")!,
            genre: "Piano Jazz"
        ),
        RadioStation(
            name: "Jazz Radio Only Women",
            url: URL(string: "http://jazz-wr16.ice.infomaniak.ch/jazz-wr16-128.mp3")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "FIP Jazz",
            url: URL(string: "http://icecast.radiofrance.fr/fipjazz-hifi.aac")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "1.FM Bay Smooth Jazz",
            url: URL(string: "http://strm112.1.fm/smoothjazz_mobile_mp3")!,
            genre: "Smooth Jazz"
        ),
        RadioStation(
            name: "The Jazz Groove East",
            url: URL(string: "http://east-mp3-128.streamthejazzgroove.com/stream")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "0 N Jazz Radio",
            url: URL(string: "https://0n-jazz.radionetz.de/0n-jazz.aac")!,
            genre: "Jazz"
        ),
        RadioStation(
            name: "0 N Smooth Jazz",
            url: URL(string: "https://0n-smoothjazz.radionetz.de/0n-smoothjazz.mp3")!,
            genre: "Smooth Jazz"
        ),

        // MARK: - Top Europe
        RadioStation(
            name: "Capital FM London",
            url: URL(string: "http://media-ice.musicradio.com/CapitalMP3")!,
            genre: "Pop"
        ),
        RadioStation(
            name: "Heart 80s UK",
            url: URL(string: "https://media-ssl.musicradio.com/Heart80sMP3")!,
            genre: "80s/Pop"
        ),
        RadioStation(
            name: "RFM France",
            url: URL(string: "https://stream.rfm.fr/rfm.mp3")!,
            genre: "Pop"
        ),
        RadioStation(
            name: "RTL2 France",
            url: URL(string: "http://streamer-02.rtl.fr/rtl2-1-44-128")!,
            genre: "Pop/Rock"
        ),
        RadioStation(
            name: "Skyrock France",
            url: URL(string: "http://icecast.skyrock.net/s/natio_mp3_128k")!,
            genre: "Hip-Hop"
        ),
        RadioStation(
            name: "SWR3 Germany",
            url: URL(string: "https://liveradio.swr.de/sw282p3/swr3/play.mp3")!,
            genre: "Pop/Rock"
        ),
        RadioStation(
            name: "1LIVE Germany",
            url: URL(string: "http://wdr-1live-live.icecast.wdr.de/wdr/1live/live/mp3/128/stream.mp3")!,
            genre: "Top 40"
        ),
        RadioStation(
            name: "Rock Antenne Germany",
            url: URL(string: "http://mp3channels.webradio.rockantenne.de/rockantenne")!,
            genre: "Rock"
        ),
        RadioStation(
            name: "Oldie Antenne Germany",
            url: URL(string: "https://s1-webradio.oldie-antenne.de/oldie-antenne?aw_0_1st.playerid=OldieAntenneWebPlayer")!,
            genre: "Oldies"
        ),
        RadioStation(
            name: "LOS 40 Spain",
            url: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/Los40.mp3")!,
            genre: "Top 40"
        ),
        RadioStation(
            name: "Cadena 100 Spain",
            url: URL(string: "http://cadena100-streamers-mp3.flumotion.com/cope/cadena100.mp3")!,
            genre: "Pop"
        ),
        RadioStation(
            name: "Rock FM Spain",
            url: URL(string: "http://flucast31-h-cloud.flumotion.com/cope/rockfm-low.mp3")!,
            genre: "Rock"
        ),
        RadioStation(
            name: "Ibiza Global Radio",
            url: URL(string: "http://ibizaglobalradio.streaming-pro.com:8024/")!,
            genre: "Electronic"
        ),
        RadioStation(
            name: "Virgin Radio Italia",
            url: URL(string: "http://icecast.unitedradio.it/Virgin.mp3")!,
            genre: "Pop/Rock"
        ),
        RadioStation(
            name: "Radio 105 Italy",
            url: URL(string: "http://icecast.unitedradio.it/Radio105.mp3")!,
            genre: "Top 40"
        ),
        RadioStation(
            name: "Radio Monte Carlo Italy",
            url: URL(string: "http://icecast.unitedradio.it/RMC.mp3")!,
            genre: "Adult Contemporary"
        ),
        RadioStation(
            name: "Radio 538 Netherlands",
            url: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/RADIO538.mp3")!,
            genre: "Top 40"
        ),
        RadioStation(
            name: "Qmusic Netherlands",
            url: URL(string: "https://icecast-qmusicnl-cdp.triple-it.nl/Qmusic_nl_live_96.mp3")!,
            genre: "Pop"
        ),
        RadioStation(
            name: "SLAM Netherlands",
            url: URL(string: "http://stream.slam.nl/slam")!,
            genre: "Dance"
        ),
        RadioStation(
            name: "Sky Radio Netherlands",
            url: URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/SKYRADIO.mp3")!,
            genre: "Pop"
        ),
        RadioStation(
            name: "RIX FM Sweden",
            url: URL(string: "https://fm01-ice.stream.khz.se/fm01_mp3")!,
            genre: "Pop"
        ),
        RadioStation(
            name: "Mix Megapol Sweden",
            url: URL(string: "https://live-bauerse-fm.sharp-stream.com/mixmegapol_instream_se_mp3")!,
            genre: "Pop"
        ),
        RadioStation(
            name: "NRK P3 Norway",
            url: URL(string: "https://cdn0-47115-liveicecast0.dna.contentdelivery.net/p3_mp3_h")!,
            genre: "Pop/Rock"
        ),
        RadioStation(
            name: "Qmusic Belgium",
            url: URL(string: "https://icecast-qmusicbe-cdp.triple-it.nl/qmusic.aac")!,
            genre: "Pop"
        ),
        RadioStation(
            name: "Studio Brussel",
            url: URL(string: "http://icecast.vrtcdn.be/stubru-high.mp3")!,
            genre: "Alternative/Pop"
        ),
        RadioStation(
            name: "ORF Hitradio O3",
            url: URL(string: "https://orf-live.ors-shoutcast.at/oe3-q2a")!,
            genre: "Pop"
        ),
        RadioStation(
            name: "FM4 Austria",
            url: URL(string: "https://orf-live.ors-shoutcast.at/fm4-q2a")!,
            genre: "Alternative"
        )
    ]
    
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
        case .byGenre, .byRegion, .userFoldersRoot:
            return []
        }
    }

    private func stationsSortedByName(_ items: [RadioStation]) -> [RadioStation] {
        items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                    WindowManager.shared.audioEngine.loadTracks([track])
                    // Only call play() for local playback - casting is handled by loadTracks
                    // Check casting state fresh here, not captured before async resolution,
                    // since user may have started casting during the network request
                    if !CastManager.shared.isCasting {
                        WindowManager.shared.audioEngine.play()
                    }
                } else {
                    NSLog("RadioManager: Failed to resolve playlist URL")
                    self.connectionState = .failed(message: "Could not resolve playlist URL")
                }
            }
        } else {
            // Direct stream URL - play immediately
            let track = station.toTrack()
            WindowManager.shared.audioEngine.loadTracks([track])
            // Only call play() for local playback - casting is handled by loadTracks
            if !CastManager.shared.isCasting {
                WindowManager.shared.audioEngine.play()
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
        let privateRanges = ["127.", "10.", "192.168.", "localhost"]
        if privateRanges.contains(where: { host.hasPrefix($0) }) { return true }
        // 172.16.0.0/12
        if host.hasPrefix("172."), let second = host.split(separator: ".").dropFirst().first,
           let octet = Int(second), (16...31).contains(octet) { return true }
        return false
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
