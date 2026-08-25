import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 65 (backlog B46) — `getPlayItemMetaDataString` answers a whole key table, and the star
/// rating is a real field.
///
/// The engine answered exactly four keys — `title`, `artist`, `album`, `filename` — and `""` for
/// everything else. A file-info panel reads an empty field as "this track has no such tag" and hides
/// that line, so the failure was invisible rather than loud: Big Bento Modern's panel filled four
/// lines and silently dropped Year, Genre, Track #, Disc, Album Artist, Composer, Decoder, Comment
/// and BPM, all of which are ticked by default in its own **… → File Info Components** menu.
///
/// The key set here is measured, not guessed. It is the union of the call sites across the 36
/// installed skins (`getPlayItemMetaDataString("…")` in Anaheim, BLAKK, Ebonite, Styx, the Nokia
/// 5220 display and four notifiers) and the string table of Big Bento's compiled `fileinfo.maki`,
/// which asks for eighteen of them. The corpus also pins the *units*, which is the part a guess gets
/// wrong: every caller of `length` wraps it in `integerToTime(stringToInteger(…))`, so it is whole
/// seconds, and `stereo`/`vbr` are compared against the literal `"1"`, so they are flags rather than
/// counts.
///
/// Ratings were the second half. The task note claimed a star rating was "a different concept" here
/// and should stay empty — that was wrong, and checking the app rather than the note is the lesson:
/// NullPlayer's Library Browser has drawn a 0–5 star row for every source (local, Plex, Subsonic,
/// Jellyfin, Emby) all along, on an internal 0–10 scale. That is exactly Winamp's
/// `getCurrentTrackRating` field, so it is now wired through `TrackRatingService`, which owns every
/// per-source conversion so the two surfaces cannot disagree about what three stars means.
final class WinampModernPhase65Tests: XCTestCase {

    // MARK: - The key table

    /// The four keys that already worked. They are asserted first and separately because the change
    /// replaced the four-case switch wholesale: a table that answers eleven new keys and quietly
    /// breaks one of the original four is a net loss.
    func testTheOriginalFourKeysStillAnswer() {
        let host = Host()
        host.trackTitle = "Blue Monday"
        host.trackArtist = "New Order"
        host.trackAlbum = "Power, Corruption & Lies"
        host.trackPath = "/Music/New Order/Blue Monday.flac"

        XCTAssertEqual(host.playItemMetadata(forKey: "title"), "Blue Monday")
        XCTAssertEqual(host.playItemMetadata(forKey: "artist"), "New Order")
        XCTAssertEqual(host.playItemMetadata(forKey: "album"), "Power, Corruption & Lies")
        XCTAssertEqual(host.playItemMetadata(forKey: "filename"), "/Music/New Order/Blue Monday.flac")
    }

    /// The tag fields the panel was missing — the whole point of B46.
    func testTheTagFieldsAFileInfoPanelPrints() {
        let host = Host()
        host.trackMetadata.albumArtist = "Various Artists"
        host.trackMetadata.composer = "Bernard Sumner"
        host.trackMetadata.genre = "Synth-pop"
        host.trackMetadata.comment = "12\" single"
        host.trackMetadata.year = "1983"
        host.trackMetadata.trackNumber = "3"
        host.trackMetadata.discNumber = "1"
        host.trackMetadata.bpm = "130"

        XCTAssertEqual(host.playItemMetadata(forKey: "albumartist"), "Various Artists")
        XCTAssertEqual(host.playItemMetadata(forKey: "composer"), "Bernard Sumner")
        XCTAssertEqual(host.playItemMetadata(forKey: "genre"), "Synth-pop")
        XCTAssertEqual(host.playItemMetadata(forKey: "comment"), "12\" single")
        XCTAssertEqual(host.playItemMetadata(forKey: "year"), "1983")
        XCTAssertEqual(host.playItemMetadata(forKey: "track"), "3")
        XCTAssertEqual(host.playItemMetadata(forKey: "disc"), "1")
        XCTAssertEqual(host.playItemMetadata(forKey: "bpm"), "130")
    }

