import XCTest
@testable import NullPlayer

final class CLIOptionsTests: XCTestCase {

    // MARK: - Flag Parsing

    func testFlagParsing() {
        // All boolean flags (index 0 is the executable path, which parse() skips)
        let args = ["NullPlayer",
                    "--json", "--shuffle", "--repeat-all", "--repeat-one", "--no-art",
                    "--list-sources", "--list-libraries", "--list-artists", "--list-albums",
                    "--list-tracks", "--list-genres", "--list-playlists", "--list-stations",
                    "--list-devices", "--list-outputs", "--list-eq",
                    "--cli"]   // --cli is silently ignored
        let opts = CLIOptions.parse(args)

        XCTAssertTrue(opts.json)
        XCTAssertTrue(opts.shuffle)
        XCTAssertTrue(opts.repeatAll)
        XCTAssertTrue(opts.repeatOne)
        XCTAssertFalse(opts.art)

        XCTAssertTrue(opts.listSources)
        XCTAssertTrue(opts.listLibraries)
        XCTAssertTrue(opts.listArtists)
        XCTAssertTrue(opts.listAlbums)
        XCTAssertTrue(opts.listTracks)
        XCTAssertTrue(opts.listGenres)
        XCTAssertTrue(opts.listPlaylists)
        XCTAssertTrue(opts.listStations)
        XCTAssertTrue(opts.listDevices)
        XCTAssertTrue(opts.listOutputs)
        XCTAssertTrue(opts.listEQ)
    }

    // MARK: - Value Parsing

    func testValueParsing() {
        let args = ["NullPlayer",
                    "--source", "plex",
                    "--artist", "Radiohead",
                    "--album", "OK Computer",
                    "--track", "Karma Police",
                    "--genre", "Rock",
                    "--playlist", "Favourites",
                    "--search", "creep",
                    "--radio", "artist",
                    "--station", "KEXP",
                    "--library", "Music",
                    "--folder", "genres",
                    "--channel", "news",
                    "--region", "us",
                    "--cast", "Living Room",
                    "--cast-type", "sonos",
                    "--sonos-rooms", "Kitchen,Office",
                    "--eq", "Rock",
                    "--output", "Built-in Output",
                    "--volume", "75",
                    "--decade", "1990"]
        let opts = CLIOptions.parse(args)

        XCTAssertEqual(opts.source, "plex")
        XCTAssertEqual(opts.artist, "Radiohead")
        XCTAssertEqual(opts.album, "OK Computer")
        XCTAssertEqual(opts.track, "Karma Police")
        XCTAssertEqual(opts.genre, "Rock")
        XCTAssertEqual(opts.playlist, "Favourites")
        XCTAssertEqual(opts.search, "creep")
        XCTAssertEqual(opts.radio, "artist")
        XCTAssertEqual(opts.station, "KEXP")
        XCTAssertEqual(opts.library, "Music")
        XCTAssertEqual(opts.folder, "genres")
        XCTAssertEqual(opts.channel, "news")
        XCTAssertEqual(opts.region, "us")
        XCTAssertEqual(opts.cast, "Living Room")
        XCTAssertEqual(opts.castType, "sonos")
        XCTAssertEqual(opts.sonosRooms, "Kitchen,Office")
        XCTAssertEqual(opts.eq, "Rock")
        XCTAssertEqual(opts.output, "Built-in Output")
        XCTAssertEqual(opts.volume, 75)
        XCTAssertEqual(opts.decade, 1990)
    }

    // MARK: - Query Mode Detection

    func testQueryModeDetection() {
        let listFlags: [(String, KeyPath<CLIOptions, Bool>)] = [
            ("--list-sources",    \.listSources),
            ("--list-libraries",  \.listLibraries),
            ("--list-artists",    \.listArtists),
            ("--list-albums",     \.listAlbums),
            ("--list-tracks",     \.listTracks),
            ("--list-genres",     \.listGenres),
            ("--list-playlists",  \.listPlaylists),
            ("--list-stations",   \.listStations),
            ("--list-devices",    \.listDevices),
            ("--list-outputs",    \.listOutputs),
            ("--list-eq",         \.listEQ),
        ]

        for (flag, _) in listFlags {
            let opts = CLIOptions.parse(["NullPlayer", flag])
            XCTAssertTrue(opts.isQueryMode, "\(flag) should set isQueryMode")
        }

        // --search alone → isSearchQuery = true, isQueryMode = true
        let searchOnly = CLIOptions.parse(["NullPlayer", "--search", "hello"])
        XCTAssertTrue(searchOnly.isSearchQuery)
        XCTAssertTrue(searchOnly.isQueryMode)

        // --search + playback flags → isSearchQuery = false (playback mode)
        let searchWithArtist = CLIOptions.parse(["NullPlayer", "--search", "hello", "--artist", "X"])
        XCTAssertFalse(searchWithArtist.isSearchQuery)

        let searchWithAlbum = CLIOptions.parse(["NullPlayer", "--search", "hello", "--album", "Y"])
        XCTAssertFalse(searchWithAlbum.isSearchQuery)

        let searchWithPlaylist = CLIOptions.parse(["NullPlayer", "--search", "hello", "--playlist", "Z"])
        XCTAssertFalse(searchWithPlaylist.isSearchQuery)

        let searchWithRadio = CLIOptions.parse(["NullPlayer", "--search", "hello", "--radio", "genre"])
        XCTAssertFalse(searchWithRadio.isSearchQuery)

        let searchWithStation = CLIOptions.parse(["NullPlayer", "--search", "hello", "--station", "KEXP"])
        XCTAssertFalse(searchWithStation.isSearchQuery)
    }
}
