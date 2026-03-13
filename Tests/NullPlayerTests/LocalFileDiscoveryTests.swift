import XCTest
@testable import NullPlayer

final class LocalFileDiscoveryTests: XCTestCase {
    func testDiscoverMediaRecursivelyFindsAudioAndVideo() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NullPlayer-Discovery-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        let audioFile = nested.appendingPathComponent("track.mp3")
        let videoFile = root.appendingPathComponent("clip.mp4")
        let ignoredFile = root.appendingPathComponent("notes.txt")

        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        fm.createFile(atPath: audioFile.path, contents: Data("a".utf8))
        fm.createFile(atPath: videoFile.path, contents: Data("b".utf8))
        fm.createFile(atPath: ignoredFile.path, contents: Data("c".utf8))

        let result = LocalFileDiscovery.discoverMedia(
            from: [root],
            recursiveDirectories: true,
            includeVideo: true
        )

        XCTAssertEqual(
            result.audioFiles.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path },
            [audioFile.resolvingSymlinksInPath().path]
        )
        XCTAssertEqual(
            result.videoFiles.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path },
            [videoFile.resolvingSymlinksInPath().path]
        )
    }

    func testHasSupportedDropContentRecognizesSupportedFilesAndDirectories() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NullPlayer-Drop-\(UUID().uuidString)", isDirectory: true)
        let audioFile = root.appendingPathComponent("song.flac")
        let unsupported = root.appendingPathComponent("doc.txt")

        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        fm.createFile(atPath: audioFile.path, contents: Data())
        fm.createFile(atPath: unsupported.path, contents: Data())

        XCTAssertTrue(LocalFileDiscovery.hasSupportedDropContent([audioFile], includeVideo: false))
        XCTAssertTrue(LocalFileDiscovery.hasSupportedDropContent([root], includeVideo: false))
        XCTAssertFalse(LocalFileDiscovery.hasSupportedDropContent([unsupported], includeVideo: false))
    }

    func testLightweightTrackInitializerSetsBasicFieldsWithoutMetadataExtraction() {
        let audioURL = URL(fileURLWithPath: "/tmp/Test Song.flac")
        let videoURL = URL(fileURLWithPath: "/tmp/Movie Clip.mp4")

        let audioTrack = Track(lightweightURL: audioURL)
        XCTAssertEqual(audioTrack.title, "Test Song")
        XCTAssertEqual(audioTrack.mediaType, .audio)
        XCTAssertNil(audioTrack.duration)
        XCTAssertNil(audioTrack.artist)

        let videoTrack = Track(lightweightURL: videoURL)
        XCTAssertEqual(videoTrack.title, "Movie Clip")
        XCTAssertEqual(videoTrack.mediaType, .video)
    }
}
