import Foundation
import NullPlayerCore

/// The library browser's state and data, shared by the classic and modern views.
///
/// Each browser instance owns one: the classic and modern windows, the windows Compact Mode
/// creates, and a `.wal` skin's embedded library. The model loads and builds the rows of the
/// current source and tab, and keeps the caches, expansion, sort and search behind them. Its view
/// draws `displayItems` and `selectedIndices` and reacts to `onChange`; the view keeps scroll
/// position, hover and animation. Loading is split per source across the `LibraryBrowserModel+<Source>` files.
@MainActor
final class LibraryBrowserModel: NSObject {

    /// What changed, for the view to react to.
    enum Change {
        /// `displayItems` changed.
        case rows
        /// What the list area shows instead of rows may have changed: `loadState`, or whether the
        /// Plex source still needs an account linked.
        case listState
        /// A new list replaced the rows and cleared the selection: the scroll position no longer applies.
        case rowsReplaced
        /// The rows were re-built in place after an expand, collapse or re-sort.
        case rebuilt
        /// A load of the current tab finished.
        case loaded
        /// The row a search → Artists navigation was looking for, now selected: scroll to it.
        case reveal(Int)
        /// `currentSource` changed; the rows and selection were cleared and are reloading.
        case source
        /// `browseMode` changed; the selection was cleared, and the new tab opens at its top.
        case browseMode
        /// A column was shown or hidden, or a group's columns were reset.
        case columns
    }

    var onChange: ((Change) -> Void)?

    /// Prefixes the keys each view keeps its own column visibility and tab-slot choice under
    /// ("Classic" for the classic view, empty for the modern view).
    let keyPrefix: String

    // MARK: - Source and tab

    var currentSource: LibraryBrowserSource = .local {
        didSet {
            currentSource.save()
            sourceDidChange()
        }
    }
    /// A saved server source whose server list had not loaded yet; restored on `serversDidChange`.
    var pendingSourceRestore: LibraryBrowserSource?

    var browseMode: LibraryBrowseMode = .artists {
        didSet {
            guard browseMode != oldValue else { return }
            if oldValue == .folders, browseMode != .folders {
                cancelLocalFolderBuild()
            }
            if browseMode.isHistoryMode { history.scheduleRefresh() }
            selectedIndices.removeAll()
            onChange?(.browseMode)
        }
    }

    var searchQuery: String = ""
    /// The query last submitted with Enter, which every search runs on. Typing changes only
    /// `searchQuery`, so a reload while the user types (a preload landing, a source switch) still
    /// shows the submitted query's results, and the typed one reads as not yet run.
    private(set) var searchedQuery = ""

    /// Enter on the Search tab: run what was typed.
    func submitSearch() {
        searchedQuery = searchQuery
        loadDataForCurrentMode()
    }

    /// The Data tab's play history, refreshed while that tab shows.
    let history = PlayHistoryAgent()

    // MARK: - Rows and loading

    /// The selected rows' indices into `displayItems`.
    var selectedIndices: Set<Int> = []

    /// The selected rows, in list order.
    var selectedItems: [LibraryBrowserItem] {
        selectedIndices.sorted().filter(displayItems.indices.contains).map { displayItems[$0] }
    }

    /// A new list replaced the rows: the selection no longer applies.
    func rowsReplaced() {
        selectedIndices.removeAll()
        onChange?(.rowsReplaced)
    }

    var displayItems: [LibraryBrowserItem] = [] {
        didSet {
            eqMarkers = LibraryRowEQMarkers()
            onChange?(.rows)
        }
    }

    /// The rows' `∿` markers, read by `LibraryBrowserActions.isEQMarked`.
    var eqMarkers = LibraryRowEQMarkers()

    /// Whether the current tab is loading, or failed to.
    enum LoadState: Equatable {
        case idle
        case loading
        case failed(String)
    }

    var loadState = LoadState.idle {
        didSet { if loadState != oldValue { onChange?(.listState) } }
    }

    var isLoading: Bool { loadState == .loading }

    var errorMessage: String? {
        if case .failed(let message) = loadState { return message }
        return nil
    }

