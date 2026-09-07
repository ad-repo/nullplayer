import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 86 — skin-supplied path ingest (B21) and the three defects that stood between it and any
/// way to exercise it.
///
/// `PlEdit.enqueueFile(path)` and `System.playFile(path)` are the only methods on this seam that take
/// a value the *skin* chose rather than one the host handed out, which is why B21 was filed as a
/// policy question and not an arity one. The policy implemented here grants **ingest, not
/// enumeration**: `findFiles` still answers `-1` and `getFileSize` still `0`, so a script has no way
/// to discover a path — only to hand back one it was given, or one the skin's author or the user
/// typed.
///
/// Reach re-measured 2026-08-29 over the 36 installed `.wal` files: `playFile` in Big Bento Modern
/// and its Windows 10 variant (`progbutton.maki`) and T800 (`quicksongpick.maki`); `enqueueFile` in
/// the shared ClassicPro engine, which the corpus command excludes. The backlog's "cPro-Bento"
/// attribution was wrong — that skin carries no such call.
///
/// The other three are here because each one independently made B21 unobservable, and each is the
/// same shape: a method or a hit test that looks implemented from one side.
final class WinampModernPhase86Tests: XCTestCase {

    // MARK: - B21: what the policy accepts

    /// The happy path for `System.playFile`: an existing regular file in a format the player
    /// supports reaches the host, and asks to be *played* rather than only queued.
    func testPlayFileAcceptsAnExistingSupportedFileAndPlaysIt() throws {
        let (runtime, host, program) = try makeRuntime()
        let file = try makeTempFile(named: "song.mp3")

        _ = try runtime.invoke(method: "playfile", on: MakiObjectReference(.system),
                               arguments: [.string(file.path)], program: program)

        XCTAssertEqual(host.appended.count, 1)
        XCTAssertEqual(host.appended.first?.url.path, file.path)
        XCTAssertEqual(host.appended.first?.play, true)
    }

    /// `PlEdit.enqueueFile` is the same policy with the other answer to "and then play it?". The two
    /// share `skinSuppliedMediaURL`, so the acceptance rules cannot drift apart.
    func testEnqueueFileAppendsWithoutPlaying() throws {
        let (runtime, host, program) = try makeRuntime()
        let file = try makeTempFile(named: "song.flac")

        _ = try runtime.invoke(method: "enqueuefile", on: MakiObjectReference(.playlistEditor),
                               arguments: [.string(file.path)], program: program)

        XCTAssertEqual(host.appended.count, 1)
        XCTAssertEqual(host.appended.first?.play, false)
    }

    /// A stream passes straight through: that is the host's existing ingest and involves no
    /// filesystem at all. T800's memory slots save exactly this — the live QA recorded a Plex
    /// `http://…/file.flac?X-Plex-Token=…` and played it back.
    func testAnHTTPStreamIsAccepted() throws {
        let (runtime, host, program) = try makeRuntime()
        let address = "http://192.168.0.10:32400/library/parts/1/file.flac?X-Plex-Token=abc"

        _ = try runtime.invoke(method: "playfile", on: MakiObjectReference(.system),
                               arguments: [.string(address)], program: program)

        XCTAssertEqual(host.appended.first?.url.absoluteString, address)
    }

    // MARK: - B21: what the policy refuses

    /// Every refusal in one place, because the rule is the *set*: a path the skin names has to be an
    /// absolute POSIX path to an existing regular file in a format the player supports. A directory
    /// with a media extension is the case a bare `fileExists` would wave through.
    func testRefusedPaths() throws {
        let directory = try makeTempDirectory(named: "album.mp3")
        let unsupported = try makeTempFile(named: "notes.txt")
        let missing = directory.deletingLastPathComponent().appendingPathComponent("absent.mp3")

        for path in ["", "   ", "relative/song.mp3", #"C:\Music\song.mp3"#,
                     directory.path, unsupported.path, missing.path,
                     "ftp://example.com/song.mp3", "file:///etc/passwd"] {
            let (runtime, host, program) = try makeRuntime()
            _ = try runtime.invoke(method: "playfile", on: MakiObjectReference(.system),
                                   arguments: [.string(path)], program: program)
            XCTAssertTrue(host.appended.isEmpty, "'\(path)' should not have reached the host.")
        }
    }

