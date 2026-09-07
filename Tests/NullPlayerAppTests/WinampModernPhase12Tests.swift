import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 12 — `Wasabi:Frame` and the surface behind it.
///
/// cPro-Bento's entire body hangs off one splitter (`<Wasabi:Frame left="centro.components"
/// right="centro.playlist1" …>`), which in Wasabi *instantiates the two groups it names*. Ours was an
/// identifier-only shell, so the library tree, the playlist and the tab strip never entered the graph
/// at all. Everything else here is what unblocking that reached next: an object-typed `Member` the
/// bytecode parser rejected, MAKI's `List`/`BitList`, `WinampConfig`, and text measurement — the skin
/// lays its own menus and tabs out from `getAutoWidth()`, so a script that measures text differently
/// from the code that draws it builds boxes that do not fit their contents.
final class WinampModernPhase12Tests: XCTestCase {

    // MARK: - Frame

    /// The splitter brings its two named groups into the graph and sizes them either side of the
    /// divider. `from="right" width="60"` puts the right pane 60px from the right edge.
    func testFrameInstantiatesAndPlacesTheGroupsItNames() throws {
        let renderer = try makeRenderer(layout: """
        <Wasabi:Frame id="split" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                      left="pane.left" right="pane.right" orientation="vertical"
                      from="right" width="60"/>
        """)
        let frames = renderer.sceneNodes().reduce(into: [String: CGRect]()) { result, node in
            if let id = node.object.xmlID { result[id] = node.frame }
        }
        let left = try XCTUnwrap(frames["pane.left"], "the frame must instantiate its `left` group")
        let right = try XCTUnwrap(frames["pane.right"], "the frame must instantiate its `right` group")
        // 200 wide overall, a 60px right pane, and an 8px divider centred on the boundary.
        XCTAssertEqual(left.minX, 0)
        XCTAssertEqual(left.width, 200 - 64)
        XCTAssertEqual(right.minX, 200 - 56)
        XCTAssertEqual(right.width, 56)
        XCTAssertEqual(left.height, 200, "a vertical divider's panes span the full height")
        XCTAssertEqual(right.height, 200)
    }

    /// `top`/`bottom` split the other axis, and the pane sizes follow the same divider arithmetic.
    func testFrameSupportsAHorizontalDivider() throws {
        let renderer = try makeRenderer(layout: """
        <Wasabi:Frame id="split" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                      top="pane.left" bottom="pane.right" orientation="h" from="top" height="50"/>
        """)
        let frames = renderer.sceneNodes().reduce(into: [String: CGRect]()) { result, node in
            if let id = node.object.xmlID { result[id] = node.frame }
        }
        let top = try XCTUnwrap(frames["pane.left"])
        let bottom = try XCTUnwrap(frames["pane.right"])
        XCTAssertEqual(top.minY, 0)
        XCTAssertEqual(top.height, 46)
        XCTAssertEqual(bottom.minY, 54)
        XCTAssertEqual(bottom.height, 200 - 54)
        XCTAssertEqual(top.width, 200, "a horizontal divider's panes span the full width")
    }

