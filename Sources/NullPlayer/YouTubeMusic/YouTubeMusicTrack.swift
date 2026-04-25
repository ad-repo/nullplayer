import Foundation

enum YouTubeMusicSourceKind: String, Codable, Sendable {
    case video
    case playlist
    case search
}

struct YouTubeMusicTrack: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let title: String
    let artist: String?
    let sourceURL: URL
    let videoID: String?
    let playlistID: String?
    let kind: YouTubeMusicSourceKind

    init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        sourceURL: URL,
        videoID: String? = nil,
        playlistID: String? = nil,
        kind: YouTubeMusicSourceKind
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.sourceURL = sourceURL
        self.videoID = videoID
        self.playlistID = playlistID
        self.kind = kind
    }

    var displayTitle: String {
        if let artist, !artist.isEmpty {
            return "\(artist) - \(title)"
        }
        return title
    }
}

enum YouTubeMusicURLParser {
    static func makeTrack(from rawValue: String) -> YouTubeMusicTrack? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let host = url.host?.lowercased(), isYouTubeHost(host) {
            let ids = extractIDs(from: url)
            let title = ids.videoID.map { "YouTube \($0)" }
                ?? ids.playlistID.map { "YouTube Playlist \($0)" }
                ?? url.lastPathComponent

            return YouTubeMusicTrack(
                title: title,
                sourceURL: url,
                videoID: ids.videoID,
                playlistID: ids.playlistID,
                kind: ids.playlistID == nil ? .video : .playlist
            )
        }

        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://music.youtube.com/search?q=\(encoded)") {
            return YouTubeMusicTrack(
                title: trimmed,
                sourceURL: url,
                videoID: nil,
                playlistID: nil,
                kind: .search
            )
        }

        return nil
    }

    static func embedURL(for track: YouTubeMusicTrack) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"

        if let videoID = track.videoID {
            components.path = "/embed/\(videoID)"
        } else {
            components.path = "/embed"
        }

        var items = [
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "rel", value: "0")
        ]

        if let playlistID = track.playlistID {
            items.append(URLQueryItem(name: "listType", value: "playlist"))
            items.append(URLQueryItem(name: "list", value: playlistID))
        }

        components.queryItems = items
        return components.url
    }

    private static func isYouTubeHost(_ host: String) -> Bool {
        host == "youtube.com"
            || host == "www.youtube.com"
            || host == "music.youtube.com"
            || host == "youtu.be"
            || host.hasSuffix(".youtube.com")
    }

    private static func extractIDs(from url: URL) -> (videoID: String?, playlistID: String?) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        let videoID = query.first(where: { $0.name == "v" })?.value
            ?? (url.host?.lowercased() == "youtu.be" ? url.pathComponents.dropFirst().first : nil)
        let playlistID = query.first(where: { $0.name == "list" })?.value
        return (videoID, playlistID)
    }
}
