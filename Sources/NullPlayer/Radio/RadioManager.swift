import Foundation
import AppKit

/// Singleton managing internet radio station connections and state
class RadioManager {
    
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
                reconnectAttempts = 0
            }
        }
    }
    
    // MARK: - Stream Metadata
    
    /// Current stream title from ICY metadata (e.g., "Artist - Song")
    private(set) var currentStreamTitle: String? {
        didSet {
            if oldValue != currentStreamTitle {
                NotificationCenter.default.post(
                    name: Self.streamMetadataDidChangeNotification,
                    object: self,
                    userInfo: currentStreamTitle.map { ["streamTitle": $0] }
                )
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
    
    /// Whether a manual stop was requested (don't auto-reconnect)
    private var manualStopRequested = false
    
    // MARK: - UserDefaults Keys
    
    private let stationsKey = "RadioStations"
    private let deletedDefaultsKey = "RadioDeletedDefaults"
    
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
        Self.defaultStations.contains { $0.url == url }
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
            url: URL(string: "https://wgbh-live.streamguys1.com/wgbh")!,
            genre: "NPR"
        ),
        
        // MARK: - News
        RadioStation(
            name: "BBC World Service",
            url: URL(string: "http://stream.live.vc.bbcmedia.co.uk/bbc_world_service")!,
            genre: "News"
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
            if deleted.contains(defaultStation.url.absoluteString) {
                continue
            }
            // Check if station with same URL already exists
            let exists = stations.contains { $0.url == defaultStation.url }
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
    
    /// Resolve a playlist URL (.pls, .m3u) to get the actual stream URL
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
        
        // PLS format
        if ext == "pls" || content.lowercased().contains("[playlist]") {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix("file") {
                    if let equalIndex = trimmed.firstIndex(of: "=") {
                        let urlString = String(trimmed[trimmed.index(after: equalIndex)...])
                        if let url = URL(string: urlString) {
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
            // Check if it's a valid URL
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                if let url = URL(string: trimmed) {
                    return url
                }
            }
        }
        
        return nil
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
        NSLog("RadioManager: Cast connected")
    }
    
    /// Called when stream metadata is received (ICY)
    func streamDidReceiveMetadata(_ metadata: [String: String]) {
        // Extract stream title (format: "Artist - Song" or just station info)
        if let streamTitle = metadata["StreamTitle"] ?? metadata["icy-name"] {
            let trimmed = streamTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                currentStreamTitle = trimmed
                NSLog("RadioManager: Stream title: %@", trimmed)
            }
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
            if let title = currentStreamTitle {
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
