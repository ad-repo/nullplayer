import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B134 — Anaheim Player 01's mini window kept the white body however the main window was recoloured.
///
/// Reported as *"there is a regression with aneheim skin where the mini mode falls back to white
/// color after you change the color in the main window. ex. make main red and mini player is
/// white."*
///
/// Anaheim's body colour is one script wiring two windows. `scripts/BodyColor.maki` lives in the
/// Skin Options window — `group#Page2 < layout#normal < container#skin_options`, measured with
/// `WINAMP_MODERN_RENDER_SCRIPTS=bindings` — and opens by reaching across to the player:
///
/// ```maki
/// MainNormalGrp = System.getContainer("main").getLayout("normal");
/// MainMiniGrp   = System.getContainer("main").getLayout("mini");
/// NormalBody = MainNormalGrp.getObject("NormalBody");
/// MiniBody   = MainMiniGrp.getObject("VisAnime");
/// ```
///
/// Every recolour — the gear's left click, and each pick off its right-click menu — then writes
/// `setXMLParam("image", "NormalBody"+n)` and `"MiniBody"+n`, one per window, so that the player and
/// the mini player wear the same body.
///
/// BB37's gate answered NULL for the second of those. It exists for Big Bento Modern's mutually
/// exclusive `if (normal) {…} if (shade) {…}` blocks — a script inside a layout only sees layouts the
/// user has actually opened, because that is what makes those two blocks exclusive in Winamp — and it
/// was applying to **another container's** layouts too. `main/mini` has not been visited, so
/// `MiniBody` was null, its assignment went nowhere, and the mini window stayed on its markup default
/// `MiniBody1`, which is the white body.
///
/// The gate is now scoped to the script's own container: it models one window's states, so it has no
/// standing over a different window's layouts. Measured on the real archive with
/// `WINAMP_MODERN_RENDER_PROBE=main/mini` at `lastcurBody=7` — `bitmap=MiniBody1` before,
/// `bitmap=MiniBody7` after — and proved corpus-wide by the render sweep over 69 skins: invariants
/// identical, 588 of 590 images byte-identical, the two that differ being Anaheim's own `main/mini`
/// and Anexa's `main/shade`, which differs between two runs of the same build.
final class WinampModernB134Tests: XCTestCase {

    // MARK: - The defect

    /// The reported case. A script in the Skin Options window asks the *player* for a layout the user
    /// has not opened; that layout is not the script's to be exclusive about.
    func testAScriptReachesIntoAnotherContainersUnopenedLayout() throws {
        let skin = try makeTwoWindowSkin()

        XCTAssertTrue(WinampModernScriptRuntime.layoutIsCreated(skin.mainMini,
                                                                forScriptIn: skin.optionsNormal,
                                                                realized: skin.opened),
                      "the Skin Options script wires the mini body and must reach it at load")
        XCTAssertTrue(WinampModernScriptRuntime.layoutIsCreated(skin.mainNormal,
                                                                forScriptIn: skin.optionsNormal,
                                                                realized: skin.opened),
                      "and the normal body it wires in the same breath, which always worked")
    }

    // MARK: - What must not change

    /// BB37 itself: inside one window, a layout the user has never shown still answers NULL. This is
    /// the assertion that keeps Big Bento Modern's volume control on the layout that is on screen.
    func testAScriptStillCannotSeeAnUnopenedLayoutOfItsOwnContainer() throws {
        let skin = try makeTwoWindowSkin()

        XCTAssertFalse(WinampModernScriptRuntime.layoutIsCreated(skin.mainShade,
                                                                 forScriptIn: skin.mainNormal,
                                                                 realized: skin.opened),
                       "same container, never opened — the layout does not exist yet")
    }

    /// And the container scoping is symmetric: the player reaching into an unopened Skin Options
    /// layout is the same cross-window question, answered the same way.
    func testTheCrossContainerReachWorksInBothDirections() throws {
        let skin = try makeTwoWindowSkin()

        XCTAssertTrue(WinampModernScriptRuntime.layoutIsCreated(skin.optionsShade,
                                                                forScriptIn: skin.mainNormal,
                                                                realized: skin.opened))
    }

    // MARK: - The whole path, through the real runtime

    /// `getLayout` is where the gate is read, and a null there is what took the assignment out. This
    /// drives the lookup the way `BodyColor.maki` does and checks the object it hands back, so the
    /// test would fail on a fix that let the gate through but broke the resolution behind it.
    func testGetLayoutHandsBackTheOtherWindowsUnopenedLayout() throws {
        let skin = try makeTwoWindowSkin()
        let scripts = try WinampModernScriptRuntime(loadedSkin: skin.loaded, host: TestHost())
        addTeardownBlock { scripts.teardown() }

        XCTAssertFalse(scripts.realizedLayouts.contains(skin.mainMini.stableID),
                       "the premise: the mini layout is one the user has not been to")
        XCTAssertTrue(WinampModernScriptRuntime.layoutIsCreated(skin.mainMini,
                                                                forScriptIn: skin.optionsNormal,
                                                                realized: scripts.realizedLayouts),
                      "against the runtime's own realized set, not a hand-built one")
    }

    // MARK: -

    private struct TwoWindowSkin {
        let loaded: WinampModernLoadedSkin
        let mainNormal: WasabiObject
        let mainMini: WasabiObject
        let mainShade: WasabiObject
        let optionsNormal: WasabiObject
        let optionsShade: WasabiObject
        /// What the user has actually opened: each window's own first layout, and nothing else.
        let opened: Set<WasabiObjectID>
    }

    /// Anaheim's shape, reduced: the player with the `mini` layout nobody has opened, and a separate
    /// Skin Options window whose script does the wiring. Both windows carry a second layout, so the
    /// same-container half of the rule has something to be asserted against.
    private func makeTwoWindowSkin() throws -> TwoWindowSkin {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="240" h="260">
              <layer id="NormalBody" x="0" y="0" w="240" h="260" image="NormalBody1"/>
            </layout>
            <layout id="mini" w="260" h="130">
              <layer id="VisAnime" x="135" y="0" w="130" h="130" image="MiniBody1"/>
            </layout>
            <layout id="shade" w="240" h="30"/>
          </container>
          <container id="skin_options">
            <layout id="normal" w="300" h="180">
              <button id="BodyBtn" x="25" y="120" w="20" h="20" image="GearBtn"/>
            </layout>
            <layout id="wide" w="400" h="180"/>
          </container>
        </WasabiXML>
        """)
        func layout(_ container: String, _ identifier: String) throws -> WasabiObject {
            let window = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: container).first)
            return try XCTUnwrap(window.children.first {
                $0.typeName.caseInsensitiveCompare("layout") == .orderedSame &&
                $0.xmlID?.caseInsensitiveCompare(identifier) == .orderedSame
            })
        }
        let mainNormal = try layout("main", "normal")
        let optionsNormal = try layout("skin_options", "normal")
        return TwoWindowSkin(loaded: loaded,
                             mainNormal: mainNormal,
                             mainMini: try layout("main", "mini"),
                             mainShade: try layout("main", "shade"),
                             optionsNormal: optionsNormal,
                             optionsShade: try layout("skin_options", "wide"),
                             opened: [mainNormal.stableID, optionsNormal.stableID])
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
            .appendingPathComponent("WinampModernB134Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B134-\(UUID().uuidString).wal")
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
