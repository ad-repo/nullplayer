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
        RadioStation(
            name: "SomaFM Groove Salad",
            url: URL(string: "https://ice2.somafm.com/groovesalad-128-mp3")!,
            genre: "Ambient/Chill"
        ),
        RadioStation(
            name: "SomaFM DEF CON Radio",
            url: URL(string: "https://ice2.somafm.com/defcon-128-mp3")!,
            genre: "Electronic"
        ),
        RadioStation(
            name: "SomaFM Drone Zone",
            url: URL(string: "https://ice2.somafm.com/dronezone-128-mp3")!,
            genre: "Ambient"
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
                    let track = resolvedStation.toTrack()
                    WindowManager.shared.audioEngine.loadTracks([track])
                    WindowManager.shared.audioEngine.play()
                } else {
                    NSLog("RadioManager: Failed to resolve playlist URL")
                    self.connectionState = .failed(message: "Could not resolve playlist URL")
                }
            }
        } else {
            // Direct stream URL - play immediately
            let track = station.toTrack()
            WindowManager.shared.audioEngine.loadTracks([track])
            WindowManager.shared.audioEngine.play()
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
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.attemptReconnect(station: station)
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
