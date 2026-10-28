import AVFoundation
import XCTest
@testable import NullPlayer

final class LocalAudioFileTests: XCTestCase {
    private var opusURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Audio/opus-in-m4a.m4a")
    }

    func testOpusInM4ADecodesToItsPresentationDurationAndSeeks() throws {
        let original = try Data(contentsOf: opusURL)
        let file = try LocalAudioFile.open(opusURL)
        XCTAssertEqual(LocalAudioFile.sourceURL(of: file), opusURL)
        XCTAssertEqual(file.processingFormat.sampleRate, 48_000)
        XCTAssertEqual(file.processingFormat.channelCount, 2)
        XCTAssertEqual(file.length, 25_776) // 0.537s, not a multiple of a 20ms Opus packet.
        let samples = try readAll(file)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].count, 25_776)
        XCTAssertGreaterThan(samples[0].map { abs($0) }.max() ?? 0, 0.15)
        XCTAssertGreaterThan(samples[1].map { abs($0) }.max() ?? 0, 0.08)
        // Different channel tones detect accidental mono mixing and channel duplication.
        XCTAssertNotEqual(samples[0], samples[1])
        // Also check alignment with the generated source: a lost Opus pre-skip is audible
        // and would otherwise pass frame-count, nonzero-output and seek checks.
        for (channel, frequency, amplitude) in [(0, 440.0, 0.2), (1, 660.0, 0.1)] {
            let error = samples[channel].enumerated().reduce(0.0) { sum, item in
                let expected = amplitude * sin(Double(item.offset) * 2 * .pi * frequency / 48_000)
                let difference = Double(item.element) - expected
                return sum + difference * difference
            }
            XCTAssertLessThan(sqrt(error / Double(samples[channel].count)), 0.025)
        }

        file.framePosition = 12_345
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 512))
        try file.read(into: buffer, frameCount: 512)
        XCTAssertEqual(buffer.frameLength, 512)
        for channel in 0..<2 {
            XCTAssertEqual(Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: 512)),
                           Array(samples[channel][12_345..<12_857]))
        }
        XCTAssertEqual(try Data(contentsOf: opusURL), original, "Opening must not modify the source")
        XCTAssertNil(AudioFileValidator.fullValidate(url: opusURL))
        XCTAssertEqual(Track(url: opusURL).duration ?? 0, 0.537, accuracy: 1 / 48_000)
    }

    func testBackingAudioLivesUntilTheLastFileReferenceIsReleased() throws {
        var first: AVAudioFile? = try LocalAudioFile.open(opusURL)
        let backing = try XCTUnwrap(first).url
        // A future macOS may fix the native reader, in which case no scratch file is needed.
        guard backing != opusURL else { return }
        var second = first
        first = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: backing.path))
        XCTAssertGreaterThan(try readAll(XCTUnwrap(second))[0].count, 0)
        second = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: backing.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: opusURL.path))
    }

    func testWAVKeepsTheNativePath() throws {
        let url = try TestAudioFile.temporaryWAV(tone: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try LocalAudioFile.open(url)
        XCTAssertEqual(file.url, url)
        XCTAssertEqual(file.length, 24_000)
        XCTAssertEqual(try readAll(file)[0].count, 24_000)
    }

    func testAACInM4AKeepsTheNativePath() throws {
        let url = opusURL.deletingLastPathComponent().appendingPathComponent("aac-in-m4a.m4a")
        let file = try LocalAudioFile.open(url)
        XCTAssertEqual(file.url, url)
        XCTAssertGreaterThan(try readAll(file)[0].count, 25_000)
    }

    func testMissingAndCorruptM4AAreRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).m4a")
        XCTAssertThrowsError(try LocalAudioFile.open(url))
        try Data("not an audio file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try LocalAudioFile.open(url))
        XCTAssertNotNil(AudioFileValidator.fullValidate(url: url))
    }

    func testWaveformUsesTheSameDecoderAndOriginalIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = WaveformCacheService(cacheDirectoryURL: directory)
        let snapshot = await service.loadSnapshot(for: Track(url: opusURL))
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.sourcePath, opusURL.path)
        XCTAssertEqual(snapshot.duration, 0.537, accuracy: 1 / 48_000)
        XCTAssertGreaterThan(snapshot.samples.max() ?? 0, 0)
    }

    private func readAll(_ file: AVAudioFile) throws -> [[Float]] {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096))
        var result = Array(repeating: [Float](), count: Int(file.processingFormat.channelCount))
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(4_096, file.length - file.framePosition)))
            guard buffer.frameLength > 0 else { break }
            for channel in result.indices {
                result[channel].append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![channel],
                                                                        count: Int(buffer.frameLength)))
            }
        }
        return result
    }
}