    /// A load ended without an error of its own: a failure reported meanwhile stays.
    func endLoading() {
        if loadState == .loading { loadState = .idle }
    }

    /// What the list area shows, outside the Data tab: a state in place of the rows, or the rows
    /// (which Flow / Tiles may stand in for).
    enum ListState: Equatable {
        case notLinked
        case loading
        case error(String)
        case rows
    }

    var listState: ListState {
        if needsPlexLink { return .notLinked }
        if isLoading { return .loading }
        if let errorMessage { return .error(errorMessage) }
        return .rows
    }

    /// A Plex source with no Plex account linked: the server bar offers the link sheet instead.
    var needsPlexLink: Bool {
        currentSource.isPlex && !PlexManager.shared.isLinked
    }

    /// What an empty list says. `enterKey` is how the view names the Return key.
    func emptyMessage(enterKey: String) -> String {
        let plexLibrary = currentSource.isPlex ? PlexManager.shared.currentLibrary : nil
        switch browseMode {
        case .artists, .albums:
            if currentSource.isPlex, plexLibrary?.isMusicLibrary != true { return "This library doesn't contain music" }
            return "No \(browseMode.title.lowercased()) found"
        case .movies:
            if currentSource.isPlex, plexLibrary?.isMovieLibrary != true { return "This library doesn't contain movies" }
            return "No movies found"
        case .shows:
            if currentSource.isPlex, plexLibrary?.isShowLibrary != true { return "This library doesn't contain TV shows" }
            return "No TV shows found"
        case .plists: return "No playlists found"
        case .folders: return "No folders found"
        // Search runs on Enter: until then, nothing has been searched.
        case .search: return searchQuery.isEmpty || hasUnsubmittedSearch ? "Type and press \(enterKey) to search" : "No results found"
        case .radio: return "No radio stations found"
        case .history: return "No play history recorded yet"
        }
    }

    /// Bumped by every reload; a load that finds it changed was superseded and drops its result.
    var loadGeneration = 0
    var sourceConnectTask: Task<Void, Never>?
    /// The current server source's load of the current tab.
    var loadTask: Task<Void, Never>?
    var radioLoadTask: Task<Void, Never>?
    /// A Subsonic, Jellyfin or Emby row's children; a newer expand replaces it.
    var expandTask: Task<Void, Never>?
    /// The albums of a server whose Artists tab loaded without them (Jellyfin).
    var albumWarmTask: Task<Void, Never>?

    // MARK: - Expansion

    var expanded: Set<ExpansionKey> = []
    /// Expanded YouTube channels, kept whole: their uploads load by channel.
    var expandedYouTubeChannels: [String: YouTubeChannel] = [:]

    // MARK: - Search → Artists

    var pendingScrollToArtistId: String?
    var pendingScrollToArtistName: String?
    var pendingScrollAttempts = 0
    /// The Artists load after a search jump fetches unfiltered, so an artist the search found
    /// outside the selected folder or library is in the list.
    var pendingArtistLoadUnfiltered = false

    // MARK: - Columns

    var visibleTrackColumnIds = LibraryBrowserColumn.defaultTrackColumnIds { didSet { saveVisibleColumns() } }
    var visibleAlbumColumnIds = LibraryBrowserColumn.defaultAlbumColumnIds { didSet { saveVisibleColumns() } }
    var visibleArtistColumnIds = LibraryBrowserColumn.defaultArtistColumnIds { didSet { saveVisibleColumns() } }
    /// Resized column widths, keyed "group:columnId" (a radio column by its id alone). Both views
    /// share one set.
    var columnWidths: [String: CGFloat] = [:] {
        didSet { UserDefaults.standard.set(columnWidths, forKey: Self.columnWidthsKey) }
    }

    // YouTube channels keep their own sort state (session-only, default = none → date
    // order as returned by yt-dlp). This keeps the persisted library column sort from
    // leaking in and re-ordering videos to A–Z on every rebuild (e.g. after a download).
    // Only an explicit header click in the YouTube tab sets this.
    var youtubeColumnSortId: LibraryBrowserColumn.ID?
    var youtubeColumnSortAscending = true

