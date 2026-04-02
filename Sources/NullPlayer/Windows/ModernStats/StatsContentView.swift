import SwiftUI
import Charts

// MARK: - Content

struct StatsContentView: View {
    @ObservedObject var agent: PlayHistoryAgent
    var skinTextColor: Color = .primary
    var headerTitle: String = "Play History"
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            StatsHeaderView(agent: agent, title: headerTitle)
            Picker("", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("History").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            if selectedTab == 0 {
                StatsOverviewView(agent: agent, skinTextColor: skinTextColor)
            } else {
                StatsHistoryTableView(agent: agent)
            }
        }
        .onAppear { agent.scheduleRefresh() }
    }
}

struct StatsHeaderView: View {
    @ObservedObject var agent: PlayHistoryAgent
    let title: String

    var body: some View {
        HStack {
            Text(title)
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
                FilterChip(label: PlayHistorySource.displayName(for: source)) { agent.selectSource(nil) }
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
            .fixedSize()
            if agent.genreBreakdown.contains(where: { $0.id == "Unknown" }) {
                if agent.isBackfilling {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("\(agent.backfillCurrent)/\(agent.backfillTotal)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                        Button("Cancel") { agent.cancelGenreBackfill() }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                    }
                } else {
                    Button("Discover Genres") { agent.startGenreBackfill() }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                }
            }
            if agent.hasVisibleFilters {
                Button("Clear") { agent.clearVisibleFilters() }
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
    var skinTextColor: Color = .primary

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 16) {
                TopDimensionChartView(
                    title: "Top Artists",
                    rows: agent.topArtists,
                    skinTextColor: skinTextColor,
                    selected: Binding(
                        get: { agent.filter.selectedArtist },
                        set: { (v: String?) in agent.selectArtist(v) }
                    )
                )
                .frame(height: 220)

                GenreChartView(
                    rows: agent.genreBreakdown,
                    selected: Binding(
                        get: { agent.filter.selectedGenre },
                        set: { (v: String?) in agent.selectGenre(v) }
                    ),
                    agent: agent
                )
                .frame(height: 240)

                SourceChartView(
                    rows: agent.sourceBreakdown,
                    selected: Binding(
                        get: { agent.filter.selectedSource },
                        set: { (v: String?) in agent.selectSource(v) }
                    )
                )
                .frame(height: 220)

                TimeSeriesChartView(agent: agent, skinTextColor: skinTextColor)
                    .frame(height: 220)
            }
            .padding(12)
        }
    }
}

struct TopDimensionChartView: View {
    let title: String
    let rows: [TopDimensionRow]
    var skinTextColor: Color = .primary
    @Binding var selected: String?
    private let labelColumnWidth: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).fontWeight(.medium)
            if rows.isEmpty {
                Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxCount = rows.map(\.playCount).max() ?? 1
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 3) {
                        ForEach(rows) { row in
                            Button { selected = (selected == row.id) ? nil : row.id } label: {
                                HStack(spacing: 6) {
                                    Text(row.displayName)
                                        .font(.caption2)
                                        .foregroundColor(row.id == selected ? Color.accentColor : skinTextColor)
                                        .lineLimit(1)
                                        .frame(width: labelColumnWidth, alignment: .trailing)
                                    GeometryReader { geo in
                                        let fraction = CGFloat(row.playCount) / CGFloat(maxCount)
                                        Capsule()
                                            .fill(row.id == selected ? Color.accentColor : Color.accentColor.opacity(0.55))
                                            .frame(width: max(2, geo.size.width * fraction), height: 10)
                                            .frame(maxHeight: .infinity, alignment: .center)
                                    }
                                    Text("\(row.playCount)")
                                        .font(.caption2)
                                        .foregroundColor(skinTextColor.opacity(0.7))
                                        .frame(width: 24, alignment: .leading)
                                }
                                .frame(height: 18)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private let genreColors: [Color] = [
    .blue, .green, .orange, .purple, .red, .yellow, .cyan, .pink
]

private let sourceColorScale: KeyValuePairs<String, Color> = [
    "Local": .blue,
    "Plex": .orange,
    "Subsonic": .green,
    "Jellyfin": .purple,
    "Emby": .pink,
    "Radio": .red
]

private func sourceColor(for source: String) -> Color {
    sourceColorScale.first(where: { $0.0 == source })?.1 ?? .gray
}

struct GenreChartView: View {
    let rows: [TopDimensionRow]
    @Binding var selected: String?
    @ObservedObject var agent: PlayHistoryAgent
    private let chartSize: CGFloat = 184

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Genres").font(.subheadline).fontWeight(.medium)
            if rows.isEmpty {
                Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack {
                        Spacer(minLength: 0)
                        Chart(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            SectorMark(
                                angle: .value("Plays", row.playCount),
                                innerRadius: .ratio(0.5)
                            )
                            .foregroundStyle(genreColors[idx % genreColors.count])
                            .opacity(selected == nil || selected == row.id ? 1.0 : 0.4)
                        }
                        .chartLegend(.hidden)
                        .frame(width: chartSize, height: chartSize)
                        .onTapGesture { selected = nil }
                        Spacer(minLength: 0)
                    }
                    .frame(width: chartSize)
                    .frame(maxHeight: .infinity)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 3) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                                Button {
                                    selected = (selected == row.id) ? nil : row.id
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(genreColors[idx % genreColors.count])
                                            .frame(width: 8, height: 8)
                                        Text(row.displayName)
                                            .font(.caption2)
                                            .foregroundColor(row.id == selected ? .accentColor : .primary)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        Text("\(row.playCount)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .monospacedDigit()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .opacity(selected == nil || selected == row.id ? 1.0 : 0.5)
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.trailing, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SourceChartView: View {
    let rows: [TopDimensionRow]
    @Binding var selected: String?
    private let chartSize: CGFloat = 156

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources").font(.subheadline).fontWeight(.medium)
            if rows.isEmpty {
                Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Chart(rows) { row in
                        SectorMark(
                            angle: .value("Plays", row.playCount),
                            innerRadius: .ratio(0.5)
                        )
                        .foregroundStyle(sourceColor(for: row.displayName))
                        .opacity(selected == nil || selected == row.id ? 1.0 : 0.4)
                    }
                    .chartLegend(.hidden)
                    .frame(width: chartSize, height: chartSize)
                    .onTapGesture { selected = nil }

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 3) {
                            ForEach(rows) { row in
                                Button {
                                    selected = (selected == row.id) ? nil : row.id
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(sourceColor(for: row.displayName))
                                            .frame(width: 8, height: 8)
                                        Text(row.displayName)
                                            .font(.caption2)
                                            .foregroundColor(row.id == selected ? .accentColor : .primary)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        Text("\(row.playCount)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .monospacedDigit()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .opacity(selected == nil || selected == row.id ? 1.0 : 0.5)
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.trailing, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct TimeSeriesChartView: View {
    @ObservedObject var agent: PlayHistoryAgent
    var skinTextColor: Color = .primary

    private var bucketCount: Int {
        Set(agent.timeSeries.map(\.bucket)).count
    }

    private var calendarUnit: Calendar.Component {
        switch agent.granularity {
        case .day:   return .day
        case .week:  return .weekOfYear
        case .month: return .month
        }
    }

    private var axisStrideCount: Int {
        let n = bucketCount
        guard n > 0 else { return 1 }
        return max(1, n / 6)
    }

    private var xAxisFormat: Date.FormatStyle {
        switch agent.granularity {
        case .day, .week: return .dateTime.month(.abbreviated).day()
        case .month:      return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

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
                    BarMark(
                        x: .value("Date", row.date, unit: calendarUnit),
                        y: .value("Plays", row.playCount)
                    )
                    .foregroundStyle(by: .value("Source", row.sourceDisplayName))
                }
                .chartForegroundStyleScale(sourceColorScale)
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: calendarUnit, count: axisStrideCount)) { value in
                        AxisGridLine().foregroundStyle(skinTextColor.opacity(0.15))
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: xAxisFormat)
                                    .font(.caption2)
                                    .foregroundColor(skinTextColor)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(skinTextColor.opacity(0.15))
                        if let count = value.as(Int.self) {
                            AxisValueLabel {
                                Text("\(count)").font(.caption2).foregroundColor(skinTextColor)
                            }
                        }
                    }
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
            ScrollView(.horizontal) {
                Table(agent.recentEvents) {
                    TableColumn("Title", value: \.title)
                    TableColumn("Artist", value: \.artist)
                    TableColumn("Album", value: \.album)
                    TableColumn("Genre", value: \.genre)
                    TableColumn("Source") { row in
                        Text(row.sourceDisplayName)
                    }
                    TableColumn("Played At") { row in
                        Text(row.playedAt, style: .date)
                    }
                    TableColumn("Duration") { row in
                        Text(String(format: "%.1f min", row.durationListened / 60))
                    }
                }
                .frame(minWidth: 980)
            }
        }
    }
}
