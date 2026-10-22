import AppKit
import XCTest
@testable import NullPlayer

/// MAKI methods the S4 demand queue ranked, and events called as methods (B182, B183, B184, B185,
/// B189, B190, B192, B193, B195, B198, B201, B206, B186, B187, B188, B191, B194, B196, B197,
/// B199, B200). Each was a call that aborted
/// the whole handler it sat in.
final class WinampModernSystemDemandTests: XCTestCase {

    /// B188: a skin's scripted transport buttons reach the host's next and previous.
    func testNextAndPreviousReachTheHost() throws {
        let host = TransportHost()
        let (runtime, program) = try makeRuntime(host: host)
        _ = try system(runtime, program, "next")
        _ = try system(runtime, program, "next")
        _ = try system(runtime, program, "previous")
        XCTAssertEqual(host.calls, ["next", "next", "previous"])
    }

    /// B191: a code point to its one-character string; a value that is no scalar answers empty.
    func testChrIsOneCharacter() throws {
        let (runtime, program) = try makeRuntime()
        XCTAssertEqual(try system(runtime, program, "chr", [.integer(92)]).stringValue, "\\")
        XCTAssertEqual(try system(runtime, program, "chr", [.integer(232)]).stringValue, "è")
        XCTAssertEqual(try system(runtime, program, "chr", [.integer(0xD800)]).stringValue, "")
    }

