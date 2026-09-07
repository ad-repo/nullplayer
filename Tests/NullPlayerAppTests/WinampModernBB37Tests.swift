import XCTest
import ZIPFoundation
@testable import NullPlayer

/// BB37 — Big Bento Modern had no working volume control, because every one of its volume bindings
/// had been stolen by the layout the user cannot see.
///
/// Reported live 2026-09-02: *"there is a bug where big bento skins where you cant adjut the volume.
/// there is no control for it."*
///
/// The skin's volume is a ring around a volume icon; clicking the icon toggles a slider panel out of
/// the player (`volclick.maki`), and `volumebyframe.maki` turns the ring into a level readout. Every
/// one of those scripts opens the same way:
///
/// ```maki
/// normal = getContainer("main").getLayout("normal");
/// shade  = getContainer("main").getLayout("shade");
/// if (normal) { vol = normal.findObject("vol.on"); ... }   // block 1
/// if (shade)  { vol = shade.findObject("vol.on");  ... }   // block 2
/// ```
///
/// Two blocks over **the same variables**, guarded so that only one can run — which is only true if
/// a layout that has never been shown answers NULL. Winamp builds a container's layouts on demand,
/// so at load `getLayout("shade")` is NULL and block 1 stands. We build every layout up front, so
/// both blocks ran, block 2 won, and the bindings landed on the shade layout's objects. Measured
/// with `WINAMP_MODERN_RENDER_SCRIPTS=bindings`: **89 of the skin's bindings pointed into
/// `layout#shade`**, including the `onLeftButtonUp` that opens the volume panel, the mute buttons,
/// the play/pause animation and the album-art wiring. Clicking the volume icon in the visible player
/// dispatched to nothing — `RENDER_CLICK` reported `hits button#vol.on bindings=false`, seven
/// handler counts of zero.
///
/// The fix is scoped to **a script that lives inside a layout**, which is the only script that can be
/// speaking about one window state. A skin-level `<scripts>` block keeps seeing every layout: that is
/// often the only place a skin wires its *other* layouts from — multipass's `skin.xml` wires normal
/// and shade together into separate variables — and gating it too cost 236 (event, object) pairs
/// across the corpus's shade and stick layouts to buy nothing.
///
/// Corpus sweep over all 62 archives, against a baseline worktree at `HEAD`: **14 (event, object)
/// pairs gained, none lost**, and 547 of 552 rendered PNGs byte-identical — the five that differ are
/// the four Big Bento variants' `main/normal` (the volume panel, now in the layout that is on screen)
/// and Anexa's `main/shade`, which differs between two runs of the *same* build.
final class WinampModernBB37Tests: XCTestCase {

    // MARK: - The defect

    /// The reported case. A script inside `normal` asks for `shade`, which has never been shown.
    /// Before the fix it got the layout and overwrote everything block 1 had just resolved.
    func testAScriptInOneLayoutCannotSeeALayoutThatHasNeverBeenShown() throws {
        let skin = try makeTwoLayoutSkin()

        XCTAssertTrue(WinampModernScriptRuntime.layoutIsCreated(skin.normal,
                                                                forScriptIn: skin.normal,
                                                                realized: [skin.normal.stableID]),
                      "its own layout is the one it is running in")
        XCTAssertFalse(WinampModernScriptRuntime.layoutIsCreated(skin.shade,
                                                                 forScriptIn: skin.normal,
                                                                 realized: [skin.normal.stableID]),
                       "the layout the user has never opened does not exist yet")
    }

    /// The other instance of the same script — the copy inside the shade layout — must still resolve
    /// its own objects, or the fix would simply move the dead control from one layout to the other.
    func testTheShadeCopyOfTheSameScriptStillResolvesItsOwnLayout() throws {
        let skin = try makeTwoLayoutSkin()

        XCTAssertTrue(WinampModernScriptRuntime.layoutIsCreated(skin.shade,
                                                                forScriptIn: skin.shade,
                                                                realized: [skin.normal.stableID]),
                      "block 2 runs for the shade copy, which is what makes shade mode work")
        XCTAssertTrue(WinampModernScriptRuntime.layoutIsCreated(skin.normal,
                                                               forScriptIn: skin.shade,
                                                               realized: [skin.normal.stableID]),
                      "and block 1 runs too, exactly as in Winamp — block 2 then wins, as intended")
    }

