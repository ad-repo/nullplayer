import Foundation

/// The Internet Radio source, whose stations also fill the YouTube source's Radio tab slot.
extension LibraryBrowserModel {

    func loadRadioStations() {
        loadState = .idle
        cachedRadioStations = RadioManager.shared.stations
        buildRadioStationItems()
        if columnSortId != nil { applyColumnSort() }
    }

    func loadRadioSearchResults() {
        loadState = .idle
        cachedRadioStations = RadioManager.shared.stations
        buildRadioSearchItems()
        if columnSortId != nil { applyColumnSort() }
    }

    /// After a station or folder edit: reload whichever Internet Radio list is showing.
    func reloadInternetRadioForCurrentMode() {
        guard isShowingInternetRadioContent else { return }
        switch browseMode {
        case .radio: loadRadioStations()
        case .search: loadRadioSearchResults()
        default:
            loadState = .idle
            displayItems = []
        }
    }

    /// The folder tree, with each expanded folder's stations or sub-folders.
    func buildRadioStationItems() {
        cachedRadioFolders = RadioManager.shared.internetRadioFolderDescriptors()
        let childrenByParent = Dictionary(grouping: cachedRadioFolders.filter { $0.parentID != nil }) { $0.parentID! }
        displayItems = Self.folderOrdered(cachedRadioFolders.filter { $0.parentID == nil }).flatMap {
            radioFolderRows($0, level: 0, childrenByParent: childrenByParent)
        }
    }

    func buildRadioSearchItems() {
        guard !searchedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { displayItems = []; return }
        displayItems = RadioManager.shared.searchStations(query: searchedQuery).map { station in
            LibraryBrowserItem(id: "radio-search-\(station.id.uuidString)", title: station.name,
                               info: RadioManager.shared.normalizedGenre(for: station),
                               indentLevel: 0, hasChildren: false, type: .radioStation(station))
        }
    }

    /// A folder row, then its stations or sub-folders when expanded.
    private func radioFolderRows(_ folder: RadioFolderDescriptor, level: Int,
                                 childrenByParent: [String: [RadioFolderDescriptor]]) -> [LibraryBrowserItem] {
        let row = LibraryBrowserItem(id: folder.id, title: folder.title, info: nil, indentLevel: level,
                                     hasChildren: folder.hasChildren, type: .radioFolder(folder))
        guard folder.hasChildren, isExpanded(.radioFolder, folder.id) else { return [row] }
        if folder.kind.isStationContainer {
            return [row] + RadioManager.shared.stations(inFolder: folder.kind).map { station in
                LibraryBrowserItem(id: "radio-station-\(folder.id)-\(station.id.uuidString)", title: station.name,
                                   info: RadioManager.shared.normalizedGenre(for: station),
                                   indentLevel: level + 1, hasChildren: false, type: .radioStation(station))
            }
        }
        return [row] + Self.folderOrdered(childrenByParent[folder.id] ?? []).flatMap {
            radioFolderRows($0, level: level + 1, childrenByParent: childrenByParent)
        }
    }

    private static func folderOrdered(_ folders: [RadioFolderDescriptor]) -> [RadioFolderDescriptor] {
        folders.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