    // MARK: - Server caches

    var plex = PlexBrowserCache()
    var subsonic = ServerMusicCache<SubsonicManager>()
    var jellyfin = ServerMusicCache<JellyfinManager>()
    var jellyfinVideo = ServerVideoCache<JellyfinManager>()
    var emby = ServerMusicCache<EmbyManager>()
    var embyVideo = ServerVideoCache<EmbyManager>()

    // MARK: - Local

    var localArtistPageOffset = 0
    var localAlbumPageOffset = 0
    let localPageSize = 200
    var localArtistTotal = 0
    var localAlbumTotal = 0
    var localArtistLetterOffsets: [String: Int] = [:]
    var localAlbumLetterOffsets: [String: Int] = [:]
    /// Bumped on each Folders rebuild; an in-flight off-actor walk discards its result if stale.
    var localFolderBuildGeneration = 0
    /// The in-flight Folders walk, cancelled when a newer rebuild starts (fast-click protection).
    var localFolderBuildTask: Task<Void, Never>?
    var cachedLocalMovies: [LocalVideo] = []
    var cachedLocalShows: [LocalShow] = []
    var localPlaylistTracks: [String: [Track]] = [:]
    var cachedLocalPlaylists: [LocalPlaylist] = []
    var localLibraryReloadWorkItem: DispatchWorkItem?
    /// Watch folders on volumes that are not mounted, as of the last local load.
    var offlineWatchFolders: [WatchFolderSummary] = []
    var offlineVolumePrefixes: Set<String> = []

    // MARK: - Internet Radio and YouTube

    var cachedRadioStations: [RadioStation] = []
    var cachedRadioFolders: [RadioFolderDescriptor] = []
    /// Search tab (YouTube source): channels found by the last submitted query.
    let youtubeSearch = YouTubeChannelSearch()

    // MARK: - Init

    /// Restores the saved source. The first load is the view's `reloadData()` once it has
    /// subscribed to `onChange`.
    init(keyPrefix: String) {
        self.keyPrefix = keyPrefix
        super.init()
        loadColumns()
        // Set directly, so `currentSource`'s observer does not start a load before the view listens.
        (currentSource, pendingSourceRestore) = Self.restoredSource()
        currentSource.save()
        // Internet Radio and YouTube list their content on the Radio tab.
        if currentSource.usesRadioTab { browseMode = .radio }
        observeNotifications()
    }

    deinit {
        localLibraryReloadWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    /// The saved source when its server is still configured. A server source saved before the
    /// server list has loaded is returned as pending, with Local shown meanwhile.
    private static func restoredSource() -> (LibraryBrowserSource, pending: LibraryBrowserSource?) {
        guard let saved = LibraryBrowserSource.load() else {
            if PlexManager.shared.isLinked, let first = PlexManager.shared.servers.first {
                return (.plex(serverId: first.id), nil)
            }
            return (.local, nil)
        }
        if saved.isPlex && !PlexManager.shared.isLinked { return (.local, nil) }
        if let source = configuredSource(for: saved) { return (source, nil) }
        return (.local, saved)
    }

    /// `source` if its server is configured, else the first configured server of its kind; nil
    /// when there is none. Local, Internet Radio and YouTube are always configured.
    static func configuredSource(for source: LibraryBrowserSource) -> LibraryBrowserSource? {
        let servers: [String]
        let first: (String) -> LibraryBrowserSource
        switch source {
        case .local, .radio, .youtube: return source
        case .plex: servers = PlexManager.shared.servers.map(\.id); first = LibraryBrowserSource.plex
        case .subsonic: servers = SubsonicManager.shared.servers.map(\.id); first = LibraryBrowserSource.subsonic
        case .jellyfin: servers = JellyfinManager.shared.servers.map(\.id); first = LibraryBrowserSource.jellyfin
        case .emby: servers = EmbyManager.shared.servers.map(\.id); first = LibraryBrowserSource.emby
        }
        if let serverId = source.serverId, servers.contains(serverId) { return source }
        return servers.first.map(first)
    }

    /// The tab a restored session was on. Folders belongs to the Local source; elsewhere its slot
    /// is Plists.
    func restoreBrowseMode(rawValue: Int) {
        guard let mode = LibraryBrowseMode(rawValue: rawValue) else { return }
        browseMode = mode == .folders && !currentSource.isLocal ? .plists : mode
        reloadData()
    }

    // MARK: - Source changes

    private func sourceDidChange() {
        invalidateActiveLoads()
        if browseMode == .folders && !currentSource.isLocal {
            browseMode = .plists
        }
        clearAllCachedData()
        clearLocalCachedData()
        displayItems.removeAll()
        loadState = .idle
        selectedIndices.removeAll()
        // Internet Radio only has radio/search content, but every library
        // source supports the Radio tab. Preserve Radio across source changes.
        // YouTube reuses the Radio tab to list its channels, so force it too.
        if !browseMode.isHistoryMode, currentSource.usesRadioTab {
            browseMode = .radio
        }
        onChange?(.source)
        reloadData()
    }

    // MARK: - Tab slots

    /// The Plists tab slot toggles between Plists and Folders (Local source only).
    var localPlistsSlotShowsFolders: Bool {
        get { UserDefaults.standard.object(forKey: keyPrefix + "LocalPlistsSlotShowsFolders") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: keyPrefix + "LocalPlistsSlotShowsFolders") }
    }

