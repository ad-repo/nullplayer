import Foundation

/// Sort state for one library-browser tab (browse mode). Shared by the classic and modern
/// browsers: both browse-mode enums use the same raw values, and both sort-option enums use
/// the same raw strings, so one store keyed by `browseMode.rawValue` serves both.
struct LibraryBrowserTabSort: Equatable {
    /// `BrowserSortOption` / `ModernBrowserSortOption` raw value
    var menuSortRawValue: String
    /// Column header sort; overrides the menu sort when set
    var columnSortId: String?
    var columnSortAscending: Bool
}

enum LibraryBrowserTabSortStore {
    /// `[String(modeRaw): ["menu": String, "column": String?, "ascending": Bool]]`
    static let key = "BrowserTabSort"

    // Global keys from before sort became per tab. Read as the fallback for a tab with no
    // saved entry, so every tab starts from the user's previous sort; never written again.
    static let legacyMenuSortKey = "BrowserSortOption"
    static let legacyColumnSortIdKey = "BrowserColumnSortId"
    static let legacyColumnSortAscendingKey = "BrowserColumnSortAscending"

    static let defaultMenuSortRawValue = "Name A-Z"

    static func load(modeRawValue: Int, defaults: UserDefaults = .standard) -> LibraryBrowserTabSort {
        let all = defaults.dictionary(forKey: key) ?? [:]
        if let entry = all[String(modeRawValue)] as? [String: Any] {
            return LibraryBrowserTabSort(
                menuSortRawValue: entry["menu"] as? String ?? defaultMenuSortRawValue,
                columnSortId: entry["column"] as? String,
                columnSortAscending: entry["ascending"] as? Bool ?? true
            )
        }
        return LibraryBrowserTabSort(
            menuSortRawValue: defaults.string(forKey: legacyMenuSortKey) ?? defaultMenuSortRawValue,
            columnSortId: defaults.string(forKey: legacyColumnSortIdKey),
            columnSortAscending: defaults.object(forKey: legacyColumnSortAscendingKey) as? Bool ?? true
        )
    }

    static func save(_ sort: LibraryBrowserTabSort, modeRawValue: Int, defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        var entry: [String: Any] = [
            "menu": sort.menuSortRawValue,
            "ascending": sort.columnSortAscending
        ]
        if let column = sort.columnSortId { entry["column"] = column }
        all[String(modeRawValue)] = entry
        defaults.set(all, forKey: key)
    }

    /// Drop a hidden column's header sort from every saved tab, so no tab keeps sorting
    /// by a column it no longer shows.
    static func clearColumnSort(id: String, defaults: UserDefaults = .standard) {
        // Tabs with no entry yet still fall back to the legacy column sort.
        if defaults.string(forKey: legacyColumnSortIdKey) == id {
            defaults.removeObject(forKey: legacyColumnSortIdKey)
        }
        guard var all = defaults.dictionary(forKey: key) else { return }
        var changed = false
        for (mode, value) in all {
            guard var entry = value as? [String: Any], entry["column"] as? String == id else { continue }
            entry.removeValue(forKey: "column")
            all[mode] = entry
            changed = true
        }
        if changed { defaults.set(all, forKey: key) }
    }
}
