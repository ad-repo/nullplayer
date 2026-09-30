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

        var stopped: PlaybackSnapshot.EngineReading?
        let stoppedRead = expectation(description: "stopped snapshot")
        engine.readPlaybackSnapshot { stopped = $0; stoppedRead.fulfill() }
        wait(for: [stoppedRead], timeout: 2)
        let stoppedReading = try XCTUnwrap(stopped)
        XCTAssertEqual(stoppedReading.state, .stopped)
        guard case .unavailable = stoppedReading.level else {
            return XCTFail("a stopped engine has no level to measure: \(stoppedReading.level)")
        }
        XCTAssertTrue(PlaybackSnapshot.engineLines(stoppedReading).contains { $0.hasPrefix("level mainMixerPeak=n/a") })

        engine.volume = 1
        engine.playNow([Track(url: url, title: "Tone")])
        XCTAssertEqual(engine.state, .playing)
        var playing: PlaybackSnapshot.EngineReading?
        let playingRead = expectation(description: "playing snapshot")
        engine.readPlaybackSnapshot { playing = $0; playingRead.fulfill() }
        wait(for: [playingRead], timeout: 2)

        let playingReading = try XCTUnwrap(playing)
        guard case .measured(let peak) = playingReading.level else {
            return XCTFail("expected a measured level, got \(playingReading.level)")
        }
        XCTAssertGreaterThan(peak, 0.05)
        XCTAssertTrue(playingReading.playerIsPlaying)
        XCTAssertEqual(playingReading.recoveryState, .ready)
    }
}
