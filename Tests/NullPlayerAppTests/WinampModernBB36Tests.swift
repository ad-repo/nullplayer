import XCTest
import ZIPFoundation
@testable import NullPlayer

/// BB36 — a window indicator lamp was a click counter, not a window.
///
/// A skin marks its playlist / media-library / EQ / AVS buttons with an `activeimage` meaning *"that
/// window is open"*. After BB26 taught `resolvedBitmapID` to read a button's own `activated`, that is
/// what those lamps drew — and the only thing writing it is `toggleActivation`, which
/// `WinampModernMainView.performAction` calls on every click **alongside** the `TOGGLE` action.
/// Nothing reconciled the two.
///
/// Reported live 2026-08-31: *"across all skins the way the window lights seem to work is that they
/// are reflective of the start state. If the window launches at launch then the toggle gets
/// reversed."* A window already open at launch starts with `activated` unset — dark — so the first
/// click closes the window and lights the lamp, and it stays inverted from then on. Closing the
/// window by its own close button or from a menu desyncs it by a different route.
///
/// **Exposed by BB26, not caused by it.** Before that fix `resolvedBitmapID` ignored `activated`
/// entirely and every one of these lamps was uniformly dark, so the wrong state had nothing to draw
/// itself with. 194 declarations across 31 skins ([M27] in the BB36 archive entry).
///
/// The fix follows the precedent already inside `resolvedBitmapID`: `shuffle`/`repeat` light from
/// `host.shuffleEnabled`/`host.repeatEnabled` and a `cfgattrib` control reads its binding — *a bound
/// control keeps no second copy of state something else owns.* A `TOGGLE` button's lamp asks whether
/// its target window is on screen, through the same routing the click itself takes.
final class WinampModernBB36Tests: XCTestCase {

    /// The shape 194 of the corpus's declarations take: a `TOGGLE` naming a component, with an
    /// `activeimage` that is a claim about that component's window.
    private let playlistLamp = #"<togglebutton id="pl" x="0" y="0" w="20" h="20" action="TOGGLE" param="guid:pl" image="pl.off" activeImage="pl.on"/>"#

    // MARK: - The defect

    /// The reported case: the window is **already open** and the button has never been clicked, so
    /// `activated` is unset. Before the fix that drew the dark artwork.
    func testALampReadsTheWindowNotTheClickCount() throws {
        let scene = try makeScene(id: "pl", button: playlistLamp)
        var playlistIsOpen = true
        scene.view.surfaceVisibilityQuery = { $0 == .playlist ? playlistIsOpen : nil }

        XCTAssertEqual(scene.bitmap(), "pl.on",
                       "a window that is up lights its lamp, clicked or not")

        playlistIsOpen = false
        XCTAssertEqual(scene.bitmap(), "pl.off",
                       "and closing it by any route puts the lamp out")
    }

    /// The other half of the same rule: the button's own `activated` must not survive as a second,
    /// drifting copy on top of the answer. This is the state a click leaves behind —
    /// `toggleActivation` still writes it, because a skin's `onToggle` reads it back.
    func testTheButtonsOwnActivationNoLongerOutranksTheWindow() throws {
        let scene = try makeScene(id: "pl", button: playlistLamp)
        scene.view.surfaceVisibilityQuery = { $0 == .playlist ? false : nil }

        XCTAssertTrue(scene.scripts.toggleActivation(of: scene.button))
        XCTAssertEqual(scene.button.attributes["activated"], "1",
                       "the attribute is still written — multipass's drawer opens from onToggle")
        XCTAssertEqual(scene.bitmap(), "pl.off",
                       "but the window is what the lamp draws, and it is shut")
    }

