import Foundation

/// The list's columns: which a row draws, which the user shows in each group, and their widths.
/// Each view keeps its own visible columns (under its `keyPrefix`); both share one set of widths.
extension LibraryBrowserModel {

    /// The column group a row's cells belong to; nil for a row drawn as a plain title line.
    func columnGroup(for item: LibraryBrowserItem) -> LibraryColumnVisibilityGroup? {
        switch item.type {
        case .track, .subsonicTrack, .localTrack, .jellyfinTrack, .embyTrack:
            return .track
        case .album, .subsonicAlbum, .localAlbum, .jellyfinAlbum, .embyAlbum:
            return .album
        case .artist, .subsonicArtist, .localArtist, .jellyfinArtist, .embyArtist:
            return item.indentLevel == 0 ? .artist : nil
        case .youtubeVideo:
            return .youtube
        default:
            return nil
        }
    }

    func isInternetRadioItem(_ item: LibraryBrowserItem) -> Bool {
        guard case .radio = currentSource, case .radioStation = item.type else { return false }
        return true
    }

    var hasInternetRadioColumns: Bool {
        guard case .radio = currentSource else { return false }
        return displayItems.contains(where: isInternetRadioItem)
    }

    /// YouTube channel uploads render through the resizable column path (title + time),
    /// gated on the "Channels" view actually containing video rows.
    var hasYouTubeColumns: Bool {
        guard radioSlotShowingChannels || isYouTubeChannelSearch else { return false }
        return displayItems.contains { if case .youtubeVideo = $0.type { return true }; return false }
    }

    func currentColumnGroup() -> LibraryColumnVisibilityGroup? {
        if hasYouTubeColumns { return .youtube }
        return LibraryColumnVisibility.headerGroup(displayItems.lazy.map { self.columnGroup(for: $0) })
    }

    /// Whether a row draws columns rather than a plain title line.
    func drawsColumns(_ item: LibraryBrowserItem) -> Bool {
        columnGroup(for: item) != nil || isInternetRadioItem(item)
    }

    /// The header's columns for the list's column group; radio has its own fixed set and no group.
    func headerColumns(for group: LibraryColumnVisibilityGroup?) -> [LibraryBrowserColumn] {
        if hasInternetRadioColumns { return LibraryBrowserColumn.internetRadioColumns }
        guard let group else { return [] }
        return LibraryColumnVisibility.visibleColumns(allColumns: LibraryBrowserColumn.all(for: group),
                                                      visibleIds: visibleColumnIds(for: group)) { $0.id.rawValue }
    }

    func visibleColumnIds(for group: LibraryColumnVisibilityGroup) -> [String] {
        switch group {
        case .artist: return normalizedColumnIds(visibleArtistColumnIds, group: .artist)
        case .album: return normalizedColumnIds(visibleAlbumColumnIds, group: .album)
        case .track: return normalizedColumnIds(visibleTrackColumnIds, group: .track)
        // YouTube columns are fixed (not user-hideable); always the full set.
        case .youtube: return LibraryBrowserColumn.defaultYouTubeColumnIds
        }
    }

    func setVisibleColumnIds(_ ids: [String], for group: LibraryColumnVisibilityGroup) {
        switch group {
        case .artist: visibleArtistColumnIds = normalizedColumnIds(ids, group: .artist)
        case .album: visibleAlbumColumnIds = normalizedColumnIds(ids, group: .album)
        case .track: visibleTrackColumnIds = normalizedColumnIds(ids, group: .track)
        case .youtube: break
        }
    }

    private func normalizedColumnIds(_ ids: [String], group: LibraryColumnVisibilityGroup) -> [String] {
        LibraryColumnVisibility.normalizedIds(ids, allIds: LibraryBrowserColumn.all(for: group).map(\.id.rawValue))
    }

    func saveVisibleColumns() {
        UserDefaults.standard.set(visibleTrackColumnIds, forKey: keyPrefix + "BrowserVisibleTrackColumns")
        UserDefaults.standard.set(visibleAlbumColumnIds, forKey: keyPrefix + "BrowserVisibleAlbumColumns")
        UserDefaults.standard.set(visibleArtistColumnIds, forKey: keyPrefix + "BrowserVisibleArtistColumns")
    }

