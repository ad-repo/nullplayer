import Foundation
import Combine

enum StatsDimension { case artist, album, genre, source }
enum StatsGranularity { case day, week, month }
enum StatsTimeRange: Equatable, Hashable {
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

struct StatsFilterState: Equatable {
    var timeRange: StatsTimeRange = .last30Days
    var selectedArtist: String? = nil
    var selectedAlbum:  String? = nil
    var selectedGenre:  String? = nil
    var selectedSource: String? = nil
    var selectedContentType: String? = nil
    var excludeSkipped: Bool = true
}

@MainActor
final class PlayHistoryAgent: ObservableObject {
    @Published var playTimeSummaries: [PlayTimeSummaryRow] = []
    @Published var topArtists:     [TopDimensionRow] = []
    @Published var timeSeries:     [TimeSeriesRow]   = []
    @Published var genreBreakdown: [TopDimensionRow] = []
    @Published var sourceBreakdown: [TopDimensionRow] = []
    @Published var contentTypeBreakdown: [TopDimensionRow] = []
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
    private var cachedTimeSeries:     [TimeSeriesRow]?
    private var cachedGenreBreakdown: [TopDimensionRow]?
    private var cachedSourceBreakdown: [TopDimensionRow]?
    private var cachedContentTypeBreakdown: [TopDimensionRow]?
    private var cachedRecentEvents:   [RecentEventRow]?

    private let store = PlayHistoryStore()

    func setTimeRange(_ range: StatsTimeRange) { filter.timeRange = range }
    func selectArtist(_ name: String?)  { filter.selectedArtist = name }
    func selectAlbum(_ name: String?)   { filter.selectedAlbum  = name }
    func selectGenre(_ name: String?)   { filter.selectedGenre  = name }
    func selectSource(_ s: String?)     { filter.selectedSource = s }
    func selectContentType(_ s: String?) { filter.selectedContentType = s }
    func clearAllFilters()              { filter = StatsFilterState() }
    func clearVisibleFilters() {
        filter = StatsFilterState(
            timeRange: .last30Days,
            selectedArtist: nil,
            selectedAlbum: nil,
            selectedGenre: nil,
            selectedSource: nil,
            selectedContentType: nil,
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
        filter.excludeSkipped != true
    }

    private func invalidateCache() {
        cachedPlayTimeSummaries = nil; cachedTopArtists = nil
        cachedTimeSeries = nil; cachedGenreBreakdown = nil
        cachedSourceBreakdown = nil; cachedContentTypeBreakdown = nil
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
            let result = try await Task(priority: .userInitiated) { [store, currentFilter, currentGranularity] in
                try Task.checkCancellation()
                let p = try store.fetchPlayTimeSummaries(filter: currentFilter)
                try Task.checkCancellation()
                let a = try store.fetchTopDimension(dimension: .artist, filter: currentFilter)
                try Task.checkCancellation()
                let s = try store.fetchTimeSeries(filter: currentFilter, granularity: currentGranularity)
                try Task.checkCancellation()
                let g = try store.fetchGenreBreakdown(filter: currentFilter)
                try Task.checkCancellation()
                let o = try store.fetchTopDimension(dimension: .source, filter: currentFilter)
                try Task.checkCancellation()
                let c = try store.fetchContentTypeBreakdown(filter: currentFilter)
                try Task.checkCancellation()
                let r = try store.fetchRecentEvents(filter: currentFilter)
                return (p, a, s, g, o, c, r)
            }.value
            try Task.checkCancellation()
            (playTimeSummaries, topArtists, timeSeries, genreBreakdown, sourceBreakdown, contentTypeBreakdown, recentEvents) = result
            cachedPlayTimeSummaries = result.0; cachedTopArtists = result.1
            cachedTimeSeries = result.2; cachedGenreBreakdown = result.3
            cachedSourceBreakdown = result.4; cachedContentTypeBreakdown = result.5
            cachedRecentEvents = result.6
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
