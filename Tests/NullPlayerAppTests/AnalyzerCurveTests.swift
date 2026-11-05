import XCTest
@testable import NullPlayer

final class AnalyzerCurveTests: XCTestCase {
    private let loud = [Float](repeating: 0.8, count: 75)

    private func advance(_ curve: inout AnalyzerCurve, _ raw: [Float], frames: Int) -> Bool {
        var visible = false
        for _ in 0..<frames {
            visible = curve.advance(raw: raw, decayFactor: 0.25, accurateNormalization: false)
        }
        return visible
    }

    /// A step in the input eases in over several frames instead of jumping.
    func testRiseIsEasedNotInstant() {
        var curve = AnalyzerCurve()
        _ = advance(&curve, loud, frames: 1)
        let mid = AnalyzerCurve.pointCount / 2
        let first = curve.levels[mid]
        _ = advance(&curve, loud, frames: 10)
        let settled = curve.levels[mid]
        XCTAssertGreaterThan(first, 0)
        XCTAssertLessThan(first, settled * 0.9)
    }

    /// After the sound stops, levels fall first while peaks hold, then everything drains to zero.
    func testPeaksHoldThenFallToSilence() {
        var curve = AnalyzerCurve()
        _ = advance(&curve, loud, frames: 30)
        let mid = AnalyzerCurve.pointCount / 2
        let peak = curve.peaks[mid]

        _ = advance(&curve, [], frames: 10)  // ~0.17 s: inside the hold
        XCTAssertEqual(curve.peaks[mid], peak)
        XCTAssertLessThan(curve.levels[mid], peak)

        XCTAssertFalse(advance(&curve, [], frames: 180))
        XCTAssertEqual(curve.peaks.max(), 0)
        XCTAssertEqual(curve.levels.max(), 0)
    }
}
