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

// MARK: - M3U Support

extension Playlist {
    /// Create playlist from M3U file
    static func fromM3U(url: URL) throws -> Playlist {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var trackURLs: [URL] = []
        let baseURL = url.deletingLastPathComponent()
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments/extended info
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Handle relative and absolute paths
            if trimmed.hasPrefix("/") || trimmed.contains("://") {
                if let trackURL = URL(string: trimmed) {
                    trackURLs.append(trackURL)
                }
            } else {
                let trackURL = baseURL.appendingPathComponent(trimmed)
                trackURLs.append(trackURL)
            }
        }
        
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
                        .trimmingCharacters(in: .whitespaces)
                    
                    if path.hasPrefix("/") || path.contains("://") {
                        if let trackURL = URL(string: path) {
                            trackURLs.append(trackURL)
                        }
                    } else {
                        let trackURL = baseURL.appendingPathComponent(path)
                        trackURLs.append(trackURL)
                    }
                }
            }
        }
        
        let name = url.deletingPathExtension().lastPathComponent
        return Playlist(name: name, trackURLs: trackURLs)
    }
}
