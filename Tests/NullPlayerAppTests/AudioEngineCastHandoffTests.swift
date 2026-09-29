import AVFoundation
import XCTest
@testable import NullPlayer

final class AudioEngineCastHandoffTests: XCTestCase {
    /// Casting stops the local player node, which discards its schedule. Play after the cast
    /// ends must still have the file queued: an empty node runs its clock and plays silence.
    func testPlayAfterCastStopsPlaysTheLocalFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        do {
            let output = try AVAudioFile(forWriting: url, settings: format.settings)
            let tone = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 14400))
            tone.frameLength = tone.frameCapacity
            for channel in 0..<2 {
                for frame in 0..<Int(tone.frameLength) {
                    tone.floatChannelData![channel][frame] = 0.2 * sin(Float(frame) * 2 * .pi * 440 / 48000)
                }
            }
            try output.write(from: tone)
        }

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
}