    /// The container-id road. Roughly half the corpus's declarations name one of the skin's own
    /// containers rather than a component (Defix's `CONF` is `action="TOGGLE" param="Config"`), and a
    /// lamp that answered for only one of the two would replace an inverted indicator with an
    /// arbitrary one.
    func testAContainerIdLampReadsThatContainersWindow() throws {
        let scene = try makeScene(id: "conf", button: #"<togglebutton id="conf" x="0" y="0" w="20" h="20" action="TOGGLE" param="Config" image="conf.off" activeImage="conf.on"/>"#)
        var open = false
        scene.view.containerWindowVisibilityQuery = { $0 == "Config" ? open : nil }

        XCTAssertEqual(scene.bitmap(), "conf.off")
        open = true
        XCTAssertEqual(scene.bitmap(), "conf.on")
    }

    // MARK: - What must not change

    /// Nil is a real answer and the common one: an embedded surface, an in-player holder, or a
    /// container this skin never declared has no open/closed to report. The button keeps its own
    /// `activated` there — which is BB26's behaviour, unchanged.
    func testAnUnanswerableTargetFallsBackToTheButtonsOwnActivation() throws {
        let scene = try makeScene(id: "pl", button: playlistLamp)
        scene.view.surfaceVisibilityQuery = { _ in nil }
        scene.view.containerWindowVisibilityQuery = { _ in nil }

        XCTAssertEqual(scene.bitmap(), "pl.off")
        XCTAssertTrue(scene.scripts.toggleActivation(of: scene.button))
        XCTAssertEqual(scene.bitmap(), "pl.on", "no window to ask, so the click is still the answer")
    }

    /// A button that is not a `TOGGLE` is never asked the question at all. Big Bento's `rate.1…5` are
    /// plain buttons a script activates (BB26), and routing them through a window query would put the
    /// rating row back to five empty dots.
    func testANonToggleButtonIsNotAskedAboutAWindow() throws {
        let scene = try makeScene(id: "rate.1", button: #"<button id="rate.1" x="0" y="0" w="27" h="20" image="rating.empty" activeImage="rating.star"/>"#)
        var asked = false
        scene.view.surfaceVisibilityQuery = { _ in asked = true; return false }
        scene.view.containerWindowVisibilityQuery = { _ in asked = true; return false }

        _ = scene.button.setAttribute("activated", value: "1")
        XCTAssertEqual(scene.bitmap(), "rating.star")
        XCTAssertFalse(asked, "no action=TOGGLE, no window question")
    }

    /// And with no queries installed — the pixel tests, the render harness, and every renderer built
    /// without a window layer — the provider answers nothing and BB26's behaviour stands untouched.
    /// That is why the corpus render sweep stays byte-identical across this change.
    func testARendererWithNoWindowLayerIsUnchanged() throws {
        let scene = try makeScene(id: "pl", button: playlistLamp)

        XCTAssertEqual(scene.bitmap(), "pl.off")
        XCTAssertTrue(scene.scripts.toggleActivation(of: scene.button))
        XCTAssertEqual(scene.bitmap(), "pl.on")
    }

    /// Press and hover are resolved *before* the active branch and must keep outranking it, or a lamp
    /// for an open window would swallow its own click feedback.
    func testPressAndHoverStillOutrankTheWindowsState() throws {
        let scene = try makeScene(id: "pl", button: #"<togglebutton id="pl" x="0" y="0" w="20" h="20" action="TOGGLE" param="guid:pl" image="pl.off" activeImage="pl.on" downImage="pl.down" hoverImage="pl.hover"/>"#)
        scene.view.surfaceVisibilityQuery = { _ in true }

        XCTAssertEqual(scene.renderer.bitmapIDForTesting(scene.button, pressed: true, hovered: false),
                       "pl.down")
        XCTAssertEqual(scene.renderer.bitmapIDForTesting(scene.button, pressed: false, hovered: true),
                       "pl.hover")
        XCTAssertEqual(scene.renderer.bitmapIDForTesting(scene.button, pressed: false, hovered: false),
                       "pl.on")
    }

    // MARK: -

    private struct Scene {
        let renderer: WasabiSceneRenderer
        let scripts: WinampModernScriptRuntime
        let view: WinampModernMainView
        let button: WasabiObject
        let bitmap: () -> String?
    }

    /// One button in one layout, plus the view that installs the lamp provider on the renderer —
    /// which is where the two queries below are read from, so the whole path is exercised.
    private func makeScene(id: String, button markup: String) throws -> Scene {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              \(markup)
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
        let object = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: id).first)
        return Scene(renderer: renderer, scripts: scripts, view: view, button: object,
                     bitmap: { [weak renderer] in
                         renderer?.bitmapIDForTesting(object, pressed: false, hovered: false)
                     })
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
            .appendingPathComponent("WinampModernBB36Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("BB36-\(UUID().uuidString).wal")
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
