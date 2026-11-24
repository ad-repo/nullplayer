import XCTest
@testable import NullPlayer

/// The Audio Analyzer Scope's history and trace (`ScopeTrace`), #797.
final class ScopeTraceTests: XCTestCase {
    /// A sine chunk, `UInt8` centred on 128, starting `phase` samples into a `period`-sample cycle.
    private func sine(period: Double, phase: Int = 0, amplitude: Double = 100) -> [UInt8] {
        (0..<WaveformPlayout.sampleCount).map {
            UInt8(128 + amplitude * sin(2 * .pi * Double($0 + phase) / period))
        }
    }

    private let silence = WaveformPlayout.silence

    /// The latest trigger plus the whole drawn window stays inside the history.
    func testTheWindowFitsTheHistoryFromTheLatestTrigger() {
        XCTAssertLessThan(ScopeTrace.triggerSearchLength + (ScopeTrace.pointCount - 1) * ScopeTrace.drawStride,
                          ScopeTrace.historyLength)
        var trace = ScopeTrace()
        // Negative everywhere except a rise at the very end of the search region.
        let low = [UInt8](repeating: 60, count: WaveformPlayout.sampleCount)
        for _ in 0..<ScopeTrace.historyChunks { trace.append(left: low, right: low) }
        trace.render(at: 0)
        XCTAssertEqual(trace.points.count, ScopeTrace.pointCount)
    }

    /// Periodic audio is drawn from a rising zero-crossing whatever phase the chunks arrived in.
    func testTheTraceStartsAtARisingZeroCrossing() {
        for phase in [0, 37, 101] {
            var trace = ScopeTrace()
            for _ in 0..<ScopeTrace.historyChunks {
                trace.append(left: sine(period: 192, phase: phase), right: sine(period: 192, phase: phase))
            }
            trace.render(at: 0)
            XCTAssertEqual(trace.points[0], 0, accuracy: 0.05, "phase \(phase)")
            XCTAssertGreaterThan(trace.points[1], trace.points[0], "phase \(phase)")
        }
    }

    /// The blend is weighted by elapsed time, not by render count: a second render at the same
    /// instant changes nothing.
    func testTheBlendIsWeightedByElapsedTime() {
        var trace = ScopeTrace()
        trace.append(left: sine(period: 192), right: sine(period: 192))
        trace.render(at: 0)
        let before = trace.points
        trace.append(left: silence, right: silence)
        trace.render(at: 0)
        XCTAssertEqual(trace.points, before)
    }

    /// Silence blends the trace down to flat.
    func testSilenceFlattensTheTrace() {
        var trace = ScopeTrace()
        for _ in 0..<ScopeTrace.historyChunks { trace.append(left: sine(period: 192), right: sine(period: 192)) }
        trace.render(at: 0)
        XCTAssertFalse(trace.isFlat)
        var time = 0.0
        for _ in 0..<200 where !trace.isFlat {
            time += 576.0 / 44_100
            trace.append(left: silence, right: silence)
            trace.render(at: time)
        }
        XCTAssertTrue(trace.isFlat)
    }
}
