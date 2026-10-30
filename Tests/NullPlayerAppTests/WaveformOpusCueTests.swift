import AVFoundation
import XCTest
@testable import NullPlayer

final class WaveformOpusCueTests: XCTestCase {
    private var opusURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Audio/opus-in-m4a.m4a")
    }
    func testOpusWaveformUsesTheOriginalIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = WaveformCacheService(cacheDirectoryURL: directory)
        let snapshot = await service.loadSnapshot(for: Track(url: opusURL))
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.sourcePath, opusURL.path)
        XCTAssertEqual(snapshot.duration, 0.537, accuracy: 1 / 48_000)
        XCTAssertGreaterThan(snapshot.samples.max() ?? 0, 0)
    }

    func testCueTracksShareAFullBackingWaveformButKeepTheirOwnDurations() async throws {
        for source in [opusURL, opusURL.deletingLastPathComponent().appendingPathComponent("aac-in-m4a.m4a")] {
            try await verifyCueCache(for: source)
        }
    }

    @MainActor
    func testCueWaveformColumnsMapToTheAudibleSourceWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("silence-then-tone.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        do {
            let output = try AVAudioFile(forWriting: source, settings: format.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
            buffer.frameLength = buffer.frameCapacity
            for frame in 0..<96_000 {
                buffer.floatChannelData![0][frame] = frame < 48_000 ? 0 : 0.5 * sin(Float(frame) * 2 * .pi * 440 / 48_000)
            }
            try output.write(from: buffer)
        }
        let cueURL = source.deletingPathExtension().appendingPathExtension("cue")
        try """
        FILE "silence-then-tone.wav" WAVE
        TRACK 01 AUDIO
          TITLE "Silence"
          INDEX 01 00:00:00
        TRACK 02 AUDIO
          TITLE "Tone"
          INDEX 01 00:01:00
        """.write(to: cueURL, atomically: true, encoding: .utf8)
        let service = WaveformCacheService(cacheDirectoryURL: directory.appendingPathComponent("cache"))
        let first = Track(url: source, title: "Silence", duration: 1, cueStartOffset: 0, cueEndOffset: 1)
        let last = Track(url: source, title: "Tone", duration: nil, cueStartOffset: 1, cueEndOffset: nil)
        let silent = await service.loadSnapshot(for: first)
        let tone = await service.loadSnapshot(for: last)
        let full = await service.loadSnapshot(for: Track(url: source))
        XCTAssertEqual(silent.duration, 1, accuracy: 1 / 48_000)
        XCTAssertEqual(tone.duration, 1, accuracy: 1 / 48_000)
        XCTAssertEqual(silent.samples.count, 2048)
        XCTAssertEqual(tone.samples.count, 2048)
        XCTAssertEqual(WaveformDrawing.makeColumnAmplitudes(samples: silent.samples, pixelWidth: 100).max(), 0)
        XCTAssertGreaterThan(WaveformDrawing.makeColumnAmplitudes(samples: tone.samples, pixelWidth: 100).min() ?? 0, 15_000)
        XCTAssertEqual(full.samples.count, WaveformSnapshot.bucketCount)
        XCTAssertEqual(Array(full.samples[..<2048]), silent.samples)
        XCTAssertEqual(Array(full.samples[2048...]), tone.samples)
        XCTAssertEqual(WaveformCueSheetParser.parse(for: first).map(\.title), ["Silence"])
        XCTAssertEqual(WaveformCueSheetParser.parse(for: last).map(\.title), ["Tone"])
        XCTAssertEqual(WaveformCueSheetParser.parse(for: last).map(\.milliseconds), [0])

        // Exercise the view's same-URL reuse path as well as the cache. A cue transition
        // must replace the presented snapshot even when both cues share one backing URL.
        let view = BaseWaveformView(frame: .zero)
        defer { view.stopLoadingForHide() }
        view.updateTrack(first)
        let firstReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            view.snapshot.state == .ready && view.snapshot.samples.max() == 0
        }, object: nil)
        await fulfillment(of: [firstReady], timeout: 3)
        view.updateTrack(last)
        let lastReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            view.snapshot.state == .ready && (view.snapshot.samples.max() ?? 0) > 15_000
        }, object: nil)
        await fulfillment(of: [lastReady], timeout: 3)
        XCTAssertEqual(view.snapshot.samples, tone.samples)
        XCTAssertEqual(view.duration, 1, accuracy: 1 / 48_000)
        await WaveformCacheService.shared.clearCache(for: first)

    }

    private func verifyCueCache(for source: URL) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = WaveformCacheService(cacheDirectoryURL: directory.appendingPathComponent("cache"))
        let referenceService = WaveformCacheService(cacheDirectoryURL: directory.appendingPathComponent("reference"))
        let full = Track(url: source)
        let reference = await referenceService.loadSnapshot(for: full)
        let cueURL = directory.appendingPathComponent("album.cue")
        let first = Track(url: source, title: "First cue", duration: 0.25,
                          cueStartOffset: 0, cueEndOffset: 0.25, cueSourceURL: cueURL)
        let second = Track(url: source, title: "Second cue", duration: nil,
                           cueStartOffset: 0.25, cueEndOffset: nil, cueSourceURL: cueURL)
        let firstSnapshot = await service.loadSnapshot(for: first)
        let secondSnapshot = await service.loadSnapshot(for: second)
        let fullSnapshot = await service.loadSnapshot(for: full)
        XCTAssertEqual(reference.state, .ready)
        XCTAssertEqual(firstSnapshot.duration, 0.25, accuracy: 1 / 48_000)
        XCTAssertEqual(secondSnapshot.duration, reference.duration - 0.25, accuracy: 1 / 48_000)
        XCTAssertEqual(fullSnapshot.duration, reference.duration, accuracy: 1 / 48_000)
        XCTAssertEqual(firstSnapshot.cacheKey, secondSnapshot.cacheKey)
        let firstEnd = Int(ceil(0.25 / reference.duration * Double(reference.samples.count)))
        let lastStart = Int(floor(0.25 / reference.duration * Double(reference.samples.count)))
        XCTAssertEqual(firstSnapshot.samples, Array(reference.samples[..<firstEnd]), "Present the first cue's source window")
        XCTAssertEqual(secondSnapshot.samples, Array(reference.samples[lastStart...]), "Present the last cue from its offset")
        XCTAssertEqual(fullSnapshot.samples, reference.samples)
        let key = try XCTUnwrap(fullSnapshot.cacheKey)
        let data = try Data(contentsOf: directory.appendingPathComponent("cache/\(key).plist"))
        let record = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(record["duration"] as? Double), reference.duration, accuracy: 1 / 48_000,
                       "Persist whole-source duration, never the first cue's presentation duration")
        let lastFirstService = WaveformCacheService(cacheDirectoryURL: directory.appendingPathComponent("last-first"))
        let lastFirst = await lastFirstService.loadSnapshot(for: second)
        XCTAssertEqual(lastFirst.duration, reference.duration - 0.25, accuracy: 1 / 48_000,
                       "The last cue's nil hint must derive a remaining duration even on generation")
        XCTAssertEqual(lastFirst.samples, secondSnapshot.samples)
        let persisted = try XCTUnwrap(record["samples"] as? [NSNumber]).map { $0.uint16Value }
        XCTAssertEqual(persisted, reference.samples, "Cue presentation must not truncate persisted backing samples")

    }

}
