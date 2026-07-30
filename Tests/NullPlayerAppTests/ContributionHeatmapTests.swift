import XCTest
@testable import NullPlayer

final class ContributionHeatmapTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    func testDateWindowStartsOnSundayFiftyTwoWeeksBeforeCurrentWeek() throws {
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 30,
                hour: 15,
                minute: 45
            ))
        )

        let window = ContributionHeatmapDateWindow.containing(
            referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            window.start,
            calendar.date(from: DateComponents(year: 2025, month: 7, day: 27))
        )
        XCTAssertEqual(
            window.today,
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 30))
        )
        XCTAssertEqual(window.end, referenceDate)
        XCTAssertEqual(calendar.component(.weekday, from: window.start), 1)
    }

    func testDateWindowIncludesEveryDayRenderedByTheGrid() throws {
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: 1,
                hour: 12
            ))
        )
        let window = ContributionHeatmapDateWindow.containing(
            referenceDate,
            calendar: calendar
        )
        let renderedDayCount = try XCTUnwrap(
            calendar.dateComponents(
                [.day],
                from: window.start,
                to: window.today
            ).day
        ) + 1

        XCTAssertEqual(renderedDayCount, 371)
        XCTAssertLessThanOrEqual(window.start, window.end)
        XCTAssertGreaterThanOrEqual(window.end, window.today)
    }

    func testHeadingUsesSingularUnits() {
        XCTAssertEqual(
            ContributionHeatmapFormatting.headingText(minutes: 1),
            "1 minute of listening in the last year"
        )
        XCTAssertEqual(
            ContributionHeatmapFormatting.headingText(minutes: 89),
            "1 hour of listening in the last year"
        )
    }

    func testHeadingRoundsHoursInsteadOfTruncating() {
        XCTAssertEqual(
            ContributionHeatmapFormatting.headingText(minutes: 90),
            "2 hours of listening in the last year"
        )
        XCTAssertEqual(
            ContributionHeatmapFormatting.headingText(minutes: 149),
            "2 hours of listening in the last year"
        )
        XCTAssertEqual(
            ContributionHeatmapFormatting.headingText(minutes: 150),
            "3 hours of listening in the last year"
        )
    }
}
