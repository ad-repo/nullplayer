import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B138 — a cPro player came back from windowshade with a dead grey column where its playlist was.
///
/// Reported as *"there is a bug with cpro skins where when they return from shade view they cannot
/// reclaim the playlist panel empty space… to reproduce simply launch > shade > unshade"*.
///
/// `dispatchResize` has a **vanished-object** path: an id that was in the previous scene but is not
/// among the current targets is read as a pane that collapsed to nothing, and is told
/// `onResize(x, y, 0, 0)` once. That is right for a pane the user closed — it is how Big Bento's side
/// playlist gives its width back — and wrong for a layout the window merely switched away from.
///
/// Shading a cPro player made every object of the **normal** layout look vanished, `centro.playlist1`
/// among them, and `xui/CentroSUI/_v1/scripts/CentroSUI.m` answers exactly that:
///
/// ```maki
/// area_right.onResize(int x, int y, int w, int h){
///     if(w<10){ area_right.hide(); }
///     else    { area_right.show(); }
/// ```
///
/// So the skin hid its own playlist pane, correctly, in response to a resize we should never have
/// sent. Nothing dispatched a second `onResize` to a hidden pane whose width was fine again, so
/// unshading returned a player with the pane's space reserved and nothing drawn in it. Measured in
/// the running app with an attribute-write trace: `group#centro.playlist1 visible: 1 -> 0`, 30 ms
/// after the shade switch, from `dispatchResize`'s vanished branch.
///
/// The fix is a boundary, not a special case: `WinampModernMainView.activateLayout` drops
/// `lastResizeFrames` before anything can dispatch, so the incoming layout is never diffed against
/// the outgoing one. The vanished-object rule itself is untouched and still fires within a layout,
/// which is what the second half of this file holds down.
///
/// Verified in the app on the real archive (`221721-cPro_MMD.wal` + ClassicPro 2.01): a clean launch
/// and two full shade round trips, captured each time and pixel-diffed against the launch state —
/// identical but for the playlist's own ticking time readout.
final class WinampModernB138Tests: XCTestCase {

    // MARK: - The defect

    /// The whole bug in one assertion. Part-way through a layout switch the baseline must already be
    /// empty, because that is the instant a skin's own geometry settle runs a diffing pass — and with
    /// the outgoing layout still in the baseline, every object of it is declared vanished.
    func testALayoutSwitchDropsTheResizeBaselineBeforeAnythingCanDiffAgainstIt() throws {
        let scene = try makeTwoLayoutScene()

        scene.view.activateLayout(id: "normal")
        scene.view.dispatchResizeIfChanged()
        let paneID = try XCTUnwrap(scene.pane.stableID as WasabiObjectID?)
        XCTAssertTrue(scene.view.resizeBaselineForTesting.keys.contains(paneID),
                      "the premise: while `normal` is up, its pane is what a diffing pass compares to")

        var baselineDuringSwitch: [WasabiObjectID: CGRect]?
        scene.view.didBeginLayoutSwitchForTesting = { [weak view = scene.view] in
            baselineDuringSwitch = view?.resizeBaselineForTesting
        }
        scene.view.activateLayout(id: "shade")

        let captured = try XCTUnwrap(baselineDuringSwitch, "the switch must reach the hook")
        XCTAssertTrue(captured.isEmpty,
                      "mid-switch the baseline is empty, so no object of `normal` can be read as "
                      + "having collapsed to nothing")
    }

    /// And the consequence: a switch, in either direction, reports nobody as vanished. Without the
    /// boundary this is where cPro's playlist pane was condemned.
    func testNeitherDirectionOfAShadeRoundTripDeclaresAnObjectVanished() throws {
        let scene = try makeTwoLayoutScene()
        scene.view.activateLayout(id: "normal")
        scene.view.dispatchResizeIfChanged()

        scene.view.activateLayout(id: "shade")
        XCTAssertEqual(scene.scripts.vanishedResizeTargetsForTesting, [],
                       "shading must not tell the normal layout's objects they are 0 wide")

        scene.view.activateLayout(id: "normal")
        XCTAssertEqual(scene.scripts.vanishedResizeTargetsForTesting, [],
                       "and unshading must not do it to the shade layout's")
    }

    // MARK: - What must not change

    /// The vanished-object rule is load-bearing *within* a layout — closing Big Bento's side playlist
    /// leaves the group that reacts to the close outside the scene, and it has to hear the collapse
    /// or the SUI keeps the hole the open playlist left. A fix that simply deleted the branch would
    /// pass everything above and break that, so it is asserted directly.
    func testAPaneThatCollapsesInsideOneLayoutIsStillToldItWentToZero() throws {
        let scene = try makeTwoLayoutScene()
        scene.view.activateLayout(id: "normal")
        scene.view.dispatchResizeIfChanged()
        let paneID = scene.pane.stableID

        // The pane leaves the layout the way a closed one does — its parent collapses, the pane
        // resolves to `0 - 10` and the negative-box rule drops it and its subtree. No layout switch.
        let content = try XCTUnwrap(scene.pane.parent)
        _ = content.setAttribute("relatw", value: "0")
        _ = content.setAttribute("w", value: "0")
        scene.view.dispatchResizeIfChanged()

        XCTAssertTrue(scene.scripts.vanishedResizeTargetsForTesting.contains(paneID),
                      "a pane that collapses inside the active layout still hears its 0x0 resize")
    }

    /// The baseline is dropped, not abandoned: the switch's own seeding dispatch refills it with the
    /// layout that is now up, so the *next* diffing pass has something to compare against.
    func testTheBaselineIsRebuiltForTheLayoutBeingEntered() throws {
        let scene = try makeTwoLayoutScene()
        scene.view.activateLayout(id: "normal")

        let baseline = scene.view.resizeBaselineForTesting
        XCTAssertFalse(baseline.isEmpty, "the seeding dispatch records the new scene")
        XCTAssertTrue(baseline.keys.contains(scene.pane.stableID),
                      "and it is the entered layout's own objects that are in it")
    }

    // MARK: -

    private struct Scene {
        let renderer: WasabiSceneRenderer
        let scripts: WinampModernScriptRuntime
        let view: WinampModernMainView
        /// A group of the `normal` layout — the stand-in for `centro.playlist1`.
        let pane: WasabiObject
    }

    /// cPro's shape, reduced to what the rule turns on: a player with a resizable `normal` layout
    /// holding a pane group, and a short `shade` layout that does not contain it.
    private func makeTwoLayoutScene() throws -> Scene {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="500" h="400" minimum_w="300" minimum_h="100">
              <group id="content" x="0" y="0" w="0" h="0" relatw="1" relath="1">
                <group id="pane" x="0" y="0" w="-10" h="0" relatw="1" relath="1"/>
              </group>
            </layout>
            <layout id="shade" w="500" h="20" minimum_w="300" minimum_h="20" maximum_h="20">
              <group id="shade.content" x="0" y="0" w="0" h="20" relatw="1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let host = TestHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        addTeardownBlock { renderer.teardown() }
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                        componentHost: nil)
        view.setFrameSize(renderer.canvasSize)
        let pane = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "pane").first)
        return Scene(renderer: renderer, scripts: scripts, view: view, pane: pane)
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
            .appendingPathComponent("WinampModernB138Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B138-\(UUID().uuidString).wal")
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
