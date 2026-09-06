import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B142 — cPro Venus drew its playback buttons jammed against the left edge of the window.
///
/// Reported with the skin's own reference shot beside ours: the transport cluster, its backing plate
/// and the venus wordmark all sat far left of centre at every window width.
///
/// The skin centres them from a script. `<group id="c.buttons.centered" x="20" y="-20"
/// fitparent="1"/>` holds the whole cluster, and `cbuttonsc.maki` answers the layout's own resize
/// with `g_buttons.setXmlParam("x", integerToString(w/2-112))`. We answered `fitparent="1"` with the
/// parent's box outright — origin included — so the write had nowhere to land.
///
/// Three rules, and all three are Wasabi's:
///
/// - `fitparent` is a **size**. The object is as big as its parent and its own `w`/`h` do not get a
///   say: ClassicPro's whole SUI is `<Centro:SUI fitparent="1" h="100"/>`, and reading that `h` as
///   `parentHeight + 100` (which is what `fitparent`'s implied `relath="1"` would make it) grew the
///   component pane past its frame and pushed the playlist's ADD/REM/SEL bar out of the window.
/// - It says nothing about **where** the object sits, so `x`/`y` — declared or written by a script —
///   place it. That is the reported defect.
/// - It is applied where the tag writes it, so geometry earlier in the same tag is geometry Winamp
///   discarded. Venus's `y="-20"` is that case: kept, it lifted the group clear of the window and
///   clipped 10px off the top of the venus wordmark in the titlebar.
///
/// Plus the one that kept the song title in its display: geometry attributes are no longer delivered
/// as XUI params. Wasabi hands a tag's attributes to the object first and scripts only what it
/// leaves unclaimed, which is why ClassicPro's `ModernSongticker.maki` can forward everything it is
/// given straight to the `<SongTicker fitparent="1"/>` inside its group. Handed the group's own
/// `x="25" y="78" w="-53"` as well, the ticker left the display and landed over the buttons.
final class WinampModernB142Tests: XCTestCase {

    // MARK: - The defect

    /// The reported symptom, in the shape Venus writes it: a parent-sized group a script slides
    /// sideways.
    func testAScriptCanSlideAFitParentGroup() throws {
        let renderer = try makeRenderer()
        let group = try XCTUnwrap(object(withID: "buttons", in: renderer))

        XCTAssertEqual(frame(of: "plate", in: renderer)?.minX, 18,
                       "the premise: with no offset written, the cluster sits at its own x")

        // What `cbuttonsc.maki` writes from `onResize`: w/2 - 112 for a 600-wide layout.
        _ = group.setAttribute("x", value: "188")

        XCTAssertEqual(frame(of: "buttons", in: renderer)?.minX, 188,
                       "the group takes the offset the script wrote")
        XCTAssertEqual(frame(of: "plate", in: renderer)?.minX, 206,
                       "and the cluster inside it moves with it — 188 + its own 18")
    }

    /// The size half is unchanged: a `fitparent` group is still exactly as big as its parent, so the
    /// children that anchor to its right and bottom edges land where they always did.
    func testAFitParentGroupIsStillTheSizeOfItsParent() throws {
        let renderer = try makeRenderer()

        XCTAssertEqual(frame(of: "buttons", in: renderer)?.size, CGSize(width: 600, height: 400))

        let group = try XCTUnwrap(object(withID: "buttons", in: renderer))
        _ = group.setAttribute("x", value: "188")
        XCTAssertEqual(frame(of: "buttons", in: renderer)?.size, CGSize(width: 600, height: 400),
                       "sliding it does not resize it")
    }

    /// `<Centro:SUI fitparent="1" h="100"/>` — a stated size loses to `fitparent`, rather than being
    /// added to the parent's. This is what pushed ClassicPro's playlist buttons out of the window.
    func testAStatedSizeLosesToFitParent() throws {
        let renderer = try makeRenderer()

        XCTAssertEqual(frame(of: "sui", in: renderer)?.height, 400,
                       "`h=\"100\"` alongside `fitparent` is the parent's height, not 500")
    }

    /// `y="-20"` written *before* `fitparent` in Venus's own tag is discarded, which is what keeps
    /// the wordmark inside the titlebar rather than 10px above the top of the window.
    func testGeometryWrittenBeforeFitParentIsDiscarded() throws {
        let renderer = try makeRenderer()

        XCTAssertEqual(frame(of: "buttons", in: renderer)?.minY, 0,
                       "the group starts at the top of its parent, not at -20")
        XCTAssertEqual(frame(of: "wordmark", in: renderer)?.minY, 10,
                       "so the wordmark draws at its own y inside the window")
    }

