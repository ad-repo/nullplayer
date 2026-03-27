import SwiftUI
import Charts

struct StatsContentView: View {
    @ObservedObject var agent: PlayHistoryAgent
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            StatsHeaderView(agent: agent)
            Picker("", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("History").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            if selectedTab == 0 {
                StatsOverviewView(agent: agent)
            } else {
                StatsHistoryTableView(agent: agent)
            }
        }
        .onAppear { agent.scheduleRefresh() }
    }
}

struct StatsHeaderView: View {
    @ObservedObject var agent: PlayHistoryAgent

    var body: some View {
        HStack {
            Text("Play History")
                .font(.headline)
            Spacer()
            // Active filter chips
            if let artist = agent.filter.selectedArtist {
                FilterChip(label: artist) { agent.selectArtist(nil) }
            }
            if let album = agent.filter.selectedAlbum {
                FilterChip(label: album) { agent.selectAlbum(nil) }
            }
            if let genre = agent.filter.selectedGenre {
                FilterChip(label: genre) { agent.selectGenre(nil) }
            }
            if let source = agent.filter.selectedSource {
                FilterChip(label: source) { agent.selectSource(nil) }
            }
            if agent.isLoading {
                ProgressView().controlSize(.small)
            }
            Picker("Range", selection: Binding(
                get: { agent.filter.timeRange },
                set: { agent.setTimeRange($0) }
            )) {
                Text("7 Days").tag(StatsTimeRange.last7Days)
                Text("30 Days").tag(StatsTimeRange.last30Days)
                Text("90 Days").tag(StatsTimeRange.last90Days)
                Text("1 Year").tag(StatsTimeRange.last365Days)
                Text("All Time").tag(StatsTimeRange.allTime)
            }
            .pickerStyle(.menu)
            .frame(width: 100)
            if agent.filter != StatsFilterState() {
                Button("Clear") { agent.clearAllFilters() }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        if let errorMsg = agent.error {
            Text(errorMsg)
                .foregroundColor(.red)
                .font(.caption)
                .padding(.horizontal, 12)
        }
    }
}

struct FilterChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(label).font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.15))
        .cornerRadius(4)
    }
}

struct StatsOverviewView: View {
    @ObservedObject var agent: PlayHistoryAgent

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    TopDimensionChartView(
                        title: "Top Artists",
                        rows: agent.topArtists,
                        selected: Binding(
                            get: { agent.filter.selectedArtist },
                            set: { (v: String?) in agent.selectArtist(v) }
                        )
                    )
                    GenreChartView(
                        rows: agent.genreBreakdown,
                        selected: Binding(
                            get: { agent.filter.selectedGenre },
                            set: { (v: String?) in agent.selectGenre(v) }
                        )
                    )
                }
                .frame(height: 220)
                TimeSeriesChartView(agent: agent)
                    .frame(height: 180)
            }
            .padding(12)
        }
    }
}

struct TopDimensionChartView: View {
    let title: String
    let rows: [TopDimensionRow]
    @Binding var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).fontWeight(.medium)
            if rows.isEmpty {
                Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(rows) { row in
                    BarMark(
                        x: .value("Plays", row.playCount),
                        y: .value("Name", row.displayName)
                    )
                    .foregroundStyle(row.displayName == selected ? Color.accentColor : Color.accentColor.opacity(0.6))
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                if let name: String = proxy.value(atY: location.y, as: String.self) {
                                    selected = (selected == name) ? nil : name
                                }
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct GenreChartView: View {
    let rows: [TopDimensionRow]
    @Binding var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Genres").font(.subheadline).fontWeight(.medium)
            if rows.isEmpty {
                Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(rows) { row in
                    SectorMark(
                        angle: .value("Plays", row.playCount),
                        innerRadius: .ratio(0.5)
                    )
                    .foregroundStyle(by: .value("Genre", row.displayName))
                    .opacity(selected == nil || selected == row.displayName ? 1.0 : 0.4)
                }
                .onTapGesture {
                    // Simplified: tap chart area clears selection
                    selected = nil
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct TimeSeriesChartView: View {
    @ObservedObject var agent: PlayHistoryAgent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Plays Over Time").font(.subheadline).fontWeight(.medium)
                Spacer()
                Picker("", selection: Binding(
                    get: { agent.granularity },
                    set: { (v: StatsGranularity) in agent.setGranularity(v) }
                )) {
                    Text("Day").tag(StatsGranularity.day)
                    Text("Week").tag(StatsGranularity.week)
                    Text("Month").tag(StatsGranularity.month)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            if agent.timeSeries.isEmpty {
                Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(agent.timeSeries) { row in
                    AreaMark(
                        x: .value("Date", row.date),
                        y: .value("Plays", row.playCount)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.3))
                    LineMark(
                        x: .value("Date", row.date),
                        y: .value("Plays", row.playCount)
                    )
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatsHistoryTableView: View {
    @ObservedObject var agent: PlayHistoryAgent

    var body: some View {
        if agent.recentEvents.isEmpty {
            VStack {
                Spacer()
                Text("No play history recorded yet.")
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else {
            Table(agent.recentEvents) {
                TableColumn("Title", value: \.title)
                TableColumn("Artist", value: \.artist)
                TableColumn("Album", value: \.album)
                TableColumn("Genre", value: \.genre)
                TableColumn("Source", value: \.source)
                TableColumn("Played At") { row in
                    Text(row.playedAt, style: .date)
                }
                TableColumn("Duration") { row in
                    Text(String(format: "%.1f min", row.durationListened / 60))
                }
            }
        }
    }
}
