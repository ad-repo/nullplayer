import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 25's regression cover, written with backlog B10.
///
/// Phase 25 took Defix Hi-END 200 from `unsupported` to `degraded` and its tests were deferred to a
/// live QA pass that then closed without them ("no unit tests were written this phase"). Five
/// behaviours were left resting on one skin's screenshot; each is asserted here.
///
/// 25.1 — `alpha` is per **object**, not per kind of drawing — is covered in pixels by
/// `WinampModernGoldenImageTests.testAlphaAppliesToEveryObjectGolden` (an `alpha="0"` text must be
/// absent from the frame; a half-alpha sprite must blend). What is left for here is the parse
/// itself, which the golden cannot see the edges of.
final class WinampModernPhase25RegressionTests: XCTestCase {

    // MARK: - 25.1 `alpha` applies to every object

    /// Defix stacks its Kbps / KHz / Channels readouts in one slot at `alpha="0"` and shows one at a
    /// time by moving the alphas. Anything unparsable is opaque — a readout that cannot be read is
    /// shown, never silently erased.
    func testAlphaFractionReadsEveryFormAnObjectCanCarry() throws {
        let runtime = try makeRuntime(xml: Self.alphaXML)
        func alpha(_ id: String) throws -> CGFloat {
            WasabiSceneRenderer.alphaFraction(of: try object(named: id, in: runtime))
        }

        XCTAssertEqual(try alpha("plain"), 1, "no attribute is opaque")
        XCTAssertEqual(try alpha("hidden"), 0)
        XCTAssertEqual(try alpha("half"), 128.0 / 255)
        XCTAssertEqual(try alpha("solid"), 1)
        XCTAssertEqual(try alpha("garbage"), 1, "an unparsable alpha is opaque, not invisible")
        XCTAssertEqual(try alpha("over"), 1, "clamped, not wrapped")
        XCTAssertEqual(try alpha("under"), 0)
    }

    // MARK: - 25.2 An image param is a load, and a failed load changes nothing

    /// Defix builds every background id by prefixing `getPrivateString(getSkinName(), "BG", "")`,
    /// which it never seeds. Taken literally, the layout was asked for background `""` and the nine
    /// frame slices for `"" + "_background_material.Element.top.left"` — ids no skin defines — and
    /// the wood panel, the frame, both speakers, the playlist and the library all went flat black.
    func testAnUnresolvableImageParamLeavesTheObjectWearingWhatItHad() throws {
        let runtime = try makeRuntime(xml: Self.alphaXML)
        let layer = try object(named: "plain", in: runtime)

        for (key, value) in [("image", "no.such.bitmap"), ("image", ""),
                             ("background", "" ), ("downimage", "also.missing"),
                             ("thumb", "nope"), ("notfoundimage", "")] {
            try setXmlParam(key, value, on: layer, in: runtime)
        }

        XCTAssertEqual(layer.attributes["image"], "sprite.red", "a failed load is not a change")
        XCTAssertNil(layer.attributes["background"])
        XCTAssertNil(layer.attributes["downimage"])
        XCTAssertNil(layer.attributes["thumb"])
        XCTAssertNil(layer.attributes["notfoundimage"])
    }

    /// …and one that *does* resolve is applied, so the guard is a load and not a refusal to swap
    /// artwork at all. A colour id counts: `background` is written with both, so the question the
    /// runtime asks is registration, not kind.
    func testAResolvableImageParamIsApplied() throws {
        let runtime = try makeRuntime(xml: Self.alphaXML)
        let layer = try object(named: "plain", in: runtime)

        try setXmlParam("image", "sprite.green", on: layer, in: runtime)
        try setXmlParam("background", "colour.ink", on: layer, in: runtime)

        XCTAssertEqual(layer.attributes["image"], "sprite.green")
        XCTAssertEqual(layer.attributes["background"], "colour.ink")
    }

