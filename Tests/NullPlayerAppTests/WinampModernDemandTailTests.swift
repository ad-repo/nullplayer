import XCTest
@testable import NullPlayer

/// The tail of the S4 demand table: the System date/math/format fields, the window and layout reads,
/// `CfgGroup`, the drop-down reads, the `GuiList` edits, `GuiTree`/`TreeItem`, gamma groups and
/// `showWindow`. Each was a call that aborted the handler it sat in.
final class WinampModernDemandTailTests: XCTestCase {

    func testDateFieldsFormatsAndMath() throws {
        let (runtime, program) = try makeRuntime()
        let stamp: [MakiValue] = [.integer(1_700_000_000)]
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let parts = Calendar.current.dateComponents([.day, .month, .weekday, .hour, .minute, .second], from: date)
        XCTAssertEqual(try system(runtime, program, "getDateDay", stamp).integerValue, Int32(parts.day!))
        XCTAssertEqual(try system(runtime, program, "getDateMonth", stamp).integerValue, Int32(parts.month! - 1))
        XCTAssertEqual(try system(runtime, program, "getDateDow", stamp).integerValue, Int32(parts.weekday! - 1))
        XCTAssertEqual(try system(runtime, program, "dateToLongTime", stamp).stringValue,
                       String(format: "%d:%02d:%02d", parts.hour!, parts.minute!, parts.second!))
        XCTAssertFalse(try system(runtime, program, "formatDate", stamp).stringValue.isEmpty)
        XCTAssertFalse(try system(runtime, program, "formatLongDate", stamp).stringValue.isEmpty)
        XCTAssertEqual(try system(runtime, program, "sqr", [.double(3)]).doubleValue, 9)
        XCTAssertEqual(try system(runtime, program, "frac", [.double(-2.25)]).doubleValue, -0.25)
        // Time of day is milliseconds since midnight, so it reads as a clock (cPro2's stopped timer).
        let timeOfDay = try system(runtime, program, "getTimeOfDay").integerValue
        XCTAssertTrue((0..<86_400_000).contains(timeOfDay))
        // A component with nothing to command answers "not handled".
        guard case .object(let wac) = try system(runtime, program, "getWac", [.string("{guid}")]) else {
            return XCTFail("no Wac")
        }
        XCTAssertEqual(try runtime.invoke(method: "sendCommand", on: wac,
                                          arguments: [.string("x"), .integer(0), .integer(0), .string("")],
                                          program: program).integerValue, 0)
    }

