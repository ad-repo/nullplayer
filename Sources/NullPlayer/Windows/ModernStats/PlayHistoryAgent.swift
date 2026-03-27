import Foundation

enum StatsDimension { case artist, album, genre }
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
    var excludeSkipped: Bool = true
}

@MainActor
final class PlayHistoryAgent: ObservableObject {
    @Published var topArtists:     [TopDimensionRow] = []
    @Published var topAlbums:      [TopDimensionRow] = []
    @Published var timeSeries:     [TimeSeriesRow]   = []
    @Published var genreBreakdown: [TopDimensionRow] = []
    @Published var recentEvents:   [RecentEventRow]  = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private(set) var filter = StatsFilterState() {
        didSet { if filter != oldValue { invalidateCache(); scheduleRefresh() } }
    }
    @Published var granularity = StatsGranularity.day {
        didSet { cachedTimeSeries = nil; scheduleRefresh() }
    }

    private var refreshTask: Task<Void, Never>?
    private var cachedTopArtists:     [TopDimensionRow]?
    private var cachedTopAlbums:      [TopDimensionRow]?
    private var cachedTimeSeries:     [TimeSeriesRow]?
    private var cachedGenreBreakdown: [TopDimensionRow]?
    private var cachedRecentEvents:   [RecentEventRow]?

    private let store = PlayHistoryStore()

    func setTimeRange(_ range: StatsTimeRange) { filter.timeRange = range }
    func selectArtist(_ name: String?)  { filter.selectedArtist = name }
    func selectAlbum(_ name: String?)   { filter.selectedAlbum  = name }
    func selectGenre(_ name: String?)   { filter.selectedGenre  = name }
    func selectSource(_ s: String?)     { filter.selectedSource = s }
    func clearAllFilters()              { filter = StatsFilterState() }
    func setGranularity(_ g: StatsGranularity) { granularity = g }

    private func invalidateCache() {
        cachedTopArtists = nil; cachedTopAlbums = nil
        cachedTimeSeries = nil; cachedGenreBreakdown = nil; cachedRecentEvents = nil
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
                let a = try store.fetchTopDimension(dimension: .artist, filter: currentFilter)
                let b = try store.fetchTopDimension(dimension: .album,  filter: currentFilter)
                let s = try store.fetchTimeSeries(filter: currentFilter, granularity: currentGranularity)
                let g = try store.fetchGenreBreakdown(filter: currentFilter)
                let r = try store.fetchRecentEvents(filter: currentFilter)
                return (a, b, s, g, r)
            }.value
            try Task.checkCancellation()
            (topArtists, topAlbums, timeSeries, genreBreakdown, recentEvents) = result
            cachedTopArtists = result.0; cachedTopAlbums = result.1
            cachedTimeSeries = result.2; cachedGenreBreakdown = result.3; cachedRecentEvents = result.4
        } catch is CancellationError {
            // Refresh was superseded by a newer request — discard results silently
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