    /// A param that is not image-valued is a value in itself and is written whatever it says — the
    /// guard must not spread to geometry, text or colours.
    func testANonImageParamIsWrittenWhateverItSays() throws {
        let runtime = try makeRuntime(xml: Self.alphaXML)
        let layer = try object(named: "plain", in: runtime)

        try setXmlParam("x", "17", on: layer, in: runtime)
        try setXmlParam("tooltip", "not a resource", on: layer, in: runtime)

        XCTAssertEqual(layer.attributes["x"], "17")
        XCTAssertEqual(layer.attributes["tooltip"], "not a resource")
    }

    // MARK: - 25.3 The methods that were taking whole handlers down

    /// Each of these surfaced only once the one before it was implemented — Defix's blocking list is
    /// a queue — and every one of them aborted the handler that called it. They are asserted for
    /// their *answers*, because "accepted and inert" and "unimplemented" are indistinguishable from
    /// the outside until you look at what comes back.
    func testGetExtensionIsTheTailAfterTheLastDot() throws {
        let (runtime, program) = try makeRuntimeAndProgram()
        func extension_(_ path: String) throws -> String {
            try runtime.invoke(method: "getExtension", on: MakiObjectReference(.system),
                               arguments: [.string(path)], program: program).stringValue
        }

        XCTAssertEqual(try extension_("/Music/Album/track.mp3"), "mp3")
        XCTAssertEqual(try extension_("track.tar.gz"), "gz", "after the *last* dot")
        XCTAssertEqual(try extension_("/Music/no-extension"), "")
        XCTAssertEqual(try extension_("/Music.d/no-extension"), "",
                       "a dot in a parent directory is not the file's extension")
        XCTAssertEqual(try extension_(""), "")
    }

    /// Layer FX is accepted and **inert**: we draw the layer undistorted rather than abort the
    /// handler that switched it on. Defix's `VU_LAYOUT_1.maki` calls eight of these in a row.
    func testLayerFXCallsAreAcceptedAndDoNotAbortTheHandler() throws {
        let (runtime, program) = try makeRuntimeAndProgram()
        let layer = try object(named: "plain", in: runtime)
        let target = MakiObjectReference(.gui(layer.stableID))

        for (method, arguments) in [("fx_setEnabled", [MakiValue.boolean(true)]),
                                    ("fx_setWrap", [.boolean(true)]),
                                    ("fx_setRect", [.boolean(false)]),
                                    ("fx_setBgFx", [.boolean(false)]),
                                    ("fx_setClear", [.boolean(true)]),
                                    ("fx_setRealtime", [.boolean(true)]),
                                    ("fx_setLocalized", [.boolean(true)]),
                                    ("fx_setBilinear", [.boolean(true)]),
                                    ("fx_setSpeed", [.integer(5)]),
                                    ("fx_setGridSize", [.integer(4), .integer(4)]),
                                    ("fx_update", [])] {
            XCTAssertNoThrow(try runtime.invoke(method: method, on: target,
                                                arguments: arguments, program: program),
                             "\(method) must not take the handler down")
            XCTAssertNil(runtime.unsupportedMethodCalls[method.lowercased()],
                         "\(method) is implemented, not merely tolerated")
        }
    }

    /// `newDynamicContainer(id)` answers with the container of that id rather than failing: Winamp
    /// builds a fresh instance, and the one already in the graph is the instance we have.
    func testNewDynamicContainerAnswersTheContainerOfThatID() throws {
        let (runtime, program) = try makeRuntimeAndProgram()

        let value = try runtime.invoke(method: "newDynamicContainer", on: MakiObjectReference(.system),
                                       arguments: [.string("Main")], program: program)

        guard case .object(let reference) = value, case .gui(let id) = reference.kind else {
            return XCTFail("expected the container object, got \(value)")
        }
        XCTAssertEqual(runtime.loadedSkin.runtime.graph.object(withID: id)?.xmlID, "Main")
    }

