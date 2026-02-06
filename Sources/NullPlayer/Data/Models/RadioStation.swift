import Foundation

/// Represents an internet radio station (Shoutcast, Icecast, etc.)
struct RadioStation: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var url: URL
    var genre: String?
    var iconURL: URL?  // Station logo if available
    
    init(id: UUID = UUID(), name: String, url: URL, genre: String? = nil, iconURL: URL? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.genre = genre
        self.iconURL = iconURL
    }
    
    /// Create a Track from this radio station for playback
    func toTrack() -> Track {
        Track(
            id: UUID(),
            url: url,
            title: name,
            artist: nil,
            album: genre,
            duration: nil,  // Radio streams have no duration
            bitrate: nil,
            sampleRate: nil,
            channels: nil,
            plexRatingKey: nil,
            subsonicId: nil,
            subsonicServerId: nil,
            artworkThumb: iconURL?.absoluteString,
            mediaType: .audio,
            genre: genre
        )
    }
}