    var effectivePlistsSlotMode: LibraryBrowseMode {
        currentSource.isLocal && localPlistsSlotShowsFolders ? .folders : .plists
    }

    /// The Radio tab slot toggles between Internet Radio stations and YouTube
    /// channels (YouTube source only), mirroring the Plists/Folders toggle.
    /// Defaults to showing channels so the YouTube source opens on "Channels".
    var radioSlotShowsChannels: Bool {
        get { UserDefaults.standard.object(forKey: keyPrefix + "RadioSlotShowsChannels") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: keyPrefix + "RadioSlotShowsChannels") }
    }
    /// Whether the Radio tab slot is currently displaying YouTube channels.
    var radioSlotShowingChannels: Bool {
        currentSource.isYouTube && radioSlotShowsChannels
    }
    /// Whether the Search tab is showing YouTube channel-search results (YouTube source).
    var isYouTubeChannelSearch: Bool {
        currentSource.isYouTube && browseMode == .search
    }
    /// A search typed but not yet run, or run and failed: Enter runs it, and until then the tab has
    /// no results to report. Once its results are showing, Enter acts on the selected row instead.
    var hasUnsubmittedSearch: Bool {
        guard browseMode == .search, !searchQuery.isEmpty else { return false }
        return searchQuery != searchedQuery || errorMessage != nil
    }

    /// The label of each tab slot, in `LibraryBrowseMode.tabs` order: a two-way slot shows what
    /// it is switched to.
    var tabLabels: [String] {
        LibraryBrowseMode.tabs.map { mode in
            if mode == .plists, currentSource.isLocal, localPlistsSlotShowsFolders { return LibraryBrowseMode.folders.title }
            if mode == .radio, radioSlotShowingChannels { return LibraryBrowseMode.channelsLabel }
            return mode.title
        }
    }

    /// The tab slot showing `browseMode`: Folders shares the Plists slot.
    var activeTabSlot: LibraryBrowseMode {
        browseMode == .folders ? .plists : browseMode
    }

    /// A source-bar name with the item count appended: "FLAC_LIB (988 items)". The local Artists
    /// and Albums tabs count the whole library rather than the loaded page; a Plex library counts
    /// its artists, movies or shows rather than the rows.
    func withItemCount(_ name: String) -> String {
        let count: Int
        switch currentSource {
        case .local:
            switch browseMode {
            case .artists: count = localArtistTotal > 0 ? localArtistTotal : displayItems.count
            case .albums: count = localAlbumTotal > 0 ? localAlbumTotal : displayItems.count
            default: count = displayItems.count
            }
        case .plex:
            switch PlexManager.shared.currentLibrary?.type {
            case "artist": count = plex.artists.count
            case "movie": count = plex.movies.count
            case "show": count = plex.shows.count
            default: count = displayItems.count
            }
        case .radio:
            return "\(name) (\(displayItems.count) stations)"
        case .subsonic, .jellyfin, .emby, .youtube:
            count = displayItems.count
        }
        return "\(name) (\(count) items)"
    }

    /// A tab-bar click on `slot`. A double-click flips what a two-way slot shows: Plists and
    /// Folders for the Local source, Internet Radio and Channels for YouTube.
    func selectTab(_ slot: LibraryBrowseMode, doubleClick: Bool) {
        if doubleClick, slot == .plists, currentSource.isLocal {
            localPlistsSlotShowsFolders.toggle()
        } else if doubleClick, slot == .radio, currentSource.isYouTube {
            radioSlotShowsChannels.toggle()
        }
        let mode = slot == .plists ? effectivePlistsSlotMode : slot
        // Clicking the Data tab again re-reads the play history.
        if mode == browseMode, mode.isHistoryMode { history.scheduleRefresh() }
        browseMode = mode
        // Even the open tab re-reads from the top.
        rowsReplaced()
        loadDataForCurrentMode()
    }


    // MARK: - Sort

    /// The current tab's sort; each tab keeps its own in `LibraryBrowserTabSortStore`.
    var tabSort: LibraryBrowserTabSort { LibraryBrowserTabSortStore.shared.sort(for: browseMode.rawValue) }
    var currentSort: LibraryBrowserSortOption { tabSort.menuSort }
    /// Column header sort; overrides `currentSort` when set
    var columnSortId: String? { tabSort.columnSortId }

    /// Column sort that applies to the current source. YouTube uses its own session
    /// state (default date order) instead of the persisted library sort.
    var activeColumnSortId: LibraryBrowserColumn.ID? {
        currentSource.isYouTube ? youtubeColumnSortId : columnSortId.flatMap(LibraryBrowserColumn.ID.init)
    }
    var activeColumnSortAscending: Bool {
        currentSource.isYouTube ? youtubeColumnSortAscending : tabSort.columnSortAscending
    }

    /// Sort-menu choice for the current tab: local paging restarts under the new order.
    func selectMenuSort(_ option: LibraryBrowserSortOption) {
        LibraryBrowserTabSortStore.shared.setMenuSort(option, for: browseMode.rawValue)
        localArtistPageOffset = 0; localAlbumPageOffset = 0
        localArtistLetterOffsets = [:]; localAlbumLetterOffsets = [:]
        rebuildCurrentModeItems()
    }

    /// A column-header click: sort by that column, or reverse the order when it already does.
    func sortByColumn(_ columnId: LibraryBrowserColumn.ID) {
        if currentSource.isYouTube {
            guard columnId != .thumbnail else { return }  // an image column has nothing to sort by
            // YouTube uses its own session sort (not persisted to the library sort).
            if youtubeColumnSortId == columnId {
                youtubeColumnSortAscending.toggle()
            } else {
                youtubeColumnSortId = columnId
                youtubeColumnSortAscending = true
            }
        } else {
            LibraryBrowserTabSortStore.shared.clickColumn(columnId.rawValue, for: browseMode.rawValue)
        }
        applyColumnSort(collapseExpanded: true)
    }

    func compareNameStrings(_ lhs: String, _ rhs: String, ascending: Bool) -> Bool {
        LibraryTextSorter.areInOrder(lhs, rhs, ascending: ascending, ignoreLeadingArticles: true)
    }

    // MARK: - Loading

    func reloadData() {
        let generation = invalidateActiveLoads()
        loadDataForCurrentMode(generation: generation)
    }

    func loadDataForCurrentMode(generation: Int? = nil) {
        let generation = generation ?? loadGeneration

        if browseMode.isHistoryMode {
            invalidateActiveLoads()
            displayItems = []
            loadState = .idle
            rowsReplaced()
            return
        }

        // YouTube content lives only in the Radio tab slot (channels or Internet Radio
        // stations) and the Search tab; Internet Radio has only Radio and Search.
        if currentSource.usesRadioTab {
            switch browseMode {
            case .radio:
                if radioSlotShowingChannels { loadYouTubeChannels() } else { loadRadioStations() }
            case .search:
                if currentSource.isYouTube { loadYouTubeSearchResults() } else { loadRadioSearchResults() }
            default:
                loadState = .idle
                displayItems = []
            }
            return
        }

        if let manager = currentServerManager {
            if browseMode == .radio {
                loadServerRadioStations(manager, generation: generation)
            } else {
                loadServerData(manager, generation: generation)
            }
            return
        }
        switch currentSource {
        case .local where browseMode == .radio: loadLocalRadioStations()
        case .local: loadLocalData()
        case .plex where browseMode == .radio: loadPlexRadioStations(generation: generation)
        case .plex(let serverId): loadPlexData(serverId: serverId, generation: generation)
        case .subsonic, .jellyfin, .emby, .radio, .youtube: break
        }
    }

    /// Rebuild the current tab's rows from the caches, after an expand, collapse or re-sort.
    func rebuildCurrentModeItems() {
        defer { onChange?(.rebuilt) }
        if currentSource.usesRadioTab {
            switch browseMode {
            case .radio:
                if radioSlotShowingChannels { buildYouTubeChannelItems() } else { buildRadioStationItems() }
            case .search:
                if currentSource.isYouTube { buildYouTubeSearchItems() } else { buildRadioSearchItems() }
            default:
                displayItems = []
            }
            if activeColumnSortId != nil { applyColumnSort() }
            return
        }
        // A server's or the library's radio stations are not rebuilt; they stay as loaded.
        if browseMode == .radio { return }
        if let manager = currentServerManager {
            rebuildServerRows(manager)
        } else if currentSource.isLocal {
            rebuildLocalItems()
        } else if currentSource.isPlex {
            rebuildPlexItems()
        }
        if columnSortId != nil { applyColumnSort() }
        resolvePendingArtist()
    }

    /// The Refresh button: re-read the current tab from its source, dropping the server's cache.
    /// On the Data tab, re-read the play history.
    func refreshCurrentSource() {
        if browseMode.isHistoryMode {
            history.scheduleRefresh()
            return
        }
        if currentSource.isYouTube && browseMode == .search {
            loadYouTubeSearchResults(force: true)
        } else if currentSource.usesRadioTab || browseMode == .radio {
            loadDataForCurrentMode()
        } else if let manager = currentServerManager {
            refreshServer(manager)
        } else if currentSource.isLocal {
            MediaLibrary.shared.rescanWatchFolders()
            loadLocalData()
        } else if currentSource.isPlex {
            refreshData()
        }
    }

    /// Show the loading state at once, then reload once the server's library is preloaded again.
    func refreshAfterPreload(_ preload: @escaping @MainActor () async -> Void) {
        loadTask?.cancel(); loadTask = nil
        let source = currentSource
        loadState = .loading; displayItems = []
        Task { @MainActor [weak self] in
            await preload()
            guard let self, self.currentSource == source else { return }
            self.refreshData()
        }
    }

    /// Clear every server cache and reload the current tab.
    func refreshData() {
        if needsPlexLink { return }
        let generation = invalidateActiveLoads()
        clearAllCachedData()
        rowsReplaced()
        loadState = .loading; displayItems = []
        PlexManager.shared.clearCachedContent()
        loadDataForCurrentMode(generation: generation)
    }

    // MARK: - Load generations

    @discardableResult
    func invalidateActiveLoads() -> Int {
        loadGeneration &+= 1
        for task in [sourceConnectTask, loadTask, radioLoadTask, expandTask, albumWarmTask] {
            task?.cancel()
        }
        sourceConnectTask = nil; loadTask = nil; radioLoadTask = nil; expandTask = nil; albumWarmTask = nil
        youtubeSearch.cancel()
        return loadGeneration
    }

    func isLoadContextActive(_ generation: Int, source expectedSource: LibraryBrowserSource) -> Bool {
        generation == loadGeneration && currentSource == expectedSource
    }

    func setLoadErrorIfActive(_ message: String, generation: Int, source expectedSource: LibraryBrowserSource) {
        guard isLoadContextActive(generation, source: expectedSource) else { return }
        loadState = .failed(message)
    }

    func finishLoadIfActive(generation: Int, source expectedSource: LibraryBrowserSource) {
        guard isLoadContextActive(generation, source: expectedSource) else { return }
        loadState = .idle
        // Apply any active column-header sort so a fresh server load matches what an
        // expand-driven rebuild produces — otherwise expanding a row would re-order the list.
        if columnSortId != nil { applyColumnSort() }
        resolvePendingArtist()
        onChange?(.loaded)
    }

    /// A server's library is preloading: wait for it (up to two seconds) rather than fetch the
    /// same content twice. Returns false once the load is superseded.
    func waitForPreload(_ isPreloading: @MainActor () -> Bool, generation: Int,
                        source expectedSource: LibraryBrowserSource) async throws -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while isPreloading(), Date() < deadline {
            try Task.checkCancellation()
            guard isLoadContextActive(generation, source: expectedSource) else { return false }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return isLoadContextActive(generation, source: expectedSource)
    }

    /// A tab's rows from the server's preload when it has them, else from `fetch`. A fetch that
    /// returns after the load was superseded throws `CancellationError`.
    func preloadedOrFetched<Item>(_ preloaded: [Item], isPreloaded: Bool, generation: Int,
                                  source expectedSource: LibraryBrowserSource,
                                  fetch: @MainActor () async throws -> [Item]) async throws -> [Item] {
        if isPreloaded && !preloaded.isEmpty { return preloaded }
        try Task.checkCancellation()
        let items = try await fetch()
        guard isLoadContextActive(generation, source: expectedSource) else { throw CancellationError() }
        return items
    }

    /// Connect a server source's manager to its server, then `load` if it is still current.
    /// `connect` is nil when the server is no longer configured.
    func connectThenLoad(generation: Int, source expectedSource: LibraryBrowserSource,
                         connect: (@MainActor () async throws -> Void)?,
                         isConnected: @escaping @MainActor () -> Bool,
                         load: @escaping @MainActor () -> Void) {
        guard let connect else {
            setLoadErrorIfActive("Server not found", generation: generation, source: expectedSource)
            return
        }
        sourceConnectTask?.cancel()
        sourceConnectTask = Task { @MainActor [weak self] in
            guard let self, self.isLoadContextActive(generation, source: expectedSource) else { return }
            do {
                try await connect()
                guard self.isLoadContextActive(generation, source: expectedSource), isConnected() else { return }
                load()
            } catch {
                self.setLoadErrorIfActive(error.localizedDescription, generation: generation, source: expectedSource)
            }
        }
    }

    // MARK: - Caches

    /// Drop every server's rows and collapse them; the local rows are kept.
    func clearAllCachedData() {
        albumWarmTask?.cancel()
        albumWarmTask = nil
        plex = PlexBrowserCache()
        collapse(.plexLibrary, .plexPlaylists)
        resetSubsonic()
        resetJellyfinMusic()
        resetJellyfinVideo()
        resetEmbyMusic()
        resetEmbyVideo()
        cachedRadioStations = []
        cachedRadioFolders = []
    }

    func clearLocalCachedData() {
        localArtistPageOffset = 0; localAlbumPageOffset = 0
        localArtistTotal = 0; localAlbumTotal = 0
        localArtistLetterOffsets = [:]; localAlbumLetterOffsets = [:]
        cachedLocalMovies = []; cachedLocalShows = []
        collapse(.local)
    }

    func resetSubsonic() { subsonic = .init(); collapse(.subsonic) }
    func resetJellyfinMusic() { jellyfin = .init(); collapse(.jellyfinMusic) }
    func resetJellyfinVideo() { jellyfinVideo = .init(); collapse(.jellyfinVideo) }
    func resetEmbyMusic() { emby = .init(); collapse(.embyMusic) }
    func resetEmbyVideo() { embyVideo = .init(); collapse(.embyVideo) }

    // MARK: - Search → Artists

    /// A search result's artist row was activated: open the Artists tab on that artist.
    func navigateToArtistFromSearch(id: String, name: String = "") {
        let artistName = name.isEmpty ? id.replacingOccurrences(of: "local-artist-", with: "") : name
        pendingScrollToArtistId = id
        pendingScrollToArtistName = artistName
        pendingScrollAttempts = 0
        pendingArtistLoadUnfiltered = true
        // Clear the artist caches to force a fresh fetch that bypasses folder/library
        // filters (so an artist found via unfiltered search is findable).
        plex.artists.removeAll()
        subsonic.artists.removeAll()
        jellyfin.artists.removeAll()
        emby.artists.removeAll()
        // Switch first so the page offset is computed under the Artists tab's own sort.
        browseMode = .artists
        if currentSource.isLocal,
           let artistOffset = MediaLibraryStore.shared.artistOffset(named: artistName, sort: currentSort) {
            localArtistPageOffset = (artistOffset / localPageSize) * localPageSize
        }
        loadDataForCurrentMode()
    }

    /// After a load or rebuild: reveal the artist a search jump is looking for, giving up after
    /// three tries.
    func resolvePendingArtist() {
        guard let artistId = pendingScrollToArtistId else { return }
        pendingScrollAttempts += 1
        let index = pendingArtistIndex(artistId: artistId, name: pendingScrollToArtistName ?? "")
        guard index != nil || pendingScrollAttempts >= 3 else { return }
        pendingScrollToArtistId = nil
        pendingScrollToArtistName = nil
        pendingScrollAttempts = 0
        pendingArtistLoadUnfiltered = false
        if let index {
            selectedIndices = [index]
            onChange?(.reveal(index))
        }
    }

    private func pendingArtistIndex(artistId: String, name: String) -> Int? {
        let titleMatch = !name.isEmpty ? displayItems.firstIndex { item in
            item.type.isArtist && item.title.caseInsensitiveCompare(name) == .orderedSame
        } : nil
        return titleMatch ?? displayItems.firstIndex { item in
            item.type.isArtist && item.id == artistId
        }
    }

    // MARK: - Letters and type-ahead

    /// The alphabet-index letters that have rows: a paged local tab's, from the store; else the
    /// loaded rows'.
    var lettersWithRows: Set<String> {
        if currentSource.isLocal, browseMode == .artists { return Set(localArtistLetterOffsets.keys) }
        if currentSource.isLocal, browseMode == .albums { return Set(localAlbumLetterOffsets.keys) }
        return Set(displayItems.map(\.sortLetter))
    }

    /// The local Artists and Albums tabs page from the store: jump the page to `letter`.
    /// Returns nil on other tabs and sources, which scroll the loaded rows instead; otherwise
    /// whether the page moved (false when nothing files under `letter`).
    func showLocalPage(atLetter letter: String) -> Bool? {
        guard currentSource.isLocal else { return nil }
        switch browseMode {
        case .artists:
            guard let offset = localArtistLetterOffsets[letter] else { return false }
            localArtistPageOffset = offset
            buildLocalArtistItems()
            return true
        case .albums:
            guard let offset = localAlbumLetterOffsets[letter] else { return false }
            localAlbumPageOffset = offset
            buildLocalAlbumItems()
            return true
        default:
            return nil
        }
    }

    // MARK: - Teardown

    /// Cancel every in-flight load, so a detached `@MainActor` expand or load task does not pin
    /// the model (and its view) alive after a UI reload.
    func cancelAll() {
        invalidateActiveLoads()
        cancelLocalFolderBuild()
        localLibraryReloadWorkItem?.cancel(); localLibraryReloadWorkItem = nil
    }
}

extension LibraryBrowserItem.ItemType {
    var isArtist: Bool {
        switch self {
        case .artist, .localArtist, .subsonicArtist, .jellyfinArtist, .embyArtist: return true
        default: return false
        }
    }
}
