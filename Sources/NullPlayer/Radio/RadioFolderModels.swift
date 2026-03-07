import Foundation

/// User-managed folder for organizing Internet Radio stations.
struct RadioUserFolder: Identifiable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
}

/// Folder kind used by the Internet Radio browser organization view.
enum RadioFolderKind: Hashable {
    case allStations
    case favorites
    case topRated
    case unrated
    case recentlyPlayed
    case byGenre
    case byRegion
    case userFoldersRoot
    case genre(String)
    case region(String)
    case manual(UUID)

    var id: String {
        switch self {
        case .allStations: return "radio-folder-all"
        case .favorites: return "radio-folder-favorites"
        case .topRated: return "radio-folder-top-rated"
        case .unrated: return "radio-folder-unrated"
        case .recentlyPlayed: return "radio-folder-recent"
        case .byGenre: return "radio-folder-by-genre"
        case .byRegion: return "radio-folder-by-region"
        case .userFoldersRoot: return "radio-folder-user-root"
        case .genre(let name): return "radio-folder-genre-\(name.lowercased())"
        case .region(let name): return "radio-folder-region-\(name.lowercased())"
        case .manual(let folderID): return "radio-folder-manual-\(folderID.uuidString.lowercased())"
        }
    }

    var isStationContainer: Bool {
        switch self {
        case .allStations, .favorites, .topRated, .unrated, .recentlyPlayed, .genre, .region, .manual:
            return true
        case .byGenre, .byRegion, .userFoldersRoot:
            return false
        }
    }

    var isSmart: Bool {
        switch self {
        case .manual, .userFoldersRoot:
            return false
        default:
            return true
        }
    }
}

/// Runtime descriptor used by radio browser views to render folder trees.
struct RadioFolderDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let kind: RadioFolderKind
    let parentID: String?
    let sortOrder: Int
    let hasChildren: Bool
}
