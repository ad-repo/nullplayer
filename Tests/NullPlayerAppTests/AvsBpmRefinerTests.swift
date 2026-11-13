import XCTest
@testable import NullPlayer

/// AVS's advanced beat detection (`AvsBpmRefiner`, a port of the Winamp frontend's bpm.cpp)
/// learns a tempo from the standard detector's beats and fills in the ones it misses.
final class AvsBpmRefinerTests: XCTestCase {

    /// 60 fps frames over a 120 BPM pulse: 30 s with every beat detected, then 10 s where the
    /// detector misses every other one. Once learned, every beat time gets a refined beat
    /// within two frames, the missed ones included, and nothing fires in between.
    func testPredictsTheBeatsA120BpmPulseDrops() {
        var refiner = AvsBpmRefiner()
        let period = 500  // ms, 120 BPM
        var fired: [Int] = []
        var lastBeatSlot = -1
        for frame in 0..<(60 * 40) {
            let now = 1000 + frame * 1000 / 60
            let slot = (now - 1000) / period
            let isDetected = slot != lastBeatSlot && (now < 31_000 || slot % 2 == 0)
            if slot != lastBeatSlot { lastBeatSlot = slot }
            if refiner.refine(isBeat: isDetected, now: now), now >= 31_000 {
                fired.append(now)
            }
        }
        // Upstream's resync nudges the smoothed tempo by ×1.01 / ×0.98, so it settles near 120.
        XCTAssertTrue((118...122).contains(refiner.tempo), "learned \(refiner.tempo) BPM")

        let beatTimes = stride(from: 31_000, to: 41_000, by: period)
        for beat in beatTimes {
            XCTAssertTrue(fired.contains { abs($0 - beat) <= 34 },
                          "no beat fired near \(beat) ms (dropped: \((beat - 1000) / period % 2 == 1))")
        }
        let strays = fired.filter { time in !beatTimes.contains { abs(time - $0) <= 34 } }
        XCTAssertTrue(strays.isEmpty, "beats fired off the tempo at \(strays)")
    }

    /// Before it has learned a tempo, the refiner passes the detector's beats through.
    func testPassesBeatsThroughWhileLearning() {
        var refiner = AvsBpmRefiner()
        XCTAssertTrue(refiner.refine(isBeat: true, now: 1000))
        XCTAssertFalse(refiner.refine(isBeat: false, now: 1017))
        XCTAssertEqual(refiner.tempo, 0)
    }
}