    // MARK: - What must not change

    /// A skin-level `<scripts>` block has no layout of its own to speak from, and is left alone.
    /// multipass wires its shade and stick layouts from exactly such a script.
    func testASkinLevelScriptStillSeesEveryLayout() throws {
        let skin = try makeTwoLayoutSkin()

        XCTAssertTrue(WinampModernScriptRuntime.layoutIsCreated(skin.shade,
                                                                forScriptIn: nil,
                                                                realized: [skin.normal.stableID]),
                      "no layout scope, no gate")
    }

    /// Once the user has actually been to a layout it exists, and a script anywhere may reach it.
    func testALayoutThatHasBeenShownAnswersEveryone() throws {
        let skin = try makeTwoLayoutSkin()

        XCTAssertTrue(WinampModernScriptRuntime.layoutIsCreated(skin.shade,
                                                                forScriptIn: skin.normal,
                                                                realized: [skin.normal.stableID,
                                                                           skin.shade.stableID]))
    }

    // MARK: - The realized set

    /// The container's opening layout is realized before a single script runs, or `getLayout("normal")`
    /// — which nearly every skin in the corpus opens with — would answer NULL at load.
    func testTheOpeningLayoutIsRealizedAtStartup() throws {
        let skin = try makeTwoLayoutSkin()
        let scripts = try WinampModernScriptRuntime(loadedSkin: skin.loaded, host: TestHost())
        addTeardownBlock { scripts.teardown() }

        XCTAssertTrue(scripts.realizedLayouts.contains(skin.normal.stableID),
                      "`normal` is what the window comes up in")
        XCTAssertFalse(scripts.realizedLayouts.contains(skin.shade.stableID))
    }

    /// A container that names no `normal` still gets one, or every layout it has would answer NULL to
    /// its own scripts' first lookup.
    func testAContainerWithNoNormalLayoutFallsBackToItsFirst() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="big" w="200" h="200"/>
            <layout id="small" w="100" h="100"/>
          </container>
        </WasabiXML>
        """)
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { scripts.teardown() }
        let big = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "big").first)

        XCTAssertTrue(scripts.realizedLayouts.contains(big.stableID))
    }

    /// The host switching a window to another layout creates it, so a script that reaches across
    /// afterwards finds it — and `getCurLayout` follows the window rather than staying at load state.
    func testTheHostSwitchingLayoutsRealizesTheNewOne() throws {
        let skin = try makeTwoLayoutSkin()
        let scripts = try WinampModernScriptRuntime(loadedSkin: skin.loaded, host: TestHost())
        addTeardownBlock { scripts.teardown() }

        scripts.markLayoutRealized(skin.shade)

        XCTAssertTrue(scripts.realizedLayouts.contains(skin.shade.stableID))
        XCTAssertEqual(scripts.activeLayoutByContainer[skin.container.stableID], skin.shade.stableID)
    }

    /// And anything that is not a layout is ignored, so a stray call cannot poison the set.
    func testOnlyALayoutCanBeRealized() throws {
        let skin = try makeTwoLayoutSkin()
        let scripts = try WinampModernScriptRuntime(loadedSkin: skin.loaded, host: TestHost())
        addTeardownBlock { scripts.teardown() }
        let before = scripts.realizedLayouts

        scripts.markLayoutRealized(skin.container)

        XCTAssertEqual(scripts.realizedLayouts, before)
    }

    // MARK: -

    private struct TwoLayoutSkin {
        let loaded: WinampModernLoadedSkin
        let container: WasabiObject
        let normal: WasabiObject
        let shade: WasabiObject
    }

    /// Big Bento's shape, reduced: one container, a `normal` the window opens in and a `shade` it
    /// does not, each carrying an object with the same id — which is what the two blocks resolve.
    private func makeTwoLayoutSkin() throws -> TwoLayoutSkin {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <button id="vol.on" x="0" y="0" w="20" h="20" image="vol"/>
            </layout>
            <layout id="shade" w="200" h="40">
              <button id="vol.on" x="0" y="0" w="20" h="20" image="vol"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        return TwoLayoutSkin(loaded: loaded,
                             container: try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "main").first),
                             normal: try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "normal").first),
                             shade: try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "shade").first))
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
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernBB37Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("BB37-\(UUID().uuidString).wal")
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
}
