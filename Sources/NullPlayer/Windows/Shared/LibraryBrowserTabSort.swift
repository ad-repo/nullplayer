import Foundation

/// Library browser Sort-menu options, shared by the classic and modern browsers and by
/// `MediaLibraryStore`'s paged queries.
enum LibraryBrowserSortOption: String, CaseIterable, Codable {
    case nameAsc = "Name A-Z"
    case nameDesc = "Name Z-A"
    case dateAddedDesc = "Recently Added"
    case dateAddedAsc = "Oldest First"
    case yearDesc = "Year (Newest)"
    case yearAsc = "Year (Oldest)"

    var shortName: String {
        switch self {
        case .nameAsc: return "A-Z"
        case .nameDesc: return "Z-A"
        case .dateAddedDesc: return "New"
        case .dateAddedAsc: return "Old"
        case .yearDesc: return "Year"
        case .yearAsc: return "Year"
        }
    }
}

/// Sort state for one library-browser tab (browse mode).
struct LibraryBrowserTabSort: Codable, Equatable {
    var menuSort: LibraryBrowserSortOption = .nameAsc
    /// Column header sort; overrides the menu sort when set
    var columnSortId: String?
    var columnSortAscending = true
}

/// Every library-browser tab's sort, shared by the classic and modern browsers (and every
/// instance of them): both browse-mode enums use the same raw values (pinned by
/// `LibraryBrowserTabSortTests`), so tabs are keyed by `browseMode.rawValue`. Each change is
/// saved at once.
final class LibraryBrowserTabSortStore {
    static let shared = LibraryBrowserTabSortStore()

    /// JSON `[String(modeRaw): LibraryBrowserTabSort]`, plus a `default` entry holding `fallback`.
    static let key = "BrowserTabSort"
    private static let fallbackEntry = "default"

    // Global keys from before sort became per tab. Read only while `key` is unset, to seed
    // `fallback` so every tab starts from the user's previous sort.
    static let legacyMenuSortKey = "BrowserSortOption"
    static let legacyColumnSortIdKey = "BrowserColumnSortId"
    static let legacyColumnSortAscendingKey = "BrowserColumnSortAscending"

    private let defaults: UserDefaults
    private var tabs: [String: LibraryBrowserTabSort]
    /// The sort a tab has until it gets its own
    private var fallback: LibraryBrowserTabSort

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var saved = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: LibraryBrowserTabSort].self, from: $0) } ?? [:]
        fallback = saved.removeValue(forKey: Self.fallbackEntry) ?? LibraryBrowserTabSort(
            menuSort: defaults.string(forKey: Self.legacyMenuSortKey).flatMap(LibraryBrowserSortOption.init) ?? .nameAsc,
            columnSortId: defaults.string(forKey: Self.legacyColumnSortIdKey),
            columnSortAscending: defaults.object(forKey: Self.legacyColumnSortAscendingKey) as? Bool ?? true
        )
        tabs = saved
    }

    func sort(for modeRawValue: Int) -> LibraryBrowserTabSort {
        tabs[String(modeRawValue)] ?? fallback
    }

    /// Sort-menu choice: becomes the tab's sole sort. A lingering column sort overrides the menu
    /// sort, so it would silently re-order the list on the next rebuild — e.g. snapping a
    /// date-sorted tab back to name order the moment a row is expanded.
    func setMenuSort(_ option: LibraryBrowserSortOption, for modeRawValue: Int) {
        update(modeRawValue) { sort in
            sort.menuSort = option
            sort.columnSortId = nil
        }
    }

    /// Column-header click: the sorted column toggles direction, a new column sorts ascending.
    func clickColumn(_ id: String, for modeRawValue: Int) {
        update(modeRawValue) { sort in
            sort.columnSortAscending = sort.columnSortId == id ? !sort.columnSortAscending : true
            sort.columnSortId = id
        }
    }

    /// Drop a hidden column's header sort from every tab, so no tab keeps sorting by a column
    /// it no longer shows.
    func dropColumn(_ id: String) {
        func dropped(_ sort: LibraryBrowserTabSort) -> LibraryBrowserTabSort {
            var sort = sort
            if sort.columnSortId == id { sort.columnSortId = nil }
            return sort
        }
        let newTabs = tabs.mapValues(dropped)
        let newFallback = dropped(fallback)
        guard newTabs != tabs || newFallback != fallback else { return }
        tabs = newTabs
        fallback = newFallback
        save()
    }

    private func update(_ modeRawValue: Int, _ change: (inout LibraryBrowserTabSort) -> Void) {
        var sort = sort(for: modeRawValue)
        change(&sort)
        tabs[String(modeRawValue)] = sort
        save()
    }

    private func save() {
        var all = tabs
        all[Self.fallbackEntry] = fallback
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
