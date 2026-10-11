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

    func testReplacementGivesANewProfileNodeCarryingTheCurve() {
        let recovery = AudioGraphRecoveryCoordinator()
        let engine = AudioEngine(audioGraphRecovery: recovery)
        var curve = EQCurve.flat
        curve.left[5] = 6
        engine.eqProfileController.audition = curve
        let oldNode = engine.eqProfileController.localNode
        var injected = false
        recovery.setFaultInjectorForTesting { stage in
            if stage == "connect" && !injected {
                injected = true
                NSException(name: .internalInconsistencyException, reason: "error -10868", userInfo: nil).raise()
            }
        }

        engine.rebuildAudioGraphForTesting()

        XCTAssertTrue(injected)
        XCTAssertFalse(oldNode === engine.eqProfileController.localNode)
        XCTAssertEqual((engine.eqProfileController.localNode.auAudioUnit as? EQProfileAudioUnit)?.curve, curve)
    }

    func testReplacementReschedulesPlayingAndPausedFilesAtSavedPosition() throws {
        let url = try TestAudioFile.temporaryWAV(seconds: 10)
        defer { try? FileManager.default.removeItem(at: url) }
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

    /// The rebuild re-queues from the position within the track; a cue track has to be re-queued
    /// at its offset into the shared file, not that far into the file's first track.
    func testReplacementReschedulesCueTrackAtItsOffset() throws {
        let url = try TestAudioFile.temporaryWAV(seconds: 10)
        defer { try? FileManager.default.removeItem(at: url) }

        let recovery = AudioGraphRecoveryCoordinator()
        let engine = AudioEngine(audioGraphRecovery: recovery)
        defer {
            recovery.cancelScheduledWork()
            engine.stop()
        }
        // The last half second of a 10 s file.
        engine.playNow([Track(url: url, title: "Last", cueStartOffset: 9.5, cueEndOffset: nil,
                              cueSourceURL: url.deletingPathExtension().appendingPathExtension("cue"))])
        XCTAssertEqual(engine.state, .playing)

        recovery.setFaultInjectorForTesting { stage in
            if stage == "disconnect" {
                NSException(name: .internalInconsistencyException, reason: "error -10868", userInfo: nil).raise()
            }
        }
        engine.rebuildAudioGraphForTesting()
        XCTAssertFalse(recovery.isDeferred)

        // Re-queued at 9.5 s the track plays out and ends the queue; at 0 s it would run 10 s.
        let finished = expectation(forNotification: .audioQueueDidExhaust, object: engine)
        wait(for: [finished], timeout: 3)
    }

    func testPlayNowHeldForGraphRecoveryPlaysTheRequestedTrack() throws {
        let oldURL = try TestAudioFile.temporaryWAV(seconds: 10)
        let newURL = try TestAudioFile.temporaryWAV(seconds: 10)
        defer {
            try? FileManager.default.removeItem(at: oldURL)
            try? FileManager.default.removeItem(at: newURL)
        }

        let recovery = AudioGraphRecoveryCoordinator()
        let engine = AudioEngine(audioGraphRecovery: recovery)
        defer {
            recovery.cancelScheduledWork()
            engine.stop()
        }
        let oldTrack = Track(url: oldURL, title: "Old")
        let newTrack = Track(url: newURL, title: "New")
        engine.playNow([oldTrack])
        XCTAssertEqual(engine.currentTrack?.id, oldTrack.id)

        holdGraphRebuild(of: engine, recovery: recovery)
        engine.playNow([newTrack])

        guard case .playNow(let request) = recovery.pendingIntent else {
            return XCTFail("Play Now was held as \(String(describing: recovery.pendingIntent)), not as Play Now")
        }
        XCTAssertEqual(engine.playlist[request.startIndex].id, newTrack.id)

        recovery.setFaultInjectorForTesting(nil)
        waitUntil("requested track plays after recovery") {
            engine.currentTrack?.id == newTrack.id && engine.state == .playing
        }
    }

    /// A held Play Now keeps Play Now's rules when it replays: an unreadable file is not skipped
    /// into the queue the user already had, and the inserted track is taken back out.
    func testHeldPlayNowOfAnUnreadableFileTakesItBackOutAfterRecovery() throws {
        let currentURL = try TestAudioFile.temporaryWAV(seconds: 10)
        let queuedURL = try TestAudioFile.temporaryWAV(seconds: 10)
        let unreadableURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try Data("not audio".utf8).write(to: unreadableURL)
        defer {
            [currentURL, queuedURL, unreadableURL].forEach { try? FileManager.default.removeItem(at: $0) }
        }

        let recovery = AudioGraphRecoveryCoordinator()
        let engine = AudioEngine(audioGraphRecovery: recovery)
        defer {
            recovery.cancelScheduledWork()
            engine.stop()
        }
        let current = Track(url: currentURL, title: "Current")
        let queued = Track(url: queuedURL, title: "Queued")
        engine.playNow([current, queued])
        XCTAssertEqual(engine.currentTrack?.id, current.id)

        holdGraphRebuild(of: engine, recovery: recovery)
        engine.playNow([Track(url: unreadableURL, title: "Unreadable")])
        XCTAssertEqual(engine.playlist.count, 3)

        recovery.setFaultInjectorForTesting(nil)
        waitUntil("held Play Now replays") { recovery.pendingIntent == nil && !recovery.isDeferred }
        // A skip past the bad file into the old queue would start `queued` after half a second.
        let settled = expectation(description: "a skip would have started by now")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 3)

        XCTAssertEqual(engine.playlist.map(\.id), [current.id, queued.id])
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertNotEqual(engine.currentTrack?.id, queued.id)
        XCTAssertNotEqual(engine.state, .playing)
    }

    /// The graph cannot be rebuilt, as after a cast ends on a device that has not settled.
    private func holdGraphRebuild(of engine: AudioEngine, recovery: AudioGraphRecoveryCoordinator) {
        recovery.setFaultInjectorForTesting { _ in
            NSException(name: .internalInconsistencyException, reason: "error -10868", userInfo: nil).raise()
        }
        engine.rebuildAudioGraphForTesting()
        XCTAssertTrue(recovery.isDeferred)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) {
        let met = expectation(description: description)
        // Cleared on the way out, so a timed-out poll does not keep rescheduling itself, holding
        // the engine, through later tests.
        var polling = true
        defer { polling = false }
        func poll() {
            guard polling else { return }
            if condition() {
                met.fulfill()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
        wait(for: [met], timeout: timeout)
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
