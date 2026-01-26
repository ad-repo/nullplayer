import Foundation

/// Represents a playlist of tracks
public struct Playlist: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var trackURLs: [URL]
    public var createdAt: Date
    public var modifiedAt: Date
    
    public init(name: String, trackURLs: [URL] = []) {
        self.id = UUID()
        self.name = name
        self.trackURLs = trackURLs
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
    
    public mutating func addTrack(url: URL) {
        trackURLs.append(url)
        modifiedAt = Date()
    }
    
    public mutating func removeTrack(at index: Int) {
        guard index >= 0 && index < trackURLs.count else { return }
        trackURLs.remove(at: index)
        modifiedAt = Date()
    }
    
    public mutating func moveTrack(from source: Int, to destination: Int) {
        guard source >= 0 && source < trackURLs.count,
              destination >= 0 && destination < trackURLs.count else { return }
        let url = trackURLs.remove(at: source)
        trackURLs.insert(url, at: destination)
        modifiedAt = Date()
    }
}

// MARK: - M3U Support

extension Playlist {
    /// Export playlist to M3U format
    public func toM3U() -> String {
        var lines = ["#EXTM3U"]
        
        for url in trackURLs {
            lines.append(url.path)
        }
        
        return lines.joined(separator: "\n")
    }
}
