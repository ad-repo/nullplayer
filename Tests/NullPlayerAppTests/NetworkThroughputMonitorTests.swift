import XCTest
@testable import NullPlayer

final class NetworkThroughputMonitorTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testValidTickAccumulatesAndComputesRates() {
        let start = date("2026-07-04T12:00:00Z")
        let now = start.addingTimeInterval(1.0)

        let result = NetworkThroughputMonitor.evaluateTick(
            previousCounters: counters("en0", input: 1_000, output: 2_000),
            previousSampleAt: start,
            currentCounters: counters("en0", input: 2_024, output: 2_512),
            now: now,
            currentDay: "2026-07-04",
            dailyDownBytes: 10,
            dailyUpBytes: 20,
            sampleInterval: 0.5,
            calendar: calendar
        )

        XCTAssertEqual(result.resetReason, .none)
        XCTAssertEqual(result.downBytesPerSecond, 1_024)
        XCTAssertEqual(result.upBytesPerSecond, 512)
        XCTAssertEqual(result.dailyDownBytes, 1_034)
        XCTAssertEqual(result.dailyUpBytes, 532)
    }

    func testFirstSampleSeedsWithoutAccumulating() {
        let now = date("2026-07-04T12:00:00Z")
        let result = NetworkThroughputMonitor.evaluateTick(
            previousCounters: nil,
            previousSampleAt: nil,
            currentCounters: counters("en0", input: 2_024, output: 2_512),
            now: now,
            currentDay: "2026-07-04",
            dailyDownBytes: 10,
            dailyUpBytes: 20,
            sampleInterval: 0.5,
            calendar: calendar
        )

        XCTAssertEqual(result.resetReason, .firstSample)
        XCTAssertEqual(result.dailyDownBytes, 10)
        XCTAssertEqual(result.dailyUpBytes, 20)
        XCTAssertEqual(result.downBytesPerSecond, 0)
    }

    func testInterfaceChangeSeedsWithoutAccumulating() {
        let start = date("2026-07-04T12:00:00Z")
        let result = NetworkThroughputMonitor.evaluateTick(
            previousCounters: counters("en0", input: 1_000, output: 2_000),
            previousSampleAt: start,
            currentCounters: counters("utun4", input: 2_024, output: 2_512),
            now: start.addingTimeInterval(1),
            currentDay: "2026-07-04",
            dailyDownBytes: 10,
            dailyUpBytes: 20,
            sampleInterval: 0.5,
            calendar: calendar
        )

        XCTAssertEqual(result.resetReason, .interfaceChanged)
        XCTAssertEqual(result.dailyDownBytes, 10)
        XCTAssertEqual(result.dailyUpBytes, 20)
    }

    func testCounterDecreaseSeedsWithoutAccumulating() {
        let start = date("2026-07-04T12:00:00Z")
        let result = NetworkThroughputMonitor.evaluateTick(
            previousCounters: counters("en0", input: 2_000, output: 2_000),
            previousSampleAt: start,
            currentCounters: counters("en0", input: 1_900, output: 2_100),
            now: start.addingTimeInterval(1),
            currentDay: "2026-07-04",
            dailyDownBytes: 10,
            dailyUpBytes: 20,
            sampleInterval: 0.5,
            calendar: calendar
        )

        XCTAssertEqual(result.resetReason, .counterDecrease)
        XCTAssertEqual(result.dailyDownBytes, 10)
        XCTAssertEqual(result.dailyUpBytes, 20)
    }

    func testGapAboveThresholdSeedsWithoutAccumulating() {
        let start = date("2026-07-04T12:00:00Z")
        let result = NetworkThroughputMonitor.evaluateTick(
            previousCounters: counters("en0", input: 1_000, output: 2_000),
            previousSampleAt: start,
            currentCounters: counters("en0", input: 2_024, output: 2_512),
            now: start.addingTimeInterval(2.01),
            currentDay: "2026-07-04",
            dailyDownBytes: 10,
            dailyUpBytes: 20,
            sampleInterval: 0.5,
            calendar: calendar
        )

        XCTAssertEqual(result.resetReason, .gapExceeded)
        XCTAssertEqual(result.dailyDownBytes, 10)
        XCTAssertEqual(result.dailyUpBytes, 20)
    }

    func testGapAtThresholdStillAccumulates() {
        let start = date("2026-07-04T12:00:00Z")
        let result = NetworkThroughputMonitor.evaluateTick(
            previousCounters: counters("en0", input: 1_000, output: 2_000),
            previousSampleAt: start,
            currentCounters: counters("en0", input: 2_000, output: 3_000),
            now: start.addingTimeInterval(2.0),
            currentDay: "2026-07-04",
            dailyDownBytes: 0,
            dailyUpBytes: 0,
            sampleInterval: 0.5,
            calendar: calendar
        )

        XCTAssertEqual(result.resetReason, .none)
        XCTAssertEqual(result.downBytesPerSecond, 500)
        XCTAssertEqual(result.upBytesPerSecond, 500)
        XCTAssertEqual(result.dailyDownBytes, 1_000)
        XCTAssertEqual(result.dailyUpBytes, 1_000)
    }

    func testDayRolloverResetsWithoutAccumulating() {
        let start = date("2026-07-04T23:59:59Z")
        let result = NetworkThroughputMonitor.evaluateTick(
            previousCounters: counters("en0", input: 1_000, output: 2_000),
            previousSampleAt: start,
            currentCounters: counters("en0", input: 2_000, output: 3_000),
            now: date("2026-07-05T00:00:00Z"),
            currentDay: "2026-07-04",
            dailyDownBytes: 50_000,
            dailyUpBytes: 60_000,
            sampleInterval: 0.5,
            calendar: calendar
        )

        XCTAssertEqual(result.resetReason, .dayRollover)
        XCTAssertEqual(result.currentDay, "2026-07-05")
        XCTAssertEqual(result.dailyDownBytes, 0)
        XCTAssertEqual(result.dailyUpBytes, 0)
    }

    func testUnitFormattingScalesRates() {
        XCTAssertEqual(NetworkThroughputFormatting.bytesPerSecond(999), "999 B/s")
        XCTAssertEqual(NetworkThroughputFormatting.bytesPerSecond(1_536), "1.5 KB/s")
        XCTAssertEqual(NetworkThroughputFormatting.bytes(1_048_576), "1.0 MB")
    }

    private func counters(_ name: String, input: UInt64, output: UInt64) -> NetworkByteCounters {
        NetworkByteCounters(interfaceName: name, inputBytes: input, outputBytes: output)
    }

    private func date(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }
}
