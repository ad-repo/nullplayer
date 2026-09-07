import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 58 — BB16, a layout must not be left with no way to seek.
///
/// Big Bento Modern's `seek.maki` binds all seven of its handlers to `Slider#seeker.ghost`, and its
/// `onLeftButtonUp` calls `hide()` on that same object — a duplicate `findObject("seeker.ghost")`
/// where stock Winamp Modern's script reaches for a *readout* (`player.seekbar.pos`) that does not
/// exist in the layout, making the call a harmless no-op on null there. The skin then mirrors
/// `progressbar` and `player.seek.bg` to the seeker's visibility from `onSetVisible`, so a single
/// press-release took the whole seek bar with it — and because an invisible object is not
/// hit-testable, nothing could ever put it back: seeking stopped working until a track change.
///
/// Defix Hi-END runs the *identical* script and is fine, because its `<Slider id="seeker">` stays
/// visible and still carries the action. That is what the rule keys on — whether the layout still
/// has a visible carrier for the action, not which skin it is.
///
/// Two design points worth keeping:
///
/// - **It settles, it does not veto.** A skin that swaps one control for another writes
///   `a.hide(); b.show();`. At the moment of the hide, `b` is still hidden, so a call-time veto would
///   refuse a perfectly good swap and leave both on screen. The check runs when the outermost event
///   unwinds, by which time `b` is up.
/// - **Only positional actions.** Transport buttons are swapped constantly (`play.hide();
///   pause.show()`) and have a paired counterpart; a seek bar has none. Protecting `PLAY` would
///   restore a play button every time a track started.
final class WinampModernPhase58Tests: XCTestCase {

    // MARK: - The defect

    /// Hiding the only visible SEEK control leaves the layout unable to seek, so it comes back.
    func testHidingTheOnlySeekControlIsUndoneWhenTheEventSettles() throws {
        let (runtime, program) = try makeRuntime(layout: """
        <slider id="seeker.ghost" action="SEEK" x="0" y="80" w="200" h="20"/>
        """)
        let seeker = try object(runtime, "seeker.ghost")
        _ = try runtime.invoke(method: "hide", on: reference(seeker), arguments: [], program: program)
        XCTAssertEqual(seeker.attributes["visible"], "1",
                       "the layout would otherwise have no way to seek, and no way to get one back")
    }

    /// The restore goes back through `setVisible`, so the `onSetVisible(1)` it dispatches is what puts
    /// a skin's mirrored trough and fill back. Asserted on the dispatch record rather than on Bento's
    /// own script, which this fixture does not ship.
    func testTheRestoreDispatchesOnSetVisibleSoAMirrorUndoesItself() throws {
        let (runtime, program) = try makeRuntime(layout: """
        <slider id="seeker.ghost" action="SEEK" x="0" y="80" w="200" h="20"/>
        """)
        runtime.recordsDispatchedEventsForTesting = true
        let seeker = try object(runtime, "seeker.ghost")
        _ = try runtime.invoke(method: "hide", on: reference(seeker), arguments: [], program: program)
        let events = runtime.dispatchedEventsForTesting
            .filter { $0.0 == "seeker.ghost" && $0.1 == "onsetvisible" }
        XCTAssertEqual(events.count, 2, "one for the hide, one for the restore")
    }

    // MARK: - What it must not touch

    /// Defix's shape: a second visible slider carries the same action, so hiding the ghost strands
    /// nothing and the skin's own behaviour stands.
    func testHidingOneOfTwoSeekControlsIsLeftAlone() throws {
        let (runtime, program) = try makeRuntime(layout: """
        <slider id="seeker" action="SEEK" x="0" y="80" w="200" h="20"/>
        <slider id="seeker.ghost" action="SEEK" x="0" y="80" w="200" h="20"/>
        """)
        let ghost = try object(runtime, "seeker.ghost")
        _ = try runtime.invoke(method: "hide", on: reference(ghost), arguments: [], program: program)
        XCTAssertEqual(ghost.attributes["visible"], "0")
    }