    /// `setFontSize(px)` writes the same pixel height the XML attribute carries, so the renderer's
    /// existing measurement path picks it up with no font-specific code.
    func testSetFontSizeWritesThePixelHeightTheXMLAttributeCarries() throws {
        let (runtime, program) = try makeRuntimeAndProgram()
        let text = try object(named: "caption", in: runtime)

        _ = try runtime.invoke(method: "setFontSize", on: MakiObjectReference(.gui(text.stableID)),
                               arguments: [.integer(19)], program: program)

        XCTAssertEqual(text.attributes["fontsize"], "19", "the attribute the XML would have carried")
        // …and it goes through the one pixel-height→point conversion the renderer and `getAutoWidth()`
        // share, rather than being handed to CoreText as a point size of its own.
        XCTAssertEqual(WasabiTextMetrics.pointSize(of: text),
                       19 * CGFloat(WasabiTextMetrics.pixelHeightToPointSize))
    }

    /// Navigation is denied, and denied *quietly* — the sandbox refuses the URL, and the handler that
    /// asked carries on. `System.hasVideoSupport()` is false for the same reason a `.wal` video
    /// holder gets the neutral backing: nothing behind it yet (backlog B20).
    func testNavigationIsDeniedQuietlyAndVideoSupportIsFalse() throws {
        let (runtime, program) = try makeRuntimeAndProgram()
        let browser = try object(named: "plain", in: runtime)

        let system = try runtime.invoke(method: "navigateUrl", on: MakiObjectReference(.system),
                                        arguments: [.string("https://example.com")], program: program)
        let object = try runtime.invoke(method: "navigateUrl",
                                        on: MakiObjectReference(.gui(browser.stableID)),
                                        arguments: [.string("https://example.com")], program: program)
        let video = try runtime.invoke(method: "hasVideoSupport", on: MakiObjectReference(.system),
                                       arguments: [], program: program)

        if case .null = system {} else { XCTFail("System.navigateUrl must answer null, got \(system)") }
        if case .null = object {} else { XCTFail("<browser>.navigateUrl must answer null, got \(object)") }
        XCTAssertFalse(video.truthy)
        XCTAssertTrue(runtime.loadedSkin.runtime.diagnostics.isEmpty,
                      "a denied navigation is not a skin defect to report")
    }

    // MARK: - 25.4 Load order: a skin-level `<scripts>` block runs last

    /// `skin.xml` puts its `<scripts>` block after every object and every XUI param, and Winamp loads
    /// it there — so it is the one script that may assume the rest of the skin is configured. Defix's
    /// lays out its whole SUI tab strip as `label.getAutoWidth() + 20` per tab; run before the labels
    /// arrived as params, all five tabs came out at that bare 20px stacked at the left edge.
    ///
    /// The object-owned script keeps its old position: its own `onScriptLoaded` first, then its
    /// params (the handler binds to the group that `onScriptLoaded` populates, so the params can
    /// never come first), and only then the skin-level block.
    func testASkinLevelScriptRunsAfterEveryObjectScriptAndItsXUIParams() throws {
        let runtime = try makeRuntime(xml: Self.orderXML,
                                      files: [("owned.maki", Self.makeScript()),
                                              ("skinlevel.maki", Self.makeScript())])
        // A program's `source` is the XML that declared it, not the `.maki` it was compiled from, so
        // the two are told apart by their owner: the skin-level block has none.
        let widget = try object(named: "widget", in: runtime)
        var order: [String] = []
        runtime.dispatchObserver = { event, program, _ in
            order.append("\(event)@\(program.ownerID == widget.stableID ? "owned" : "skin-level")")
        }

        try runtime.start()

        XCTAssertEqual(order.first, "onscriptloaded@owned")
        XCTAssertEqual(order.last, "onscriptloaded@skin-level")
        let params = order.filter { $0.hasPrefix("onsetxuiparam@") }
        XCTAssertFalse(params.isEmpty, "the XUI instance's attributes are delivered as params")
        XCTAssertTrue(params.allSatisfy { $0.hasSuffix("@owned") },
                      "params go only to the programs the instance owns")
        let lastParam = try XCTUnwrap(order.lastIndex { $0.hasPrefix("onsetxuiparam@") })
        let skinLevel = try XCTUnwrap(order.lastIndex(of: "onscriptloaded@skin-level"))
        XCTAssertLessThan(lastParam, skinLevel, "the skin-level block runs after the params land")
    }

