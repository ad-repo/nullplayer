import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 84 — `autowidthsource` ignored where its source **sits** (B68), and a skin-drawn equalizer
/// beating the skin's own equalizer window (B73).
///
/// A group that names an `autowidthsource` was sized to the source's measured *string*, and the
/// source then resolved its own geometry inside that group — so every source that keeps room beside
/// itself came out short by exactly that room. impulse's switches are the live case: `<groupdef
/// id="impulse.checkbox" autowidthsource="checkbox.text">` holds `<text id="checkbox.text" x="13"
/// w="-14" relatw="1">`, the group measured the bare string, and the label inside it got 14px less
/// than that — about two characters clipped off every *Skin Options* and *Notifier Options* row.
///
/// The correction is not a constant but the resolve solved for the group's width, in the two shapes
/// the corpus actually declares: a relative width (`w="-14" relatw="1"`) makes the source
/// `groupWidth + w` wide, so the group needs `sourceWidth - w`; an absolute width does not depend on
/// the group at all, so what matters is how far the source *reaches*, `x + sourceWidth`.
///
/// The containment is what makes this safe. Of the 53 declarations in 13 corpus skins, 26 name an
/// offset source and 27 do not — and the 27 are the tuned case this machinery was built for:
/// ClassicPro's and stock Winamp Modern's whole menu bar (`<layer id="File.txt" x="0" y="0"/>`) and
/// three `wasabi.titlebox.center.group` bodies at `x="0" w="0" relatw="1"`. Both answer an inset of
/// zero, which is the width they already returned.
///
/// **B73** is the same trap `.video` fell into in B20: an equalizer recognised from the player's own
/// `EQ_BAND`/`EQ_PREAMP` sliders was embedded *unconditionally*, so impulse — which draws those
/// sliders **and** ships a 198×158 `Equalizer` container — had that window routed to as the
/// equalizer surface and therefore openable from nowhere, **Skin Windows** included. Embedding is now
/// gated on the skin declaring no equalizer window, exactly as video is.
final class WinampModernPhase84Tests: XCTestCase {

    // MARK: - The inset itself

    /// impulse's shape, and the majority of the 26: a source that gives width back on both sides.
    /// The negative `w` already accounts for both insets, so `x` is not added on top of it — the
    /// skin picks `w="-14"` for `x="13"` and `w="-13"` for `x="5"` precisely because it is stating
    /// the *total*.
    func testRelativeWidthSourceAsksForWhatItGivesBack() {
        XCTAssertEqual(WasabiGeometrySpec.autoWidthInset(of: ["x": "13", "w": "-14", "relatw": "1"]), 14)
        XCTAssertEqual(WasabiGeometrySpec.autoWidthInset(of: ["x": "5", "w": "-13", "relatw": "1"]), 13)
        XCTAssertEqual(WasabiGeometrySpec.autoWidthInset(of: ["x": "11", "w": "-24", "relatw": "1"]), 24)
    }

    /// A source whose width does not depend on the group: the answer is its right edge.
    func testAbsoluteSourceAsksForItsRightEdge() {
        XCTAssertEqual(WasabiGeometrySpec.autoWidthInset(of: ["x": "14"]), 14)
        XCTAssertEqual(WasabiGeometrySpec.autoWidthInset(of: ["x": "12", "w": "80"]), 12)
    }

    /// The 27 declarations that must not move, both shapes of them.
    func testSourcesThatKeepNoRoomAskForNothing() {
        XCTAssertEqual(WasabiGeometrySpec.autoWidthInset(of: ["x": "0", "y": "0"]), 0,
                       "a menu-bar label at the group's origin — the tuned case")
        XCTAssertEqual(WasabiGeometrySpec.autoWidthInset(of: ["x": "0", "w": "0", "relatw": "1"]), 0,
                       "`wasabi.titlebox.center.group`'s body, which fills the box exactly")
        XCTAssertEqual(WasabiGeometrySpec.autoWidthInset(of: ["relatw": "1"]), 0,
                       "mmd3's `ctitlebar`: relative with no `w` at all")
        XCTAssertEqual(WasabiGeometrySpec.autoWidthInset(of: [:]), 0)
    }

    /// A source declared *wider* than its parent is the fill-and-overflow idiom, not a request for a
    /// narrower group. Clamped rather than allowed to shrink the group below its content.
    func testASourceWiderThanItsParentDoesNotShrinkTheGroup() {
        XCTAssertEqual(WasabiGeometrySpec.autoWidthInset(of: ["x": "0", "w": "20", "relatw": "1"]), 0)
    }