    /// The ordering hazard a call-time veto would fail: within one event the skin hides one control
    /// and shows another. Driven through a dispatched event so both writes land inside it.
    func testAHideThenShowSwapInsideOneEventIsNotDisturbed() throws {
        let (runtime, program) = try makeRuntime(layout: """
        <slider id="seek.a" action="SEEK" x="0" y="80" w="200" h="20"/>
        <slider id="seek.b" action="SEEK" x="0" y="80" w="200" h="20" visible="0"/>
        """)
        let a = try object(runtime, "seek.a")
        let b = try object(runtime, "seek.b")
        try runtime.withSimulatedEventForTesting {
            _ = try runtime.invoke(method: "hide", on: reference(a), arguments: [], program: program)
            _ = try runtime.invoke(method: "show", on: reference(b), arguments: [], program: program)
        }
        XCTAssertEqual(a.attributes["visible"], "0", "the swap must stand — b carries the action now")
        XCTAssertEqual(b.attributes["visible"], "1")
    }

    /// Transport buttons are swapped constantly and are deliberately outside the protected set.
    func testHidingTheOnlyPlayButtonIsLeftAlone() throws {
        let (runtime, program) = try makeRuntime(layout: """
        <button id="play" action="PLAY" x="0" y="0" w="20" h="20"/>
        """)
        let play = try object(runtime, "play")
        _ = try runtime.invoke(method: "hide", on: reference(play), arguments: [], program: program)
        XCTAssertEqual(play.attributes["visible"], "0")
    }

    /// An object with no action at all is ordinary furniture.
    func testHidingAPlainLayerIsLeftAlone() throws {
        let (runtime, program) = try makeRuntime(layout: """
        <slider id="seeker.ghost" action="SEEK" x="0" y="80" w="200" h="20"/>
        <layer id="decor" x="0" y="0" w="20" h="20"/>
        """)
        let decor = try object(runtime, "decor")
        _ = try runtime.invoke(method: "hide", on: reference(decor), arguments: [], program: program)
        XCTAssertEqual(decor.attributes["visible"], "0")
    }

    /// Scoped to the layout: the shade layout's own seeker is not a carrier for the normal layout.
    func testACarrierInAnotherLayoutDoesNotCount() throws {
        let (runtime, program) = try makeRuntime(layout: """
        <slider id="seeker.ghost" action="SEEK" x="0" y="80" w="200" h="20"/>
        """, extraLayout: """
        <layout id="shade" w="200" h="20">
          <slider id="shade.seeker" action="SEEK" x="0" y="0" w="200" h="20"/>
        </layout>
        """)
        let seeker = try object(runtime, "seeker.ghost")
        _ = try runtime.invoke(method: "hide", on: reference(seeker), arguments: [], program: program)
        XCTAssertEqual(seeker.attributes["visible"], "1")
    }

    /// A carrier inside a hidden group is not a carrier: the user cannot reach it either.
    func testACarrierInsideAHiddenGroupDoesNotCount() throws {
        let (runtime, program) = try makeRuntime(layout: """
        <slider id="seeker.ghost" action="SEEK" x="0" y="80" w="200" h="20"/>
        <group id="drawer" x="0" y="0" w="200" h="20" visible="0">
          <slider id="hidden.seeker" action="SEEK" x="0" y="0" w="200" h="20"/>
        </group>
        """)
        let seeker = try object(runtime, "seeker.ghost")
        _ = try runtime.invoke(method: "hide", on: reference(seeker), arguments: [], program: program)
        XCTAssertEqual(seeker.attributes["visible"], "1")
    }

    // MARK: - Fixture

    private func reference(_ object: WasabiObject) -> MakiObjectReference {
        MakiObjectReference(.gui(object.stableID))
    }

    private func object(_ runtime: WinampModernScriptRuntime, _ id: String) throws -> WasabiObject {
        try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: id).first)
    }

    private func makeRuntime(layout: String, extraLayout: String = "")
        throws -> (WinampModernScriptRuntime, MakiProgram) {
        let xml = """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="120">
        \(layout)
            </layout>
        \(extraLayout)
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [],
                                  bindings: [], instructions: [],
                                  source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        return (runtime, program)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase58Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase58-\(UUID().uuidString).wal")
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

    private final class Host: WinampModernHost {
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
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
