import XCTest
@testable import NullPlayer

@MainActor
final class LibraryPlayableTests: XCTestCase {
    /// A video row must queue as `.video` tracks: that is what `loadTrack` routes to the video
    /// player. As `.audio` the engine would open the film as an audio file.
    func testLocalVideoRowsQueueAsVideoTracksInOrder() async throws {
        let movie = LocalVideo(url: URL(fileURLWithPath: "/films/Heat.mkv"))
        let episodes = (1...3).map {
            LocalEpisode(url: URL(fileURLWithPath: "/tv/Show/S01E0\($0).mp4"), showTitle: "Show", episodeNumber: $0)
        }

        let movieTracks = try await LibraryPlayable.localMovie(movie).tracks()
        XCTAssertEqual(movieTracks.map(\.url), [movie.url])
        XCTAssertEqual(movieTracks.map(\.title), ["Heat"])
        XCTAssertEqual(movieTracks.map(\.mediaType), [.video])

        let episodeTracks = try await LibraryPlayable.localEpisodes(episodes).tracks()
        XCTAssertEqual(episodeTracks.map(\.url), episodes.map(\.url))
        XCTAssertTrue(episodeTracks.allSatisfy { $0.mediaType == .video && $0.artist == "Show" })
    }
}
