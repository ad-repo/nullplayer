import XCTest
@testable import NullPlayer

/// Sweet Fades and gapless feed the next track straight into the playing pipeline, skipping
/// `loadTrack`'s routing, so anything that routing would send elsewhere must be refused here.
final class AudioEngineHandOffTests: XCTestCase {
    private let localAudio = Track(url: URL(fileURLWithPath: "/tmp/a.m4a"), title: "a")
    private let streamAudio = Track(url: URL(string: "https://example.com/a.flac")!, title: "a")
    private let localVideo = Track(url: URL(fileURLWithPath: "/tmp/v.mp4"), title: "v", mediaType: .video)
    private let streamVideo = Track(url: URL(string: "https://example.com/v.mkv")!, title: "v", mediaType: .video)
    private let placeholder = Track(url: URL(string: "about:blank")!, title: "p")

    func testPlaybackRouteMatchesLoadTrackRouting() {
        XCTAssertEqual(localAudio.playbackRoute, .local)
        XCTAssertEqual(streamAudio.playbackRoute, .streaming)
        XCTAssertEqual(localVideo.playbackRoute, .video)
        XCTAssertEqual(streamVideo.playbackRoute, .video)
        XCTAssertEqual(placeholder.playbackRoute, .unresolved)
    }

    func testSamePipelineAudioHandsOff() {
        XCTAssertTrue(AudioEngine.canHandOff(to: localAudio, fromStreaming: false))
        XCTAssertTrue(AudioEngine.canHandOff(to: streamAudio, fromStreaming: true))
    }

    func testOtherPipelineDoesNotHandOff() {
        XCTAssertFalse(AudioEngine.canHandOff(to: streamAudio, fromStreaming: false))
        XCTAssertFalse(AudioEngine.canHandOff(to: localAudio, fromStreaming: true))
    }

    func testVideoNeverHandsOff() {
        XCTAssertFalse(AudioEngine.canHandOff(to: localVideo, fromStreaming: false))
        XCTAssertFalse(AudioEngine.canHandOff(to: streamVideo, fromStreaming: true))
    }

    func testPlaceholderNeverHandsOff() {
        XCTAssertFalse(AudioEngine.canHandOff(to: placeholder, fromStreaming: false))
        XCTAssertFalse(AudioEngine.canHandOff(to: placeholder, fromStreaming: true))
    }
}
