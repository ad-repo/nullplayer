import Foundation

/// Represents a single audio track
struct Track: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let bitrate: Int?
    let sampleRate: Int?
    let channels: Int?
    
    init(url: URL) {
        self.id = UUID()
        self.url = url
        
        // Try to parse metadata
        // For now, use filename as title
        self.title = url.deletingPathExtension().lastPathComponent
        self.artist = nil
        self.album = nil
        self.duration = nil
        self.bitrate = nil
        self.sampleRate = nil
        self.channels = nil
    }
    
    init(id: UUID = UUID(),
         url: URL,
         title: String,
         artist: String? = nil,
         album: String? = nil,
         duration: TimeInterval? = nil,
         bitrate: Int? = nil,
         sampleRate: Int? = nil,
         channels: Int? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
    }
    
    /// Display title (artist - title or just title)
    var displayTitle: String {
        if let artist = artist, !artist.isEmpty {
            return "\(artist) - \(title)"
        }
        return title
    }
    
    /// Formatted duration string (MM:SS)
    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Hashable

extension Track: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
