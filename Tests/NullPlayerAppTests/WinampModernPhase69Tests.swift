import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 69 (BENTO_TASKS BB27) — the track-change notifier lays itself out.
///
/// Reported live against all four Big Bento variants as *"the notifications are using a giant font
/// and it is all jumbled"*, then *"the space within the notification to write is only like the
/// middle 1/3 of the notification window — I have noticed this on other skins"*. Four separate
/// defects, none of them about fonts, and three of them engine-wide rather than notifier-shaped.
///
/// The skin does all of this work itself. Bento's `notifier.maki` starts a 30 ms poll from
/// `onTitleChange`; the poll reads its four `Notifications` settings, hides the album line or the
/// transport row, moves the text group, measures the result with `getAutoWidth`, and then sizes and
/// positions its own window. What was wrong was everything the engine did with those requests:
///
/// 1. **A `<text>` with no `h` was zero pixels tall** and clipped to nothing. Bento's `title`,
///    `artist` and `album` are all declared that way, so the toast drew none of them until the host
///    pasted a height on (`ensureTextHeight`, `fontsize * 1.4`) — 18px taller than the rows the skin
///    is spaced for, which is the reported overlap. Now the renderer gives a heightless `<text>` its
///    font's line height, the same number `getAutoHeight()` answers.
/// 2. **A container's own geometry never left the graph.** `resize()` forwarded to the window only
///    for a *layout* receiver and the `setTargetX/Y/W/H` animation had no container path at all, so
///    the toast stayed at its declared 540 with the text pinned inside the third of it the XML
///    reserves for album art the script had already hidden.
/// 3. **`isDesktopAlphaAvailable()` answered true.** A skin asks once, takes
///    `getLayout("desktopalpha")` and addresses that layout forever after — it never switches to it,
///    because in Winamp the container is already on it. Nothing here activates such a layout, so
///    every write landed on a layout no window draws. This is the one that made the headless render
///    perfect while the live app was visibly unchanged.
/// 4. **The host clamped every notifier to 350px wide**, a number chosen for stock Winamp Modern
///    (`w="128"`, text group 33px). 350 is a floor now, never a size.
final class WinampModernPhase69Tests: XCTestCase {

    // MARK: - A `<text>` with no `h` is one line tall

    /// The defect, at its smallest: `fontsize="46"` with no `h` resolved to a 0-height box, and the
    /// renderer clips to the frame, so the string was absent from a scene that otherwise looked
    /// right. A skin that declares a height still gets exactly what it declared.
    func testAHeightlessTextSizesToItsFontsRatherThanToNothing() throws {
        let renderer = try makeRenderer(layout: """
          <text id="auto" x="0" y="0" w="200" fontsize="46" text="Song"/>
          <text id="declared" x="0" y="0" w="200" h="12" fontsize="46" text="Song"/>
        """)
        XCTAssertEqual(try frame(of: "auto", in: renderer).height, 46)
        XCTAssertEqual(try frame(of: "declared", in: renderer).height, 12)
    }

    /// The rows the notifier is spaced for. Bento stacks `title` at `y="22"` (46pt) over `artist` at
    /// `y="64"` (34pt, `h="66"`, `valign="top"`) over its transport group at `y="100"`, and the whole
    /// arrangement only works if the title occupies one line. The old `fontsize * 1.4` gave it 64
    /// pixels — down to `y=86`, 22 past where the artist starts — which is the overlap in the report.
    func testTheTitleNoLongerRunsDownIntoTheArtistBeneathIt() throws {
        let renderer = try makeRenderer(layout: """
          <text id="title" x="0" y="22" w="200" fontsize="46" text="Song"/>
          <text id="artist" x="0" y="64" w="200" h="66" fontsize="34" valign="top" text="Artist"/>
        """)
        let title = try frame(of: "title", in: renderer)
        let artist = try frame(of: "artist", in: renderer)
        XCTAssertEqual(title.maxY, 68)
        XCTAssertLessThanOrEqual(title.maxY, artist.minY + 4,
                                 "the title box must not reach into the artist row")
        XCTAssertEqual(ceil(46 * 1.4), 65, "the height the removed host patch used, for the record")
    }