    // MARK: - 25.5 `@HAVE_LIBRARY@` is a script param macro, not a path variable

    /// Defix reads `stringToInteger(getParam())` as "is there a media library?". Reading the literal
    /// `@HAVE_LIBRARY@` as 0, it dropped the Media Library and Playlist tabs out of its SUI tab
    /// strip. NullPlayer hosts the library surface, so the answer is 1 — and a macro we do not know
    /// is left exactly as written, because a skin that invented one gets what it wrote.
    func testTheLibraryMacroIsExpandedAndAnUnknownOneIsNot() throws {
        let runtime = try makeRuntime(xml: Self.macroXML,
                                      files: [("owned.maki", Self.makeScript()),
                                              ("skinlevel.maki", Self.makeScript())])
        let parameters = Dictionary(uniqueKeysWithValues: runtime.loadedSkin.runtime.scriptBindings
            .map { ((($0.logicalPath as NSString).lastPathComponent), $0.parameter) })

        XCTAssertEqual(parameters["skinlevel.maki"], "1", "@HAVE_LIBRARY@ — we host the library")
        XCTAssertEqual(parameters["owned.maki"], "@NOT_A_MACRO@ 4",
                       "an unrecognized macro passes through untouched")
    }

    // MARK: - 25.6 `notify="key,value"` delivers XUI params on a `<group>` instance

    /// Lobe's Pledit uses `<group id="wasabi.standardframe.statusbar" notify="content,pledit.normal.
    /// content.group">` — a `<group>` instance, not a XUI tag like `<Wasabi:StandardFrame:Status>`.
    /// The standard frame script reads the `content` param to instantiate the playlist body, so
    /// `notify` must deliver it as `onSetXuiParam("content", "...")` even though the tag is `group`.
    func testNotifyAttributeDeliversXUIParamsOnAGroupInstance() throws {
        let runtime = try makeRuntime(xml: Self.notifyXML,
                                      files: [("frame.maki", Self.makeScript())])
        let frame = try object(named: "synthetic.frame", in: runtime)
        var params: [(String, String)] = []
        runtime.dispatchObserver = { event, program, _ in
            guard event == "onsetxuiparam", program.ownerID == frame.stableID else { return }
            params.append(("onsetxuiparam", program.ownerID == frame.stableID ? "owned" : "other"))
        }

        try runtime.start()

        XCTAssertFalse(params.isEmpty, "notify= must deliver onSetXuiParam to the group's script")
    }

    private static let notifyXML = """
    <WasabiXML>
      <groupdef id="synthetic.frame" xuitag="Synthetic:Frame">
        <script file="frame.maki"/>
      </groupdef>
      <container id="Main">
        <layout id="normal" w="300" h="250">
          <group id="synthetic.frame" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                 notify="content,my.content.group"/>
        </layout>
      </container>
    </WasabiXML>
    """

    // MARK: - Fixtures

    private static let alphaXML = """
    <WasabiXML>
      <elements>
        <bitmap id="sprite.red" file="atlas.png" x="0" y="0" w="8" h="8"/>
        <bitmap id="sprite.green" file="atlas.png" x="8" y="0" w="8" h="8"/>
        <color id="colour.ink" value="10,20,30"/>
      </elements>
      <container id="Main">
        <layout id="normal" w="40" h="20">
          <layer id="plain"   image="sprite.red" x="0" y="0" w="8" h="8"/>
          <layer id="hidden"  image="sprite.red" alpha="0"/>
          <layer id="half"    image="sprite.red" alpha="128"/>
          <layer id="solid"   image="sprite.red" alpha="255"/>
          <layer id="garbage" image="sprite.red" alpha="opaque"/>
          <layer id="over"    image="sprite.red" alpha="900"/>
          <layer id="under"   image="sprite.red" alpha="-40"/>
          <text  id="caption" text="abc" x="0" y="8" w="40" h="12" fontsize="9"/>
        </layout>
      </container>
    </WasabiXML>
    """

