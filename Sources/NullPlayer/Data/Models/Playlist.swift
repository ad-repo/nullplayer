import Foundation

/// Represents a playlist of tracks
struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var trackURLs: [URL]
    var createdAt: Date
    var modifiedAt: Date
    
    init(name: String, trackURLs: [URL] = []) {
        self.id = UUID()
        self.name = name
        self.trackURLs = trackURLs
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
    
    mutating func addTrack(url: URL) {
        trackURLs.append(url)
        modifiedAt = Date()
    }
    
    mutating func removeTrack(at index: Int) {
        guard index >= 0 && index < trackURLs.count else { return }
        trackURLs.remove(at: index)
        modifiedAt = Date()
    }
    
    mutating func moveTrack(from source: Int, to destination: Int) {
        guard source >= 0 && source < trackURLs.count,
              destination >= 0 && destination < trackURLs.count else { return }
        let url = trackURLs.remove(at: source)
        trackURLs.insert(url, at: destination)
        modifiedAt = Date()
    }
}

// MARK: - Entry Resolution

extension Playlist {
    /// One playlist entry — a stream URL, an absolute path, or a path relative to the playlist's
    /// own directory — resolved to the URL it names.
    ///
    /// **`URL(string:)` is not a path parser.** On current Foundation it happily accepts
    /// `01 - Those Hills.flac` and returns a *schemeless, non-file* URL: `isFileURL` is false and
    /// nothing downstream can open it. Every call site that tested that initialiser for nil to
    /// decide "absolute or relative" therefore took the absolute branch for **every** entry, and
    /// the relative branch was dead code. That is how a playlist of bare filenames — the ordinary
    /// spelling of an `.m3u` written next to its music — became a playlist of unplayable entries,
    /// and it is why absolute entries were broken too: `/Users/…/a b.flac` came back schemeless
    /// as well, so it matched neither `isFileURL` nor an `http` scheme at playback time.
    ///
    /// Only a scheme longer than one character counts, so a Windows drive letter (`C:\Music\…`)
    /// is not mistaken for a `c:` URL scheme.
    static func resolveEntry(_ entry: String, relativeTo directory: URL) -> URL? {
        let trimmed = entry.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        if let parsed = URL(string: trimmed), let scheme = parsed.scheme, scheme.count > 1 {
            return scheme == "file" ? URL(fileURLWithPath: parsed.path) : parsed
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }

        return directory.appendingPathComponent(trimmed).standardizedFileURL
    }

    /// The local entries that resolved to a file that is not there.
    ///
    /// Resolution is a guess — a relative entry is resolved against the playlist file's own
    /// directory, which is right only while the playlist sits beside its music — and nothing used
    /// to check the guess. A playlist that had moved away from its tracks produced a full set of
    /// entries that all looked fine and none of which could play.
    var missingFileEntries: [URL] {
        trackURLs.filter { $0.isFileURL && !FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Parse an `.m3u`, `.m3u8` or `.pls` file, or return nil for anything else.
    static func load(from url: URL) -> Playlist? {
        switch url.pathExtension.lowercased() {
        case "m3u", "m3u8": return try? Playlist.fromM3U(url: url)
        case "pls":         return try? Playlist.fromPLS(url: url)
        default:            return nil
        }
    }
}

// MARK: - M3U Support

extension Playlist {
    /// Create playlist from M3U file
    static func fromM3U(url: URL) throws -> Playlist {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        let baseURL = url.deletingLastPathComponent()
        let trackURLs = lines.compactMap { resolveEntry($0, relativeTo: baseURL) }

        let name = url.deletingPathExtension().lastPathComponent
        return Playlist(name: name, trackURLs: trackURLs)
    }
    
    /// Export playlist to M3U format
    func toM3U() -> String {
        var lines = ["#EXTM3U"]
        
        for url in trackURLs {
            lines.append(url.path)
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Save playlist to M3U file
    func saveAsM3U(to url: URL) throws {
        let content = toM3U()
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - PLS Support

extension Playlist {
    /// Create playlist from PLS file
    static func fromPLS(url: URL) throws -> Playlist {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var trackURLs: [URL] = []
        let baseURL = url.deletingLastPathComponent()
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Look for File entries
            if trimmed.lowercased().hasPrefix("file") {
                if let equalsIndex = trimmed.firstIndex(of: "=") {
                    let path = String(trimmed[trimmed.index(after: equalsIndex)...])
                    if let trackURL = resolveEntry(path, relativeTo: baseURL) {
                        trackURLs.append(trackURL)
                    }
                }
            }
        }
        
        let name = url.deletingPathExtension().lastPathComponent
        return Playlist(name: name, trackURLs: trackURLs)
    }
}
