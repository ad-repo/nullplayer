import Foundation

// MARK: - Cast Device Types

/// Type of cast device
enum CastDeviceType: String, Codable, Equatable {
    case chromecast = "chromecast"
    case sonos = "sonos"
    case dlnaTV = "dlnaTV"
    
    var displayName: String {
        switch self {
        case .chromecast:
            return "Chromecast"
        case .sonos:
            return "Sonos"
        case .dlnaTV:
            return "TVs"
        }
    }
}

/// State of a cast session
enum CastState: String, Equatable {
    case idle
    case connecting
    case connected
    case casting
    case error
}

// MARK: - Cast Device

/// Represents a discovered cast device
struct CastDevice: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let type: CastDeviceType
    let address: String
    let port: Int
    let manufacturer: String?
    let modelName: String?
    
    /// URL for UPnP AVTransport control (for Sonos/DLNA)
    var avTransportControlURL: URL?
    
    /// URL for UPnP device description (for Sonos/DLNA)
    var descriptionURL: URL?
    
    init(
        id: String,
        name: String,
        type: CastDeviceType,
        address: String,
        port: Int,
        manufacturer: String? = nil,
        modelName: String? = nil,
        avTransportControlURL: URL? = nil,
        descriptionURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.address = address
        self.port = port
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.avTransportControlURL = avTransportControlURL
        self.descriptionURL = descriptionURL
    }
    
    static func == (lhs: CastDevice, rhs: CastDevice) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Cast Session

/// Represents an active cast session
class CastSession {
    let device: CastDevice
    var state: CastState = .idle
    var currentURL: URL?
    var metadata: CastMetadata?
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 1.0
    
    init(device: CastDevice) {
        self.device = device
    }
}

// MARK: - Cast Metadata

/// Metadata for the currently casting media
struct CastMetadata {
    let title: String
    let artist: String?
    let album: String?
    let artworkURL: URL?
    let duration: TimeInterval?
    let contentType: String
    
    init(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        artworkURL: URL? = nil,
        duration: TimeInterval? = nil,
        contentType: String = "audio/mpeg"
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
        self.contentType = contentType
    }
    
    /// Generate DIDL-Lite metadata for UPnP devices
    func toDIDLLite(streamURL: URL) -> String {
        let escapedTitle = title.xmlEscaped
        let escapedArtist = (artist ?? "Unknown Artist").xmlEscaped
        let escapedAlbum = (album ?? "Unknown Album").xmlEscaped
        let durationStr = duration.map { formatDuration($0) } ?? "00:00:00"
        
        var didl = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
        <item id="1" parentID="0" restricted="1">
        <dc:title>\(escapedTitle)</dc:title>
        <dc:creator>\(escapedArtist)</dc:creator>
        <upnp:artist>\(escapedArtist)</upnp:artist>
        <upnp:album>\(escapedAlbum)</upnp:album>
        <upnp:class>object.item.audioItem.musicTrack</upnp:class>
        <res protocolInfo="http-get:*:\(contentType):*" duration="\(durationStr)">\(streamURL.absoluteString.xmlEscaped)</res>
        """
        
        if let artworkURL = artworkURL {
            didl += """
            <upnp:albumArtURI>\(artworkURL.absoluteString.xmlEscaped)</upnp:albumArtURI>
            """
        }
        
        didl += """
        </item>
        </DIDL-Lite>
        """
        
        return didl
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

// MARK: - Cast Errors

/// Errors that can occur during casting
enum CastError: Error, LocalizedError {
    case deviceNotFound
    case connectionFailed(String)
    case connectionTimeout
    case playbackFailed(String)
    case unsupportedDevice
    case invalidURL
    case networkError(Error)
    case sessionNotActive
    case deviceOffline
    case authenticationRequired
    
    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Cast device not found"
        case .connectionFailed(let reason):
            return "Failed to connect: \(reason)"
        case .connectionTimeout:
            return "Connection timed out"
        case .playbackFailed(let reason):
            return "Playback failed: \(reason)"
        case .unsupportedDevice:
            return "Device type not supported"
        case .invalidURL:
            return "Invalid media URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .sessionNotActive:
            return "No active cast session"
        case .deviceOffline:
            return "Cast device is offline"
        case .authenticationRequired:
            return "Authentication required for streaming"
        }
    }
}

// MARK: - String Extensions

private extension String {
    /// XML-escape special characters
    var xmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
