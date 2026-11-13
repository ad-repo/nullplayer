import XCTest
@testable import NullPlayer

final class FractalDirectorTests: XCTestCase {
    private let quiet = SIMD3<Float>(repeating: 0.2)

    /// 120 BPM for `seconds` at 60 fps, a beat every 0.5 s, `offset` seconds late.
    private func play(_ director: inout FractalDirector, seconds: Double, offset: Double = 0, check: (FractalDirector) -> Void = { _ in }) {
        let dt = 1.0 / 60
        var nextBeat = offset
        for _ in 0..<Int(seconds * 60) {
            let beat = director.time + dt >= nextBeat
            if beat { nextBeat += 0.5 }
            director.advance(dt: dt, beat: beat, bpm: 120, bands: quiet)
            check(director)
        }
    }

    func testBeatClockRunsAtTheTempoAndNeverBackwards() {
        var director = FractalDirector(seed: 1)
        director.setScene(ranges: [0...1])
        var last = director.beatTime
        play(&director, seconds: 20, offset: 0.2) {
            XCTAssertGreaterThanOrEqual($0.beatTime, last)
            last = $0.beatTime
        }
        // 20 s at 120 BPM is 40 beats; the clock locks on, so it ends within a beat of that.
        XCTAssertEqual(director.beatTime, 40, accuracy: 1)
        XCTAssertEqual(director.beatCount, 40)
        XCTAssertEqual(director.barCount, 10)
    }

    func testBeatClockKeepsTempoAtFiveFPS() {
        var director = FractalDirector(seed: 1)
        director.setScene(ranges: [0...1])
        for _ in 0..<50 { director.advance(dt: 0.2, beat: false, bpm: 120, bands: quiet) }
        // 10 s at 120 BPM is 20 beats, however coarse the frames.
        XCTAssertEqual(director.beatTime, 20, accuracy: 1e-6)
        XCTAssertEqual(director.time, 10, accuracy: 1e-6)
    }

    func testParamBeatsIntegratesTheParameters() {
        var director = FractalDirector(seed: 3)
        director.setScene(ranges: [0.5...0.5])
        play(&director, seconds: 10)
        // A parameter held at 0.5 over ~20 beats integrates to half the beat count.
        XCTAssertEqual(director.paramBeats.x, director.beatTime * 0.5, accuracy: 1e-6)
    }

    func testBeatClockLocksOntoLateBeats() {
        var director = FractalDirector(seed: 1)
        director.setScene(ranges: [0...1])
        // Beats a quarter-beat late: after settling, a beat lands near a whole beat of the clock.
        play(&director, seconds: 10, offset: 0.125)
        var phases: [Double] = []
        let dt = 1.0 / 60
        var nextBeat = (director.time / 0.5).rounded(.up) * 0.5 + 0.125
        for _ in 0..<240 {
            let beat = director.time + dt >= nextBeat
            if beat { nextBeat += 0.5 }
            director.advance(dt: dt, beat: beat, bpm: 120, bands: quiet)
            if beat { phases.append(director.tempoPhase) }
        }
        for phase in phases { XCTAssertLessThan(min(phase, 1 - phase), 0.15) }
    }

    func testParametersStayInRangeAndRetargetEveryTwoBars() {
        var director = FractalDirector(seed: 7)
        let ranges: [ClosedRange<Float>] = [0...1, 2...3, -1...0, 10...20]
        director.setScene(ranges: ranges)
        var targetChanges = 0
        var lastTargets = director.targets
        play(&director, seconds: 32) { d in
            for (i, r) in ranges.enumerated() { XCTAssertTrue(r.contains(d.params[i])) }
            if d.targets != lastTargets { targetChanges += 1; lastTargets = d.targets }
        }
        // 32 s at 120 BPM is 16 bars: a new target every 2 bars.
        XCTAssertEqual(targetChanges, 8)
    }

    func testSameSeedSameChoices() {
        var a = FractalDirector(seed: 42), b = FractalDirector(seed: 42)
        a.setScene(ranges: [0...1, 0...1])
        b.setScene(ranges: [0...1, 0...1])
        play(&a, seconds: 10)
        play(&b, seconds: 10)
        XCTAssertEqual(a.params, b.params)
        XCTAssertEqual(a.palette.d, b.palette.d)
    }
}
