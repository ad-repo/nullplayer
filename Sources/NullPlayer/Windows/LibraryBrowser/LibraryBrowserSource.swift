import Foundation

/// Source for browsing content. Persisted under `"BrowserSource"`, so the case names are
/// part of the saved format.
enum LibraryBrowserSource: Equatable, Codable {
    case local
    case plex(serverId: String)
    case subsonic(serverId: String)
    case jellyfin(serverId: String)
    case emby(serverId: String)
    case radio
    case youtube

    /// Whether this is the local library
    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    /// Whether this is a Plex source
    var isPlex: Bool {
        if case .plex = self { return true }
        return false
    }
    
    /// Whether this is a radio source
    var isRadio: Bool {
        if case .radio = self { return true }
        return false
    }

    /// Whether this is a YouTube source
    var isYouTube: Bool {
        if case .youtube = self { return true }
        return false
    }

    /// YouTube reuses the Internet Radio tab's UI to list its channels/videos.
    var usesRadioTab: Bool { isRadio || isYouTube }

    /// The server of a remote source
    var serverId: String? {
        switch self {
        case .local, .radio, .youtube:
            return nil
        case .plex(let id), .subsonic(let id), .jellyfin(let id), .emby(let id):
            return id
        }
    }
    
    /// Persistence key
    private static let userDefaultsKey = "BrowserSource"
    
    /// Save to UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
    
    /// Load from UserDefaults
    static func load() -> LibraryBrowserSource? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let source = try? JSONDecoder().decode(LibraryBrowserSource.self, from: data) else {
            return nil
        }
        return source
    }
}
