import Foundation

/// Column-header sort: re-orders the built rows by the clicked column.
extension LibraryBrowserModel {

    /// Apply the active column sort to `displayItems`.
    /// - Parameter collapseExpanded: Collapse every expanded row first (when the sort changes), so
    ///   no child row is left under a parent that moved.
    func applyColumnSort(collapseExpanded: Bool = false) {
        guard let sortColumnId = activeColumnSortId, !displayItems.isEmpty else { return }

        if collapseExpanded {
            let expandedCount = expanded.count
            collapseLibraryRows()
            if expanded.count != expandedCount {
                displayItems = displayItems.filter { $0.indentLevel == 0 }
            }
        }

        guard let sortColumn = LibraryBrowserColumn.findColumn(id: sortColumnId) else { return }
        if applyInternetRadioColumnSort(sortColumn: sortColumn, ascending: activeColumnSortAscending) { return }
        if applyYouTubeColumnSort(sortColumn: sortColumn) { return }

        // When rows are expanded, the build order comes from the store (SQLite BINARY
        // collation), which diverges from the in-memory column sort (LibraryTextSorter:
        // diacritic-insensitive, numeric, article-stripping) precisely around special
        // characters / case / leading articles. Re-sort the top-level groups — each level-0
        // leader plus its contiguous descendants — so expanding a row keeps the same
        // top-level order instead of snapping back to the raw store order.
        if displayItems.contains(where: { $0.indentLevel > 0 }) {
            sortNestedGroupsByColumn(sortColumn: sortColumn)
            return
        }

        // A flat list: sort the column rows in place, leaving any other row where it is
        let sortableIndices = displayItems.indices.filter { drawsColumns(displayItems[$0]) && displayItems[$0].indentLevel == 0 }
        guard !sortableIndices.isEmpty else { return }
        let sorted = stableColumnSortedItems(sortableIndices.map { displayItems[$0] }, sortColumn: sortColumn)
        var items = displayItems
        for (sortedIndex, originalIndex) in sortableIndices.enumerated() {
            items[originalIndex] = sorted[sortedIndex]
        }
        displayItems = items
    }

    /// Reorders the top-level groups in `displayItems` (a level-0 leader plus its contiguous
    /// descendants) by the active column, keeping each group's internal order intact. Bails
    /// to the build order if any top-level row is not sortable (e.g. a section header) or if a
    /// nested row appears before any leader, since grouping would be ambiguous there.
    private func sortNestedGroupsByColumn(sortColumn: LibraryBrowserColumn) {
        var groups: [[LibraryBrowserItem]] = []
        for item in displayItems {
            if item.indentLevel == 0 {
                guard drawsColumns(item) else { return }
                groups.append([item])
            } else if !groups.isEmpty {
                groups[groups.count - 1].append(item)
            } else {
                return
            }
        }
        displayItems = stableColumnSorted(groups, sortColumn: sortColumn) { $0[0] }.flatMap { $0 }
    }

    /// Sorts column-capable rows while preserving their current order for equal keys.
    private func stableColumnSortedItems(_ items: [LibraryBrowserItem], sortColumn: LibraryBrowserColumn) -> [LibraryBrowserItem] {
        stableColumnSorted(items, sortColumn: sortColumn) { $0 }
    }