    // MARK: - What the group is sized to

    /// The defect, end to end: the label must get the width it was measured at. Before this, the
    /// group took the string and the label resolved to string − 14.
    func testAnOffsetSourceReachesItsOwnMeasuredWidth() throws {
        let renderer = try makeRenderer(layout: """
        <group id="box" x="0" y="0" h="14" autowidthsource="checkbox.text">
          <text id="checkbox.text" x="13" y="0" w="-14" relatw="1" h="14"
                text="Show Only When Minimized" fontsize="14"/>
        </group>
        <text id="reference" x="0" y="40" h="14" text="Show Only When Minimized" fontsize="14"/>
        """)
        let box = try XCTUnwrap(frame(of: "box", in: renderer))
        let label = try XCTUnwrap(frame(of: "checkbox.text", in: renderer))
        // A `<text>` with no `w` sizes to its own string, so this is the same measurement the group
        // is supposed to make room for — and the number the label was 14px short of.
        let wanted = try XCTUnwrap(frame(of: "reference", in: renderer)).width

        XCTAssertEqual(label.width, wanted, accuracy: 0.001,
                       "the label draws the whole string, not the string minus its own inset")
        XCTAssertEqual(box.width, wanted + 14, accuracy: 0.001,
                       "the group is its source's width plus the room the source keeps")
        XCTAssertEqual(label.minX - box.minX, 13, accuracy: 0.001, "the label still sits at x=13")
    }

    /// The same markup with the source at the origin: unchanged, which is the safety argument for
    /// the 27 declarations the fix must not move.
    func testASourceAtTheOriginSizesTheGroupToItExactly() throws {
        let renderer = try makeRenderer(layout: """
        <group id="box" x="0" y="0" h="21" autowidthsource="label">
          <text id="label" x="0" y="0" h="21" text="Options" fontsize="11"
                leftpadding="6" rightpadding="3"/>
        </group>
        """)
        let box = try XCTUnwrap(frame(of: "box", in: renderer))
        let label = try XCTUnwrap(frame(of: "label", in: renderer))
        XCTAssertEqual(box.width, label.width, accuracy: 0.001,
                       "ClassicPro's menu bar answers what it always answered")
    }

    /// A group whose source measures nothing stays collapsed. S7Reflex's config tabs are
    /// `<text default="">` filled in by a script, and widening them to their own padding would
    /// invent two 24px tabs out of a label that has no text yet.
    func testASourceThatMeasuresNothingLeavesTheGroupCollapsed() throws {
        let renderer = try makeRenderer(layout: """
        <group id="box" x="0" y="0" h="19" autowidthsource="tab.text">
          <text id="tab.text" x="11" y="3" w="-24" relatw="1" h="8" default=""/>
        </group>
        """)
        let box = try XCTUnwrap(frame(of: "box", in: renderer))
        XCTAssertEqual(box.width, 0, accuracy: 0.001)
    }

    // MARK: - The script's measurement and the drawn box are one number