    private static let orderXML = """
    <WasabiXML>
      <groupdef id="synthetic.widget" xuitag="Synthetic:Widget">
        <script file="owned.maki"/>
      </groupdef>
      <container id="Main">
        <layout id="normal" w="40" h="20">
          <Synthetic:Widget id="widget" label="Media Library"/>
        </layout>
      </container>
      <scripts><script file="skinlevel.maki"/></scripts>
    </WasabiXML>
    """

    private static let macroXML = """
    <WasabiXML>
      <groupdef id="synthetic.widget" xuitag="Synthetic:Widget">
        <script file="owned.maki" param="@NOT_A_MACRO@ 4"/>
      </groupdef>
      <container id="Main">
        <layout id="normal" w="40" h="20">
          <Synthetic:Widget id="widget"/>
        </layout>
      </container>
      <scripts><script file="skinlevel.maki" param="@HAVE_LIBRARY@"/></scripts>
    </WasabiXML>
    """

    // MARK: - Helpers

    private func setXmlParam(_ key: String, _ value: String, on object: WasabiObject,
                             in runtime: WinampModernScriptRuntime) throws {
        _ = try runtime.invoke(method: "setXmlParam", on: MakiObjectReference(.gui(object.stableID)),
                               arguments: [.string(key), .string(value)],
                               program: Self.makeProgram())
    }

    private func makeRuntimeAndProgram() throws -> (WinampModernScriptRuntime, MakiProgram) {
        (try makeRuntime(xml: Self.alphaXML), Self.makeProgram())
    }

    private func makeRuntime(xml: String, files: [(String, Data)] = []) throws
        -> WinampModernScriptRuntime {
        let loaded = try WinampModernSkinLoader(engineStore: nil)
            .load(from: try makeArchive(files: [("skin.xml", Data(xml.utf8)),
                                                ("atlas.png", try Self.makeAtlas())] + files))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func object(named xmlID: String, in runtime: WinampModernScriptRuntime) throws
        -> WasabiObject {
        try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: xmlID).first)
    }

    private static func makeProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                    ownerID: nil, parameter: nil)
    }

    /// A program that binds `onScriptLoaded` and `onSetXuiParam` on the System object and returns
    /// immediately from both. Enough to observe *when* the runtime dispatches each of them, which is
    /// the whole of 25.4.
    private static func makeScript() -> Data {
        var data = Data([0x46, 0x47])
        func u8(_ value: UInt8) { data.append(value) }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func string(_ value: String) {
            let bytes = Data(value.utf8)
            u16(UInt16(bytes.count))
            data.append(bytes)
        }
        u16(0x0403)
        u32(23)
        u32(1)                                   // one class: the System object's
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        let methods = ["onscriptloaded", "onsetxuiparam"]
        u32(UInt32(methods.count))
        for method in methods {
            u16(0); u16(0); string(method)
        }
        u32(1)                                   // one variable: System
        u8(0); u8(1); u16(0); u16(0); u16(0); u16(0); u16(0); u8(1); u8(1)
        u32(0)                                   // no constants
        u32(UInt32(methods.count))               // both handlers enter at offset 0
        for method in 0..<methods.count {
            u32(0); u32(UInt32(method)); u32(0)
        }
        u32(1)
        u8(33)                                   // `return`
        return data
    }

    private static func makeAtlas() throws -> Data {
        let side = 16
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for row in 0..<side {
            for column in 0..<side {
                let offset = (row * side + column) * 4
                pixels[offset] = column < 8 ? 220 : 40
                pixels[offset + 1] = column < 8 ? 40 : 200
                pixels[offset + 2] = 40
            }
        }
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: side, height: side,
                                                  bitsPerComponent: 8, bytesPerRow: side * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    private func makeArchive(files: [(String, Data)]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase25RegressionTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase25.wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
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