    /// Skins spell the same field several ways and Winamp accepts all of them, so the aliases are
    /// part of the contract rather than a convenience. `filepath` in particular is Big Bento's
    /// spelling of `filename`, and answering only one of the pair leaves its File Path line blank.
    func testEveryAliasReachesTheSameField() {
        let host = Host()
        host.trackPath = "/Music/track.flac"
        host.trackMetadata.albumArtist = "VA"
        host.trackMetadata.trackNumber = "7"
        host.trackMetadata.discNumber = "2"
        host.sampleRateHz = 48_000

        XCTAssertEqual(host.playItemMetadata(forKey: "filepath"),
                       host.playItemMetadata(forKey: "filename"))
        XCTAssertEqual(host.playItemMetadata(forKey: "album artist"),
                       host.playItemMetadata(forKey: "albumartist"))
        XCTAssertEqual(host.playItemMetadata(forKey: "tracknumber"),
                       host.playItemMetadata(forKey: "track"))
        XCTAssertEqual(host.playItemMetadata(forKey: "discnumber"),
                       host.playItemMetadata(forKey: "disc"))
        XCTAssertEqual(host.playItemMetadata(forKey: "samplerate"),
                       host.playItemMetadata(forKey: "srate"))
    }

    /// The Nokia 5220's display asks in block capitals (`"TIMEELAPSED"`), Anaheim asks in camel case
    /// — Winamp's key match is case-insensitive and the corpus depends on it.
    func testKeysAreMatchedCaseInsensitively() {
        let host = Host()
        host.trackMetadata.year = "1983"
        XCTAssertEqual(host.playItemMetadata(forKey: "YEAR"), "1983")
        XCTAssertEqual(host.playItemMetadata(forKey: "Year"), "1983")
        XCTAssertEqual(host.playItemMetadata(forKey: "AlbumArtist"),
                       host.playItemMetadata(forKey: "albumartist"))
    }

    /// Whole seconds, because every caller in the corpus wraps the answer in
    /// `integerToTime(stringToInteger(l))` — a millisecond answer would print a four-hour track.
    /// An unknown length is `""`, which is the case the callers' `if (l != "")` guard exists for.
    func testLengthIsWholeSecondsAndUnknownIsEmpty() {
        let host = Host()
        host.duration = 269.7
        XCTAssertEqual(host.playItemMetadata(forKey: "length"), "269")
        host.duration = 0
        XCTAssertEqual(host.playItemMetadata(forKey: "length"), "")
    }

    /// A flag compared against the literal `"1"`, not a channel count — a skin prints "Stereo" or
    /// "Mono" from it. Unknown takes the same branch as mono but claims nothing, which matters
    /// because a stream reports no channel count until it has decoded something.
    func testStereoIsAFlagAndUnknownIsEmpty() {
        let host = Host()
        host.channelCount = 2
        XCTAssertEqual(host.playItemMetadata(forKey: "stereo"), "1")
        host.channelCount = 6
        XCTAssertEqual(host.playItemMetadata(forKey: "stereo"), "1")
        host.channelCount = 1
        XCTAssertEqual(host.playItemMetadata(forKey: "stereo"), "0")
        host.channelCount = 0
        XCTAssertEqual(host.playItemMetadata(forKey: "stereo"), "")
    }

    /// Numeric readouts, with zero meaning "unknown" rather than a real zero — a skin appends
    /// "KBPS" to whatever it gets, and "0KBPS" is worse than a hidden line.
    func testBitrateAndSampleRateHideThemselvesWhenUnknown() {
        let host = Host()
        host.bitrateKbps = 320
        host.sampleRateHz = 44_100
        XCTAssertEqual(host.playItemMetadata(forKey: "bitrate"), "320")
        XCTAssertEqual(host.playItemMetadata(forKey: "srate"), "44100")
        host.bitrateKbps = 0
        host.sampleRateHz = 0
        XCTAssertEqual(host.playItemMetadata(forKey: "bitrate"), "")
        XCTAssertEqual(host.playItemMetadata(forKey: "srate"), "")
    }

    /// These two go straight into a text object without passing through `integerToTime`, so they are
    /// formatted here — and they roll over to `h:mm:ss` rather than printing "78:03" for a long set.
    func testElapsedAndRemainingAreFormattedClockStrings() {
        let host = Host()
        host.duration = 300
        host.currentTime = 65
        XCTAssertEqual(host.playItemMetadata(forKey: "timeelapsed"), "1:05")
        XCTAssertEqual(host.playItemMetadata(forKey: "timeremaining"), "3:55")

        host.duration = 7_200
        host.currentTime = 3_723
        XCTAssertEqual(host.playItemMetadata(forKey: "timeelapsed"), "1:02:03")

        // A stream has no duration, so there is no "remaining" to report.
        host.duration = 0
        XCTAssertEqual(host.playItemMetadata(forKey: "timeremaining"), "")
    }