    /// **A refusal must not throw.** Both methods are void and Winamp ignores a path it cannot play;
    /// raising here would abandon the rest of the caller's handler over one bad string — the failure
    /// mode that made every other defect in this file invisible.
    func testARefusedPathIsSilentRatherThanFatal() throws {
        let (runtime, _, program) = try makeRuntime()

        XCTAssertNoThrow(try runtime.invoke(method: "playfile", on: MakiObjectReference(.system),
                                            arguments: [.string("/nope/absent.mp3")],
                                            program: program))
        XCTAssertNoThrow(try runtime.invoke(method: "enqueuefile",
                                            on: MakiObjectReference(.playlistEditor),
                                            arguments: [.string("")], program: program))
    }

    /// A refusal is not "demand for an unimplemented method" either. `unsupportedMethodCalls` drives
    /// what gets built next, and counting a rejected path there would report the feature as missing
    /// forever.
    func testARefusedPathIsNotRecordedAsUnsupportedDemand() throws {
        let (runtime, _, program) = try makeRuntime()

        _ = try runtime.invoke(method: "playfile", on: MakiObjectReference(.system),
                               arguments: [.string("/nope/absent.mp3")], program: program)

        XCTAssertNil(runtime.unsupportedMethodCalls["playfile"])
    }

    // MARK: - `MLPlaylists`, the Media Library's saved playlists

    /// The global `std.mi` declares for the playlist manager was never carved out, so the parser
    /// seeded it with the **System** object and every call on it reported the method unsupported.
    /// Big Bento's programmable-button menu died on the first one, `getNumItems`, after building
    /// three submenus — so a right-click looked like a dead button.
    func testThePlaylistManagerGlobalIsBoundByClassRatherThanLeftAsSystem() {
        XCTAssertTrue(MakiClassGUID.runtimeBound.contains(MakiClassGUID.playlistManager))
        // The stored constant is the canonical form and `canonical` is an involution, so folding it
        // again has to give back the raw form the class table carries — the trap recorded in
        // `reference/scripting.md`.
        XCTAssertEqual(MakiClassGUID.canonical(MakiClassGUID.canonical(MakiClassGUID.playlistManager)),
                       MakiClassGUID.playlistManager)
    }

    /// The three methods the corpus reaches, answered from the host's own library.
    func testTheManagerAnswersFromTheHostsSavedPlaylists() throws {
        let (runtime, host, program) = try makeRuntime()
        host.savedPlaylists = ["Late Night", "Those Hills - Anika Nilles"]
        let manager = MakiObjectReference(.playlistManager)

        let count = try runtime.invoke(method: "getnumitems", on: manager, arguments: [],
                                       program: program)
        XCTAssertEqual(count.integerValue, 2)

        let name = try runtime.invoke(method: "getitemname", on: manager,
                                      arguments: [.integer(1)], program: program)
        XCTAssertEqual(name.stringValue, "Those Hills - Anika Nilles")

        _ = try runtime.invoke(method: "playitem", on: manager, arguments: [.integer(0)],
                               program: program)
        XCTAssertEqual(host.playedPlaylistIndex, 0)
    }

