import Foundation

enum LibraryColumnVisibilityGroup: String, CaseIterable {
    case artist
    case album
    case track

    var headerTitle: String {
        switch self {
        case .artist: return "Artist columns"
        case .album: return "Album columns"
        case .track: return "Track columns"
        }
    }

    var resetTitle: String {
        switch self {
        case .artist: return "Reset Artist Columns"
        case .album: return "Reset Album Columns"
        case .track: return "Reset Track Columns"
        }
    }
}

enum LibraryColumnVisibility {
    static func normalizedIds(_ visibleIds: [String], allIds: [String]) -> [String] {
        let validIds = Set(allIds)
        var normalizedIds: [String] = []

        for id in visibleIds where validIds.contains(id) && !normalizedIds.contains(id) {
            normalizedIds.append(id)
        }

        if validIds.contains("title"), !normalizedIds.contains("title") {
            normalizedIds.insert("title", at: 0)
        }

        return normalizedIds
    }

    static func visibleColumns<Column>(
        allColumns: [Column],
        visibleIds: [String],
        id: (Column) -> String
    ) -> [Column] {
        let normalized = normalizedIds(visibleIds, allIds: allColumns.map(id))
        return normalized.compactMap { columnId in
            allColumns.first { id($0) == columnId }
        }
    }

    static func menuGroups(
        isArtistsMode: Bool,
        isAlbumsMode: Bool,
        hasTrackRows: Bool,
        hasAlbumRows: Bool,
        hasArtistRows: Bool
    ) -> [LibraryColumnVisibilityGroup] {
        if isArtistsMode {
            return [.artist, .album, .track]
        }
        if isAlbumsMode {
            return [.album, .track]
        }
        if hasTrackRows {
            return [.track]
        }
        if hasAlbumRows {
            return [.album]
        }
        if hasArtistRows {
            return [.artist]
        }
        return []
    }
}
