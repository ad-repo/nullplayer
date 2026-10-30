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
        XCTAssertEqual(firstSnapshot.samples, reference.samples, "A short cue must not truncate the backing decode")
        XCTAssertEqual(secondSnapshot.samples, reference.samples)
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
        XCTAssertEqual(lastFirst.samples, reference.samples)

    }

}
