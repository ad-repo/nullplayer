import XCTest
@testable import NullPlayer

/// Fade Out Only's end-of-track gain (M70) and the pause/resume ramp (M71).
final class AudioEngineFadeTests: XCTestCase {

    func testEndFadeIsUnityUntilTheLastDurationSecondsThenReachesSilence() {
        XCTAssertEqual(AudioEngine.endFadeGain(remaining: 30, over: 5), 1)
        XCTAssertEqual(AudioEngine.endFadeGain(remaining: 5, over: 5), 1)
        XCTAssertEqual(AudioEngine.endFadeGain(remaining: 2.5, over: 5), Float(cos(Double.pi / 4)), accuracy: 0.0001)
        XCTAssertEqual(AudioEngine.endFadeGain(remaining: 0, over: 5), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioEngine.endFadeGain(remaining: -1, over: 5), 0, accuracy: 0.0001)
        // A zero duration never fades, rather than dividing by it.
        XCTAssertEqual(AudioEngine.endFadeGain(remaining: 0, over: 0), 1)
    }

    func testEndFadeFallsSteadilyAcrossTheDuration() {
        var previous: Float = 1
        for remaining in stride(from: 4.9, through: 0, by: -0.1) {
            let gain = AudioEngine.endFadeGain(remaining: remaining, over: 5)
            XCTAssertLessThan(gain, previous, "remaining \(remaining)")
            previous = gain
        }
    }

    func testTransportFadeRampsToTheTargetThenRunsItsCompletion() {
        var applied: [Float] = []
        let fade = TransportFade { applied.append($0) }
        let done = expectation(description: "ramp completes")
        fade.ramp(to: 0) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(fade.gain, 0)
        XCTAssertGreaterThan(applied.count, 2, "the gain steps down rather than jumping")
        XCTAssertEqual(applied, applied.sorted(by: >))
    }

    func testANewRampOrSetCancelsTheRunningRampsCompletion() {
        let fade = TransportFade { _ in }
        fade.ramp(to: 0) { XCTFail("a resume must cancel the pending pause") }
        let resumed = expectation(description: "replacement ramp completes")
        fade.ramp(to: 1) { resumed.fulfill() }
        wait(for: [resumed], timeout: 2)

        fade.ramp(to: 0) { XCTFail("set must cancel the ramp") }
        fade.set(1)
        let settle = expectation(description: "past the ramp's length")
        DispatchQueue.main.asyncAfter(deadline: .now() + TransportFade.duration * 2) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        XCTAssertEqual(fade.gain, 1)
    }
}
