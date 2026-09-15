import AVFoundation
import XCTest
@testable import NullPlayer

final class AudioEngineGraphRecoveryTests: XCTestCase {
    func testDisconnectAndReconnectExceptionsReplaceGraphAndPreserveSettings() {
        for failedStage in ["disconnect", "connect"] {
            let engine = AudioEngine()
            engine.setEQEnabled(true)
            engine.setEQBand(0, gain: 4)
            engine.tuningController.applyPreset(.hz432)
            engine.tuningController.setRate(1.5)
            let oldPitch = engine.tuningController.localPitchNode
            var injected = false
            engine.debugAudioGraphFault = { stage in
                if stage == failedStage && !injected {
                    injected = true
                    NSException(name: .internalInconsistencyException, reason: "error -10868", userInfo: nil).raise()
                }
            }

            engine.debugRebuildAudioGraphForTesting()

            XCTAssertTrue(injected)
            XCTAssertFalse(engine.debugAudioGraphRecoveryState.deferred)
            XCTAssertFalse(engine.debugAudioGraphRecoveryState.scheduled)
            XCTAssertFalse(oldPitch === engine.tuningController.localPitchNode)
            XCTAssertTrue(engine.isEQEnabled())
            XCTAssertEqual(engine.getEQBand(0), 4)
            XCTAssertEqual(engine.tuningController.localPitchNode.rate, 1.5)
            XCTAssertEqual(engine.tuningController.localPitchNode.pitch, Float(engine.tuningController.appliedCents))
            XCTAssertEqual(engine.state, .stopped)
        }
    }

    func testReplacementReschedulesPlayingAndPausedFilesAtSavedPosition() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        do {
            let output = try AVAudioFile(forWriting: url, settings: format.settings)
            let silence = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480000))
            silence.frameLength = silence.frameCapacity
            for channel in 0..<2 {
                silence.floatChannelData![channel].initialize(repeating: 0, count: Int(silence.frameLength))
            }
            try output.write(from: silence)
        }
        for initialState in [PlaybackState.playing, .paused] {
            let engine = AudioEngine()
            let file = try AVAudioFile(forReading: url)
            engine.debugSetAudioGraphFileForTesting(file, state: initialState, position: 3)
            engine.debugAudioGraphFault = { stage in
                if stage == "disconnect" {
                    NSException(name: .internalInconsistencyException, reason: "error -10868", userInfo: nil).raise()
                }
            }
            engine.debugRebuildAudioGraphForTesting()
            XCTAssertFalse(engine.debugAudioGraphRecoveryState.deferred)
            XCTAssertEqual(engine.state, initialState)
            XCTAssertEqual(engine.currentTime, 3, accuracy: 0.25)
            XCTAssertEqual(engine.debugLocalGraphIsPlaying, initialState == .playing)
            engine.pauseLocalOnly()
        }
    }

    func testPersistentFailureStopsSchedulingAndLaterRecoverySucceeds() {
        let engine = AudioEngine()
        engine.debugAudioGraphFault = { _ in
            NSException(name: .internalInconsistencyException, reason: "error -10868", userInfo: nil).raise()
        }
        // Run attempts synchronously so the test does not wait for the backoff timers.
        for _ in 0..<7 { engine.debugRebuildAudioGraphForTesting() }
        XCTAssertTrue(engine.debugAudioGraphRecoveryState.deferred)
        XCTAssertEqual(engine.debugAudioGraphRecoveryState.retries, 6)
        XCTAssertFalse(engine.debugAudioGraphRecoveryState.scheduled)

        engine.debugAudioGraphFault = nil
        engine.debugRebuildAudioGraphForTesting()
        XCTAssertFalse(engine.debugAudioGraphRecoveryState.deferred)
        XCTAssertFalse(engine.debugAudioGraphRecoveryState.scheduled)
    }
}