    /// Both readouts name the codec on purpose. Winamp shows a decoder ("Nullsoft MPEG Audio
    /// Decoder") and a format ("MPEG-1 Layer 3") that describe the same thing; deriving a second
    /// string here from the path extension would let the two lines of one panel disagree.
    func testFormatAndDecoderAreTheSameAnswer() {
        let host = Host()
        host.decoderName = "FLAC"
        XCTAssertEqual(host.playItemMetadata(forKey: "format"), "FLAC")
        XCTAssertEqual(host.playItemMetadata(forKey: "decoder"), "FLAC")
    }

    /// Radio. The station is what Winamp calls the stream, and Big Bento draws its name and URL on
    /// two dedicated lines (`infodisplay.line.sname` / `.surl`).
    func testTheStreamFieldsAnswerForRadio() {
        let host = Host()
        host.trackMetadata.streamName = "SomaFM: Groove Salad"
        host.trackMetadata.streamURL = "https://somafm.com/groovesalad"
        host.trackMetadata.streamTitle = "Bonobo - Kiara"
        host.trackMetadata.streamGenre = "Ambient"

        XCTAssertEqual(host.playItemMetadata(forKey: "streamname"), "SomaFM: Groove Salad")
        XCTAssertEqual(host.playItemMetadata(forKey: "streamurl"), "https://somafm.com/groovesalad")
        XCTAssertEqual(host.playItemMetadata(forKey: "streamtitle"), "Bonobo - Kiara")
        XCTAssertEqual(host.playItemMetadata(forKey: "streamgenre"), "Ambient")
    }

    /// The three fields the engine genuinely cannot answer. They are asserted rather than left
    /// untested so that "empty" stays a decision someone made: NullPlayer stores no publisher tag,
    /// and it never learns whether a file is VBR or what flavour of shoutcast a stream is.
    func testTheDeliberatelyUnanswerableKeysStayEmpty() {
        let host = Host()
        host.trackTitle = "Something"
        XCTAssertEqual(host.playItemMetadata(forKey: "publisher"), "")
        XCTAssertEqual(host.playItemMetadata(forKey: "vbr"), "")
        XCTAssertEqual(host.playItemMetadata(forKey: "streamtype"), "")
    }

    /// An unrecognised key is empty, not a crash and not a placeholder — Wasabi's key set is
    /// open-ended and a skin may ask for anything.
    func testAnUnknownKeyIsEmpty() {
        XCTAssertEqual(Host().playItemMetadata(forKey: "no-such-field"), "")
        XCTAssertEqual(Host().playItemMetadata(forKey: ""), "")
    }

    /// The protocol default. The render harness and every test double get the same table, which is
    /// what makes a probe run comparable to the live app — they simply have nothing to put in it.
    func testAHostWithNoMetadataAnswersEveryKeyEmpty() {
        let host = BareHost()
        for key in ["title", "artist", "album", "year", "genre", "albumartist", "composer",
                    "comment", "bpm", "track", "disc", "rating", "publisher", "streamname"] {
            XCTAssertEqual(host.playItemMetadata(forKey: key), "", "key \(key)")
        }
    }

    // MARK: - Ratings

    /// Stars in, stars out. Unrated is `""` rather than `"0"`, because a panel hides an empty line
    /// but would print a deliberate-looking zero.
    func testTheRatingKeyAnswersStarsAndHidesWhenUnrated() {
        let host = Host()
        host.currentTrackRating = 4
        XCTAssertEqual(host.playItemMetadata(forKey: "rating"), "4")
        host.currentTrackRating = 0
        XCTAssertEqual(host.playItemMetadata(forKey: "rating"), "")
    }

    /// The app's internal scale is 0–10 and every user-facing surface is 0–5 stars, so the pair has
    /// to round-trip. A star is two points; the conversions live together in `TrackRatingService`
    /// precisely so a change to one cannot be made without the other.
    func testStarAndRatingConversionsRoundTrip() {
        for stars in 0...5 {
            XCTAssertEqual(TrackRatingService.stars(fromRating: TrackRatingService.rating(fromStars: stars)),
                           stars)
        }
        XCTAssertEqual(TrackRatingService.rating(fromStars: 3), 6)
        XCTAssertEqual(TrackRatingService.stars(fromRating: 6), 3)
        // The half-star the scale can represent even though no surface offers one: 7/10 rounds up
        // rather than truncating, so a 3.5-star track never reads as 3.
        XCTAssertEqual(TrackRatingService.stars(fromRating: 7), 4)
    }

