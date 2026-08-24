import SwiftUI

/// A GitHub-style contribution heatmap of daily listening activity over the trailing year.
///
/// Rendered as a self-contained card using a light or dark GitHub-style contribution palette based
/// on the surrounding skin's appearance. Each cell's shade tracks the minutes listened that day.
struct ContributionHeatmapView: View {
    @ObservedObject var agent: PlayHistoryAgent
    @State private var model: HeatmapModel
    @Environment(\.colorScheme) private var colorScheme

    // MARK: GitHub-style adaptive palette
    private struct Palette {
        let l0: Color
        let l1: Color
        let l2: Color
        let l3: Color
        let l4: Color
        let card: Color
        let border: Color
        let text: Color
        let label: Color

        static let light = Palette(
            l0: Color(red: 235/255, green: 237/255, blue: 240/255),
            l1: Color(red: 155/255, green: 233/255, blue: 168/255),
            l2: Color(red: 64/255, green: 196/255, blue: 99/255),
            l3: Color(red: 48/255, green: 161/255, blue: 78/255),
            l4: Color(red: 33/255, green: 110/255, blue: 57/255),
            card: .white,
            border: Color(red: 208/255, green: 215/255, blue: 222/255),
            text: Color(red: 31/255, green: 35/255, blue: 40/255),
            label: Color(red: 89/255, green: 99/255, blue: 110/255)
        )

        static let dark = Palette(
            l0: Color(red: 22/255, green: 27/255, blue: 34/255),
            l1: Color(red: 14/255, green: 68/255, blue: 41/255),
            l2: Color(red: 0/255, green: 109/255, blue: 50/255),
            l3: Color(red: 38/255, green: 166/255, blue: 65/255),
            l4: Color(red: 57/255, green: 211/255, blue: 83/255),
            card: Color(red: 13/255, green: 17/255, blue: 23/255),
            border: Color(red: 48/255, green: 54/255, blue: 61/255),
            text: Color(red: 240/255, green: 246/255, blue: 252/255),
            label: Color(red: 139/255, green: 148/255, blue: 158/255)
        )
    }

    private var palette: Palette { colorScheme == .dark ? .dark : .light }

    private let cellSize: CGFloat = 11
    private let gap: CGFloat = 3
    private let weekdayLabelWidth: CGFloat = 28
    private var colWidth: CGFloat { cellSize + gap }

    init(agent: PlayHistoryAgent) {
        self.agent = agent
        _model = State(initialValue: Self.buildModel(from: agent.dailyActivity))
    }