    func loadColumns() {
        let defaults = UserDefaults.standard
        if let saved = defaults.dictionary(forKey: Self.columnWidthsKey) as? [String: CGFloat] {
            columnWidths = Self.migratedColumnWidths(saved)
        }
        if let saved = defaults.stringArray(forKey: keyPrefix + "BrowserVisibleTrackColumns") {
            visibleTrackColumnIds = normalizedColumnIds(saved, group: .track)
        }
        if let saved = defaults.stringArray(forKey: keyPrefix + "BrowserVisibleAlbumColumns") {
            visibleAlbumColumnIds = normalizedColumnIds(saved, group: .album)
        }
        if let saved = defaults.stringArray(forKey: keyPrefix + "BrowserVisibleArtistColumns") {
            visibleArtistColumnIds = normalizedColumnIds(saved, group: .artist)
        }
    }

    // MARK: - Showing and hiding

    /// A column-menu tick: show or hide `id` in `group`. A hidden column stops sorting any tab.
    func setColumn(_ id: LibraryBrowserColumn.ID, visible: Bool, in group: LibraryColumnVisibilityGroup) {
        guard id != .title else { return }
        var ids = visibleColumnIds(for: group)
        if visible {
            if !ids.contains(id.rawValue) { ids.append(id.rawValue) }
        } else {
            ids.removeAll { $0 == id.rawValue }
            LibraryBrowserTabSortStore.shared.dropColumn(id.rawValue)
        }
        setVisibleColumnIds(ids, for: group)
        onChange?(.columns)
    }

    /// The group's default columns at their default widths.
    func resetColumns(_ group: LibraryColumnVisibilityGroup) {
        setVisibleColumnIds(LibraryBrowserColumn.defaultIds(for: group), for: group)
        let prefix = "\(group.rawValue):"
        columnWidths = columnWidths.filter { !$0.key.hasPrefix(prefix) }
        onChange?(.columns)
    }

    /// The column menu's group: the header's own, since every row shows those columns. YouTube's
    /// and Internet Radio's columns are fixed, so they have none.
    var configurableColumnGroup: LibraryColumnVisibilityGroup? {
        guard !hasInternetRadioColumns, let group = currentColumnGroup(), group != .youtube else { return nil }
        return group
    }

    // MARK: - Widths

    static let columnWidthsKey = "BrowserColumnWidths"

    func storedColumnWidth(for column: LibraryBrowserColumn, group: LibraryColumnVisibilityGroup?) -> CGFloat? {
        columnWidths[Self.columnWidthKey(column.id, group: group)]
    }

    /// Each column's width across `available`: its stored width, else its minimum. Until it is
    /// resized, Title takes what the others leave.
    func widths(of columns: [LibraryBrowserColumn], group: LibraryColumnVisibilityGroup?,
                available: CGFloat) -> [CGFloat] {
        let fixed = columns.filter { $0.id != .title }.reduce(0) { $0 + (storedColumnWidth(for: $1, group: group) ?? $1.minWidth) }
        return columns.map { column in
            if column.id == .title {
                return max(column.minWidth, storedColumnWidth(for: column, group: group) ?? available - fixed - 8)
            }
            return storedColumnWidth(for: column, group: group) ?? column.minWidth
        }
    }

    /// The columns' width with their leading and trailing inset; past `available`, the list
    /// scrolls sideways.
    func totalWidth(of columns: [LibraryBrowserColumn], group: LibraryColumnVisibilityGroup?,
                    available: CGFloat) -> CGFloat {
        8 + widths(of: columns, group: group, available: available).reduce(0, +)
    }

    func setColumnWidth(_ width: CGFloat, for id: LibraryBrowserColumn.ID, group: LibraryColumnVisibilityGroup) {
        columnWidths[Self.columnWidthKey(id, group: group)] = width
    }

    private static func columnWidthKey(_ id: LibraryBrowserColumn.ID, group: LibraryColumnVisibilityGroup?) -> String {
        group.map { "\($0.rawValue):\(id.rawValue)" } ?? id.rawValue
    }

    /// Widths saved before they were kept per group apply to every group with that column.
    private static func migratedColumnWidths(_ saved: [String: CGFloat]) -> [String: CGFloat] {
        var migrated: [String: CGFloat] = [:]
        for (key, width) in saved {
            if key.contains(":") {
                migrated[key] = width
                continue
            }
            for group in LibraryColumnVisibilityGroup.allCases {
                guard let column = LibraryBrowserColumn.all(for: group).first(where: { $0.id.rawValue == key }) else { continue }
                migrated[columnWidthKey(column.id, group: group)] = width
            }
        }
        return migrated
    }
}
