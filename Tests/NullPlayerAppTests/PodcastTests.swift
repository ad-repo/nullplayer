import XCTest
import SQLite
@testable import NullPlayer

final class PodcastTests: XCTestCase {
    private let feed = PodcastFeed(
        indexId: 42,
        title: "Example Show",
        author: "Example Network",
        feedURL: URL(string: "https://example.com/feed.xml")!,
        imageURL: URL(string: "https://example.com/cover.jpg")!
    )

    func testFeedIdentityIsStableAcrossEquivalentInstances() {
        let duplicate = PodcastFeed(title: "Renamed Show", feedURL: feed.feedURL)
        XCTAssertEqual(feed.id, duplicate.id)
    }

    func testEpisodeDetectsAudioAndVideoEnclosures() {
        let audio = PodcastEpisode(feed: feed, title: "Audio", enclosureURL: URL(string: "https://example.com/e.mp3")!, enclosureType: "audio/mpeg")
        let video = PodcastEpisode(feed: feed, title: "Video", enclosureURL: URL(string: "https://example.com/e.bin")!, enclosureType: "video/mp4")

        XCTAssertFalse(audio.isVideo)
        XCTAssertTrue(video.isVideo)
    }

    func testPodcastTrackIsNotClassifiedAsInternetRadio() {
        let track = Track(
            url: URL(string: "https://cdn.example.com/episode.mp3")!,
            title: "Episode",
            duration: 1_800,
            playHistoryContentTypeOverride: "podcast",
            podcastEpisodeID: "episode-1",
            contentType: "audio/mpeg"
        )

        XCTAssertFalse(track.isRadioStream)
        XCTAssertEqual(track.playHistorySource, .local)
        XCTAssertEqual(track.playHistoryContentType, "podcast")
    }

    func testPodcastPlaylistStatePreservesRemoteVideoMetadata() throws {
        let track = Track(
            url: URL(string: "https://cdn.example.com/episode.mp4")!,
            title: "Video Episode",
            artist: "Host",
            album: "Example Show",
            duration: 2_400,
            artworkThumb: "https://example.com/cover.jpg",
            mediaType: .video,
            playHistoryContentTypeOverride: "video-podcast",
            podcastEpisodeID: "video-episode-1",
            contentType: "video/mp4"
        )

        let saved = AppStateManager.SavedTrack.from(track)
        let restored = try JSONDecoder().decode(
            AppStateManager.SavedTrack.self,
            from: JSONEncoder().encode(saved)
        )

        XCTAssertEqual(restored.remoteURL, track.url.absoluteString)
        XCTAssertEqual(restored.mediaType, .video)
        XCTAssertEqual(restored.artworkThumb, track.artworkThumb)
        XCTAssertEqual(restored.playHistoryContentTypeOverride, "video-podcast")
        XCTAssertEqual(restored.podcastEpisodeID, "video-episode-1")
        XCTAssertEqual(restored.contentType, "video/mp4")
        XCTAssertFalse(restored.isRadio)
    }

    func testRSSParserReadsPlayableAudioAndVideoEpisodes() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
          <channel>
            <title>Example Show</title>
            <item>
              <title>Audio Episode</title>
              <guid>audio-1</guid>
              <description><![CDATA[<p>Hello &amp; welcome.</p>]]></description>
              <itunes:duration>1:02:03</itunes:duration>
              <enclosure url="https://cdn.example.com/audio.mp3" type="audio/mpeg" length="123"/>
            </item>
            <item>
              <title>Video Episode</title>
              <guid>video-1</guid>
              <enclosure url="https://cdn.example.com/video.mp4" type="video/mp4" length="456"/>
            </item>
          </channel>
        </rss>
        """

        let episodes = try RSSPodcastParser.parse(data: Data(xml.utf8), feed: feed)

        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(episodes[0].title, "Audio Episode")
        XCTAssertEqual(episodes[0].duration, 3_723)
        XCTAssertEqual(episodes[0].summary, "Hello & welcome.")
        XCTAssertFalse(episodes[0].isVideo)
        XCTAssertTrue(episodes[1].isVideo)
    }

    func testPodcastLibraryRoundTripsThroughSQLite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodcastDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MediaLibraryStore.makeForTesting()
        store.open(at: directory.appendingPathComponent("library.db"))
        defer { store.close() }

        let episode = PodcastEpisode(
            guid: "stable-guid",
            feed: feed,
            title: "Saved Episode",
            summary: "Episode notes",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 1_800,
            enclosureURL: URL(string: "https://cdn.example.com/saved.mp3")!,
            enclosureType: "audio/mpeg",
            imageURL: feed.imageURL
        )
        let state = PodcastEpisodeState(
            position: 120,
            duration: 1_800,
            isPlayed: false,
            isFavorite: true,
            downloadedPath: "/tmp/saved.mp3",
            lastPlayedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let snapshot = PodcastLibrarySnapshot(
            subscriptions: [PodcastSubscription(feed: feed, subscribedAt: Date(timeIntervalSince1970: 1_699_000_000), autoDownloadNewest: true)],
            episodeStates: [episode.id: state],
            knownEpisodes: [episode.id: episode]
        )

        XCTAssertTrue(store.savePodcastLibrary(snapshot))
        let restored = store.loadPodcastLibrary()

        XCTAssertEqual(restored.subscriptions, snapshot.subscriptions)
        XCTAssertEqual(restored.knownEpisodes[episode.id], episode)
        XCTAssertEqual(restored.episodeStates[episode.id], state)

        store.updatePodcastPlaybackProgress(
            episodeID: episode.id,
            current: 300,
            duration: 1_800,
            playedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let progressedState = store.loadPodcastLibrary().episodeStates[episode.id]
        XCTAssertEqual(progressedState?.position, 300)
        XCTAssertEqual(progressedState?.duration, 1_800)
        XCTAssertEqual(progressedState?.isFavorite, true)
        XCTAssertEqual(progressedState?.downloadedPath, "/tmp/saved.mp3")
    }

    func testV8MigrationCreatesPodcastTablesWithoutRebuildingPlayEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodcastMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("library.db")

        do {
            let db = try Connection(databaseURL.path)
            try db.execute("""
                CREATE TABLE play_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    played_at REAL NOT NULL,
                    duration_listened REAL NOT NULL DEFAULT 0,
                    source TEXT NOT NULL CHECK(source IN ('local','plex','subsonic','jellyfin','emby','radio')),
                    skipped INTEGER NOT NULL DEFAULT 0,
                    content_type TEXT,
                    output_device TEXT
                );
                """)
            try db.run("PRAGMA user_version = 8")
        }

        let store = MediaLibraryStore.makeForTesting()
        store.open(at: databaseURL)
        defer { store.close() }
        let db = try XCTUnwrap(store.testDB)

        XCTAssertEqual(try db.scalar("PRAGMA user_version") as? Int64, 9)
        XCTAssertTrue(try tableExists("podcast_subscriptions", in: db))
        XCTAssertTrue(try tableExists("podcast_episodes", in: db))
        XCTAssertTrue(try tableExists("podcast_episode_states", in: db))
        XCTAssertThrowsError(try db.run(
            "INSERT INTO play_events (played_at, duration_listened, source, skipped, content_type) VALUES (?, ?, ?, ?, ?)",
            [Date().timeIntervalSince1970 as Binding, 60.0 as Binding, "podcast" as Binding, 0 as Binding, "podcast" as Binding]
        ))
    }

    private func tableExists(_ name: String, in db: Connection) throws -> Bool {
        let count = try db.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
            [name as Binding]
        ) as? Int64 ?? 0
        return count == 1
    }
}