    /// An index from a menu the skin built off an earlier snapshot, and an empty library. Neither may
    /// raise: skins guard the whole feature on the count (Big Bento draws "no playlist found"), so an
    /// empty list is a state they already handle and an abort would take the menu with it.
    func testOutOfRangeAndEmptyAreAnsweredRatherThanRaised() throws {
        let (runtime, host, program) = try makeRuntime()
        let manager = MakiObjectReference(.playlistManager)

        XCTAssertEqual(try runtime.invoke(method: "getnumitems", on: manager, arguments: [],
                                          program: program).integerValue, 0)
        XCTAssertEqual(try runtime.invoke(method: "getitemname", on: manager,
                                          arguments: [.integer(7)], program: program).stringValue, "")
        XCTAssertNoThrow(try runtime.invoke(method: "playitem", on: manager,
                                            arguments: [.integer(7)], program: program))
        XCTAssertNil(host.playedPlaylistIndex)
    }

    /// Gated by **class**, not by name. `getNumItems` is already registered globally for a MAKI
    /// `List`, and handing `getItemName`'s arity to every list-like class is the error the
    /// interpreter cannot recover from — a wrong argument count leaves values on the stack and
    /// desynchronises everything after the call.
    func testTheManagersMethodsAreGatedByItsClassGUID() throws {
        let (runtime, _, _) = try makeRuntime()
        let raw = MakiClassGUID.canonical(MakiClassGUID.playlistManager)

        XCTAssertEqual(runtime.signature(for: "getItemName", classGUID: raw)?.argumentCount, 1)
        XCTAssertEqual(runtime.signature(for: "playItem", classGUID: raw)?.argumentCount, 1)
        // The same names on any other class stay unclaimed by this table.
        XCTAssertNil(runtime.signature(for: "getItemName", classGUID: nil))
        XCTAssertNil(runtime.signature(for: "playItem", classGUID: nil))
    }

    // MARK: - A script-bound `<Wasabi:Button>` is under the mouse

