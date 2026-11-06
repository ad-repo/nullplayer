import XCTest
@testable import NullPlayer

/// Fade Out Only's end-of-track gain (M70) and the pause/resume ramp (M71).
final class AudioEngineFadeTests: XCTestCase {

    func testEndFadeIsUnityUntilTheLastDurationSecondsThenReachesSilence() {
        XCTAssertEqual(OutputFades.endFadeCurve(remaining: 30, over: 5), 1)
        XCTAssertEqual(OutputFades.endFadeCurve(remaining: 5, over: 5), 1)
        XCTAssertEqual(OutputFades.endFadeCurve(remaining: 2.5, over: 5), Float(cos(Double.pi / 4)), accuracy: 0.0001)
        XCTAssertEqual(OutputFades.endFadeCurve(remaining: 0, over: 5), 0, accuracy: 0.0001)
        XCTAssertEqual(OutputFades.endFadeCurve(remaining: -1, over: 5), 0, accuracy: 0.0001)
        // A zero duration never fades, rather than dividing by it.
        XCTAssertEqual(OutputFades.endFadeCurve(remaining: 0, over: 0), 1)
    }

    func testEndFadeFallsSteadilyAcrossTheDuration() {
        var previous: Float = 1
        for remaining in stride(from: 4.9, through: 0, by: -0.1) {
            let gain = OutputFades.endFadeCurve(remaining: remaining, over: 5)
            XCTAssertLessThan(gain, previous, "remaining \(remaining)")
            previous = gain
        }
    }

    func testTheOutputGainStacksBothFadesAndATrackChangeClearsThem() {
        var changes = 0
        let fades = OutputFades { changes += 1 }
        fades.updateEndFade(remaining: 2.5, over: 5)
        fades.transport.set(0.5)
        XCTAssertEqual(fades.gain, 0.5 * Float(cos(Double.pi / 4)), accuracy: 0.0001)
        XCTAssertEqual(changes, 2)

        // Off (a nil duration) is no fade, wherever the track is.
        fades.updateEndFade(remaining: 0, over: nil)
        XCTAssertEqual(fades.endFade, 1)

        fades.updateEndFade(remaining: 1, over: 5)
        fades.trackDidChange()
        XCTAssertEqual(fades.gain, 1)
    }

    func testTransportFadeRampsToTheTargetThenRunsItsCompletion() {
        var applied: [Float] = []
        var fade: TransportFade!
        fade = TransportFade { applied.append(fade.gain) }
        let done = expectation(description: "ramp completes")
        fade.ramp(to: 0) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(fade.gain, 0)
        XCTAssertGreaterThan(applied.count, 2, "the gain steps down rather than jumping")
        XCTAssertEqual(applied, applied.sorted(by: >))
    }

    func testAResumeReplacesAPauseStillFadingOut() {
        let fade = TransportFade {}
        fade.ramp(to: 0) { XCTFail("a resume must cancel the pending pause") }
        let midway = expectation(description: "the pause ramp is under way")
        DispatchQueue.main.asyncAfter(deadline: .now() + TransportFade.duration / 3) { midway.fulfill() }
        wait(for: [midway], timeout: 2)
        XCTAssertLessThan(fade.gain, 1)
        XCTAssertGreaterThan(fade.gain, 0)

        let resumed = expectation(description: "the resume ramp completes")
        fade.ramp(to: 1) { resumed.fulfill() }
        wait(for: [resumed], timeout: 2)
        XCTAssertEqual(fade.gain, 1)
    }

    /// #699: restoring the gain when the ramp ended played the players' tail, still rendering
    /// after their pause, at full level. A resume ramps it back up; a stop resets it through
    /// `resetLocalCrossfadeStateForDirectPlayback()`, the same reset every track load runs.
    func testAFadedPauseStaysSilentUntilAResumeOrStopRestoresTheGain() throws {
        let url = try TestAudioFile.temporaryWAV(seconds: 10)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = AudioEngine()
        defer { engine.stop() }
        engine.pauseFadeEnabled = true
        engine.playNow([Track(url: url, title: "Tone")])
        XCTAssertEqual(engine.state, .playing)
        func pastTheRamp() {
            let past = expectation(description: "past the ramp")
            DispatchQueue.main.asyncAfter(deadline: .now() + TransportFade.duration * 2) { past.fulfill() }
            wait(for: [past], timeout: 2)
        }

        engine.pause()
        pastTheRamp()
        XCTAssertEqual(engine.outputFadeGainForTesting, 0)

        engine.play()
        pastTheRamp()
        XCTAssertEqual(engine.outputFadeGainForTesting, 1)

        engine.pause()
        pastTheRamp()
        XCTAssertEqual(engine.outputFadeGainForTesting, 0)
        engine.stop()
        XCTAssertEqual(engine.outputFadeGainForTesting, 1)
    }

    func testSetCancelsARunningRamp() {
        let fade = TransportFade {}
        fade.ramp(to: 0) { XCTFail("set must cancel the ramp") }
        fade.set(1)
        let past = expectation(description: "past the ramp's length")
        DispatchQueue.main.asyncAfter(deadline: .now() + TransportFade.duration * 2) { past.fulfill() }
        wait(for: [past], timeout: 2)
        XCTAssertEqual(fade.gain, 1)
    }
}
