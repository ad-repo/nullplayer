import XCTest
@testable import NullPlayer

/// Unit tests for `CLIOptions.parse` and the query-mode classification that drives
/// whether the CLI prints results and exits (query) or resolves media and plays
/// (playback). These are the pure, deterministic pieces of the CLI — the source
/// resolution paths (`CLISourceResolver`) depend on live servers and are exercised
/// by manual QA / the process-level checks in the cli skill.
final class CLIOptionsTests: XCTestCase {

    /// The parser treats index 0 as the executable path, matching `CommandLine.arguments`.
    private func parse(_ argsAfterExecutable: String...) -> CLIOptions {
        CLIOptions.parse(["nullplayer"] + argsAfterExecutable)
    }

    // MARK: - Defaults

    func testDefaultsWhenNoArgs() {
        let opts = parse()
        XCTAssertFalse(opts.json)
        XCTAssertFalse(opts.help)
        XCTAssertFalse(opts.version)
        XCTAssertNil(opts.source)
        XCTAssertTrue(opts.art, "album art is on by default")
        XCTAssertFalse(opts.shuffle)
        XCTAssertFalse(opts.isQueryMode)
        XCTAssertFalse(opts.isSearchQuery)
    }

    func testExecutablePathIsSkipped() {
        // Index 0 is the executable path and must be ignored: the leading "--source"
        // here is NOT parsed (so it never tries to consume the next token as a value),
        // while "--list-artists" at index 1 is parsed normally.
        let opts = CLIOptions.parse(["--source", "--list-artists"])
        XCTAssertNil(opts.source, "leading --source is the executable-path slot, not a flag")
        XCTAssertTrue(opts.listArtists, "index 1 onward is parsed normally")
    }

    // MARK: - Boolean / list flags

    func testBooleanFlags() {
        let opts = parse("--json", "--shuffle", "--repeat-all", "--repeat-one", "--no-art")
        XCTAssertTrue(opts.json)
        XCTAssertTrue(opts.shuffle)
        XCTAssertTrue(opts.repeatAll)
        XCTAssertTrue(opts.repeatOne)
        XCTAssertFalse(opts.art, "--no-art disables album art")
    }

    func testAllListFlags() {
        XCTAssertTrue(parse("--list-sources").listSources)
        XCTAssertTrue(parse("--list-libraries").listLibraries)
        XCTAssertTrue(parse("--list-artists").listArtists)
        XCTAssertTrue(parse("--list-albums").listAlbums)
        XCTAssertTrue(parse("--list-tracks").listTracks)
        XCTAssertTrue(parse("--list-genres").listGenres)
        XCTAssertTrue(parse("--list-playlists").listPlaylists)
        XCTAssertTrue(parse("--list-stations").listStations)
        XCTAssertTrue(parse("--list-devices").listDevices)
        XCTAssertTrue(parse("--list-outputs").listOutputs)
        XCTAssertTrue(parse("--list-eq").listEQ)
    }

    func testCliFlagIsIgnored() {
        // --cli is consumed in main.swift; the options parser must treat it as a no-op.
        let opts = parse("--cli", "--source", "plex")
        XCTAssertEqual(opts.source, "plex")
    }

    // MARK: - Value flags

    func testStringValueFlags() {
        let opts = parse(
            "--source", "plex",
            "--library", "AD-FLAC",
            "--artist", "Soundgarden",
            "--album", "SuperUnknown",
            "--track", "Black Hole Sun",
            "--genre", "Reggae",
            "--playlist", "All Music",
            "--search", "soundgarden",
            "--radio", "artist",
            "--station", "Radio Paradise",
            "--file", "~/Movies/sample.mkv",
            "--movie", "Blade Runner",
            "--show", "The Office",
            "--episode", "Dinner Party",
            "--folder", "genre",
            "--channel", "Jazz",
            "--region", "US",
            "--cast", "Living Room",
            "--cast-type", "sonos",
            "--sonos-rooms", "Kitchen,Office",
            "--eq", "Rock",
            "--output", "MacBook Pro Speakers",
            "--tuning", "432",
            "--tuning-source", "440"
        )
        XCTAssertEqual(opts.source, "plex")
        XCTAssertEqual(opts.library, "AD-FLAC")
        XCTAssertEqual(opts.artist, "Soundgarden")
        XCTAssertEqual(opts.album, "SuperUnknown")
        XCTAssertEqual(opts.track, "Black Hole Sun")
        XCTAssertEqual(opts.genre, "Reggae")
        XCTAssertEqual(opts.playlist, "All Music")
        XCTAssertEqual(opts.search, "soundgarden")
        XCTAssertEqual(opts.radio, "artist")
        XCTAssertEqual(opts.station, "Radio Paradise")
        XCTAssertEqual(opts.file, "~/Movies/sample.mkv")
        XCTAssertEqual(opts.movie, "Blade Runner")
        XCTAssertEqual(opts.show, "The Office")
        XCTAssertEqual(opts.episode, "Dinner Party")
        XCTAssertEqual(opts.folder, "genre")
        XCTAssertEqual(opts.channel, "Jazz")
        XCTAssertEqual(opts.region, "US")
        XCTAssertEqual(opts.cast, "Living Room")
        XCTAssertEqual(opts.castType, "sonos")
        XCTAssertEqual(opts.sonosRooms, "Kitchen,Office")
        XCTAssertEqual(opts.eq, "Rock")
        XCTAssertEqual(opts.output, "MacBook Pro Speakers")
        XCTAssertEqual(opts.tuning, "432")
        XCTAssertEqual(opts.tuningSource, "440")
    }