    /// Out-of-range input is clamped rather than trusted: both ends are reachable from a skin, which
    /// can pass `setCurrentTrackRating` any integer at all.
    func testStarConversionsClampOutOfRangeInput() {
        XCTAssertEqual(TrackRatingService.rating(fromStars: 9), 10)
        XCTAssertEqual(TrackRatingService.rating(fromStars: -3), 0)
        XCTAssertEqual(TrackRatingService.stars(fromRating: 99), 5)
        XCTAssertEqual(TrackRatingService.stars(fromRating: -4), 0)
    }

    // MARK: - The runtime seam

    /// The runtime must go through the host's table rather than keeping a switch of its own — the
    /// duplicate switch is what B46 was.
    func testTheRuntimeAnswersMetadataFromTheHostTable() throws {
        let host = Host()
        host.trackMetadata.year = "1983"
        host.trackMetadata.composer = "Bernard Sumner"
        let runtime = try makeRuntime(host: host)

        XCTAssertEqual(try metadata(runtime, key: "year"), "1983")
        XCTAssertEqual(try metadata(runtime, key: "composer"), "Bernard Sumner")
        XCTAssertEqual(try metadata(runtime, key: "publisher"), "")
    }

    /// `setCurrentTrackRating` previously was not in the method table at all, so Big Bento's star
    /// click threw `unsupported` and **aborted the handler** — the stars did not merely fail to
    /// save, the rest of that handler never ran.
    func testTheRatingRoundTripsThroughTheRuntime() throws {
        let host = Host()
        let runtime = try makeRuntime(host: host)

        XCTAssertEqual(try invoke(runtime, "getcurrenttrackrating").integerValue, 0)
        _ = try invoke(runtime, "setcurrenttrackrating", arguments: [.integer(4)])
        XCTAssertEqual(host.currentTrackRating, 4)
        XCTAssertEqual(try invoke(runtime, "getcurrenttrackrating").integerValue, 4)
        XCTAssertEqual(try metadata(runtime, key: "rating"), "4")
    }

    /// `onCurrentTrackRated` has to be dispatchable: a server track's rating arrives after the track
    /// does, so a star row is told rather than polled. Calling it as a method is the same test —
    /// that is how Wasabi lets a script re-run its own handler.
    func testOnCurrentTrackRatedIsDispatchable() throws {
        let runtime = try makeRuntime(host: Host())
        XCTAssertNoThrow(try invoke(runtime, "oncurrenttrackrated", arguments: [.integer(3)]))
        XCTAssertNoThrow(try runtime.dispatchSystem(event: "oncurrenttrackrated",
                                                    arguments: [.integer(3)]))
    }

    // MARK: - Helpers

    private func metadata(_ runtime: WinampModernScriptRuntime, key: String) throws -> String {
        try invoke(runtime, "getplayitemmetadatastring", arguments: [.string(key)]).stringValue
    }

    private func invoke(_ runtime: WinampModernScriptRuntime, _ method: String,
                        arguments: [MakiValue] = []) throws -> MakiValue {
        try runtime.invoke(method: method, on: MakiObjectReference(.system),
                           arguments: arguments, program: emptyProgram())
    }

    private func makeRuntime(host: WinampModernHost) throws -> WinampModernScriptRuntime {
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <layer id="plain" x="0" y="0" w="10" h="10"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase65Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase65-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    /// Every field the table reads, settable — the table is the unit under test, not the adapter
    /// that fills it.
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackArtist = ""
        var trackAlbum = ""
        var trackInfo = ""
        var trackMetadata = WinampModernTrackMetadata()
        var currentTrackRating = 0
        var trackPath = ""
        var decoderName = ""
        var bitrateKbps = 0
        var sampleRateHz = 0
        var channelCount = 0
        var spectrumLevels: [Float] = []

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }

    /// A host that implements only what the protocol demands, so every metadata field falls to its
    /// default — the shape the render harness runs in.
    private final class BareHost: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
