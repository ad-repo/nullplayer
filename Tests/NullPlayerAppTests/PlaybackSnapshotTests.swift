import AVFoundation
import XCTest
@testable import NullPlayer

final class PlaybackSnapshotTests: XCTestCase {
    /// The level line is the snapshot's reason to exist: it must measure what the mixer renders,
    /// not repeat what the player node reports.
    func testSnapshotMeasuresTheRenderedLevel() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        do {
            let output = try AVAudioFile(forWriting: url, settings: format.settings)
            let tone = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96000))
            tone.frameLength = tone.frameCapacity
            for channel in 0..<2 {
                for frame in 0..<Int(tone.frameLength) {
                    tone.floatChannelData![channel][frame] = 0.5 * sin(Float(frame) * 2 * .pi * 440 / 48000)
                }
            }
            try output.write(from: tone)
        }

        let engine = AudioEngine()
        defer { engine.stop() }

        var stoppedLines: [String] = []
        let stopped = expectation(description: "stopped snapshot")
        engine.playbackSnapshotLines { stoppedLines = $0; stopped.fulfill() }
        wait(for: [stopped], timeout: 2)
        XCTAssertTrue(stoppedLines.contains { $0.hasPrefix("engine state=stopped") })
        XCTAssertTrue(stoppedLines.contains { $0.hasPrefix("level mainMixerPeak=n/a") })

        engine.volume = 1
        engine.playNow([Track(url: url, title: "Tone")])
        XCTAssertEqual(engine.state, .playing)
        var playingLines: [String] = []
        let playing = expectation(description: "playing snapshot")
        engine.playbackSnapshotLines { playingLines = $0; playing.fulfill() }
        wait(for: [playing], timeout: 2)

        let level = try XCTUnwrap(playingLines.first { $0.hasPrefix("level mainMixerPeak=") })
        let peak = try XCTUnwrap(Float(level.dropFirst("level mainMixerPeak=".count)), level)
        XCTAssertGreaterThan(peak, 0.05, level)
        XCTAssertTrue(playingLines.contains { $0.contains("player.playing=true") })
        XCTAssertTrue(playingLines.contains { $0.hasPrefix("graph recovery=ready") })
    }
}
