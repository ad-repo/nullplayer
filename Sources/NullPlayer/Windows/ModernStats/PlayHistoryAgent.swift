import Foundation
import Combine

enum StatsDimension: Sendable { case artist, album, genre, source, outputDevice }
enum StatsGranularity: Sendable { case day, week, month }
enum StatsTimeRange: Equatable, Hashable, Sendable {
    case last7Days, last30Days, last90Days, last365Days, allTime
    case custom(Date, Date)
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.last7Days, .last7Days), (.last30Days, .last30Days),
             (.last90Days, .last90Days), (.last365Days, .last365Days),
             (.allTime, .allTime): return true
        case (.custom(let a1, let b1), .custom(let a2, let b2)):
            return a1 == a2 && b1 == b2
        default: return false
        }
    }
    func hash(into hasher: inout Hasher) {
        switch self {
        case .last7Days:   hasher.combine(0)
        case .last30Days:  hasher.combine(1)
        case .last90Days:  hasher.combine(2)
        case .last365Days: hasher.combine(3)
        case .allTime:     hasher.combine(4)
        case .custom(let s, let e): hasher.combine(5); hasher.combine(s); hasher.combine(e)
        }
    }
}

struct StatsFilterState: Equatable, Sendable {
    var timeRange: StatsTimeRange = .last30Days
    var selectedArtist: String? = nil
    var selectedAlbum:  String? = nil
    var selectedGenre:  String? = nil
    var selectedSource: String? = nil
    var selectedContentType: String? = nil
    var selectedOutputDevice: String? = nil
    var excludeSkipped: Bool = true
}

private struct StatsRefreshResult {
    var playTimeSummaries: [PlayTimeSummaryRow]
    var topArtists: [TopDimensionRow]
    var topMovies: [TopDimensionRow]
    var topTVShows: [TopDimensionRow]
    var topRadioStations: [TopDimensionRow]
    var radioListenSeconds: Double
    var timeSeries: [TimeSeriesRow]
    var genreBreakdown: [TopDimensionRow]
    var sourceBreakdown: [TopDimensionRow]
    var contentTypeBreakdown: [TopDimensionRow]
    var outputDeviceBreakdown: [TopDimensionRow]
    var recentEvents: [RecentEventRow]
}

@MainActor
final class PlayHistoryAgent: ObservableObject {
    @Published var playTimeSummaries: [PlayTimeSummaryRow] = []
    @Published var topArtists:     [TopDimensionRow] = []
    @Published var topMovies:      [TopDimensionRow] = []
    @Published var topTVShows:     [TopDimensionRow] = []
    @Published var topRadioStations: [TopDimensionRow] = []
    @Published var radioListenSeconds: Double = 0
    @Published var timeSeries:     [TimeSeriesRow]   = []
    @Published var genreBreakdown: [TopDimensionRow] = []
    @Published var sourceBreakdown: [TopDimensionRow] = []
    @Published var contentTypeBreakdown: [TopDimensionRow] = []
    @Published var outputDeviceBreakdown: [TopDimensionRow] = []
    @Published var recentEvents:   [RecentEventRow]  = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var isBackfilling = false
    @Published var backfillCurrent = 0
    @Published var backfillTotal = 0

    @Published private(set) var filter = StatsFilterState() {
        didSet { if filter != oldValue { invalidateCache(); scheduleRefresh() } }
    }
    @Published var granularity = StatsGranularity.day {
        didSet { cachedTimeSeries = nil; scheduleRefresh() }
    }

    private var refreshTask: Task<Void, Never>?
    private var backfillTask: Task<Void, Never>?
    private var cachedPlayTimeSummaries: [PlayTimeSummaryRow]?
    private var cachedTopArtists:     [TopDimensionRow]?
    private var cachedTopMovies:      [TopDimensionRow]?
    private var cachedTopTVShows:     [TopDimensionRow]?
    private var cachedTopRadioStations: [TopDimensionRow]?
    private var cachedRadioListenSeconds: Double?
    private var cachedTimeSeries:     [TimeSeriesRow]?
    private var cachedGenreBreakdown: [TopDimensionRow]?
    private var cachedSourceBreakdown: [TopDimensionRow]?
    private var cachedContentTypeBreakdown: [TopDimensionRow]?
    private var cachedOutputDeviceBreakdown: [TopDimensionRow]?
    private var cachedRecentEvents:   [RecentEventRow]?

    private let store = PlayHistoryStore()

    func setTimeRange(_ range: StatsTimeRange) { filter.timeRange = range }
    func selectArtist(_ name: String?)  { filter.selectedArtist = name }
    func selectAlbum(_ name: String?)   { filter.selectedAlbum  = name }
    func selectGenre(_ name: String?)   { filter.selectedGenre  = name }
    // Internet radio is presented in its own section; music/video source filtering ignores it.
    func selectSource(_ s: String?)     { filter.selectedSource = s == PlayHistorySource.radio.rawValue ? nil : s }
    func selectContentType(_ s: String?) { filter.selectedContentType = s }
    func selectOutputDevice(_ s: String?) { filter.selectedOutputDevice = s }
    func clearAllFilters()              { filter = StatsFilterState() }
    func clearVisibleFilters() {
        filter = StatsFilterState(
            timeRange: .last30Days,
            selectedArtist: nil,
            selectedAlbum: nil,
            selectedGenre: nil,
            selectedSource: nil,
            selectedContentType: nil,
            selectedOutputDevice: nil,
            excludeSkipped: true
        )
    }
    func setGranularity(_ g: StatsGranularity) { granularity = g }