    /// Only `<text>` auto-sizes. A layer or a group with no `h` keeps taking its height from its
    /// artwork or from nothing, which is what every other object in the corpus is laid out against.
    func testOnlyTextTakesAFontsHeight() throws {
        let renderer = try makeRenderer(layout: """
          <group id="box" x="0" y="0" w="200" fontsize="46"/>
        """)
        XCTAssertEqual(try frame(of: "box", in: renderer).height, 0)
    }

    // MARK: - Desktop alpha

    /// Split from its three neighbours deliberately: those are about a *window's* alpha and stay
    /// true. This one is about a second layout built from a second set of artwork, and answering it
    /// truthfully is what puts a skin's layout work on the layout that is actually on screen.
    func testDesktopAlphaIsRefusedWhileTheOtherTransparencyQuestionsAreNot() throws {
        let (runtime, program) = try makeRuntime()
        XCTAssertFalse(try ask(runtime, program, "isDesktopAlphaAvailable"))
        XCTAssertTrue(try ask(runtime, program, "isTransparencyAvailable"))
        XCTAssertTrue(try ask(runtime, program, "isTransparencySafe"))
        XCTAssertTrue(try ask(runtime, program, "isLayoutAnimationSafe"))
    }

    // MARK: - A container's geometry reaches its window

    /// `container.resize(x, y, w, h)` — the call Bento's notifier makes before it animates into the
    /// corner. The size is the window's and the position is on the desktop, so neither is readable
    /// back out of the scene: both have to be handed to the host.
    func testResizingAContainerMovesAndSizesItsWindow() throws {
        let (runtime, program) = try makeRuntime()
        var size: CGSize?
        var origin: CGPoint?
        runtime.layoutResizeRequested = { _, requested in size = requested }
        runtime.containerMoveRequested = { _, point, _ in origin = point }

        let container = try XCTUnwrap(object(runtime, type: "container", id: "main"))
        _ = try runtime.invoke(method: "resize", on: MakiObjectReference(.gui(container.stableID)),
                               arguments: [.integer(1207), .integer(928), .integer(711), .integer(150)],
                               program: program)

        XCTAssertEqual(size, CGSize(width: 711, height: 150))
        XCTAssertEqual(origin, CGPoint(x: 1207, y: 928))
    }

    /// The other half of the same request. Winamp's notifier grows into place rather than jumping, so
    /// the final geometry arrives through `setTargetW`/`gotoTarget` and not through `resize` at all —
    /// a `resize`-only fix would have left the toast at whatever size it started the animation from.
    /// `targetspeed="0"` takes the animation's instant path, which is the one a test can settle on.
    func testATargetAnimationOnAContainerReachesTheWindowToo() throws {
        let (runtime, program) = try makeRuntime()
        var size: CGSize?
        var origin: CGPoint?
        runtime.layoutResizeRequested = { _, requested in size = requested }
        runtime.containerMoveRequested = { _, point, _ in origin = point }

        let container = try XCTUnwrap(object(runtime, type: "container", id: "main"))
        let target = MakiObjectReference(.gui(container.stableID))
        for (method, value) in [("setTargetX", 1207), ("setTargetY", 928),
                                ("setTargetW", 711), ("setTargetH", 150)] {
            _ = try runtime.invoke(method: method, on: target,
                                   arguments: [.integer(Int32(value))], program: program)
        }
        _ = try runtime.invoke(method: "setTargetSpeed", on: target,
                               arguments: [.double(0)], program: program)
        _ = try runtime.invoke(method: "gotoTarget", on: target, arguments: [], program: program)

        XCTAssertEqual(size, CGSize(width: 711, height: 150))
        XCTAssertEqual(origin, CGPoint(x: 1207, y: 928))
    }

    /// A plain object is not a window, and its `x`/`y`/`w`/`h` are read back out of the scene like
    /// everything else. Sending those to the host would move whichever window it happened to be in.
    func testAnObjectInsideALayoutIsNotAWindow() throws {
        let (runtime, program) = try makeRuntime()
        var moved = false
        runtime.containerMoveRequested = { _, _, _ in moved = true }
        let text = try XCTUnwrap(object(runtime, type: "text", id: "title"))
        _ = try runtime.invoke(method: "resize", on: MakiObjectReference(.gui(text.stableID)),
                               arguments: [.integer(0), .integer(0), .integer(10), .integer(10)],
                               program: program)
        XCTAssertFalse(moved)
    }

    // MARK: - The notifier width floor

