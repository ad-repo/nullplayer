import AVFoundation
import XCTest

/// WAV files for tests that open or play real audio.
enum TestAudioFile {
    /// Writes `seconds` of 48 kHz stereo to `url`: silence, or a quiet 440 Hz tone.
    static func writeWAV(to url: URL, seconds: Double = 0.5, tone: Bool = false) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let output = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
                                                    frameCapacity: AVAudioFrameCount(seconds * 48_000)))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(buffer.frameLength) {
                samples[frame] = tone ? 0.2 * sin(Float(frame) * 2 * .pi * 440 / 48_000) : 0
            }
        }
        try output.write(from: buffer)
    }

    /// A new WAV file in the temporary directory; the caller removes it.
    static func temporaryWAV(seconds: Double = 0.5, tone: Bool = false) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try writeWAV(to: url, seconds: seconds, tone: tone)
        return url
    }
}
