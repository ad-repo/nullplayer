import Foundation

enum LibraryColumnVisibilityGroup: String, CaseIterable {
    case artist
    case album
    case track
    case youtube

    var headerTitle: String {
        switch self {
        case .artist: return "Artist columns"
        case .album: return "Album columns"
        case .track: return "Track columns"
        case .youtube: return "Channel columns"
        }
    }

    var resetTitle: String {
        switch self {
        case .artist: return "Reset Artist Columns"
        case .album: return "Reset Album Columns"
        case .track: return "Reset Track Columns"
        case .youtube: return "Reset Channel Columns"
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

    /// The music group the list's one header shows: the most detailed one in the list, so expanding
    /// an artist brings up album columns and expanding an album brings up track columns. Every row
    /// fills those columns by meaning, so a parent's genre or rating stays under its own heading.
    static func headerGroup(_ rows: some Sequence<LibraryColumnVisibilityGroup?>) -> LibraryColumnVisibilityGroup? {
        let groups = Set(rows.compactMap { $0 })
        return [LibraryColumnVisibilityGroup.track, .album, .artist].first { groups.contains($0) }
    }

    static func channelSortValue(_ label: String) -> Double {
        switch label {
        case "Mono": return 1
        case "Stereo": return 2
        case "5.1": return 6
        case "7.1": return 8
        default:
            let decimalSeparator = UnicodeScalar(".")
            let numeric = label.unicodeScalars.filter {
                CharacterSet.decimalDigits.contains($0) || $0 == decimalSeparator
            }
            return Double(String(String.UnicodeScalarView(numeric))) ?? 0
        }
    }
}