    var body: some View {
        card(model)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: agent.dailyActivity) { _, dailyActivity in
                model = Self.buildModel(from: dailyActivity)
            }
    }

    // MARK: - Card

    @ViewBuilder
    private func card(_ model: HeatmapModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ContributionHeatmapFormatting.headingText(minutes: model.totalMinutes))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(palette.text)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            if !model.hasActivity {
                Text("No listening activity yet.")
                    .font(.system(size: 12))
                    .foregroundColor(palette.label)
                    .padding(12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            monthRow(model)
                            HStack(alignment: .top, spacing: gap) {
                                weekdayColumn()
                                HStack(alignment: .top, spacing: gap) {
                                    ForEach(Array(model.weeks.enumerated()), id: \.offset) { index, week in
                                        VStack(spacing: gap) {
                                            ForEach(week) { day in
                                                cellView(day, max: model.maxMinutes)
                                            }
                                        }
                                        .id(index)
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                    .onAppear {
                        guard !model.weeks.isEmpty else { return }
                        proxy.scrollTo(model.weeks.count - 1, anchor: .trailing)
                    }
                }
                legend()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
    }

    private func monthRow(_ model: HeatmapModel) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: weekdayLabelWidth + gap, height: 12)
            ZStack(alignment: .topLeading) {
                ForEach(model.monthLabels, id: \.col) { label in
                    Text(label.text)
                        .font(.system(size: 10))
                        .foregroundColor(palette.label)
                        .offset(x: CGFloat(label.col) * colWidth)
                }
            }
            .frame(width: CGFloat(max(model.weeks.count, 1)) * colWidth, height: 12, alignment: .topLeading)
        }
    }

    private func weekdayColumn() -> some View {
        VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                Text(weekdayLabel(row))
                    .font(.system(size: 9))
                    .foregroundColor(palette.label)
                    .frame(width: weekdayLabelWidth, height: cellSize, alignment: .leading)
            }
        }
    }

    private func cellView(_ day: DayCell, max maxMinutes: Double) -> some View {
        let level = day.date == nil ? 0 : intensityLevel(day.minutes, max: maxMinutes)
        return RoundedRectangle(cornerRadius: 2)
            .fill(color(for: level))
            .frame(width: cellSize, height: cellSize)
            .help(day.tooltip)
    }

    private func legend() -> some View {
        HStack(spacing: 4) {
            Spacer()
            Text("Less").font(.system(size: 10)).foregroundColor(palette.label)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: level))
                    .frame(width: cellSize, height: cellSize)
            }
            Text("More").font(.system(size: 10)).foregroundColor(palette.label)
        }
    }

    // MARK: - Helpers

    private func weekdayLabel(_ row: Int) -> String {
        switch row {
        case 1: return "Mon"
        case 3: return "Wed"
        case 5: return "Fri"
        default: return ""
        }
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 1:  return palette.l1
        case 2:  return palette.l2
        case 3:  return palette.l3
        case 4:  return palette.l4
        default: return palette.l0
        }
    }

    private func intensityLevel(_ minutes: Double, max maxMinutes: Double) -> Int {
        guard minutes > 0 else { return 0 }
        guard maxMinutes > 0 else { return 1 }
        let ratio = minutes / maxMinutes
        return min(4, max(1, Int(ceil(ratio * 4))))
    }

    // MARK: - Grid model

    private struct DayCell: Identifiable {
        let id: Int
        let date: Date?    // nil = padding slot outside the [start, today] window
        let minutes: Double
        let tooltip: String
    }

    private struct HeatmapModel {
        let weeks: [[DayCell]]                     // week columns, each 7 cells (Sun…Sat)
        let monthLabels: [(col: Int, text: String)]
        let totalMinutes: Double
        let maxMinutes: Double
        let hasActivity: Bool
    }

    private static func buildModel(
        from dailyActivity: [DailyActivityRow],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> HeatmapModel {
        var minutesByDay: [Date: Double] = [:]
        for row in dailyActivity {
            let day = calendar.startOfDay(for: row.date)
            minutesByDay[day, default: 0] += row.minutes
        }

        let dateWindow = ContributionHeatmapDateWindow.containing(
            referenceDate,
            calendar: calendar
        )
        let today = dateWindow.today

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "en_US")
        monthFormatter.dateFormat = "MMM"

        var weeks: [[DayCell]] = []
        var monthLabels: [(col: Int, text: String)] = []
        var index = 0
        var col = 0
        var lastMonth = -1
        var totalMinutes = 0.0
        var maxMinutes = 0.0
        var cursor = dateWindow.start

        while cursor <= today {
            var column: [DayCell] = []
            for _ in 0..<7 {
                if cursor > today {
                    column.append(DayCell(id: index, date: nil, minutes: 0, tooltip: ""))
                } else {
                    let minutes = minutesByDay[cursor] ?? 0
                    totalMinutes += minutes
                    maxMinutes = max(maxMinutes, minutes)
                    column.append(
                        DayCell(
                            id: index,
                            date: cursor,
                            minutes: minutes,
                            tooltip: ContributionHeatmapFormatting.tooltip(
                                minutes: minutes,
                                date: cursor
                            )
                        )
                    )
                }
                index += 1
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86400)
            }
            if let firstDate = column.first(where: { $0.date != nil })?.date {
                let month = calendar.component(.month, from: firstDate)
                if month != lastMonth {
                    // Drop a preceding label that would sit too close (e.g. a 1-column leading
                    // partial month) so labels never overlap, matching GitHub's spacing.
                    if let last = monthLabels.last, col - last.col < 3 {
                        monthLabels.removeLast()
                    }
                    monthLabels.append((col: col, text: monthFormatter.string(from: firstDate)))
                    lastMonth = month
                }
            }
            weeks.append(column)
            col += 1
        }

        return HeatmapModel(
            weeks: weeks,
            monthLabels: monthLabels,
            totalMinutes: totalMinutes,
            maxMinutes: maxMinutes,
            hasActivity: !dailyActivity.isEmpty
        )
    }
}

enum ContributionHeatmapFormatting {
    private static let tooltipDateFormat = Date.FormatStyle(date: .abbreviated, time: .omitted)

    static func headingText(minutes: Double) -> String {
        if minutes < 60 {
            let roundedMinutes = max(0, Int(minutes.rounded()))
            let unit = roundedMinutes == 1 ? "minute" : "minutes"
            return "\(roundedMinutes) \(unit) of listening in the last year"
        }
        let roundedHours = max(0, Int((minutes / 60).rounded()))
        let unit = roundedHours == 1 ? "hour" : "hours"
        return "\(roundedHours) \(unit) of listening in the last year"
    }

    static func tooltip(minutes: Double, date: Date) -> String {
        "\(Int(minutes.rounded())) min · \(date.formatted(tooltipDateFormat))"
    }
}
