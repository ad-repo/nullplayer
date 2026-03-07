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
    private static let defaultURLAliases: [String: String] = [
        "https://wgbh-live.streamguys1.com/wgbh": "https://wgbh-live.streamguys1.com/wgbh.mp3",
        "https://wgbh-live.streamguys1.com/wgbh.mp3": "https://wgbh-live.streamguys1.com/wgbh"
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
            name: "GBH Boston 89.7",
            url: URL(string: "https://wgbh-live.streamguys1.com/wgbh.mp3")!,
            genre: "NPR"
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
    
    // MARK: - Playback
    
    /// Play a radio station
    func play(station: RadioStation) {
        manualStopRequested = false
        currentStation = station
        connectionState = .connecting
        reconnectAttempts = 0
        
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
            return URL(string: trimmed)
        }

        if let absolute = URL(string: trimmed, relativeTo: sourceURL)?.absoluteURL {
            return absolute
        }

        let base = sourceURL.deletingLastPathComponent()
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
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
