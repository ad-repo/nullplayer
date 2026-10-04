import Foundation

/// Sort state for one library-browser tab (browse mode). Shared by the classic and modern
/// browsers: both browse-mode enums use the same raw values (pinned by
/// `LibraryBrowserTabSortTests`), so one store keyed by `browseMode.rawValue` serves both.
struct LibraryBrowserTabSort: Codable, Equatable {
    var menuSort: ModernBrowserSortOption = .nameAsc
    /// Column header sort; overrides the menu sort when set
    var columnSortId: String?
    var columnSortAscending = true
}

enum LibraryBrowserTabSortStore {
    /// JSON `[String(modeRaw): LibraryBrowserTabSort]`. The `default` entry is the sort a tab
    /// starts from until it has its own.
    static let key = "BrowserTabSort"
    private static let defaultEntry = "default"

    // Global keys from before sort became per tab. Read only until the first save, which
    // writes them into the `default` entry so every tab starts from the user's previous sort.
    static let legacyMenuSortKey = "BrowserSortOption"
    static let legacyColumnSortIdKey = "BrowserColumnSortId"
    static let legacyColumnSortAscendingKey = "BrowserColumnSortAscending"

    static func load(modeRawValue: Int, defaults: UserDefaults = .standard) -> LibraryBrowserTabSort {
        let all = entries(defaults)
        return all[String(modeRawValue)] ?? all[defaultEntry] ?? LibraryBrowserTabSort()
    }

    static func save(_ sort: LibraryBrowserTabSort, modeRawValue: Int, defaults: UserDefaults = .standard) {
        var all = entries(defaults)
        all[String(modeRawValue)] = sort
        write(all, defaults)
    }

    /// Drop a hidden column's header sort from every saved tab, so no tab keeps sorting
    /// by a column it no longer shows.
    static func clearColumnSort(id: String, defaults: UserDefaults = .standard) {
        let all = entries(defaults)
        let cleared = all.mapValues { sort in
            var sort = sort
            if sort.columnSortId == id { sort.columnSortId = nil }
            return sort
        }
        if cleared != all { write(cleared, defaults) }
    }

    private static func entries(_ defaults: UserDefaults) -> [String: LibraryBrowserTabSort] {
        if let data = defaults.data(forKey: key),
           let all = try? JSONDecoder().decode([String: LibraryBrowserTabSort].self, from: data) {
            return all
        }
        return [defaultEntry: LibraryBrowserTabSort(
            menuSort: defaults.string(forKey: legacyMenuSortKey).flatMap(ModernBrowserSortOption.init) ?? .nameAsc,
            columnSortId: defaults.string(forKey: legacyColumnSortIdKey),
            columnSortAscending: defaults.object(forKey: legacyColumnSortAscendingKey) as? Bool ?? true
        )]
    }

    private static func write(_ all: [String: LibraryBrowserTabSort], _ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: key)
        }
    }
}