    /// `getPosition`/`setPosition` on a splitter are the divider offset, not a slider value —
    /// ClassicPro closes its side view with `mainFrame.setPosition(0)` and tests
    /// `getPosition() == 0` to ask whether it is already closed.
    func testFramePositionMovesTheDividerAndClosesAtZero() throws {
        let (runtime, program, renderer) = try makeRuntimeAndRenderer(layout: """
        <Wasabi:Frame id="split" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                      left="pane.left" right="pane.right" from="right" width="60"/>
        """)
        let frame = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "split").first)
        let reference = MakiObjectReference(.gui(frame.stableID))

        XCTAssertEqual(try runtime.invoke(method: "getPosition", on: reference, arguments: [],
                                          program: program).integerValue, 60)

        _ = try runtime.invoke(method: "setPosition", on: reference, arguments: [.integer(100)],
                               program: program)
        XCTAssertEqual(try runtime.invoke(method: "getPosition", on: reference, arguments: [],
                                          program: program).integerValue, 100)
        var frames = renderer.sceneNodes().reduce(into: [String: CGRect]()) { result, node in
            if let id = node.object.xmlID { result[id] = node.frame }
        }
        XCTAssertEqual(try XCTUnwrap(frames["pane.right"]).width, 96)

        _ = try runtime.invoke(method: "setPosition", on: reference, arguments: [.integer(0)],
                               program: program)
        frames = renderer.sceneNodes().reduce(into: [String: CGRect]()) { result, node in
            if let id = node.object.xmlID { result[id] = node.frame }
        }
        XCTAssertEqual(try XCTUnwrap(frames["pane.right"]).width, 0,
                       "closing the split collapses the pane rather than flipping it inside out")
        XCTAssertEqual(try XCTUnwrap(frames["pane.left"]).width, 196)
    }

    // MARK: - Object-typed `Member` (opcode 104)

    /// The opcode's immediate has the same shape as a variable record's first two bytes: a type
    /// offset, then an "is object" flag. `Member GuiObject Tab.left;` in ClassicPro's `CproTabs`
    /// compiles to `0x0100 | 9` — read as a primitive value kind that is "unknown value type 265",
    /// which failed the *parse* and so took the whole skin down, not just one event.
    func testObjectTypedMemberAccessParsesAsAClassReference() throws {
        var code = Data()
        code.append(pushVariable(0))            // owner object
        code.append(pushVariable(0))            // member name
        code.append(memberAccess(0x0100 | 0))   // Member <class 0> owner.name
        let data = makeScript(code: code, methodName: "getid")
        let program = try MakiBytecodeParser().parse(data, source: WalSourceLocation(path: "/member.maki"))
        guard case .valueKind(let kind, let classGUID) = program.instructions[2].argument else {
            return XCTFail("opcode 104 must decode to a member type")
        }
        XCTAssertEqual(kind, .object)
        XCTAssertEqual(classGUID, program.classes[0])
    }

    /// A primitive member is still a plain value kind, and a class index that does not exist is
    /// still rejected — the flag byte must not become a way to reference anything at all.
    func testMemberAccessKeepsPrimitiveKindsAndRejectsUnknownClasses() throws {
        var code = Data()
        code.append(pushVariable(0))
        code.append(pushVariable(0))
        code.append(memberAccess(2))            // Member Int
        let program = try MakiBytecodeParser().parse(makeScript(code: code, methodName: "getid"),
                                                     source: WalSourceLocation(path: "/member.maki"))
        guard case .valueKind(let kind, let classGUID) = program.instructions[2].argument else {
            return XCTFail("opcode 104 must decode to a member type")
        }
        XCTAssertEqual(kind, .integer)
        XCTAssertNil(classGUID)

        var bad = Data()
        bad.append(pushVariable(0))
        bad.append(pushVariable(0))
        bad.append(memberAccess(0x0100 | 7))    // the fixture declares one class, not eight
        XCTAssertThrowsError(try MakiBytecodeParser().parse(makeScript(code: bad, methodName: "getid"),
                                                            source: WalSourceLocation(path: "/member.maki")))
    }

    // MARK: - `List` and `BitList`

    /// MAKI's own container. ClassicPro builds its tab order in one, and a missing `addItem` aborted
    /// the script that assembles the SUI's tab strip.
    func testListStoresEnumeratesAndFindsItems() throws {
        let (runtime, program) = try makeRuntime()
        let list = try runtime.makeObject(classGUID: String(repeating: "0", count: 32), program: program)
        func call(_ method: String, _ arguments: [MakiValue] = []) throws -> MakiValue {
            try runtime.invoke(method: method, on: list, arguments: arguments, program: program)
        }
        _ = try call("addItem", [.string("first")])
        _ = try call("addItem", [.string("second")])
        XCTAssertEqual(try call("getNumItems").integerValue, 2)
        XCTAssertEqual(try call("enumItem", [.integer(1)]).stringValue, "second")
        XCTAssertEqual(try call("findItem", [.string("second")]).integerValue, 1)
        XCTAssertEqual(try call("findItem", [.string("absent")]).integerValue, -1)
        XCTAssertEqual(try call("enumItem", [.integer(9)]).truthy, false,
                       "an out-of-range index answers null rather than trapping")
        _ = try call("removeItem", [.integer(0)])
        XCTAssertEqual(try call("enumItem", [.integer(0)]).stringValue, "second")
        _ = try call("removeAll")
        XCTAssertEqual(try call("getNumItems").integerValue, 0)
    }

    /// `BitList` is a sized array of flags — ClassicPro sizes one to its widget count and ticks off
    /// the widgets it has already initialised.
    func testBitListIsSizedAndFlagged() throws {
        let (runtime, program) = try makeRuntime()
        let bits = try runtime.makeObject(classGUID: String(repeating: "0", count: 32), program: program)
        func call(_ method: String, _ arguments: [MakiValue] = []) throws -> MakiValue {
            try runtime.invoke(method: method, on: bits, arguments: arguments, program: program)
        }
        _ = try call("setSize", [.integer(3)])
        XCTAssertEqual(try call("getSize").integerValue, 3)
        XCTAssertFalse(try call("getItem", [.integer(1)]).truthy)
        _ = try call("setItem", [.integer(1), .boolean(true)])
        XCTAssertTrue(try call("getItem", [.integer(1)]).truthy)
        XCTAssertFalse(try call("getItem", [.integer(99)]).truthy,
                       "a flag past the end reads false rather than trapping")
    }

    // MARK: - `WinampConfig`

    /// `WinampConfig.getGroup(guid).getInt("frequencies")` is ClassicPro's one read of Winamp's own
    /// preferences: 0 means the classic EQ frequencies, which is what NullPlayer's classic-10 EQ
    /// uses. It resolves against the skin's namespaced store, never real Winamp settings.
    func testWinampConfigGroupReadsTheSkinsOwnConfiguration() throws {
        let (runtime, program) = try makeRuntime()
        // The configuration store is durable (it is the skin's own namespaced preferences), so the
        // section is unique per run — otherwise this test reads back what its last run wrote.
        let section = "{\(UUID().uuidString)}"
        let group = try runtime.invoke(method: "getGroup", on: MakiObjectReference(.system),
                                       arguments: [.string(section)], program: program)
        let reference = try XCTUnwrap({ if case .object(let value) = group { return value } else { return nil } }())
        XCTAssertEqual(try runtime.invoke(method: "getInt", on: reference,
                                          arguments: [.string("frequencies")], program: program).integerValue, 0)

        runtime.loadedSkin.configuration.setInteger(1, section: section, key: "frequencies")
        XCTAssertEqual(try runtime.invoke(method: "getInt", on: reference,
                                          arguments: [.string("frequencies")], program: program).integerValue, 1)
        XCTAssertTrue(try runtime.invoke(method: "getBool", on: reference,
                                         arguments: [.string("frequencies")], program: program).truthy)
    }

    // MARK: - Text measurement

    /// `getAutoWidth()` must answer what the string will actually occupy, because the skin lays
    /// itself out from that number: ClassicPro sizes every SUI tab to `label.getAutoWidth() + 14`.
    /// The old character-count estimate ran narrow and clipped every label inside a box the skin
    /// believed fitted it.
    func testGetAutoWidthMeasuresTheTextAndItsPadding() throws {
        let (runtime, program, _) = try makeRuntimeAndRenderer(layout: """
        <group id="box" x="0" y="0" h="21" autowidthsource="label">
          <text id="label" x="0" y="0" h="21" text="Options" fontsize="11" leftpadding="6" rightpadding="3"/>
        </group>
        <text id="short" x="0" y="30" h="21" text="A" fontsize="11"/>
        """)
        func autoWidth(_ id: String) throws -> Int32 {
            let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: id).first)
            return try runtime.invoke(method: "getAutoWidth", on: MakiObjectReference(.gui(object.stableID)),
                                      arguments: [], program: program).integerValue
        }
        let label = try autoWidth("label")
        XCTAssertGreaterThan(label, 9, "a seven-character string plus 9px of padding is wider than the padding")
        XCTAssertGreaterThan(label, try autoWidth("short"), "a longer string measures wider")
        XCTAssertEqual(try autoWidth("box"), label,
                       "`autowidthsource` reports the width of the element it names")
    }

    /// The renderer sizes from the same measurement, so a group that only declares
    /// `autowidthsource` — ClassicPro's five menu-bar groups — is as wide as its label instead of
    /// 0, which is what made the File/Play/Options/View/Help strip disappear entirely.
    func testAutoWidthSourceGroupIsSizedToItsLabel() throws {
        let (runtime, program, renderer) = try makeRuntimeAndRenderer(layout: """
        <group id="box" x="0" y="0" h="21" autowidthsource="label">
          <text id="label" x="0" y="0" h="21" text="Options" fontsize="11" leftpadding="6" rightpadding="3"/>
        </group>
        """)
        let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "label").first)
        let measured = try runtime.invoke(method: "getAutoWidth",
                                          on: MakiObjectReference(.gui(object.stableID)),
                                          arguments: [], program: program).integerValue
        let box = try XCTUnwrap(renderer.sceneNodes().first { $0.object.xmlID == "box" })
        XCTAssertEqual(box.frame.width.rounded(.up), CGFloat(measured),
                       "the drawn box and the script's measurement must agree")
        XCTAssertGreaterThan(box.frame.width, 0)
    }

    // MARK: - Helpers

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        try makeRuntimeAndRenderer(layout: layout).2
    }

    private func makeRuntimeAndRenderer(layout: String) throws
        -> (WinampModernScriptRuntime, MakiProgram, WasabiSceneRenderer) {
        let xml = """
        <WasabiXML>
          <groupdef id="pane.left"/>
          <groupdef id="pane.right"/>
          <container id="Main">
            <layout id="normal" w="200" h="200">
        \(layout)
            </layout>
          </container>
        </WasabiXML>
        """
        let (runtime, program) = try makeRuntime(xml: xml)
        let host = TestHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: runtime.loadedSkin, host: host)
        addTeardownBlock { renderer.teardown() }
        return (runtime, program, renderer)
    }

    private func makeRuntime(xml: String? = nil) throws -> (WinampModernScriptRuntime, MakiProgram) {
        let document = xml ?? """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="16" h="16"/>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: document))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { runtime.teardown() }
        let program = try MakiBytecodeParser().parse(makeScript(code: Data(), methodName: "getid"),
                                                     source: WalSourceLocation(path: "/Skins/Synthetic/skin.xml"))
        return (runtime, program)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase12Tests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Minimal MAKI assembler (mirrors the Phase 8/10/11 helpers)

    private func pushVariable(_ index: UInt32) -> Data {
        var data = Data([1])
        appendUInt32(index, to: &data)
        return data
    }

    private func memberAccess(_ immediate: UInt32) -> Data {
        var data = Data([104])
        appendUInt32(immediate, to: &data)
        return data
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
