import XCTest
@testable import NullPlayer

final class TrackPlayHistoryContentTypeTests: XCTestCase {
    func testPlayHistoryContentTypeUsesOverrideForPlaylistVideoTracks() {
        let movieTrack = Track(
            url: URL(string: "https://example.com/movie.mp4")!,
            title: "Movie",
            plexRatingKey: "movie-1",
            mediaType: .video,
            playHistoryContentTypeOverride: "movie"
        )
        XCTAssertEqual(movieTrack.playHistoryContentType, "movie")

        let episodeTrack = Track(
            url: URL(string: "https://example.com/episode.mp4")!,
            title: "Episode",
            jellyfinId: "episode-1",
            jellyfinServerId: "server-1",
            mediaType: .video,
            playHistoryContentTypeOverride: "tv"
        )
        XCTAssertEqual(episodeTrack.playHistoryContentType, "tv")
    }

    func testPlayHistoryContentTypeFallsBackToGenericVideoWithoutOverride() {
        let videoTrack = Track(
            url: URL(fileURLWithPath: "/tmp/video.mp4"),
            title: "Video",
            mediaType: .video
        )

        XCTAssertEqual(videoTrack.playHistoryContentType, "video")
    }
}
