import AVFoundation
import XCTest
@testable import NullPlayer

final class AudioEngineGraphRecoveryTests: XCTestCase {
    func testDisconnectAndReconnectExceptionsReplaceGraphAndPreserveSettings() {
        for failedStage in ["disconnect", "connect"] {
            let recovery = AudioGraphRecoveryCoordinator()
            let engine = AudioEngine(audioGraphRecovery: recovery)
            engine.setEQEnabled(true)
            engine.setEQBand(0, gain: 4)
            engine.tuningController.applyPreset(.hz432)
            engine.tuningController.setRate(1.5)
            let oldPitch = engine.tuningController.localPitchNode
            var injected = false
            recovery.setFaultInjectorForTesting { stage in
                if stage == failedStage && !injected {
                    injected = true
                    NSException(name: .internalInconsistencyException, reason: "error -10868", userInfo: nil).raise()
                }
            }

            engine.rebuildAudioGraphForTesting()

            XCTAssertTrue(injected)
            XCTAssertFalse(recovery.isDeferred)
            XCTAssertFalse(recovery.hasScheduledWork)
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
            let recovery = AudioGraphRecoveryCoordinator()
            let engine = AudioEngine(audioGraphRecovery: recovery)
            let file = try AVAudioFile(forReading: url)
            engine.setAudioGraphFileForTesting(file, state: initialState, position: 3)
            recovery.setFaultInjectorForTesting { stage in
                if stage == "disconnect" {
                    NSException(name: .internalInconsistencyException, reason: "error -10868", userInfo: nil).raise()
                }
            }
            engine.rebuildAudioGraphForTesting()
            XCTAssertFalse(recovery.isDeferred)
            XCTAssertEqual(engine.state, initialState)
            XCTAssertEqual(engine.currentTime, 3, accuracy: 0.25)
            XCTAssertEqual(engine.isLocalGraphPlayingForTesting, initialState == .playing)
            engine.pauseLocalOnly()
        }
    }

    func testFailedRebuildArmsExactlyOneRetryAttempt() {
        let recovery = AudioGraphRecoveryCoordinator()
        let engine = AudioEngine(audioGraphRecovery: recovery)
        recovery.setFaultInjectorForTesting { _ in
            NSException(name: .internalInconsistencyException, reason: "error -10868", userInfo: nil).raise()
        }

        engine.rebuildAudioGraphForTesting()

        XCTAssertEqual(recovery.retryCount, 1)
        XCTAssertTrue(recovery.hasScheduledWork)

        // The retry callback re-arms when it sees the rebuild fail, and so does the rebuild
        // itself. Only one of the two may consume an attempt, or the six-retry budget is
        // really three and each armed backoff is cancelled before it fires.
        recovery.scheduleRetry {}

        XCTAssertEqual(recovery.retryCount, 1)
        XCTAssertTrue(recovery.hasScheduledWork)
        recovery.cancelScheduledWork()
    }

    func testPersistentFailureStopsSchedulingAndLaterRecoverySucceeds() {
        let recovery = AudioGraphRecoveryCoordinator()
        let engine = AudioEngine(audioGraphRecovery: recovery)
        recovery.setFaultInjectorForTesting { _ in
            NSException(name: .internalInconsistencyException, reason: "error -10868", userInfo: nil).raise()
        }
        // Run attempts synchronously so the test does not wait for the backoff timers.
        for _ in 0..<7 { engine.rebuildAudioGraphForTesting() }
        XCTAssertTrue(recovery.isDeferred)
        XCTAssertEqual(recovery.retryCount, 6)
        XCTAssertFalse(recovery.hasScheduledWork)

        recovery.setFaultInjectorForTesting(nil)
        engine.rebuildAudioGraphForTesting()
        XCTAssertFalse(recovery.isDeferred)
        XCTAssertFalse(recovery.hasScheduledWork)
    }
}