    /// 350 exists for stock Winamp Modern, whose notifier layout declares `w="128"` and hangs a
    /// `w="-95" relatw="1"` text group inside it — 33 pixels, too narrow for a song title. It must
    /// never *shrink* a skin that already declares a usable width: Bento's 540 became 120 pixels of
    /// room for 46pt text, which is the "giant font" in the first report.
    func testTheNotifierWidthIsAFloorAndNotASize() throws {
        for (declared, expected) in [(128, 350), (350, 350), (540, 540)] {
            let runtime = try makeNotifierRuntime(layoutWidth: declared)
            var size: CGSize?
            runtime.layoutResizeRequested = { _, requested in size = requested }
            runtime.setNotifierText(title: "Song", artist: "Artist", album: "Album")
            XCTAssertEqual(size?.width, CGFloat(expected),
                           "a notifier declaring \(declared) must end up \(expected) wide")
        }
    }

    /// The host still owns the *text*, because the skins' own timer-driven text chains do not
    /// reliably run — and it must not leave the XML's placeholder behind it, which the renderer would
    /// resolve as `text ?? default` and draw as ghost text under a shorter title.
    func testTheHostOverwritesBothTheTextAndItsPlaceholder() throws {
        let runtime = try makeNotifierRuntime(layoutWidth: 540)
        runtime.setNotifierText(title: "Song", artist: "Artist", album: "Album")
        let title = try XCTUnwrap(object(runtime, type: "text", id: "title"))
        XCTAssertEqual(title.attributes["text"], "Song")
        XCTAssertEqual(title.attributes["default"], "Song")
    }

    // MARK: - Helpers

    /// The graph, walked. The runtime's own root lookup is private, and a test that reached for it
    /// would be asserting against a helper rather than against the object the skin declared.
    private func object(_ runtime: WinampModernScriptRuntime, type: String, id: String) -> WasabiObject? {
        func walk(_ objects: [WasabiObject]) -> WasabiObject? {
            for object in objects {
                if object.typeName.caseInsensitiveCompare(type) == .orderedSame,
                   object.xmlID?.caseInsensitiveCompare(id) == .orderedSame { return object }
                if let match = walk(object.children) { return match }
            }
            return nil
        }
        return walk(runtime.loadedSkin.runtime.graph.roots)
    }

    private func ask(_ runtime: WinampModernScriptRuntime, _ program: MakiProgram,
                     _ method: String) throws -> Bool {
        try runtime.invoke(method: method, on: MakiObjectReference(.system),
                           arguments: [], program: program).truthy
    }

    private func frame(of id: String, in renderer: WasabiSceneRenderer) throws -> CGRect {
        try XCTUnwrap(renderer.sceneNodes()
            .first { $0.object.xmlID?.caseInsensitiveCompare(id) == .orderedSame }?.frame,
                      "no scene node for \(id)")
    }

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="300" h="200">
        \(layout)
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, MakiProgram) {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="300" h="200">
              <text id="title" x="0" y="0" w="200" fontsize="20" text="Song"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        return (try makeRuntime(loaded: loaded), Self.syntheticProgram)
    }

    private func makeNotifierRuntime(layoutWidth: Int) throws -> WinampModernScriptRuntime {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="notifier">
            <layout id="normal" w="\(layoutWidth)" h="80">
              <text id="title" x="0" y="0" w="-95" relatw="1" fontsize="17" default="Nithin Sawhney"/>
              <text id="artist" x="0" y="20" w="-95" relatw="1" fontsize="13" default="Prophesy"/>
              <text id="album" x="0" y="40" w="-95" relatw="1" fontsize="13" default="Prophesy"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        return try makeRuntime(loaded: loaded)
    }

    private func makeRuntime(loaded: WinampModernLoadedSkin) throws -> WinampModernScriptRuntime {
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private static let syntheticProgram = MakiProgram(
        version: 0x0403, classes: [], methods: [], variables: [], bindings: [], instructions: [],
        source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"), ownerID: nil, parameter: nil)

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase69Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase69-\(UUID().uuidString).wal")
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

    private final class TestHost: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var trackDisplayTitle = ""
        var bitrateKbps = 0
        var sampleRateHz = 0
        var channelCount = 2
        var spectrumLevels: [Float] = []
        var isArtworkLoading = false
        var vuLevels: (left: Double, right: Double) = (0, 0)

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