    /// `getAutoWidth()` is how a skin lays its own strip out — ClassicPro sizes every SUI tab from
    /// it — so the number a script reads and the box the renderer draws have to be the same one.
    func testGetAutoWidthAgreesWithTheDrawnGroup() throws {
        let layout = """
        <group id="box" x="0" y="0" h="14" autowidthsource="checkbox.text">
          <text id="checkbox.text" x="13" y="0" w="-14" relatw="1" h="14"
                text="Animate Drawers" fontsize="14"/>
        </group>
        """
        let (runtime, program, renderer) = try makeRuntimeAndRenderer(layout: layout)
        let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "box").first)
        let measured = try runtime.invoke(method: "getAutoWidth",
                                          on: MakiObjectReference(.gui(object.stableID)),
                                          arguments: [], program: program).integerValue
        let box = try XCTUnwrap(renderer.sceneNodes().first { $0.object.xmlID == "box" })
        XCTAssertEqual(box.frame.width.rounded(.up), CGFloat(measured))
    }

    /// The runtime's own guard, matching the renderer's: a source measuring 0 answers 0 rather than
    /// its padding, so a script laying out from these numbers does not stack empty tabs.
    func testGetAutoWidthAnswersZeroForASourceThatMeasuresNothing() throws {
        let (runtime, program, _) = try makeRuntimeAndRenderer(layout: """
        <group id="box" x="0" y="0" h="19" autowidthsource="tab.text">
          <text id="tab.text" x="11" y="3" w="-24" relatw="1" h="8" default=""/>
        </group>
        """)
        let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "box").first)
        XCTAssertEqual(try runtime.invoke(method: "getAutoWidth",
                                          on: MakiObjectReference(.gui(object.stableID)),
                                          arguments: [], program: program).integerValue, 0)
    }

    // MARK: - B73: a declared equalizer window outranks the player's own sliders

    /// impulse in miniature: EQ sliders in the player *and* an equalizer container. The window wins.
    func testADeclaredEqualizerWindowOutranksThePlayersOwnSliders() throws {
        let inventory = try makeInventory(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <slider action="EQ_BAND" param="3" x="0" y="0" w="8" h="40"/>
            </layout>
          </container>
          <container id="Equalizer" default_visible="0" default_w="198" default_h="158">
            <layout id="normal" w="198" h="158">
              <slider action="EQ_BAND" param="3" x="0" y="0" w="8" h="40"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        XCTAssertEqual(inventory.declaredContainers[.equalizer], "Equalizer")
        XCTAssertFalse(inventory.embeddedKinds.contains(.equalizer),
                       "the skin's own window is the equalizer surface, not the player's drawer")
    }

    /// The case the embed rule exists for, unchanged: cPro, mmd3, stock Winamp Modern and micro all
    /// draw an equalizer in the player and declare no window for it.
    func testAPlayerDrawnEqualizerStillEmbedsWhenTheSkinDeclaresNoWindow() throws {
        let inventory = try makeInventory(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <slider action="EQ_PREAMP" x="0" y="0" w="8" h="40"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        XCTAssertNil(inventory.declaredContainers[.equalizer])
        XCTAssertTrue(inventory.embeddedKinds.contains(.equalizer))
    }

    /// A container that declares no `component` and no equalizer id is still the equalizer window
    /// when its own controls say so — the fallback the `declared` loop already had, which is what the
    /// gate above now reads.
    func testAnEqualizerWindowIsRecognisedFromItsOwnControls() throws {
        let inventory = try makeInventory(xml: """
        <WasabiXML>
          <container id="drawer" default_w="198" default_h="158">
            <layout id="normal" w="198" h="158">
              <slider action="EQ_BAND" param="0" x="0" y="0" w="8" h="40"/>
            </layout>
          </container>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <slider action="EQ_BAND" param="0" x="0" y="0" w="8" h="40"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        XCTAssertEqual(inventory.declaredContainers[.equalizer], "drawer")
        XCTAssertFalse(inventory.embeddedKinds.contains(.equalizer))
    }

    // MARK: - Fixtures

    private func makeInventory(xml: String) throws -> WinampModernSurfaceInventory {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        return loaded.surfaceInventory
    }

    private func frame(of id: String, in renderer: WasabiSceneRenderer) -> CGRect? {
        renderer.sceneNodes().first { $0.object.xmlID == id }?.frame
    }

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let loaded = try load(layout: layout)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeRuntimeAndRenderer(layout: String) throws
        -> (WinampModernScriptRuntime, MakiProgram, WasabiSceneRenderer) {
        let loaded = try load(layout: layout)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        let program = try MakiBytecodeParser().parse(makeScript(code: Data(), methodName: "getid"),
                                                     source: WalSourceLocation(path: "/Skins/Synthetic/skin.xml"))
        return (runtime, program, renderer)
    }

    private func load(layout: String) throws -> WinampModernLoadedSkin {
        let url = try makeArchive(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="400" h="200" default_w="400" default_h="200">
        \(layout)
            </layout>
          </container>
        </WasabiXML>
        """)
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase84Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
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

    private func makeScript(code: Data, methodName: String) -> Data {
        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)

        appendUInt32(1, to: &data)                                  // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))

        appendUInt32(1, to: &data)                                  // methods
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendString(methodName, to: &data)

        appendUInt32(1, to: &data)                                  // variables
        appendVariable(typeOffset: 0, object: true, system: true, to: &data)

        appendUInt32(0, to: &data)                                  // constants
        appendUInt32(0, to: &data)                                  // bindings
        appendUInt32(UInt32(code.count), to: &data)
        data.append(code)
        return data
    }

    private func appendVariable(typeOffset: UInt8, object: Bool = false, system: Bool = false,
                                initial: UInt16 = 0, to data: inout Data) {
        data.append(typeOffset)
        data.append(object ? 1 : 0)
        appendUInt16(0, to: &data)
        appendUInt16(initial, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)
        data.append(system ? 1 : 0)
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    private func appendString(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count), to: &data)
        data.append(bytes)
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
}
