import XCTest
@testable import NullPlayer
// `@testable import NullPlayer` exposes types from NullPlayer including those
// re-exported via internal imports. Plex types are defined in NullPlayerCore,
// so we import it explicitly for those constructors. NOTE: Jellyfin/Emby/etc.
// types that exist in BOTH targets will need module-qualified access elsewhere.
import NullPlayerCore

final class RadioRequestConstructionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RadioPlaybackOptions.maxTracksPerArtist = RadioPlaybackOptions.defaultMaxTracksPerArtist
        RadioPlaybackOptions.playlistLength = RadioPlaybackOptions.defaultPlaylistLength
    }

    func testJellyfinRadioItemsRequestIncludesLeanAudioParams() throws {
        let client = try XCTUnwrap(makeJellyfinClient())

        let request = try XCTUnwrap(client.makeRadioItemsRequest(limit: 250, libraryId: "lib-1", genre: "Jazz"))
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.path, "/Users/user-1/Items")
        XCTAssertEqual(params["IncludeItemTypes"], "Audio")
        XCTAssertEqual(params["MediaTypes"], "Audio")
        XCTAssertEqual(params["Recursive"], "true")
        XCTAssertEqual(params["SortBy"], "Random")
        XCTAssertEqual(params["Limit"], "250")
        XCTAssertEqual(params["parentId"], "lib-1")
        XCTAssertEqual(params["Genres"], "Jazz")
        XCTAssertEqual(params["EnableImages"], "false")
        XCTAssertEqual(params["EnableUserData"], "false")
        XCTAssertEqual(params["EnableTotalRecordCount"], "false")
        XCTAssertEqual(params["Fields"], "Path,Genres,DateCreated,MediaSources")
    }

    func testJellyfinInstantMixRequestIncludesLeanParams() throws {
        let client = try XCTUnwrap(makeJellyfinClient())

        let request = try XCTUnwrap(client.makeRadioInstantMixRequest(path: "/Items/track-1/InstantMix", limit: 100))
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.path, "/Items/track-1/InstantMix")
        XCTAssertEqual(params["Limit"], "100")
        XCTAssertEqual(params["userId"], "user-1")
        XCTAssertEqual(params["EnableImages"], "false")
        XCTAssertEqual(params["EnableUserData"], "false")
        XCTAssertEqual(params["EnableTotalRecordCount"], "false")
        XCTAssertEqual(params["Fields"], "Path,Genres,DateCreated,MediaSources")
    }

    func testEmbyRadioItemsRequestIncludesLeanAudioParams() throws {
        let client = try XCTUnwrap(makeEmbyClient())

        let request = try XCTUnwrap(client.makeRadioItemsRequest(limit: 500, libraryId: "lib-2", filters: "IsFavorite"))
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.path, "/Users/user-2/Items")
        XCTAssertEqual(params["IncludeItemTypes"], "Audio")
        XCTAssertEqual(params["MediaTypes"], "Audio")
        XCTAssertEqual(params["Recursive"], "true")
        XCTAssertEqual(params["SortBy"], "Random")
        XCTAssertEqual(params["Limit"], "500")
        XCTAssertEqual(params["parentId"], "lib-2")
        XCTAssertEqual(params["Filters"], "IsFavorite")
        XCTAssertEqual(params["EnableImages"], "false")
        XCTAssertEqual(params["EnableUserData"], "false")
        XCTAssertEqual(params["EnableTotalRecordCount"], "false")
        XCTAssertEqual(params["Fields"], "Path,Genres,DateCreated,MediaSources")
    }

    func testPlexBuildRequestKeepsLeadingSlashPathReadable() throws {
        let client = try XCTUnwrap(makePlexClient())

        let request = try XCTUnwrap(client.buildRequest(
            path: "/library/sections/5/all",
            queryItems: [
                URLQueryItem(name: "type", value: "10"),
                URLQueryItem(name: "sort", value: "random"),
                URLQueryItem(name: "limit", value: "100")
            ]
        ))
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.path, "/library/sections/5/all")
        XCTAssertFalse(url.absoluteString.contains("%2Flibrary"))
        XCTAssertEqual(params["type"], "10")
        XCTAssertEqual(params["sort"], "random")
        XCTAssertEqual(params["limit"], "100")
    }

    func testPlexLibraryRadioRequestIncludesExpectedTrackQuery() throws {
        let client = try XCTUnwrap(makePlexClient())

        let request = try XCTUnwrap(client.makeLibraryRadioRequest(libraryID: "5", limit: 1000))
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.path, "/library/sections/5/all")
        XCTAssertEqual(params["type"], "10")
        XCTAssertEqual(params["sort"], "random")
        XCTAssertEqual(params["limit"], "1000")
    }

    func testPlexDecadeRadioRequestPreservesLiteralComparisonOperators() throws {
        let client = try XCTUnwrap(makePlexClient())

        let request = try XCTUnwrap(client.makeDecadeRadioRequest(startYear: 1990, endYear: 1999, libraryID: "5", limit: 250))
        let absoluteString = try XCTUnwrap(request.url?.absoluteString)

        XCTAssertTrue(absoluteString.contains("/library/sections/5/all?"))
        XCTAssertTrue(absoluteString.contains("type=10"))
        XCTAssertTrue(absoluteString.contains("year>=1990") || absoluteString.contains("year%3E=1990"))
        XCTAssertTrue(absoluteString.contains("year<=1999") || absoluteString.contains("year%3C=1999"))
        XCTAssertTrue(absoluteString.contains("sort=random"))
        XCTAssertTrue(absoluteString.contains("limit=250"))
    }

    func testCandidateFetchLimitDoesNotOverfetchWhenArtistLimitIsUnlimited() {
        XCTAssertEqual(
            RadioPlaybackOptions.candidateFetchLimit(for: 1000, maxPerArtist: RadioPlaybackOptions.unlimitedMaxTracksPerArtist),
            1000
        )
        XCTAssertEqual(
            RadioPlaybackOptions.candidateFetchLimit(for: 1000, maxPerArtist: 2),
            3000
        )
        XCTAssertEqual(
            RadioPlaybackOptions.candidateFetchLimit(for: 0, maxPerArtist: 2),
            0
        )
    }

    func testPlaylistLengthNormalizesInvalidValues() {
        RadioPlaybackOptions.playlistLength = 500
        XCTAssertEqual(RadioPlaybackOptions.playlistLength, 500)

        RadioPlaybackOptions.playlistLength = 123
        XCTAssertEqual(RadioPlaybackOptions.playlistLength, RadioPlaybackOptions.defaultPlaylistLength)
    }

    private func makeJellyfinClient() -> JellyfinServerClient? {
        // Disambiguate JellyfinServer — it exists in both NullPlayer and NullPlayerCore
        // targets. The app uses its own copy, so qualify explicitly.
        let server = NullPlayer.JellyfinServer(
            id: "srv-jf",
            name: "Test Jellyfin",
            url: "http://127.0.0.1:8096",
            username: "user",
            userId: "user-1"
        )
        return JellyfinServerClient(server: server, accessToken: "token")
    }

    private func makeEmbyClient() -> EmbyServerClient? {
        let server = EmbyServer(
            id: "srv-emby",
            name: "Test Emby",
            url: "http://127.0.0.1:8097",
            username: "user",
            userId: "user-2"
        )
        return EmbyServerClient(server: server, accessToken: "token")
    }

    private func makePlexClient() -> PlexServerClient? {
        let server = PlexServer(
            id: "server-1",
            name: "Test Plex",
            product: nil,
            productVersion: nil,
            platform: nil,
            platformVersion: nil,
            device: nil,
            owned: true,
            connections: [
                PlexConnection(uri: "http://127.0.0.1:32400", local: true, relay: false, address: nil, port: nil, protocol: "http")
            ],
            accessToken: "server-token"
        )
        return PlexServerClient(server: server, authToken: "auth-token")
    }
}
