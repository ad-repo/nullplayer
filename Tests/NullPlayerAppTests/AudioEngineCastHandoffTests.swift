import AVFoundation
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        tempFiles.append(url)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let output = try AVAudioFile(forWriting: url, settings: format.settings)
        let tone = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 48000)))
        tone.frameLength = tone.frameCapacity
        for channel in 0..<2 {
            for frame in 0..<Int(tone.frameLength) {
                tone.floatChannelData![channel][frame] = 0.2 * sin(Float(frame) * 2 * .pi * 440 / 48000)
            }
        }
        try output.write(from: tone)
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
        engine.stopCastPlayback(resumeLocally: false)

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
        engine.stopCastPlayback(resumeLocally: false)

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
        engine.stopCastPlayback(resumeLocally: false)

        // The picked track is the last, so it plays out and ends the queue; the 10 s pre-cast
        // file would still be playing.
        let finished = expectation(forNotification: .audioQueueDidExhaust, object: engine)
        engine.play()
        XCTAssertEqual(engine.currentTrack?.url, pickedDuringCast)
        wait(for: [finished], timeout: 3)
    }
}
