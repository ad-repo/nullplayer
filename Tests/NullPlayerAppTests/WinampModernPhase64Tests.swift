import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 64 (backlog B39) — a script's `setText()` beats the object's `display=` binding.
///
/// Winamp's `display=` binding *writes* an object's text whenever its value changes, so whatever was
/// written last is what shows. This engine resolved the binding live on every draw instead, and the
/// binding therefore won forever: `setText` wrote the XML `text` attribute, which
/// `WasabiTextMetrics.bound()` reads **only** for an object that declares no `display=` at all.
///
/// Big Bento Modern is where it was found. All **17** of its `Bento:InfoLine` objects declare
/// `display="SONGNAME"` purely so `ticker="1"` works — the author says so in the markup
/// (`xml/player-normal-mcv.xml:378`, "Victhor trick") — and `fileinfo.m` then fills each one with
/// `setText()`. Every line drew the song title, which read on screen as *the title repeated down the
/// panel* rather than as a broken panel, because the layout was right and only the content was wrong.
///
/// The revert half is not optional, and it is the commoner pattern in the corpus: a transient readout
/// laid over the songticker — MMD3's SEEK/VOLUME/BASS/TREBLE, Styx's and Ebonite's seek and volume
/// overlays, micro's `oldtimer.m` clock over a `display="time"` timer — taken back down a second later
/// with `setText("")`. A sweep of the 36 installed skins found 13 that call `setText` on a
/// display-bound object; every one either reverts explicitly or rewrites on the next track change,
/// which is why a non-empty override is allowed to stand indefinitely rather than expiring when the
/// bound value moves. An expiry would break micro and Ebonite, whose whole purpose is to hold a
/// different clock format over the binding.
final class WinampModernPhase64Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 240
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Title"
        var trackArtist = "Artist"
        var trackInfo = "Artist - Album"
        var trackDisplayTitle = "Artist - Title"
        var bitrateKbps = 320
        var sampleRateHz = 44_100
        var channelCount = 2
        var spectrumLevels: [Float] = [0.2, 0.9, 0.5, 1]

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

    /// Big Bento's info line reduced to its two moving parts — the binding that exists only to enable
    /// the ticker, and a second line with no binding at all, which must keep behaving as it always has.
    private static let skinXML = """
    <WasabiXML>
      <container id="main">
        <layout id="normal" w="120" h="64">
          <text id="line" display="SONGNAME" ticker="1" x="0" y="0" w="112" h="8"/>
          <text id="ticker" display="songname" alternatetext="placeholder" x="0" y="8" w="112" h="8"/>
          <text id="plain" text="declared" x="0" y="16" w="112" h="8"/>
          <text id="artist" display="songartist" x="0" y="24" w="112" h="8"/>
        </layout>
      </container>
    </WasabiXML>
    """

    // MARK: - The override

    /// The defect itself: the line draws what the script wrote, not the display title.
    func testANonEmptyScriptTextBeatsTheDisplayBinding() throws {
        let (loaded, runtime) = try makeSkin()
        let host = Host()
        let line = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "line").first)

        // Untouched, the binding answers — this is what all 17 lines used to show, forever.
        XCTAssertEqual(WasabiTextMetrics.content(of: line, host: host), "Artist - Title")

        try setText("Dark Side of the Moon", on: line, runtime: runtime)
        XCTAssertEqual(WasabiTextMetrics.content(of: line, host: host), "Dark Side of the Moon")
    }

    /// `setText("")` hands the object back to its binding. MMD3's ticker timer fires exactly this a
    /// second after a `setAlternateText`, and a dozen other skins do the same after a seek or a drag.
    func testEmptyScriptTextRevertsToTheBinding() throws {
        let (loaded, runtime) = try makeSkin()
        let host = Host()
        let line = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "line").first)

        try setText("SEEK: 1:04", on: line, runtime: runtime)
        XCTAssertEqual(WasabiTextMetrics.content(of: line, host: host), "SEEK: 1:04")
        try setText("", on: line, runtime: runtime)
        XCTAssertEqual(WasabiTextMetrics.content(of: line, host: host), "Artist - Title")
    }

    /// The override stands while the bound value moves underneath it — the case that rules out
    /// expiring it on a change. micro's `oldtimer.m` overrides `display="time"` every 20 ms to draw
    /// the old `00:00` format; an expiry would flicker between the two formats.
    func testTheOverrideSurvivesAChangeInTheBoundValue() throws {
        let (loaded, runtime) = try makeSkin()
        let host = Host()
        let line = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "line").first)

        try setText("Wish You Were Here", on: line, runtime: runtime)
        host.trackDisplayTitle = "Another Artist - Another Title"
        XCTAssertEqual(WasabiTextMetrics.content(of: line, host: host), "Wish You Were Here")
    }

    /// Each object owns its override: filling one of Big Bento's 17 lines must not touch the other 16.
    func testTheOverrideIsScopedToTheObjectThatWasWritten() throws {
        let (loaded, runtime) = try makeSkin()
        let host = Host()
        let line = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "line").first)
        let artist = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "artist").first)

        try setText("Breathe", on: line, runtime: runtime)
        XCTAssertEqual(WasabiTextMetrics.content(of: artist, host: host), "Artist")
    }

    // MARK: - What must not change

    /// `setAlternateText` still outranks `setText`: the two are a pair, and MMD3 sets the alternate
    /// *over* a line the ticker script has already written.
    func testAlternateTextStillOutranksScriptText() throws {
        let (loaded, runtime) = try makeSkin()
        let host = Host()
        let ticker = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "ticker").first)
        let reference = MakiObjectReference(.gui(ticker.stableID))

        try setText("Money", on: ticker, runtime: runtime)
        _ = try runtime.invoke(method: "setalternatetext", on: reference,
                               arguments: [.string("VOLUME: 40%")], program: Self.makeProgram())
        XCTAssertEqual(WasabiTextMetrics.content(of: ticker, host: host), "VOLUME: 40%")

        // And `setText` still takes the alternate back down, which is how MMD3 clears it.
        try setText("", on: ticker, runtime: runtime)
        XCTAssertEqual(WasabiTextMetrics.content(of: ticker, host: host), "Artist - Title")
    }

    /// An object with no binding is unaffected: the declared literal shows until a script replaces it,
    /// exactly as before.
    func testAnUnboundObjectStillReadsItsDeclaredText() throws {
        let (loaded, runtime) = try makeSkin()
        let host = Host()
        let plain = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "plain").first)

        XCTAssertEqual(WasabiTextMetrics.content(of: plain, host: host), "declared")
        try setText("written", on: plain, runtime: runtime)
        XCTAssertEqual(WasabiTextMetrics.content(of: plain, host: host), "written")
        try setText("", on: plain, runtime: runtime)
        XCTAssertEqual(WasabiTextMetrics.content(of: plain, host: host), "")
    }

    /// The override lives on a key of its own, so a skin cannot declare one in markup — the same rule
    /// `setAlternateText` follows. `setText` keeps the XML attribute in step for everything that reads
    /// it directly, such as a `<Wasabi:Button>` label.
    func testAMarkupTextAttributeIsNeverAnOverride() throws {
        let (loaded, runtime) = try makeSkin()
        let host = Host()
        let line = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "line").first)

        // Declared in markup on a bound object: not an override, the binding still wins.
        _ = line.setAttribute("text", value: "declared in markup")
        XCTAssertEqual(WasabiTextMetrics.content(of: line, host: host), "Artist - Title")

        try setText("from a script", on: line, runtime: runtime)
        XCTAssertEqual(line.attributes["text"], "from a script")
        XCTAssertEqual(line.attributes[WasabiTextMetrics.scriptTextKey], "from a script")
    }

    /// `getText()` answers what the object shows, so a script that reads a line back — Big Bento's
    /// lyrics finder builds its search query from two of them — gets the value it wrote.
    func testGetTextAnswersTheOverride() throws {
        let (loaded, runtime) = try makeSkin()
        let line = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "line").first)

        try setText("Comfortably Numb", on: line, runtime: runtime)
        let value = try runtime.invoke(method: "gettext", on: MakiObjectReference(.gui(line.stableID)),
                                       arguments: [], program: Self.makeProgram())
        XCTAssertEqual(value.stringValue, "Comfortably Numb")
    }

    // MARK: - Fixture

    private func setText(_ text: String, on object: WasabiObject,
                         runtime: WinampModernScriptRuntime) throws {
        _ = try runtime.invoke(method: "settext", on: MakiObjectReference(.gui(object.stableID)),
                               arguments: [.string(text)], program: Self.makeProgram())
    }

    private func makeSkin() throws -> (WinampModernLoadedSkin, WinampModernScriptRuntime) {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive())
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        return (loaded, runtime)
    }

    private static func makeProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    private func makeArchive() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase64Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(Self.skinXML.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        return url
    }
}