    func testContainerAndLayoutReads() throws {
        let (runtime, program) = try makeRuntime(body: #"<layer id="a" w="2" h="2"/><layer id="b" w="2" h="2"/><vis id="v"/>"#)
        let container = try object(runtime, "main")
        XCTAssertEqual(try call(runtime, program, container, "getNumLayouts").integerValue, 1)
        guard case .object(let layoutReference) = try call(runtime, program, container, "enumLayout", [.integer(0)]),
              case .gui(let layoutID) = layoutReference.kind,
              let layout = runtime.loadedSkin.runtime.graph.object(withID: layoutID) else { return XCTFail("no layout") }
        XCTAssertTrue(try call(runtime, program, layout, "isLayout").truthy)
        XCTAssertFalse(try call(runtime, program, container, "isLayout").truthy)
        _ = try call(runtime, program, container, "setName", [.string("Renamed")])
        XCTAssertEqual(container.attributes["name"], "Renamed")
        _ = try call(runtime, program, layout, "snapAdjust", [.integer(1), .integer(2), .integer(3), .integer(4)])
        XCTAssertEqual(try call(runtime, program, layout, "getSnapAdjustBottom").integerValue, 4)
        XCTAssertEqual(try call(runtime, program, layout, "clientToScreenH", [.integer(17)]).integerValue, 17)
        // `bringBelow` puts the object just under the other, among the same parent's children.
        let a = try object(runtime, "a"), b = try object(runtime, "b")
        _ = try call(runtime, program, b, "bringBelow", [runtime.objectValue(a)])
        XCTAssertEqual(layout.children.compactMap(\.xmlID).prefix(2), ["b", "a"])
        let vis = try object(runtime, "v")
        _ = try call(runtime, program, vis, "nextMode")
        XCTAssertEqual(try call(runtime, program, vis, "getMode").integerValue, 2)
    }

    func testCfgGroupReadsAndWritesItsAttribute() throws {
        let (runtime, program) = try makeRuntime(body: #"<group id="g" cfgattrib="{1234};Volume step"/>"#)
        let group = try object(runtime, "g")
        _ = try call(runtime, program, group, "cfgSetInt", [.integer(5)])
        XCTAssertEqual(try call(runtime, program, group, "cfgGetInt").integerValue, 5)
        XCTAssertEqual(try call(runtime, program, group, "cfgGetName").stringValue, "Volume step")
        XCTAssertEqual(try call(runtime, program, group, "cfgGetGuid").stringValue, "{1234}")
        _ = try call(runtime, program, group, "cfgSetString", [.string("hi")])
        XCTAssertEqual(try call(runtime, program, group, "cfgGetString").stringValue, "hi")
    }

    func testDropDownAndListEdits() throws {
        let (runtime, program) = try makeRuntime(
            body: #"<Wasabi:DropDownList id="d" items="one;two;three"/><list id="l" w="40" h="40"/>"#)
        let dropDown = try object(runtime, "d")
        _ = try call(runtime, program, dropDown, "selectItem", [.integer(1), .integer(0)])
        XCTAssertEqual(try call(runtime, program, dropDown, "getSelectedText").stringValue, "two")

        let list = try object(runtime, "l")
        _ = try call(runtime, program, list, "addItem", [.string("a")])
        _ = try call(runtime, program, list, "addItem", [.string("c")])
        _ = try call(runtime, program, list, "insertItem", [.integer(1), .string("b")])
        XCTAssertEqual(WasabiGuiList.items(of: list), ["a", "b", "c"])
        _ = try call(runtime, program, list, "moveItem", [.integer(0), .integer(2)])
        _ = try call(runtime, program, list, "deleteByPos", [.integer(0)])
        XCTAssertEqual(WasabiGuiList.items(of: list), ["c", "a"])
        _ = try call(runtime, program, list, "setSubItem", [.integer(0), .integer(1), .string("sub")])
        XCTAssertEqual(try call(runtime, program, list, "getSubitemText", [.integer(0), .integer(1)]).stringValue, "sub")
        XCTAssertEqual(try call(runtime, program, list, "addColumn", [.string("Name"), .integer(50), .integer(0)]).integerValue, 0)
        _ = try call(runtime, program, list, "setColumnLabel", [.integer(0), .string("Title")])
        XCTAssertEqual(try call(runtime, program, list, "getColumnLabel", [.integer(0)]).stringValue, "Title")
    }

    /// A tree is a model of script-made items, drawn through the list renderer as visible rows.
    func testTreeItemsAddExpandAndDraw() throws {
        let (runtime, program) = try makeRuntime(body: #"<tree id="t" w="60" h="60"/>"#)
        let tree = try object(runtime, "t")
        func newItem(_ label: String) throws -> MakiValue {
            let item = runtime.dynamicValue(role: .generic)
            guard case .object(let reference) = item else { throw XCTSkip("no item") }
            _ = try runtime.invoke(method: "setLabel", on: reference, arguments: [.string(label)], program: program)
            return item
        }
        let general = try newItem("General"), audio = try newItem("Audio")
        _ = try call(runtime, program, tree, "addTreeItem", [general, .null, .integer(0), .integer(1)])
        _ = try call(runtime, program, tree, "addTreeItem", [audio, general, .integer(0), .integer(0)])
        XCTAssertEqual(try call(runtime, program, tree, "getNumVisibleItems").integerValue, 1)
        guard case .object(let generalReference) = general else { return XCTFail() }
        _ = try runtime.invoke(method: "expand", on: generalReference, arguments: [], program: program)
        XCTAssertEqual(try call(runtime, program, tree, "getNumVisibleItems").integerValue, 2)
        XCTAssertEqual(WasabiGuiList.items(of: tree).map { $0.trimmingCharacters(in: .whitespaces) },
                       ["▾ General", "Audio"])
        guard case .object(let found) = try call(runtime, program, tree, "getByLabel", [general, .string("Audio")]),
              case .object(let audioReference) = audio else { return XCTFail("getByLabel") }
        XCTAssertEqual(found, audioReference)
        // From null the search covers the whole tree, nested items included.
        guard case .object(let nested) = try call(runtime, program, tree, "getByLabel", [.null, .string("Audio")])
        else { return XCTFail("getByLabel from null") }
        XCTAssertEqual(nested, audioReference)
        guard case .object(let root) = try call(runtime, program, tree, "enumRootItem", [.integer(0)]) else { return XCTFail() }
        XCTAssertEqual(root, generalReference)
        XCTAssertEqual(try runtime.invoke(method: "getLabel", on: audioReference, arguments: [], program: program).stringValue, "Audio")
    }

    func testGammaGroupRetintsTheActiveTheme() throws {
        let (runtime, program) = try makeRuntime(
            definitions: #"<gammaset id="default"><gammagroup id="body" value="0,0,0"/><gammagroup id="lcd" value="0,0,0"/></gammaset>"#)
        guard case .object(let set) = runtime.dynamicValue(role: .gammaSet(name: "default")),
              case .object(let group) = try runtime.invoke(method: "enumGammaGroup", on: set, arguments: [.integer(1)],
                                                           program: program) else { return XCTFail("no group") }
        _ = try runtime.invoke(method: "setRed", on: group, arguments: [.integer(2048)], program: program)
        XCTAssertEqual(try runtime.invoke(method: "getRed", on: group, arguments: [], program: program).integerValue, 2048)
        XCTAssertEqual(runtime.loadedSkin.themeCoordinator.transform(group: "lcd")?.red, 0.5)
    }

    func testShowWindowOpensTheContainerHoldingAGroup() throws {
        let (runtime, program) = try makeRuntime(
            definitions: #"<container id="extra" default_visible="0"><layout id="normal" w="10" h="10"><group id="panel"/></layout></container>"#)
        var shown: [String] = []
        runtime.hooks.containerVisibilityRequested = { id, visible in if visible { shown.append(id) } }
        _ = try system(runtime, program, "showWindow", [.string("panel"), .string(""), .integer(0)])
        XCTAssertEqual(shown, ["extra"])
        var components: [WinampModernComponentKind] = []
        runtime.hooks.componentShowRequested = { components.append($0) }
        _ = try system(runtime, program, "showWindow", [.string("guid:pl"), .string(""), .integer(0)])
        XCTAssertEqual(components, [.playlist])
    }

    /// B211: a test process keeps skin settings in memory, so no run inherits the last one's.
    func testATestProcessKeepsSkinSettingsInMemory() {
        let defaults = WinampModernConfiguration.processDefaults
        XCTAssertFalse(defaults === UserDefaults.standard)
        let configuration = WinampModernConfiguration(namespace: "B211")
        configuration.setInteger(7, section: "s", key: "k")
        XCTAssertEqual(configuration.integer(section: "s", key: "k"), 7)
        XCTAssertNil(UserDefaults.standard.object(forKey: "winampModern.config.B211.s.k"))
        configuration.removeValue(section: "s", key: "k")
        XCTAssertEqual(configuration.integer(section: "s", key: "k", default: -1), -1)
    }

    /// `new Text; t.init(parent)` puts a real text in the graph (Nitrous Audio's playlist rows), the
    /// reference then answers as it, and `delete` takes it out.
    func testAScriptMadeTextEntersTheGraphOnInit() throws {
        let (runtime, program) = try makeRuntime()
        let layout = try object(runtime, "normal")
        let text = try runtime.makeObject(classGUID: MakiClassGUID.canonical("efaa867241fa310ea985dcb74bcb5b52"),
                                          program: program)
        _ = try runtime.invoke(method: "init", on: text, arguments: [runtime.objectValue(layout)], program: program)
        _ = try runtime.invoke(method: "setXmlParam", on: text, arguments: [.string("id"), .string("line0")],
                               program: program)
        let created = try object(runtime, "line0")
        XCTAssertEqual(created.typeName, "text")
        XCTAssertTrue(created.parent === layout)
        runtime.releaseObject(text)
        XCTAssertNil(runtime.loadedSkin.runtime.graph.allObjectsUnordered.first { $0.xmlID == "line0" })
    }

    /// Params a script sets before `init` are the element's own (1010 Fullscreen's analyzer).
    func testParamsSetBeforeInitAreTheElementsOwn() throws {
        let (runtime, program) = try makeRuntime()
        let layout = try object(runtime, "normal")
        let layer = try runtime.makeObject(classGUID: MakiClassGUID.canonical("5ab9fa1545579a7d5765c8aba97cc6a6"),
                                           program: program)
        _ = try runtime.invoke(method: "setXmlParam", on: layer, arguments: [.string("id"), .string("pixel_0")], program: program)
        _ = try runtime.invoke(method: "setXmlParam", on: layer, arguments: [.string("w"), .string("7")], program: program)
        _ = try runtime.invoke(method: "setAlpha", on: layer, arguments: [.integer(40)], program: program)
        _ = try runtime.invoke(method: "init", on: layer, arguments: [runtime.objectValue(layout)], program: program)
        XCTAssertEqual(try object(runtime, "pixel_0").attributes["w"], "7")
        XCTAssertEqual(try object(runtime, "pixel_0").attributes["alpha"], "40", "a call made before init is replayed")
    }

    func testGroupListAndDropDownItems() throws {
        let (runtime, program) = try makeRuntime(
            body: #"<grouplist id="gl"/><Wasabi:DropDownList id="d" items="a;b"/>"#,
            definitions: #"<groupdef id="row"><layer id="cell"/></groupdef>"#)
        let list = try object(runtime, "gl")
        _ = try call(runtime, program, list, "instantiate", [.string("row"), .integer(2)])
        XCTAssertEqual(try call(runtime, program, list, "getNumItems").integerValue, 2)
        guard case .object = try call(runtime, program, list, "enumItem", [.integer(1)]) else { return XCTFail() }
        _ = try call(runtime, program, list, "removeAll")
        XCTAssertEqual(try call(runtime, program, list, "getNumItems").integerValue, 0)

        let dropDown = try object(runtime, "d")
        XCTAssertEqual(try call(runtime, program, dropDown, "addItem", [.string("c")]).integerValue, 2)
        XCTAssertEqual(try call(runtime, program, dropDown, "findItem", [.string("b")]).integerValue, 1)
        _ = try call(runtime, program, dropDown, "delItem", [.integer(0)])
        XCTAssertEqual(try call(runtime, program, dropDown, "getItemText", [.integer(0)]).stringValue, "b")
        _ = try call(runtime, program, dropDown, "deleteAllItems")
        XCTAssertEqual(try call(runtime, program, dropDown, "getNumItems").integerValue, 0)
    }

    /// `newGroup` of a group the skin never defined answers null, as in Winamp, instead of aborting.
    func testNewGroupOfAnUnknownGroupAnswersNull() throws {
        let (runtime, _) = try makeRuntime()
        let layout = try object(runtime, "normal")
        let owned = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [], instructions: [],
                                source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"), ownerID: layout.stableID,
                                parameter: nil)
        let result = try runtime.invoke(method: "newGroup", on: MakiObjectReference(.system),
                                        arguments: [.string("component.content.group")], program: owned)
        guard case .null = result else { return XCTFail("expected null, got \(result)") }
        XCTAssertTrue(runtime.loadedSkin.runtime.diagnostics.contains {
            $0.code == .missingGroupDefinition && $0.severity == .warning
        })
    }

    /// B194: a script-played AnimatedLayer raises `onFrame` for each frame its play head reaches and
    /// `onStop` at the end of the range. mmd3's knobs set the EQ from `onFrame` alone.
    func testAPlayedAnimationRaisesFrameAndStopEvents() throws {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML><container id="main"><layout id="normal" w="64" h="64">
          <animatedlayer id="knob" w="10" h="10" frames="10"/><script id="s" file="s.maki"/>
        </layout></container></WasabiXML>
        """, files: ["s.maki": Self.handlerScript(["onframe", "onstop"])])
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: WinampModernStubHost())
        addTeardownBlock { runtime.teardown() }
        let knob = try object(runtime, "knob")
        let program = try XCTUnwrap(runtime.programs.first)
        program.variables[0].value = .object(MakiObjectReference(.gui(knob.stableID)))
        var events: [String] = []
        runtime.dispatchObserver = { event, _, _ in events.append(event) }

        _ = try call(runtime, program, knob, "setStartFrame", [.integer(0)])
        _ = try call(runtime, program, knob, "setEndFrame", [.integer(2)])
        _ = try call(runtime, program, knob, "setSpeed", [.integer(10)])
        _ = try call(runtime, program, knob, "play")
        let deadline = Date().addingTimeInterval(2)
        while !events.contains("onstop"), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(events, ["onframe", "onframe", "onstop"])
    }

    // MARK: - Helpers

    /// One object variable with a bare-`return` handler bound per event name.
    private static func handlerScript(_ events: [String]) -> Data {
        var data = Data([0x46, 0x47])
        func u8(_ value: UInt8) { data.append(value) }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        u16(0x0403); u32(23)
        u32(1); data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        u32(UInt32(events.count))
        for name in events { u16(0); u16(0); u16(UInt16(name.utf8.count)); data.append(contentsOf: name.utf8) }
        u32(1); u8(0); u8(1); u16(0); u16(0); u16(0); u16(0); u16(0); u8(1); u8(0)
        u32(0)
        u32(UInt32(events.count))
        for index in events.indices { u32(0); u32(UInt32(index)); u32(UInt32(index)) }
        u32(UInt32(events.count)); for _ in events { u8(33) }
        return data
    }

    private static let program = MakiProgram(
        version: 0x0403, classes: [], methods: [], variables: [], bindings: [], instructions: [],
        source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"), ownerID: nil, parameter: nil)

    private func makeRuntime(body: String = "", definitions: String = "") throws -> (WinampModernScriptRuntime, MakiProgram) {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>\(definitions)<container id="main"><layout id="normal" w="64" h="64">\(body)</layout></container></WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: WinampModernStubHost())
        addTeardownBlock { runtime.teardown() }
        return (runtime, Self.program)
    }

    private func object(_ runtime: WinampModernScriptRuntime, _ id: String) throws -> WasabiObject {
        try XCTUnwrap(runtime.loadedSkin.runtime.graph.allObjectsUnordered.first { $0.xmlID == id }, id)
    }

    private func call(_ runtime: WinampModernScriptRuntime, _ program: MakiProgram, _ object: WasabiObject,
                      _ method: String, _ arguments: [MakiValue] = []) throws -> MakiValue {
        try runtime.invoke(method: method, on: MakiObjectReference(.gui(object.stableID)), arguments: arguments, program: program)
    }

    private func system(_ runtime: WinampModernScriptRuntime, _ program: MakiProgram, _ method: String,
                        _ arguments: [MakiValue] = []) throws -> MakiValue {
        try runtime.invoke(method: method, on: MakiObjectReference(.system), arguments: arguments, program: program)
    }
}