    /// Sorts by each element's leading row, keeping the current order for equal keys.
    private func stableColumnSorted<Element>(_ elements: [Element], sortColumn: LibraryBrowserColumn,
                                             row: (Element) -> LibraryBrowserItem) -> [Element] {
        let ascending = activeColumnSortAscending
        return elements.enumerated().sorted { lhs, rhs in
            let left = row(lhs.element), right = row(rhs.element)
            if columnSortAreInOrder(left, right, sortColumn: sortColumn, ascending: ascending) { return true }
            if columnSortAreInOrder(right, left, sortColumn: sortColumn, ascending: ascending) { return false }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Ordering predicate shared by the flat and nested column-sort paths so both produce
    /// an identical top-level order. `a` and `b` are level-0 rows.
    private func columnSortAreInOrder(_ a: LibraryBrowserItem, _ b: LibraryBrowserItem,
                                      sortColumn: LibraryBrowserColumn, ascending: Bool) -> Bool {
        func ordered<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> Bool {
            ascending ? lhs < rhs : lhs > rhs
        }
        switch sortColumn.id {
        // Date columns: sort by raw date, not formatted string
        case .dateAdded, .lastPlayed, .youtubeDate:
            return ordered(a.columnDateValue(for: sortColumn) ?? .distantPast, b.columnDateValue(for: sortColumn) ?? .distantPast)
        default:
            break
        }
        let aVal = a.columnValue(for: sortColumn)
        let bVal = b.columnValue(for: sortColumn)
        switch sortColumn.id {
        case .trackNum, .year, .plays, .albums, .discNum:
            // "2-5" (disc-track) sorts by its track number
            let number = { (value: String) in Int(value.components(separatedBy: "-").last ?? value) ?? 0 }
            return ordered(number(aVal), number(bVal))
        case .channels:
            return ordered(LibraryColumnVisibility.channelSortValue(aVal), LibraryColumnVisibility.channelSortValue(bVal))
        case .duration:
            return ordered(Self.parseDuration(aVal), Self.parseDuration(bVal))
        case .bitrate, .sampleRate:
            let number = { (value: String) in Double(value.replacingOccurrences(of: "k", with: "")) ?? 0 }
            return ordered(number(aVal), number(bVal))
        case .size:
            return ordered(Self.parseSize(aVal), Self.parseSize(bVal))
        case .rating:
            return ordered(aVal.filter { $0 == "★" }.count, bVal.filter { $0 == "★" }.count)
        default:
            return compareNameStrings(aVal, bVal, ascending: ascending)
        }
    }

    // MARK: - Internet Radio and YouTube

    /// Sorts each run of Internet Radio station rows in place.
    private func applyInternetRadioColumnSort(sortColumn: LibraryBrowserColumn, ascending: Bool) -> Bool {
        guard case .radio = currentSource,
              LibraryBrowserColumn.internetRadioColumns.contains(where: { $0.id == sortColumn.id }),
              displayItems.contains(where: isInternetRadioItem) else {
            return false
        }
        displayItems = sortingRuns(of: isInternetRadioItem) { sortedInternetRadioItems($0, sortColumn: sortColumn, ascending: ascending) }
        return true
    }

    /// Sorts the videos within each expanded YouTube channel (contiguous runs of video rows)
    /// by the clicked column, leaving the channel leaders in place. Mirrors the internet-radio
    /// in-place run sort so the "Channels" view supports sortable column headers like other tabs.
    private func applyYouTubeColumnSort(sortColumn: LibraryBrowserColumn) -> Bool {
        guard radioSlotShowingChannels || isYouTubeChannelSearch,
              LibraryBrowserColumn.youtubeColumns.contains(where: { $0.id == sortColumn.id }) else {
            return false
        }
        let isVideo = { (item: LibraryBrowserItem) -> Bool in
            if case .youtubeVideo = item.type { return true }
            return false
        }
        // Search results keep YouTube's relevance order under their header row.
        guard displayItems.contains(where: isVideo) else { return isYouTubeChannelSearch }
        displayItems = sortingRuns(of: isVideo) { stableColumnSortedItems($0, sortColumn: sortColumn) }
        return true
    }

    /// `displayItems` with each contiguous run of `matching` rows replaced by `sort` of it.
    private func sortingRuns(of matching: (LibraryBrowserItem) -> Bool,
                             _ sort: ([LibraryBrowserItem]) -> [LibraryBrowserItem]) -> [LibraryBrowserItem] {
        var items = displayItems
        var index = 0
        while index < items.count {
            guard matching(items[index]) else { index += 1; continue }
            let start = index
            while index < items.count, matching(items[index]) { index += 1 }
            items.replaceSubrange(start..<index, with: sort(Array(items[start..<index])))
        }
        return items
    }

    private func sortedInternetRadioItems(_ items: [LibraryBrowserItem], sortColumn: LibraryBrowserColumn,
                                          ascending: Bool) -> [LibraryBrowserItem] {
        let ratings = Dictionary(uniqueKeysWithValues: items.map { item -> (String, Int) in
            guard case .radioStation(let station) = item.type else { return (item.id, 0) }
            return (item.id, RadioManager.shared.rating(for: station))
        })
        return items.enumerated().sorted { lhs, rhs in
            let comparison = compareInternetRadioItems(lhs.element, rhs.element, sortColumn: sortColumn, ratings: ratings)
            if comparison == .orderedSame { return lhs.offset < rhs.offset }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }.map(\.element)
    }

    private func compareInternetRadioItems(_ lhs: LibraryBrowserItem, _ rhs: LibraryBrowserItem,
                                           sortColumn: LibraryBrowserColumn, ratings: [String: Int]) -> ComparisonResult {
        switch sortColumn.id {
        case .rating:
            let lhsRating = ratings[lhs.id] ?? 0
            let rhsRating = ratings[rhs.id] ?? 0
            if lhsRating != rhsRating {
                return lhsRating < rhsRating ? .orderedAscending : .orderedDescending
            }
            return LibraryTextSorter.compare(lhs.title, rhs.title, ignoreLeadingArticles: true)
        case .genre:
            let genreComparison = LibraryTextSorter.compare(lhs.columnValue(for: sortColumn), rhs.columnValue(for: sortColumn), ignoreLeadingArticles: true)
            if genreComparison != .orderedSame { return genreComparison }
            return LibraryTextSorter.compare(lhs.title, rhs.title, ignoreLeadingArticles: true)
        default:
            return LibraryTextSorter.compare(lhs.columnValue(for: sortColumn), rhs.columnValue(for: sortColumn), ignoreLeadingArticles: true)
        }
    }

    // MARK: - Parsing

    /// Parse duration string (e.g., "3:45" or "1:23:45") to seconds
    private static func parseDuration(_ str: String) -> Int {
        let parts = str.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return 0
        }
    }

    /// Parse size string (e.g., "12.5M" or "1.2G") to bytes
    private static func parseSize(_ str: String) -> Int64 {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("G") { return Int64((Double(trimmed.dropLast()) ?? 0) * 1024 * 1024 * 1024) }
        if trimmed.hasSuffix("M") { return Int64((Double(trimmed.dropLast()) ?? 0) * 1024 * 1024) }
        return Int64(trimmed) ?? 0
    }
}
