import Foundation

// MARK: - Cast Device Types

/// Type of cast device
public enum CastDeviceType: String, Codable, Equatable, Sendable {
    case chromecast = "chromecast"
    case sonos = "sonos"
    case dlnaTV = "dlnaTV"
    
    public var displayName: String {
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
public enum CastState: String, Equatable, Sendable {
    case idle
    case connecting
    case connected
    case casting
    case error
}

// MARK: - Cast Device

/// Represents a discovered cast device
public struct CastDevice: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let type: CastDeviceType
    public let address: String
    public let port: Int
    public let manufacturer: String?
    public let modelName: String?
    
    /// Whether this device supports video casting (Sonos is audio-only)
    public let supportsVideo: Bool
    
    /// URL for UPnP AVTransport control (for Sonos/DLNA)
    public var avTransportControlURL: URL?
    
    /// URL for UPnP device description (for Sonos/DLNA)
    public var descriptionURL: URL?
    
    public init(
        id: String,
        name: String,
        type: CastDeviceType,
        address: String,
        port: Int,
        manufacturer: String? = nil,
        modelName: String? = nil,
        supportsVideo: Bool? = nil,
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
        // Default supportsVideo based on device type (Sonos is audio-only)
        self.supportsVideo = supportsVideo ?? (type != .sonos)
        self.avTransportControlURL = avTransportControlURL
        self.descriptionURL = descriptionURL
    }
    
    public static func == (lhs: CastDevice, rhs: CastDevice) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Cast Session

/// Represents an active cast session
public final class CastSession: @unchecked Sendable {
    public let device: CastDevice
    public var state: CastState = .idle
    public var currentURL: URL?
    public var metadata: CastMetadata?
    public var position: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var volume: Float = 1.0
    
    public init(device: CastDevice) {
        self.device = device
    }
}

// MARK: - Cast Metadata

/// Metadata for the currently casting media
public struct CastMetadata: Sendable {
    public let title: String
    public let artist: String?
    public let album: String?
    public let artworkURL: URL?
    public let duration: TimeInterval?
    public let contentType: String
    public let mediaType: MediaType  // .audio or .video
    
    // Video-specific metadata (optional)
    public let resolution: String?   // e.g., "1920x1080"
    public let year: Int?
    public let summary: String?
    
    public init(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        artworkURL: URL? = nil,
        duration: TimeInterval? = nil,
        contentType: String = "audio/mpeg",
        mediaType: MediaType = .audio,
        resolution: String? = nil,
        year: Int? = nil,
        summary: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
        self.contentType = contentType
        self.mediaType = mediaType
        self.resolution = resolution
        self.year = year
        self.summary = summary
    }
    
    /// Generate DIDL-Lite metadata for UPnP devices
    public func toDIDLLite(streamURL: URL) -> String {
        let escapedTitle = title.xmlEscaped
        let durationStr = duration.map { formatDuration($0) } ?? "00:00:00"
        
        // Choose UPnP class and elements based on media type
        let upnpClass: String
        var extraElements = ""
        
        switch mediaType {
        case .audio:
            upnpClass = "object.item.audioItem.musicTrack"
            let escapedArtist = (artist ?? "Unknown Artist").xmlEscaped
            let escapedAlbum = (album ?? "Unknown Album").xmlEscaped
            extraElements = """
            <dc:creator>\(escapedArtist)</dc:creator>
            <upnp:artist>\(escapedArtist)</upnp:artist>
            <upnp:album>\(escapedAlbum)</upnp:album>
            """
        case .video:
            upnpClass = "object.item.videoItem.movie"
            if let year = year {
                extraElements += "<dc:date>\(year)-01-01</dc:date>\n"
            }
            if let summary = summary {
                extraElements += "<dc:description>\(summary.xmlEscaped)</dc:description>\n"
            }
            if let resolution = resolution {
                extraElements += "<upnp:resolution>\(resolution)</upnp:resolution>\n"
            }
        }
        
        var didl = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
        <item id="1" parentID="0" restricted="1">
        <dc:title>\(escapedTitle)</dc:title>
        \(extraElements)<upnp:class>\(upnpClass)</upnp:class>
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
public enum CastError: Error, LocalizedError, Sendable {
    case deviceNotFound
    case connectionFailed(String)
    case connectionTimeout
    case playbackFailed(String)
    case unsupportedDevice
    case invalidURL
    case noTrackPlaying
    case localServerError(String)
    case networkError(Error)
    case sessionNotActive
    case deviceOffline
    case authenticationRequired
    
    public var errorDescription: String? {
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
        case .noTrackPlaying:
            return "No track loaded. Load a track first, then cast."
        case .localServerError(let message):
            return "Local server error: \(message)"
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

extension String {
    /// XML-escape special characters
    var xmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
