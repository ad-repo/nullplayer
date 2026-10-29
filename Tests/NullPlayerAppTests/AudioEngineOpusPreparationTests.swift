import AVFoundation
import XCTest
@testable import NullPlayer

@MainActor
final class AudioEngineOpusPreparationTests: XCTestCase {
    private var opusURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Audio/opus-in-m4a.m4a")
    }

    private func engine() -> AudioEngine {
        let engine = AudioEngine()
        engine.volume = 0
        engine.sweetFadeEnabled = false
        engine.gaplessPlaybackEnabled = false
        engine.volumeNormalizationEnabled = false
        engine.shuffleEnabled = false
        engine.repeatEnabled = false
        return engine
    }

    private func loaded(_ engine: AudioEngine, url: URL) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            engine.currentTrack?.url == url && engine.hasLocalAudioFileForTesting
        }, object: nil)
        wait(for: [ready], timeout: 3)
    }

    func testNormalizationAppliesToTheOriginalOpusTrackWhilePaused() {
        let engine = engine()
        defer { engine.clearPlaylist() }
        engine.volumeNormalizationEnabled = true
        engine.playNow([Track(url: opusURL)])
        engine.pause()
        let applied = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            engine.hasLocalAudioFileForTesting && engine.normalizationGainForTesting > 1.1
        }, object: nil)
        wait(for: [applied], timeout: 3)
        XCTAssertEqual(engine.currentTrack?.url, opusURL)
        XCTAssertEqual(engine.state, .paused)
    }

    func testPausedNavigationThroughEveryTransportEntryPoint() {
        let engine = engine()
        defer { engine.clearPlaylist() }
        let aac = opusURL.deletingLastPathComponent().appendingPathComponent("aac-in-m4a.m4a")
        engine.setPlaylistTracks([Track(url: opusURL), Track(url: aac)])
        engine.playTrack(at: 1)
        engine.pause()
        loaded(engine, url: aac)
        engine.previous()
        loaded(engine, url: opusURL)
        XCTAssertEqual(engine.state, .paused)
        engine.next()
        loaded(engine, url: aac)
        XCTAssertEqual(engine.state, .paused)
        engine.skipTracks(count: -1)
        loaded(engine, url: opusURL)
        XCTAssertEqual(engine.state, .paused)
    }

    func testPlayWithAnEmptyPipelineAndOpenFilesBothPrepareAsynchronously() {
        let engine = engine()
        defer { engine.clearPlaylist() }
        engine.setPlaylistTracks([Track(url: opusURL)])
        engine.play()
        engine.pause()
        loaded(engine, url: opusURL)
        XCTAssertEqual(engine.state, .paused)
        engine.clearPlaylist()
        engine.loadFiles([opusURL])
        engine.pause()
        loaded(engine, url: opusURL)
        XCTAssertEqual(engine.state, .paused)
    }

    func testStopDiscardsAnInFlightPreparationAndPlayCanRetry() {
        let engine = engine()
        defer { engine.clearPlaylist() }
        engine.playNow([Track(url: opusURL)])
        engine.stop()
        let unexpectedPlay = expectation(forNotification: .audioPlaybackStateChanged, object: engine) { _ in
            engine.state == .playing
        }
        unexpectedPlay.isInverted = true
        wait(for: [unexpectedPlay], timeout: 0.3)
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertFalse(engine.hasLocalAudioFileForTesting)
        engine.play()
        engine.pause()
        loaded(engine, url: opusURL)
        XCTAssertEqual(engine.state, .paused)
    }

    func testReplacingTheQueueDiscardsAnInFlightPreparation() {
        let engine = engine()
        defer { engine.clearPlaylist() }
        engine.playNow([Track(url: opusURL)])
        let aac = opusURL.deletingLastPathComponent().appendingPathComponent("aac-in-m4a.m4a")
        engine.setPlaylistTracks([Track(url: aac)])
        let unexpectedPlay = expectation(forNotification: .audioPlaybackStateChanged, object: engine) { _ in
            engine.state == .playing
        }
        unexpectedPlay.isInverted = true
        wait(for: [unexpectedPlay], timeout: 0.3)
        XCTAssertEqual(engine.playlist.map(\.url), [aac])
        XCTAssertEqual(engine.currentIndex, -1)
        XCTAssertEqual(engine.state, .stopped)
    }

    func testQueueMoveDiscardsTheOldPositionAndPlayCanReloadTheMovedTrack() {
        let engine = engine()
        defer { engine.clearPlaylist() }
        let aac = opusURL.deletingLastPathComponent().appendingPathComponent("aac-in-m4a.m4a")
        engine.setPlaylistTracks([Track(url: opusURL), Track(url: aac)])
        engine.playTrack(at: 0)
        engine.moveTrack(from: 0, to: 1)
        let discarded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !engine.isPreparingLocalFileForTesting
        }, object: nil)
        wait(for: [discarded], timeout: 3)
        XCTAssertEqual(engine.state, .stopped)
        engine.play()
        engine.pause()
        loaded(engine, url: opusURL)
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.state, .paused)
    }

    func testFailedPlayNowRollsBackOnlyItsInsertedRange() throws {
        let engine = engine()
        defer { engine.clearPlaylist() }
        let old = try TestAudioFile.temporaryWAV(seconds: 5, tone: true)
        let corrupt = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).m4a")
        let secondBad = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).m4a")
        defer {
            try? FileManager.default.removeItem(at: secondBad)
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.removeItem(at: corrupt)
        }
        try Data("not MPEG-4".utf8).write(to: corrupt)
        try Data("also not MPEG-4".utf8).write(to: secondBad)
        let failed = expectation(description: "Play Now failure reported")
        let recorder = FailureRecorder(failed)
        engine.delegate = recorder
        engine.setPlaylistTracks([Track(url: old)])
        engine.playNow([Track(url: corrupt), Track(url: secondBad)])
        wait(for: [failed], timeout: 3)
        XCTAssertEqual(engine.playlist.map(\.url), [old])
        XCTAssertEqual(engine.currentIndex, -1)
        XCTAssertNil(engine.currentTrack)
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertEqual(recorder.failedURLs, [corrupt])
    }

    func testPlayNowSkipsBadM4AWithinItsBoundAndStartsTheOpusSuccessor() throws {
        let engine = engine()
        defer { engine.clearPlaylist() }
        let corrupt = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).m4a")
        defer { try? FileManager.default.removeItem(at: corrupt) }
        try Data("not MPEG-4".utf8).write(to: corrupt)
        engine.playNow([Track(url: corrupt), Track(url: opusURL)])
        engine.pause()
        loaded(engine, url: opusURL)
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.state, .paused)
    }

    func testCrossfadePreparesBeforeTheFadeWindowAndUsesTheReadyFile() throws {
        let engine = engine()
        defer { engine.clearPlaylist() }
        let first = try TestAudioFile.temporaryWAV(seconds: 3, tone: true)
        defer { try? FileManager.default.removeItem(at: first) }
        let incoming = Track(url: opusURL)
        engine.sweetFadeDuration = 0.1
        engine.sweetFadeEnabled = true
        engine.playNow([Track(url: first), incoming])
        let prepared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            engine.preparedCrossfadeTrackIDForTesting == incoming.id
        }, object: nil)
        wait(for: [prepared], timeout: 2)
        XCTAssertLessThan(engine.currentTime, 2, "Preparation must precede the 2.9s fade boundary")
        let changed = expectation(forNotification: .audioTrackDidChange, object: engine) { _ in
            engine.currentTrack?.id == incoming.id
        }
        engine.seek(to: 2.8)
        wait(for: [changed], timeout: 2)
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.state, .playing)
    }

    /// Optional local stress fixture; generated externally so CI carries no 1-hour recording.
    func testLongOpusNextIsResponsiveAndCanBeSuperseded() throws {
        guard let path = ProcessInfo.processInfo.environment["NULLPLAYER_LONG_OPUS_FILE"] else {
            throw XCTSkip("Set NULLPLAYER_LONG_OPUS_FILE to a generated long Opus M4A")
        }
        let engine = engine()
        defer { engine.clearPlaylist() }
        let first = try TestAudioFile.temporaryWAV(seconds: 5, tone: true)
        defer { try? FileManager.default.removeItem(at: first) }
        let long = URL(fileURLWithPath: path)
        let aac = opusURL.deletingLastPathComponent().appendingPathComponent("aac-in-m4a.m4a")
        engine.playNow([Track(url: first), Track(url: long, title: "Long Opus", duration: 3600), Track(url: aac)])
        let start = Date()
        engine.next()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.5, "Next must not decode the whole track on main")
        let heartbeat = expectation(description: "main queue remains responsive during preparation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { heartbeat.fulfill() }
        wait(for: [heartbeat], timeout: 1)
        engine.next()
        engine.pause()
        loaded(engine, url: aac)
        XCTAssertEqual(engine.currentIndex, 2)
        XCTAssertEqual(engine.state, .paused)
        NSLog("Long Opus Next returned in %.4fs; superseding AAC loaded successfully", elapsed)
    }

    func testLongGaplessPreparationDoesNotQueueBlockANewSelection() throws {
        guard let path = ProcessInfo.processInfo.environment["NULLPLAYER_LONG_OPUS_FILE"] else {
            throw XCTSkip("Set NULLPLAYER_LONG_OPUS_FILE to a generated long Opus M4A")
        }
        let engine = engine()
        defer { engine.clearPlaylist() }
        let first = try TestAudioFile.temporaryWAV(seconds: 5, tone: true)
        defer { try? FileManager.default.removeItem(at: first) }
        let aac = opusURL.deletingLastPathComponent().appendingPathComponent("aac-in-m4a.m4a")
        engine.gaplessPlaybackEnabled = true
        engine.playNow([Track(url: first),
                        Track(url: URL(fileURLWithPath: path), title: "Long Opus", duration: 3600),
                        Track(url: aac)])
        let preparing = expectation(description: "gapless preparation gets background time")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { preparing.fulfill() }
        wait(for: [preparing], timeout: 1)
        let start = Date()
        engine.playTrack(at: 2)
        engine.pause()
        loaded(engine, url: aac)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2,
                          "A new selection must not wait for the serial queue's long preparation")
        XCTAssertEqual(engine.state, .paused)
        NSLog("AAC superseded long gapless preparation in %.4fs", Date().timeIntervalSince(start))
    }

    private final class FailureRecorder: AudioEngineDelegate {
        let failure: XCTestExpectation
        var failedURLs: [URL] = []
        init(_ failure: XCTestExpectation) { self.failure = failure }
        func audioEngineDidChangeState(_ state: PlaybackState) {}
        func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval) {}
        func audioEngineDidChangeTrack(_ track: Track?) {}
        func audioEngineDidUpdateSpectrum(_ levels: [Float]) {}
        func audioEngineDidChangePlaylist() {}
        func audioEngineDidFailToLoadTrack(_ track: Track, error: Error) {}
        func audioEngineUserPlayRequestDidFail(_ track: Track, error: Error, fileIsMissing: Bool) {
            failedURLs.append(track.url)
            failure.fulfill()
        }
    }
}
