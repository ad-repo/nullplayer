import XCTest
@testable import NullPlayer

/// The format a lightweight import leaves out, read back from the file and filled into the row.
final class TrackFormatTests: XCTestCase {
    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Audio/\(name)")
    }

    /// `AVAudioFile` opens MPEG-4 Opus with zero frames (macOS 27; older systems refuse it outright,
    /// the branch that reads the asset's own track format), so the duration comes from the asset.
    func testAnOpusFileReadsInFull() async throws {
        let url = fixture("opus-in-m4a.m4a")
        let format = await Track.Format.read(from: url)

        XCTAssertGreaterThan(try XCTUnwrap(format.duration), 0)
        XCTAssertNotNil(format.bitrate)
        XCTAssertEqual(format.sampleRate, 48_000)
        XCTAssertNotNil(format.channels)
        XCTAssertFalse(Track(lightweightURL: url).filling(format).lacksFormat)
    }

    func testAFileTheNativeReaderOpensReadsInFull() async {
        let url = fixture("aac-in-m4a.m4a")
        let format = await Track.Format.read(from: url)
        XCTAssertFalse(Track(lightweightURL: url).filling(format).lacksFormat)
    }

    /// Only the unknown fields fill, and nothing else about the track is lost on the way — the
    /// stream's detected format used to drop the cue range and the origin flags.
    func testFillingKeepsKnownFieldsAndEverythingElse() {
        let source = URL(fileURLWithPath: "/tmp/album.flac")
        let track = Track(url: source, title: "Side A", bitrate: 900,
                          playHistoryContentTypeOverride: "audiobook",
                          cueStartOffset: 12, cueEndOffset: 34, cueSourceURL: source,
                          isRadioOrigin: true, isYouTubeOrigin: true)

        let filled = track.filling(Track.Format(duration: 300, bitrate: 128, sampleRate: 44_100, channels: 2))

        XCTAssertEqual(filled.id, track.id)
        XCTAssertEqual(filled.bitrate, 900)
        XCTAssertEqual(filled.duration, 300)
        XCTAssertEqual(filled.sampleRate, 44_100)
        XCTAssertEqual(filled.channels, 2)
        XCTAssertEqual(filled.playHistoryContentTypeOverride, "audiobook")
        XCTAssertEqual(filled.cueStartOffset, 12)
        XCTAssertEqual(filled.cueEndOffset, 34)
        XCTAssertEqual(filled.cueSourceURL, source)
        XCTAssertTrue(filled.isRadioOrigin)
        XCTAssertTrue(filled.isYouTubeOrigin)
    }
}