    /// B196: the clock fields of a `getDate()` stamp, and of now when the stamp is 0.
    func testDateFieldsReadTheStamp() throws {
        let (runtime, program) = try makeRuntime()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: stamp)
        let argument = [MakiValue.integer(1_700_000_000)]
        XCTAssertEqual(try system(runtime, program, "getDateHour", argument).integerValue, Int32(parts.hour!))
        XCTAssertEqual(try system(runtime, program, "getDateMin", argument).integerValue, Int32(parts.minute!))
        XCTAssertEqual(try system(runtime, program, "getDateSec", argument).integerValue, Int32(parts.second!))
        let hourNow = try system(runtime, program, "getDateHour", [.integer(0)]).integerValue
        XCTAssertTrue((0..<24).contains(hourNow))
    }

    /// B200: null and a vanished graph object are invalid; a live one is valid.
    func testIsObjectValidResolvesTheReference() throws {
        let (runtime, program) = try makeRuntime()
        let layout = try XCTUnwrap(runtime.loadedSkin.runtime.graph.roots.first?.children.first)
        XCTAssertEqual(try system(runtime, program, "isObjectValid", [runtime.objectValue(layout)]).truthy, true)
        XCTAssertEqual(try system(runtime, program, "isObjectValid", [.null]).truthy, false)
        let gone = MakiValue.object(MakiObjectReference(.gui(WasabiObjectID(rawValue: 9_999))))
        XCTAssertEqual(try system(runtime, program, "isObjectValid", [gone]).truthy, false)
    }

    /// B183, B186, B187, B194, B197, B199: the host-action methods reach the host, each the way the
    /// matching skin action or menu does.
    func testHostActionMethodsReachTheHost() throws {
        let host = TransportHost()
        let (runtime, program) = try makeRuntime(host: host)
        var requests: [String] = []
        runtime.hooks.actionRequested = { action, _ in requests.append(action) }
        runtime.hooks.applicationRaiseRequested = { requests.append($0 ? "restore" : "activate") }
        runtime.hooks.windowMenuRequested = { requests.append("windowmenu") }
        runtime.hooks.equalizerEnabledSetterRequested = { requests.append("eq \($0)") }
        for method in ["eject", "minimizeApplication", "shutdown", "restoreApplication",
                       "activateApplication", "windowMenu"] {
            _ = try system(runtime, program, method)
        }
        _ = try system(runtime, program, "setEq", [.integer(1)])
        _ = try system(runtime, program, "setEq", [.integer(0)])
        XCTAssertEqual(host.calls, ["openFiles"])
        XCTAssertEqual(requests, ["MINIMIZE", "CLOSE", "restore", "activate", "windowmenu", "eq true", "eq false"])
    }

    /// B183: the stock notifier's "only when minimized" modes read `isMinimized`, which answered false.
    func testIsMinimizedAsksTheHost() throws {
        let (runtime, program) = try makeRuntime()
        XCTAssertEqual(try system(runtime, program, "isMinimized").integerValue, 0)
        runtime.hooks.applicationMinimizedRequested = { true }
        XCTAssertEqual(try system(runtime, program, "isMinimized").integerValue, 1)
    }

    /// `shutdown` has an arity only on `Application`, so another class declaring the verb is not given it.
    func testShutdownIsGatedToApplication() throws {
        let (runtime, _) = try makeRuntime()
        // The interpreter passes the GUID in bytecode word order; `canonical` is its own inverse.
        let bytecodeGUID = MakiClassGUID.canonical(MakiClassGUID.application)
        XCTAssertNotNil(runtime.signature(for: "Shutdown", classGUID: bytecodeGUID))
        XCTAssertNil(runtime.signature(for: "shutdown", classGUID: nil))
    }

    /// B182: the thirteen events scripts call as methods have their `std.mi` arity, and the three
    /// names another class declares with a different arity get that one on that class.
    func testEventsCalledAsMethodsHaveTheirDeclaredArity() throws {
        let (runtime, _) = try makeRuntime()
        let arities = ["onLeftButtonDown": 2, "onLeftButtonUp": 2, "onRightButtonDown": 2,
                       "onRightButtonUp": 2, "onMouseMove": 2, "onNotify": 4, "onEqChanged": 1,
                       "onInfoChange": 1, "onSwitchToLayout": 1, "onPlay": 0, "onStop": 0,
                       "onAccelerator": 1, "onFrame": 1]
        for (event, arity) in arities {
            XCTAssertEqual(runtime.signature(for: event, classGUID: nil)?.argumentCount, arity, event)
        }
        let bytecode = MakiClassGUID.canonical
        XCTAssertEqual(runtime.signature(for: "onNotify", classGUID: bytecode(MakiClassGUID.wac))?.argumentCount, 3)
        XCTAssertEqual(runtime.signature(for: "onAccelerator", classGUID: bytecode(MakiClassGUID.system))?.argumentCount, 3)
        XCTAssertEqual(runtime.signature(for: "onFrame", classGUID: bytecode(MakiClassGUID.vis))?.argumentCount, 0)
    }

    /// B190: `getMode` reads back what `setMode` wrote, and the analyzer when nothing has.
    func testVisGetModeReadsTheMode() throws {
        let (runtime, program) = try makeRuntime(body: #"<vis id="v" w="8" h="8"/>"#)
        let vis = try XCTUnwrap(runtime.loadedSkin.runtime.graph.allObjectsUnordered.first { $0.xmlID == "v" })
        let reference = MakiObjectReference(.gui(vis.stableID))
        XCTAssertEqual(try runtime.invoke(method: "getMode", on: reference, arguments: [], program: program).integerValue, 1)
        _ = try runtime.invoke(method: "setMode", on: reference, arguments: [.integer(2)], program: program)
        XCTAssertEqual(try runtime.invoke(method: "getMode", on: reference, arguments: [], program: program).integerValue, 2)
    }

    /// B206: the point is in the object's parent space; B201: `center` moves the layout's window.
    func testIsMouseOverAndCenterUseTheResolvedFrame() throws {
        let (runtime, program) = try makeRuntime()
        let layout = try XCTUnwrap(runtime.loadedSkin.runtime.graph.roots.first?.children.first)
        let reference = MakiObjectReference(.gui(layout.stableID))
        runtime.hooks.resolvedGeometryRequested = { _ in
            (frame: CGRect(x: 15, y: 15, width: 20, height: 10), parent: CGRect(x: 5, y: 5, width: 100, height: 100))
        }
        func over(_ x: Int32, _ y: Int32) throws -> Bool {
            try runtime.invoke(method: "isMouseOver", on: reference, arguments: [.integer(x), .integer(y)],
                               program: program).truthy
        }
        XCTAssertTrue(try over(10, 10))
        XCTAssertFalse(try over(31, 10))

        var moved: CGPoint?
        runtime.hooks.containerMoveRequested = { _, point, _ in moved = point }
        _ = try runtime.invoke(method: "center", on: reference, arguments: [], program: program)
        let screen = NSScreen.main?.frame.size ?? .zero
        XCTAssertEqual(moved, CGPoint(x: Int(Int32(screen.width) - 20) / 2, y: Int(Int32(screen.height) - 10) / 2))
    }

    /// B185: a config attribute answers the name it was registered under.
    func testConfigAttributeAnswersItsName() throws {
        let (runtime, program) = try makeRuntime()
        let item = try system(runtime, program, "newItem", [.string("Options"), .string("{guid}")])
        guard case .object(let itemReference) = item else { return XCTFail("no config item") }
        let attribute = try runtime.invoke(method: "newAttribute", on: itemReference,
                                           arguments: [.string("Show clock"), .string("1")], program: program)
        guard case .object(let attributeReference) = attribute else { return XCTFail("no attribute") }
        XCTAssertEqual(try runtime.invoke(method: "getAttributeName", on: attributeReference, arguments: [],
                                          program: program).stringValue, "Show clock")
    }

    /// B195: the display under a point, in Winamp's top-left screen space — its work area, the
    /// menu bar and the Dock taken out, as Winamp's viewport is the screen minus its taskbars.
    func testViewportFromPointAnswersTheDisplayUnderIt() throws {
        let primary = try XCTUnwrap(NSScreen.screens.first, "no display")
        let visible = primary.visibleFrame
        let (runtime, program) = try makeRuntime()
        let point: [MakiValue] = [.integer(10), .integer(10)]
        XCTAssertEqual(try system(runtime, program, "getViewportLeftFromPoint", point).integerValue, Int32(visible.minX))
        XCTAssertEqual(try system(runtime, program, "getViewportTopFromPoint", point).integerValue,
                       Int32(primary.frame.height - visible.maxY))
        XCTAssertEqual(try system(runtime, program, "getViewportWidthFromPoint", point).integerValue, Int32(visible.width))
        XCTAssertEqual(try system(runtime, program, "getViewportHeightFromPoint", point).integerValue, Int32(visible.height))
    }

    /// B184: positive only for the playing item, and only when the host has its art.
    func testGetAlbumArtAnswersForThePlayingItem() throws {
        let host = TransportHost()
        host.trackPath = "/music/a.mp3"
        let (runtime, program) = try makeRuntime(host: host)
        XCTAssertEqual(try system(runtime, program, "getAlbumArt", [.string("/music/a.mp3")]).integerValue, 0)
        host.albumArtwork = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        XCTAssertEqual(try system(runtime, program, "getAlbumArt", [.string("/music/a.mp3")]).integerValue, 1)
        XCTAssertEqual(try system(runtime, program, "getAlbumArt", [.string("/music/b.mp3")]).integerValue, 0)
    }

    /// B192, B198, B189: a check box's checked state is its activation, a tab sheet's page reads
    /// and switches, and an edit keeps its auto-enter flag.
    func testFormWidgetMethods() throws {
        let (runtime, program) = try makeRuntime(
            body: #"<Wasabi:CheckBox id="c"/><Wasabi:TabSheet id="t" children="p1;p2"/><Wasabi:EditBox id="e"/>"#,
            definitions: #"<groupdef id="p1" name="One"/><groupdef id="p2" name="Two"/>"#)
        func call(_ id: String, _ method: String, _ arguments: [MakiValue] = []) throws -> MakiValue {
            let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.allObjectsUnordered.first { $0.xmlID == id })
            return try runtime.invoke(method: method, on: MakiObjectReference(.gui(object.stableID)),
                                      arguments: arguments, program: program)
        }
        XCTAssertFalse(try call("c", "isChecked").truthy)
        _ = try call("c", "setChecked", [.integer(1)])
        XCTAssertTrue(try call("c", "isChecked").truthy)

        XCTAssertEqual(try call("t", "getCurPage").integerValue, 0)
        _ = try call("t", "setCurPage", [.integer(1)])
        XCTAssertEqual(try call("t", "getCurPage").integerValue, 1)

        _ = try call("e", "setAutoEnter", [.integer(1)])
        XCTAssertEqual(try call("e", "getAutoEnter").integerValue, 1)
        _ = try call("e", "enter")
        XCTAssertEqual(runtime.signature(for: "onIdleEditUpdate", classGUID: nil)?.argumentCount, 0)
    }

    /// B193: a holder answers the name the thinger gives its surface, and an unknown one nothing.
    func testWindowHolderAnswersItsComponentName() throws {
        let (runtime, program) = try makeRuntime(
            body: #"<windowholder id="h" hold="guid:pl"/><windowholder id="x" hold="guid:{12345678-0000-0000-0000-000000000000}"/>"#)
        func name(_ id: String) throws -> String {
            let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.allObjectsUnordered.first { $0.xmlID == id })
            return try runtime.invoke(method: "getComponentName", on: MakiObjectReference(.gui(object.stableID)),
                                      arguments: [], program: program).stringValue
        }
        XCTAssertEqual(try name("h"), "Playlist Editor")
        XCTAssertEqual(try name("x"), "")
    }

    // MARK: - Helpers

    private static let syntheticProgram = MakiProgram(
        version: 0x0403, classes: [], methods: [], variables: [], bindings: [], instructions: [],
        source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"), ownerID: nil, parameter: nil)

    private func system(_ runtime: WinampModernScriptRuntime, _ program: MakiProgram,
                        _ method: String, _ arguments: [MakiValue] = []) throws -> MakiValue {
        try runtime.invoke(method: method, on: MakiObjectReference(.system), arguments: arguments, program: program)
    }

    private func makeRuntime(host: WinampModernHost = WinampModernStubHost(), body: String = "",
                             definitions: String = "") throws -> (WinampModernScriptRuntime, MakiProgram) {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>\(definitions)<container id="main"><layout id="normal" w="16" h="16">\(body)</layout></container></WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { runtime.teardown() }
        return (runtime, Self.syntheticProgram)
    }

    private final class TransportHost: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []
        var trackPath = ""
        var albumArtwork: CGImage?
        var calls: [String] = []

        func play() {}
        func pause() {}
        func stop() {}
        func previous() { calls.append("previous") }
        func next() { calls.append("next") }
        func seek(to seconds: TimeInterval) {}
        func openFiles() { calls.append("openFiles") }
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