    func testNumericValueFlags() {
        let opts = parse("--volume", "75", "--decade", "1990", "--season", "4", "--number", "9", "--tuning-offset-cents", "-31.766")
        XCTAssertEqual(opts.volume, 75)
        XCTAssertEqual(opts.decade, 1990)
        XCTAssertEqual(opts.season, 4)
        XCTAssertEqual(opts.number, 9)
        XCTAssertEqual(opts.tuningOffsetCents, -31.766)
    }

    // MARK: - Query-mode classification

    func testEveryListFlagIsQueryMode() {
        for flag in ["--list-sources", "--list-libraries", "--list-artists", "--list-albums",
                     "--list-tracks", "--list-genres", "--list-playlists", "--list-stations",
                     "--list-devices", "--list-outputs", "--list-eq"] {
            XCTAssertTrue(parse(flag).isQueryMode, "\(flag) should be query mode")
        }
    }

    func testSearchAloneIsQuery() {
        let opts = parse("--source", "plex", "--search", "radiohead")
        XCTAssertTrue(opts.isSearchQuery)
        XCTAssertTrue(opts.isQueryMode)
    }

    func testSearchWithPlaybackFlagIsNotQuery() {
        // --search combined with a playback selector means "resolve and play", not "print".
        for playbackFlag in [("--artist", "Rush"), ("--album", "Moving Pictures"),
                             ("--playlist", "Focus"), ("--radio", "artist"), ("--station", "KEXP"),
                             ("--file", "~/song.flac"), ("--movie", "Blade Runner"),
                             ("--episode", "Dinner Party")] {
            let opts = parse("--search", "x", playbackFlag.0, playbackFlag.1)
            XCTAssertFalse(opts.isSearchQuery, "--search + \(playbackFlag.0) is playback, not a query")
            XCTAssertFalse(opts.isQueryMode, "--search + \(playbackFlag.0) is playback, not a query")
        }
    }

    func testPlaybackSelectionIsNotQueryMode() {
        let opts = parse("--source", "plex", "--library", "AD-FLAC", "--artist", "Soundgarden", "--album", "SuperUnknown")
        XCTAssertFalse(opts.isQueryMode, "artist/album playback should not be query mode")
    }

    // MARK: - Representative end-to-end command shapes

    func testPlexListAlbumsCommand() {
        // The command from the original bug report.
        let opts = parse("--cli", "--source", "plex", "--list-albums", "--artist", "Soundgarden")
        XCTAssertEqual(opts.source, "plex")
        XCTAssertTrue(opts.listAlbums)
        XCTAssertEqual(opts.artist, "Soundgarden")
        XCTAssertTrue(opts.isQueryMode)
    }

    func testVideoFlagsArePlaybackMode() {
        XCTAssertFalse(parse("--file", "~/Movies/sample.mkv").isQueryMode)
        XCTAssertFalse(parse("--source", "plex", "--movie", "Blade Runner").isQueryMode)
        XCTAssertFalse(parse("--source", "jellyfin", "--show", "The Office", "--episode", "Dinner Party").isQueryMode)
    }

    func testDetectContentTypeForLocalVideoAndAudio() {
        let video = detectContentType(for: URL(fileURLWithPath: "/tmp/sample.mkv"))
        XCTAssertEqual(video.mediaType, .video)
        XCTAssertEqual(video.contentType, "video/x-matroska")

        let audio = detectContentType(for: URL(fileURLWithPath: "/tmp/sample.flac"))
        XCTAssertEqual(audio.mediaType, .audio)
        XCTAssertEqual(audio.contentType, "audio/flac")
    }
}
