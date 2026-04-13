import Foundation

public protocol BrowserPreferenceStoring: Sendable {
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    func set(_ value: Data?, forKey key: String)
    func set(_ value: String?, forKey key: String)
}

public struct UserDefaultsBrowserPreferenceStore: BrowserPreferenceStoring {
    public init() {}

    public func data(forKey key: String) -> Data? {
        UserDefaults.standard.data(forKey: key)
    }

    public func string(forKey key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    public func set(_ value: Data?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    public func set(_ value: String?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

public enum BrowserPreferences {
    public static var store: any BrowserPreferenceStoring = UserDefaultsBrowserPreferenceStore()
}

public enum ModernBrowserSource: Equatable, Codable, Sendable {
    case local
    case plex(serverId: String)
    case subsonic(serverId: String)
    case jellyfin(serverId: String)
    case emby(serverId: String)
    case radio

    public var isSubsonic: Bool { if case .subsonic = self { return true }; return false }
    public var isJellyfin: Bool { if case .jellyfin = self { return true }; return false }
    public var isEmby: Bool { if case .emby = self { return true }; return false }
    public var isPlex: Bool { if case .plex = self { return true }; return false }
    public var isRadio: Bool { if case .radio = self { return true }; return false }

    public var isRemote: Bool {
        switch self {
        case .local, .radio:
            return false
        case .plex, .subsonic, .jellyfin, .emby:
            return true
        }
    }

    public var displayName: String {
        switch self {
        case .local:
            return "LOCAL FILES"
        case .plex:
            return "PLEX"
        case .subsonic:
            return "SUBSONIC"
        case .jellyfin:
            return "JELLYFIN"
        case .emby:
            return "EMBY"
        case .radio:
            return "INTERNET RADIO"
        }
    }

    public var shortName: String {
        switch self {
        case .local:
            return "Local Files"
        case .plex:
            return "Plex"
        case .subsonic:
            return "Subsonic"
        case .jellyfin:
            return "Jellyfin"
        case .emby:
            return "Emby"
        case .radio:
            return "Radio"
        }
    }

    private static let userDefaultsKey = "BrowserSource"

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            BrowserPreferences.store.set(data, forKey: Self.userDefaultsKey)
        }
    }

    public static func load() -> ModernBrowserSource? {
        guard let data = BrowserPreferences.store.data(forKey: userDefaultsKey),
              let source = try? JSONDecoder().decode(ModernBrowserSource.self, from: data) else {
            return nil
        }
        return source
    }
}

public enum ModernBrowseMode: Int, CaseIterable, Sendable {
    case artists = 0
    case albums = 1
    case plists = 3
    case movies = 4
    case shows = 5
    case search = 6
    case radio = 7
    case history = 8

    public var title: String {
        switch self {
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .plists: return "Plists"
        case .movies: return "Movies"
        case .shows: return "Shows"
        case .search: return "Search"
        case .radio: return "Radio"
        case .history: return "Data"
        }
    }

    public var isVideoMode: Bool { self == .movies || self == .shows }
    public var isMusicMode: Bool { self == .artists || self == .albums || self == .plists }
    public var isRadioMode: Bool { self == .radio }
    public var isHistoryMode: Bool { self == .history }
}

public enum ModernBrowserSortOption: String, CaseIterable, Codable, Sendable {
    case nameAsc = "Name A-Z"
    case nameDesc = "Name Z-A"
    case dateAddedDesc = "Recently Added"
    case dateAddedAsc = "Oldest First"
    case yearDesc = "Year (Newest)"
    case yearAsc = "Year (Oldest)"

    public var shortName: String {
        switch self {
        case .nameAsc: return "A-Z"
        case .nameDesc: return "Z-A"
        case .dateAddedDesc: return "New"
        case .dateAddedAsc: return "Old"
        case .yearDesc: return "Year"
        case .yearAsc: return "Year"
        }
    }

    private static let userDefaultsKey = "BrowserSortOption"

    public func save() {
        BrowserPreferences.store.set(rawValue, forKey: Self.userDefaultsKey)
    }

    public static func load() -> ModernBrowserSortOption {
        guard let raw = BrowserPreferences.store.string(forKey: userDefaultsKey),
              let option = ModernBrowserSortOption(rawValue: raw) else {
            return .nameAsc
        }
        return option
    }
}
