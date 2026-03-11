import AVFoundation
import XCTest
@testable import NullPlayer

final class WaveformTests: XCTestCase {
    func testBucketAccumulatorMapsFramesIntoStableBuckets() {
        var accumulator = WaveformBucketAccumulator(totalFrames: 8, bucketCount: 4)
        let amplitudes: [Float] = [0.1, 0.2, 0.9, 0.3, 0.4, 0.8, 0.05, 0.6]

        for (index, amplitude) in amplitudes.enumerated() {
            accumulator.add(frameAmplitude: amplitude, at: Int64(index))
        }

        let samples = accumulator.makeSamples()
        XCTAssertEqual(samples.count, 4)
        XCTAssertEqual(samples[0], UInt16(round(0.2 * 32767)))
        XCTAssertEqual(samples[1], UInt16(round(0.9 * 32767)))
        XCTAssertEqual(samples[2], UInt16(round(0.8 * 32767)))
        XCTAssertEqual(samples[3], UInt16(round(0.6 * 32767)))
    }

    func testCueSheetParserParsesTitlesPerformersAndTimes() throws {
        let url = temporaryURL(named: "sample.cue")
        try """
        TRACK 01 AUDIO
          PERFORMER "Artist One"
          TITLE "Intro"
          INDEX 01 00:00:00
        TRACK 02 AUDIO
          TITLE "Drop"
          INDEX 01 01:23:15
        """.write(to: url, atomically: true, encoding: .utf8)

        let cuePoints = WaveformCueSheetParser.parse(cueURL: url)
        XCTAssertEqual(cuePoints.count, 2)
        XCTAssertEqual(cuePoints[0].performer, "Artist One")
        XCTAssertEqual(cuePoints[0].title, "Intro")
        XCTAssertEqual(cuePoints[0].milliseconds, 0)
        XCTAssertEqual(cuePoints[1].title, "Drop")
        XCTAssertEqual(cuePoints[1].milliseconds, 83_200)
    }

    func testCacheKeyChangesWithFileMetadata() {
        let path = "/tmp/example.wav"
        let date = Date(timeIntervalSinceReferenceDate: 1234)
        let key1 = WaveformCacheService.cacheKey(canonicalPath: path, fileSize: 100, modificationDate: date)
        let key2 = WaveformCacheService.cacheKey(canonicalPath: path, fileSize: 200, modificationDate: date)
        let key3 = WaveformCacheService.cacheKey(canonicalPath: path, fileSize: 100, modificationDate: date.addingTimeInterval(1))

        XCTAssertNotEqual(key1, key2)
        XCTAssertNotEqual(key1, key3)
    }

    func testStreamingAccumulatorBuildsSeekableSnapshotForTimedStreams() {
        let accumulator = StreamingWaveformAccumulator(duration: 120)
        let left = Array(repeating: UInt8(255), count: 576)
        let right = Array(repeating: UInt8(128), count: 576)

        accumulator.append(left: left, right: right, sampleRate: 48_000, currentTime: 30)
        let snapshot = accumulator.snapshot(sourcePath: "https://example.com/stream", currentTime: 30)

        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertTrue(snapshot.isStreaming)
        XCTAssertTrue(snapshot.allowsSeeking)
        XCTAssertEqual(snapshot.duration, 120)
        XCTAssertGreaterThan(snapshot.samples.max() ?? 0, 0)
    }

    func testStreamingAccumulatorBuildsRollingSnapshotForLiveStreams() {
        let accumulator = StreamingWaveformAccumulator(duration: nil)
        let left = Array(repeating: UInt8(255), count: 576)
        let right = Array(repeating: UInt8(255), count: 576)

        accumulator.append(left: left, right: right, sampleRate: 48_000, currentTime: 12)
        let snapshot = accumulator.snapshot(sourcePath: "https://example.com/live", currentTime: 12)

        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertTrue(snapshot.isStreaming)
        XCTAssertFalse(snapshot.allowsSeeking)
        XCTAssertEqual(snapshot.duration, 30)
        XCTAssertGreaterThan(snapshot.samples.max() ?? 0, 0)
    }

    func testWaveformServiceGeneratesSnapshotForStereoFile() async throws {
        let url = temporaryURL(named: "stereo.caf")
        let cacheDirectory = temporaryURL(named: "WaveformCache")
        try writeAudioFile(
            to: url,
            channelCount: 2,
            frames: 22_050
        ) { frame, channel in
            if channel == 0 {
                return frame % 400 == 0 ? 0.9 : 0.15
            }
            return frame % 200 == 0 ? 0.7 : 0.05
        }

        let track = Track(
            url: url,
            title: "stereo",
            duration: Double(22_050) / 44_100,
            mediaType: .audio
        )
        let service = WaveformCacheService(cacheDirectoryURL: cacheDirectory)
        let snapshot = await service.loadSnapshot(for: track, forceRegeneration: true)

        XCTAssertEqual(snapshot.state, .ready, snapshot.message ?? "Missing waveform error")
        XCTAssertEqual(snapshot.samples.count, WaveformSnapshot.bucketCount)
        XCTAssertGreaterThan(snapshot.samples.max() ?? 0, 0)

        await service.clearCache(for: track)
    }

    private func temporaryURL(named name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory.appendingPathComponent(name)
    }

    private func writeAudioFile(
        to url: URL,
        channelCount: AVAudioChannelCount,
        frames: AVAudioFrameCount,
        sampleProvider: (Int, Int) -> Float
    ) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        try autoreleasepool {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: channelCount)!
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames

            guard let channelData = buffer.floatChannelData else {
                XCTFail("Expected float channel data")
                return
            }

            for channel in 0..<Int(channelCount) {
                for frame in 0..<Int(frames) {
                    channelData[channel][frame] = sampleProvider(frame, channel)
                }
            }

            try file.write(from: buffer)
        }
    }
}