    /// The same tag's geometry written *after* `fitparent` is the author's and stands — the position
    /// half of `<group id="bars" fitparent="1" x="4" y="10"/>` (Ebonite's equalizer).
    func testGeometryWrittenAfterFitParentStands() throws {
        let renderer = try makeRenderer()

        XCTAssertEqual(frame(of: "inset", in: renderer)?.origin, CGPoint(x: 4, y: 10))
    }

    // MARK: - XUI params

    /// A `GuiObject` answers its own geometry, so a XUI wrapper's script never hears it — and cannot
    /// forward it onto the control it wraps.
    func testGeometryIsNotDeliveredAsAXUIParam() {
        for name in ["x", "y", "w", "h", "relatx", "relaty", "relatw", "relath"] {
            XCTAssertTrue(WinampModernScriptRuntime.isConsumedBeforeXUIParams(name),
                          "\(name) is the object's own business")
        }
    }

    /// Everything else still reaches the script. `ModernSongticker.maki` forwards `font`, `align` and
    /// `color` onto its ticker on purpose — a `<group>` has no use for them, and that forwarding is
    /// the whole point of the tag.
    func testNonGeometryParamsAreStillDelivered() {
        for name in ["font", "align", "color", "fontsize", "showlen", "ghost_all", "id_layout"] {
            XCTAssertFalse(WinampModernScriptRuntime.isConsumedBeforeXUIParams(name),
                           "\(name) is the wrapper's to pass on")
        }
    }

    // MARK: - What must not change

    /// The reason the old reading existed: a bare `fitparent` group with no geometry of its own must
    /// still fill its parent rather than collapse to 0x0 in the corner.
    func testABareFitParentGroupStillFillsItsParent() throws {
        let renderer = try makeRenderer()

        XCTAssertEqual(frame(of: "overlay", in: renderer),
                       CGRect(x: 0, y: 0, width: 600, height: 400))
    }

    /// ClassicPro's drawer pages are `<group id="drawer.video" fitparent="1" y="1" h="-1"/>`. That
    /// `h="-1"` is a margin written against `fitparent`'s implied `relath="1"`, never an absolute
    /// height — read as one it is a negative box, and the negative-box rule drops the group and
    /// every child under it. Here `fitparent` answers the size, so the page keeps its subtree.
    func testAFitParentGroupWithAMarginIsNotANegativeBox() throws {
        let renderer = try makeRenderer()

        XCTAssertEqual(frame(of: "page", in: renderer),
                       CGRect(x: 0, y: 1, width: 600, height: 400),
                       "its stated `h=\"-1\"` loses to `fitparent`, as every stated size does")
        XCTAssertNotNil(frame(of: "page.child", in: renderer),
                        "and its subtree is still in the scene")
    }

    // MARK: -

    private func object(withID id: String, in renderer: WasabiSceneRenderer) -> WasabiObject? {
        renderer.sceneNodes().first { $0.object.xmlID == id }?.object
    }

    private func frame(of id: String, in renderer: WasabiSceneRenderer) -> CGRect? {
        renderer.sceneNodes().first { $0.object.xmlID == id }?.frame
    }

    /// Venus's cluster and the ClassicPro shapes around it, reduced to the attributes the rules read.
    private func makeRenderer() throws -> WasabiSceneRenderer {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <groupdef id="buttons">
            <layer id="plate" x="18" y="20" w="188" h="59"/>
            <layer id="wordmark" x="65" y="10" w="90" h="23"/>
          </groupdef>
          <groupdef id="page">
            <layer id="page.child" x="0" y="0" w="10" h="10"/>
          </groupdef>
          <container id="main">
            <layout id="normal" w="600" h="400" minimum_w="317" minimum_h="205">
              <group id="buttons" x="20" y="-20" fitparent="1" sysregion="1"/>
              <group id="overlay" fitparent="1"/>
              <group id="sui" fitparent="1" h="100"/>
              <group id="inset" fitparent="1" x="4" y="10"/>
              <group id="page" fitparent="1" y="1" h="-1"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
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
            .appendingPathComponent("WinampModernB142Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B142-\(UUID().uuidString).wal")
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