    var hasVisibleFilters: Bool {
        filter.timeRange != .last30Days ||
        filter.selectedArtist != nil ||
        filter.selectedAlbum != nil ||
        filter.selectedGenre != nil ||
        filter.selectedSource != nil ||
        filter.selectedContentType != nil ||
        filter.selectedOutputDevice != nil ||
        filter.excludeSkipped != true
    }

    private func invalidateCache() {
        cachedPlayTimeSummaries = nil; cachedTopArtists = nil
        cachedTopMovies = nil; cachedTopTVShows = nil
        cachedTopRadioStations = nil; cachedRadioListenSeconds = nil
        cachedTimeSeries = nil; cachedGenreBreakdown = nil
        cachedSourceBreakdown = nil; cachedContentTypeBreakdown = nil
        cachedOutputDeviceBreakdown = nil
        cachedRecentEvents = nil
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { await refresh() }
    }

    func refresh() async {
        let currentFilter = filter
        let currentGranularity = granularity
        isLoading = true
        error = nil
        do {
            let result = try await Task.detached(priority: .userInitiated) { [store, currentFilter, currentGranularity] in
                try Task.checkCancellation()
                let playTimeSummaries = try store.fetchPlayTimeSummaries(filter: currentFilter)
                try Task.checkCancellation()
                let topArtists = try store.fetchTopArtists(filter: currentFilter)
                try Task.checkCancellation()
                let topMovies = try store.fetchTopMovies(filter: currentFilter)
                try Task.checkCancellation()
                let topTVShows = try store.fetchTopTVShows(filter: currentFilter)
                try Task.checkCancellation()
                let topRadioStations = try store.fetchTopRadioStations(filter: currentFilter)
                try Task.checkCancellation()
                let radioListenSeconds = try store.fetchRadioListenSeconds(filter: currentFilter)
                try Task.checkCancellation()
                let timeSeries = try store.fetchTimeSeries(filter: currentFilter, granularity: currentGranularity)
                try Task.checkCancellation()
                let genreBreakdown = try store.fetchGenreBreakdown(filter: currentFilter)
                try Task.checkCancellation()
                let sourceBreakdown = try store.fetchTopDimension(dimension: .source, filter: currentFilter)
                try Task.checkCancellation()
                let contentTypeBreakdown = try store.fetchContentTypeBreakdown(filter: currentFilter)
                try Task.checkCancellation()
                let outputDeviceBreakdown = try store.fetchTopDimension(dimension: .outputDevice, filter: currentFilter)
                try Task.checkCancellation()
                let recentEvents = try store.fetchRecentEvents(filter: currentFilter)
                return StatsRefreshResult(
                    playTimeSummaries: playTimeSummaries,
                    topArtists: topArtists,
                    topMovies: topMovies,
                    topTVShows: topTVShows,
                    topRadioStations: topRadioStations,
                    radioListenSeconds: radioListenSeconds,
                    timeSeries: timeSeries,
                    genreBreakdown: genreBreakdown,
                    sourceBreakdown: sourceBreakdown,
                    contentTypeBreakdown: contentTypeBreakdown,
                    outputDeviceBreakdown: outputDeviceBreakdown,
                    recentEvents: recentEvents
                )
            }.value
            try Task.checkCancellation()
            playTimeSummaries = result.playTimeSummaries
            topArtists = result.topArtists
            topMovies = result.topMovies
            topTVShows = result.topTVShows
            topRadioStations = result.topRadioStations
            radioListenSeconds = result.radioListenSeconds
            timeSeries = result.timeSeries
            genreBreakdown = result.genreBreakdown
            sourceBreakdown = result.sourceBreakdown
            contentTypeBreakdown = result.contentTypeBreakdown
            outputDeviceBreakdown = result.outputDeviceBreakdown
            recentEvents = result.recentEvents
            cachedPlayTimeSummaries = result.playTimeSummaries
            cachedTopArtists = result.topArtists
            cachedTopMovies = result.topMovies
            cachedTopTVShows = result.topTVShows
            cachedTopRadioStations = result.topRadioStations
            cachedRadioListenSeconds = result.radioListenSeconds
            cachedTimeSeries = result.timeSeries
            cachedGenreBreakdown = result.genreBreakdown
            cachedSourceBreakdown = result.sourceBreakdown
            cachedContentTypeBreakdown = result.contentTypeBreakdown
            cachedOutputDeviceBreakdown = result.outputDeviceBreakdown
            cachedRecentEvents = result.recentEvents
        } catch is CancellationError {
            // Refresh was superseded by a newer request — discard results silently
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Genre Backfill

    func startGenreBackfill() {
        guard !isBackfilling else { return }
        isBackfilling = true
        backfillCurrent = 0
        backfillTotal = 0
        backfillTask = Task {
            let resolved = await GenreDiscoveryService.shared.backfillNullGenres { [weak self] current, total in
                self?.backfillCurrent = current
                self?.backfillTotal = total
            }
            isBackfilling = false
            if resolved > 0 {
                invalidateCache()
                scheduleRefresh()
            }
        }
    }

    func cancelGenreBackfill() {
        backfillTask?.cancel()
        backfillTask = nil
        isBackfilling = false
    }
}
