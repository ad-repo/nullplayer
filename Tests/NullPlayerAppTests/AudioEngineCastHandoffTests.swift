import XCTest
@testable import NullPlayer

final class AudioEngineCastHandoffTests: XCTestCase {
    private var tempFiles: [URL] = []

    override func tearDown() {
        tempFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        tempFiles = []
        super.tearDown()
    }

    private func toneWAV(seconds: Double) throws -> URL {
        let url = try TestAudioFile.temporaryWAV(seconds: seconds, tone: true)
        tempFiles.append(url)
        return url
    }

    /// Casting stops the local player node, which discards its schedule. Play after the cast
    /// ends must still have the file queued: an empty node runs its clock and plays silence.
    func testPlayAfterCastStopsPlaysTheLocalFile() throws {
        let url = try toneWAV(seconds: 0.3)

        let engine = AudioEngine()
        defer { engine.stop() }
        engine.playNow([Track(url: url, title: "Tone")])
        engine.stopLocalForCasting()
        engine.stopCastPlayback()

        // A queued 0.3 s file plays out and ends the queue; an empty node never finishes.
        let finished = expectation(forNotification: .audioQueueDidExhaust, object: engine)
        engine.play()
        XCTAssertEqual(engine.state, .playing)
        wait(for: [finished], timeout: 5)
    }

    /// A Stop pressed during the cast queues the local file; ending the cast must not queue a
    /// second copy behind it, or Play plays the file twice before the track ends.
    func testStopDuringCastThenStopCastingPlaysTheFileOnce() throws {
        let url = try toneWAV(seconds: 1)

        let engine = AudioEngine()
        defer { engine.stop() }
        engine.playNow([Track(url: url, title: "Tone")])
        engine.stopLocalForCasting()
        engine.stop()
        engine.stopCastPlayback()

        let finished = expectation(forNotification: .audioQueueDidExhaust, object: engine)
        let start = Date()
        engine.play()
        wait(for: [finished], timeout: 5)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.7, "the 1 s file played more than once")
    }

    /// A track picked during the cast replaces only the selection, not the open local file.
    /// Play after the cast ends must play the track on screen, not the one from before the cast.
    func testPlayAfterCastPlaysTheTrackPickedDuringTheCast() throws {
        let beforeCast = try toneWAV(seconds: 10)
        let pickedDuringCast = try toneWAV(seconds: 0.3)

        let engine = AudioEngine()
        defer { engine.stop() }
        engine.playNow([Track(url: beforeCast, title: "Before"), Track(url: pickedDuringCast, title: "Picked")])
        engine.stopLocalForCasting()
        engine.selectTrackDuringCastForTesting(at: 1)
        engine.stopCastPlayback()

        // The picked track is the last, so it plays out and ends the queue; the 10 s pre-cast
        // file would still be playing.
        let finished = expectation(forNotification: .audioQueueDidExhaust, object: engine)
        engine.play()
        XCTAssertEqual(engine.currentTrack?.url, pickedDuringCast)
        wait(for: [finished], timeout: 3)
    }
}