    /// `isInteractive` accepted `button`/`togglebutton`/`nstatesbutton`/`slider` by type, and a
    /// `<Wasabi:Button>` only through a label or an `action=`. T800's five `Mem1…Mem5` song slots
    /// carry neither — they are `rectrgn="1"` 4x3 boxes driven entirely from `quicksongpick.maki` —
    /// so `object(at:)` never returned one and every click fell past them onto the layout.
    func testAScriptBoundWasabiButtonTakesTheClick() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="177" h="400" default_w="177" default_h="400">
          <Wasabi:Button id="Mem1" x="17" y="121" w="4" h="3" rectrgn="1" alpha="5"
                         tooltip="Saved Song 1"/>
        </layout>
        """)

        let hit = renderer.object(at: CGPoint(x: 19, y: 122))
        XCTAssertEqual(hit?.xmlID, "Mem1")
    }

    /// The regression this fix invites, and the reason it belongs in `isInteractive` rather than in
    /// `hasOwnCommand` beside it: Styx's title strip is a `<Wasabi:button move="1">` and dragging the
    /// window by it must keep working. `hasOwnCommand` decides that, and a `Wasabi:Button` with no
    /// command of its own is still a drag surface.
    func testAWasabiButtonTitleStripStillDragsTheWindow() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="400" h="200" default_w="400" default_h="200">
          <Wasabi:button id="top.middle" x="120" y="0" w="200" h="50" move="1" tile="1"
                         tooltip="Double click to maximize/restaure window"/>
        </layout>
        """)
        // `objectOverridingDivider` is the renderer-side reading of `hasOwnCommand`: it ignores a
        // surface whose only interactivity is `move="1"`, which is exactly "this drags the window".
        // A `Wasabi:Button` that had gained a command of its own would stop being ignored here.
        XCTAssertNil(renderer.objectOverridingDivider(at: CGPoint(x: 200, y: 25)))
    }

    // MARK: - `AnimatedLayer.isStopped()`

    /// The pair that looked complete. `isPlaying` was implemented for animated layers, and
    /// `isStopped` — the same receiver, pinned by `RENDER_DISASM` showing `play()` taking it too —
    /// was not, so T800's jaw animation aborted on it every time the button under the mouth was
    /// pressed. It reads like a transport question and is not one.
    func testAnAnimatedLayerAnswersIsStoppedAsTheInverseOfIsPlaying() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="177" h="400" default_w="177" default_h="400">
          <AnimatedLayer id="animationlayer" x="61" y="244" w="91" h="40" autoplay="0"/>
        </layout>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: renderer.loadedSkin, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        let layer = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "animationlayer").first)
        let program = Self.emptyProgram
        let reference = MakiObjectReference(.gui(layer.stableID))

        func ask(_ method: String) throws -> Bool {
            try runtime.invoke(method: method, on: reference, arguments: [], program: program).truthy
        }

        // `autoplay="0"` and nothing has played it yet.
        XCTAssertTrue(try ask("isstopped"))
        XCTAssertFalse(try ask("isplaying"))

        _ = try runtime.invoke(method: "play", on: reference, arguments: [], program: program)
        XCTAssertFalse(try ask("isstopped"))
        XCTAssertTrue(try ask("isplaying"))
    }

    // MARK: - Fixtures

    private static let emptyProgram = MakiProgram(
        version: 0x0403, classes: [], methods: [], variables: [], bindings: [], instructions: [],
        source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"), ownerID: nil, parameter: nil)

    private func makeRuntime() throws -> (WinampModernScriptRuntime, TestComponentHost, MakiProgram) {
        let loaded = try load(layout: """
        <layout id="normal" w="100" h="100" default_w="100" default_h="100"/>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        let host = TestComponentHost()
        runtime.componentHost = host
        return (runtime, host, Self.emptyProgram)
    }

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let renderer = try WasabiSceneRenderer(loadedSkin: try load(layout: layout), host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func load(layout: String) throws -> WinampModernLoadedSkin {
        let url = try makeArchive(xml: """
        <WasabiXML>
          <container id="main">
            \(layout)
          </container>
        </WasabiXML>
        """)
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = try makeTempDirectory(named: "archive")
        let url = directory.appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        return url
    }

    private func makeTempDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase86Tests-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return directory
    }

    private func makeTempFile(named name: String) throws -> URL {
        let directory = try makeTempDirectory(named: "media")
        let file = directory.appendingPathComponent(name)
        try Data("not really audio".utf8).write(to: file)
        return file
    }

    /// Records what the seam was asked for. The runtime owns the policy, so a call reaching here at
    /// all is the assertion.
    private final class TestComponentHost: WinampModernComponentHost {
        var appended: [(url: URL, play: Bool)] = []
        var savedPlaylists: [String] = []
        var playedPlaylistIndex: Int?

        func playlistAppend(mediaAt url: URL, play: Bool) { appended.append((url, play)) }
        func savedPlaylistNames() -> [String] { savedPlaylists }
        func playSavedPlaylist(at index: Int) {
            guard savedPlaylists.indices.contains(index) else { return }
            playedPlaylistIndex = index
        }

        func playlistSnapshot() -> WinampModernPlaylistSnapshot {
            WinampModernPlaylistSnapshot(rows: [], currentIndex: -1, selectedIndex: -1)
        }
        func playlistSelect(row: Int) {}
        func playlistPlay(row: Int) {}
        func playlistRemove(row: Int) {}
        func equalizerSnapshot() -> WinampModernEQSnapshot { .flat }
        func equalizerSetBandGainDB(_ band: Int, gainDB: Float) {}
        func equalizerSetPreampDB(_ gainDB: Float) {}
        func equalizerSetEnabled(_ enabled: Bool) {}
        func equalizerSetAuto(_ enabled: Bool) {}
        func equalizerApplyPreset(named name: String) {}
        func toggleClassicWindow(for kind: WinampModernComponentKind) {}
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
        var spectrumLevels: [Float] = []

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to time: TimeInterval) {}
        func setVolume(_ volume: Double) {}
        func toggleShuffle() {}
        func toggleRepeat() {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
