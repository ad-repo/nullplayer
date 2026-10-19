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
            jellyfinId: nil,
            jellyfinServerId: nil,
            artworkThumb: iconURL?.absoluteString,
            mediaType: .audio,
            genre: genre,
            isRadioOrigin: true
        )
    }
}

extension RadioStation {
    /// The streams in an M3U or PLS playlist, or failing either format, every http(s) line.
    static func stations(inPlaylist content: String, sourceURL: URL) -> [RadioStation] {
        let lines = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let ext = sourceURL.pathExtension.lowercased()
        let isStream = { (line: String) in line.hasPrefix("http://") || line.hasPrefix("https://") }

        if content.hasPrefix("#EXTM3U") || ext == "m3u" || ext == "m3u8" {
            var stations: [RadioStation] = []
            var currentTitle: String?
            for line in lines {
                if line.hasPrefix("#EXTINF:") {
                    // #EXTINF:-1,Station Name
                    if let comma = line.firstIndex(of: ",") { currentTitle = String(line[line.index(after: comma)...]) }
                } else if isStream(line) {
                    if let url = URL(string: line) {
                        stations.append(RadioStation(name: currentTitle ?? url.lastPathComponent, url: url))
                    }
                    currentTitle = nil
                }
            }
            return stations
        }

        if content.lowercased().contains("[playlist]") || ext == "pls" {
            // File1=http://…, Title1=Station Name
            var files: [Int: String] = [:]
            var titles: [Int: String] = [:]
            for line in lines {
                guard let equals = line.firstIndex(of: "=") else { continue }
                let key = line[..<equals].lowercased()
                let value = String(line[line.index(after: equals)...])
                if key.hasPrefix("file"), let n = Int(key.dropFirst(4)) { files[n] = value }
                if key.hasPrefix("title"), let n = Int(key.dropFirst(5)) { titles[n] = value }
            }
            return files.sorted { $0.key < $1.key }.compactMap { n, urlString in
                URL(string: urlString).map { RadioStation(name: titles[n] ?? $0.lastPathComponent, url: $0) }
            }
        }

        return lines.filter(isStream).compactMap { URL(string: $0) }.map { RadioStation(name: $0.lastPathComponent, url: $0) }
    }
}
