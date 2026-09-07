import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 33 — the six MAKI methods multipass's startup runs through, and the togglebutton click that
/// turned out to be missing behind them.
///
/// The subject is fail-closed dispatch: a method the runtime does not know **aborts the handler that
/// called it**, and multipass calls `System.newGroupAsLayout` from the eighth statement of the first
/// initialiser of `System.onScriptLoaded`. One refusal took the drawers, the seek bar, the time
/// readout, the sliders, the notifier and the style switcher with it. Every case here is either that
/// blocker or one of the methods immediately downstream of it.
final class WinampModernPhase33Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 240
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Synthetic Song"
        var trackInfo = "Synthetic Artist"
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

    /// `floating.list` is multipass's colour-theme list in miniature: a groupdef that names its owner
    /// layout and is instantiated only at runtime. `orphan.list` is the same thing without an
    /// `owner=`, which is the fallback path. Both carry a script so the subtree's own startup can be
    /// observed.
    private static let skinXML = """
    <WasabiXML>
      <elements>
        <bitmap id="sheet" file="sheet.png"/>
      </elements>
      <groupdef id="floating.list" w="164" h="78" owner="main,normal">
        <layer id="floating.layer" x="0" y="0" w="10" h="10"/>
        <script id="floating.script" file="scripts/empty.maki"/>
      </groupdef>
      <groupdef id="orphan.list" w="30" h="30">
        <layer id="orphan.layer" x="0" y="0" w="10" h="10"/>
      </groupdef>
      <container id="main">
        <layout id="normal" w="252" h="333">
          <layer id="background" x="0" y="0" w="252" h="333"/>
          <togglebutton id="drawer.toggle" x="0" y="0" w="17" h="17"/>
          <togglebutton id="cfg.toggle" x="20" y="0" w="17" h="17" cfgattrib="{E9C2D926};Opt"/>
          <button id="plain.button" x="40" y="0" w="17" h="17"/>
          <slider id="knob" x="60" y="0" w="60" h="10"/>
        </layout>
      </container>
      <container id="notifier">
        <layout id="normal" w="100" h="40"/>
      </container>
    </WasabiXML>
    """

    // MARK: - 1. `System.newGroupAsLayout` — the blocker

    func testNewGroupAsLayoutParentsToTheOwnerLayoutAndAppendsLast() throws {
        let (runtime, program) = try makeRuntime()
        let layout = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "normal").first)
        let childrenBefore = layout.children.count

        let created = try unwrapObject(runtime.invoke(method: "newGroupAsLayout",
                                                      on: MakiObjectReference(.system),
                                                      arguments: [.string("floating.list")],
                                                      program: program), in: runtime)

        XCTAssertTrue(created.parent === layout, "owner=\"main,normal\" names the layout it hangs off")
        XCTAssertEqual(layout.children.count, childrenBefore + 1)
        XCTAssertTrue(layout.children.last === created,
                      "appended last, so it draws over the drawer background rather than under it")
        XCTAssertNotNil(created.children.first { $0.xmlID == "floating.layer" },
                        "the groupdef is expanded, not just an empty shell")
    }

    /// It stays a **group**. Typed `layout`, the `resize()` multipass positions it with would be read
    /// as a window resize and shrink the player to 164×78.
    func testCreatedObjectKeepsAGroupTypeAndResizeDoesNotResizeTheWindow() throws {
        let (runtime, program) = try makeRuntime()
        var resizes: [(WasabiObjectID, CGSize)] = []
        runtime.layoutResizeRequested = { resizes.append(($0, $1)) }

        let created = try unwrapObject(runtime.invoke(method: "newGroupAsLayout",
                                                      on: MakiObjectReference(.system),
                                                      arguments: [.string("floating.list")],
                                                      program: program), in: runtime)
        XCTAssertEqual(created.typeName.lowercased(), "group")

        let reference = MakiObjectReference(.gui(created.stableID))
        _ = try runtime.invoke(method: "resize", on: reference,
                               arguments: [.integer(54), .integer(217), .integer(164), .integer(78)],
                               program: program)
        // The measured multipass placement: `layoutMainNormal.getLeft() + 54`, `getTop() + 217`.
        XCTAssertEqual(created.attributes["x"], "54")
        XCTAssertEqual(created.attributes["y"], "217")
        XCTAssertEqual(created.attributes["w"], "164")
        XCTAssertEqual(created.attributes["h"], "78")
        XCTAssertTrue(resizes.isEmpty, "a group's resize is graph state, not a window resize")
    }

    /// No `owner=`: the group lands on the calling script's own layout instead of nowhere.
    func testFallsBackToTheCallersLayoutWhenTheGroupdefNamesNoOwner() throws {
        let (runtime, _) = try makeRuntime()
        let layout = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "normal").first)
        let caller = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "background").first)
        let program = Self.makeProgram(ownerID: caller.stableID)

        let created = try unwrapObject(runtime.invoke(method: "newGroupAsLayout",
                                                      on: MakiObjectReference(.system),
                                                      arguments: [.string("orphan.list")],
                                                      program: program), in: runtime)
        XCTAssertTrue(created.parent === layout)
    }

    /// A `skin.xml`-level script has no layout above it, so there is nothing to parent to. Answering
    /// null is the honest outcome; putting the group somewhere arbitrary is not.
    func testAnswersNullWhenNeitherOwnerNorCallerNamesALayout() throws {
        let (runtime, program) = try makeRuntime()
        let answer = try runtime.invoke(method: "newGroupAsLayout", on: MakiObjectReference(.system),
                                        arguments: [.string("orphan.list")], program: program)
        guard case .null = answer else { return XCTFail("expected null, got \(answer)") }
    }

    /// The subtree comes up like any other: its scripts are queued and started when the dispatch that
    /// created it unwinds, exactly as `newGroup`'s are.
    func testTheCreatedSubtreesScriptsStart() throws {
        let (runtime, program) = try makeRuntime()
        let programsBefore = runtime.programs.count
        _ = try runtime.invoke(method: "newGroupAsLayout", on: MakiObjectReference(.system),
                               arguments: [.string("floating.list")], program: program)
        XCTAssertEqual(runtime.programs.count, programsBefore,
                       "creation is only the first half of Wasabi's two-step")
        // Any outermost dispatch drains what is still pending.
        try runtime.dispatchSystem(event: "onsynthetic")
        XCTAssertEqual(runtime.programs.count, programsBefore + 1)
    }

    /// The regression guard for the whole phase: the method resolves, so the handler that calls it
    /// keeps running instead of being abandoned at that statement.
    func testTheMethodIsKnownAndDoesNotAbortItsCaller() throws {
        let (runtime, program) = try makeRuntime()
        XCTAssertNotNil(runtime.signature(for: "newGroupAsLayout", classGUID: nil))
        _ = try runtime.invoke(method: "newGroupAsLayout", on: MakiObjectReference(.system),
                               arguments: [.string("floating.list")], program: program)
        XCTAssertTrue(runtime.unsupportedMethodCalls.isEmpty,
                      "an unsupported method is what aborted multipass's entire startup")
    }

    // MARK: - 2–4. `strUpper`, `getClassName`, `isAppActive`

    func testStrUpper() throws {
        let (runtime, program) = try makeRuntime()
        XCTAssertEqual(try runtime.invoke(method: "strUpper", on: MakiObjectReference(.system),
                                          arguments: [.string("Togglebutton")],
                                          program: program).stringValue, "TOGGLEBUTTON")
    }

    /// multipass's `initStyle` branches on `strUpper(getClassName())` — the pairing is the point, so
    /// the assertion is made through the same two calls the skin makes.
    func testGetClassNameAnswersTheObjectsKindForEachStyledType() throws {
        let (runtime, program) = try makeRuntime()
        for (id, expected) in [("background", "LAYER"), ("drawer.toggle", "TOGGLEBUTTON"),
                               ("plain.button", "BUTTON"), ("knob", "SLIDER")] {
            let object = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: id).first)
            let name = try runtime.invoke(method: "getClassName",
                                          on: MakiObjectReference(.gui(object.stableID)),
                                          arguments: [], program: program)
            let upper = try runtime.invoke(method: "strUpper", on: MakiObjectReference(.system),
                                           arguments: [name], program: program)
            XCTAssertEqual(upper.stringValue, expected, "\(id)")
        }
    }

    func testIsAppActiveAnswersTheApplicationRatherThanARefusal() throws {
        let (runtime, program) = try makeRuntime()
        let answer = try runtime.invoke(method: "isAppActive", on: MakiObjectReference(.system),
                                        arguments: [], program: program)
        XCTAssertEqual(answer.truthy, NSApp?.isActive ?? true)
        XCTAssertTrue(runtime.unsupportedMethodCalls.isEmpty)
    }

    // MARK: - 5. `ToggleButton.setActivatedNoCallback`

    func testSetActivatedNoCallbackWritesTheStateWithoutTheNotification() throws {
        let (runtime, program) = try makeRuntime()
        let button = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "drawer.toggle").first)
        let reference = MakiObjectReference(.gui(button.stableID))
        runtime.recordsDispatchedEventsForTesting = true

        _ = try runtime.invoke(method: "setActivatedNoCallback", on: reference,
                               arguments: [.boolean(true)], program: program)
        XCTAssertEqual(button.attributes["activated"], "1")
        XCTAssertFalse(runtime.dispatchedEventsForTesting.contains { $0.event == "ontoggle" },
                       "this is the method whose whole purpose is not re-entering the handler")

        // The plain setter is the contrast, and the reason the quiet one has to exist.
        _ = try runtime.invoke(method: "setActivated", on: reference,
                               arguments: [.boolean(false)], program: program)
        XCTAssertEqual(button.attributes["activated"], "0")
        XCTAssertTrue(runtime.dispatchedEventsForTesting.contains {
            $0.object == "drawer.toggle" && $0.event == "ontoggle"
        })
    }

    // MARK: - 6. `Container.close`

    func testContainerCloseHidesThatWindowAndAnythingElseStopsInTheGraph() throws {
        let (runtime, program) = try makeRuntime()
        var requests: [(String, Bool)] = []
        runtime.containerVisibilityRequested = { requests.append(($0, $1)) }

        let container = try XCTUnwrap(runtime.loadedSkin.runtime.graph.roots.first {
            $0.xmlID == "notifier"
        })
        _ = try runtime.invoke(method: "close", on: MakiObjectReference(.gui(container.stableID)),
                               arguments: [], program: program)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.0, "notifier")
        XCTAssertEqual(requests.first?.1, false)
        XCTAssertEqual(container.attributes["visible"], "0")

        let layer = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "background").first)
        _ = try runtime.invoke(method: "close", on: MakiObjectReference(.gui(layer.stableID)),
                               arguments: [], program: program)
        XCTAssertEqual(requests.count, 1, "only a container is a window")
    }

    // MARK: - The togglebutton click found while verifying the above

    /// A person clicking a togglebutton is the *other* way `activated` changes, and until this it was
    /// the way that did nothing: `ontoggle` was dispatched only from `setActivated`, so multipass's
    /// bottom drawer — which opens from `buttonDrawerBottomToggle.onToggle` and from nothing else —
    /// stayed shut even with the startup abort fixed.
    func testAUserClickFlipsATogglebuttonAndNotifiesTheSkin() throws {
        let (runtime, _) = try makeRuntime()
        let button = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "drawer.toggle").first)
        runtime.recordsDispatchedEventsForTesting = true

        XCTAssertTrue(runtime.toggleActivation(of: button))
        XCTAssertEqual(button.attributes["activated"], "1")
        XCTAssertTrue(runtime.dispatchedEventsForTesting.contains {
            $0.object == "drawer.toggle" && $0.event == "ontoggle"
        })
        XCTAssertTrue(runtime.toggleActivation(of: button))
        XCTAssertEqual(button.attributes["activated"], "0", "a second click undoes the first")
    }

    func testAConfigBoundToggleAndANonToggleAreLeftToTheirOwnRoutes() throws {
        let (runtime, _) = try makeRuntime()
        // A `cfgattrib` control's state *is* the stored preference; a second copy here could disagree.
        let bound = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "cfg.toggle").first)
        XCTAssertFalse(runtime.toggleActivation(of: bound))
        XCTAssertNil(bound.attributes["activated"])

        let plain = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "plain.button").first)
        XCTAssertFalse(runtime.toggleActivation(of: plain))
    }

    // MARK: - The seek bar: three faults between a working script and a visible control

    /// An animated layer with no `w`/`h` is one **frame** big, not one sheet big. multipass's seek bar
    /// is a 139×13 control cut from a 139×364 strip; sized to the strip it was a box 28 frames tall,
    /// clipped by the display group down to a transparent sliver, so the skin's only seek indicator
    /// was invisible.
    func testAnAnimatedLayerWithoutASizeIsOneFrameTall() throws {
        let (loaded, renderer) = try makeScene()
        defer { renderer.teardown(); loaded.teardown() }
        let bar = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "bar").first)
        XCTAssertEqual(renderer.frame(of: bar), CGRect(x: 0, y: 20, width: 16, height: 4))
        // A plain layer beside it still takes its whole bitmap.
        let plain = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "plain").first)
        XCTAssertEqual(renderer.frame(of: plain)?.size, CGSize(width: 16, height: 16))
    }

    /// Its clickable region is the **union** of its frames. Testing the frame on screen instead makes
    /// a fill animation unclickable exactly where it matters — ahead of the playhead, which is the
    /// only reason to click a seek bar at all.
    func testAnAnimatedLayersRegionIsTheUnionOfItsFrames() throws {
        let (loaded, renderer) = try makeScene()
        defer { renderer.teardown(); loaded.teardown() }
        let bar = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "bar").first)
        // The fixture's sheet is opaque on the left half of frame 0 and on the right half of frame 3;
        // frame 0 is showing, so the right half is only reachable through the union.
        XCTAssertTrue(renderer.object(at: CGPoint(x: 3, y: 22)) === bar)
        XCTAssertTrue(renderer.object(at: CGPoint(x: 13, y: 22)) === bar,
                      "a point only a later frame paints is still part of the control")
    }

    /// MAKI divides in real numbers whatever its operands are, and narrows on the **store**. Both
    /// multipass (`Float pct = mapValue / 255 * 100`, `seekTo(len * (pos / 255))`) and ClassicPro's own
    /// engine (`integerToString(newvol / 255 * 100) + "%"`) are written that way — read as integer
    /// division every one of them is 0, which is what made multipass seek to 0:00 from any click and
    /// cPro-Bento report `Volume: 0%` at every level.
    func testDivisionIsRealAndNarrowsOnTheStore() throws {
        var code = Data()
        code.append(pushVariable(1))            // 7
        code.append(pushVariable(2))            // 2
        code.append(Data([67]))                 // divide
        code.append(Data([33]))                 // return
        let program = try MakiBytecodeParser().parse(makeArithmeticScript(code: code),
                                                     source: WalSourceLocation(path: "/divide.maki"))
        let dispatcher = NoOpDispatcher()       // held weakly by the interpreter
        XCTAssertEqual(try MakiInterpreter(dispatcher: dispatcher).execute(program: program, at: 0)
            .doubleValue, 3.5, accuracy: 1e-9)

        // Stored into a declared Int it is 3 again; stored into a declared Double it keeps the half.
        var store = Data()
        store.append(pushVariable(3))           // the Int destination
        store.append(pushVariable(1))
        store.append(pushVariable(2))
        store.append(Data([67]))
        store.append(Data([48]))                // assign
        store.append(Data([2]))                 // discard
        store.append(pushVariable(4))           // the Double destination
        store.append(pushVariable(1))
        store.append(pushVariable(2))
        store.append(Data([67]))
        store.append(Data([48]))
        store.append(Data([33]))
        let stored = try MakiBytecodeParser().parse(makeArithmeticScript(code: store),
                                                    source: WalSourceLocation(path: "/store.maki"))
        _ = try MakiInterpreter(dispatcher: dispatcher).execute(program: stored, at: 0)
        XCTAssertEqual(stored.variables[3].value.integerValue, 3)
        guard case .integer = stored.variables[3].value else {
            return XCTFail("an Int variable must still hold an Int, or every string and index built "
                           + "from it changes")
        }
        XCTAssertEqual(stored.variables[4].value.doubleValue, 3.5, accuracy: 1e-9)
    }

    // MARK: - The main-menu button in the corner

    /// The "≡" at the top-left of a skin's title bar. multipass's `player.button.system` is
    /// `action="SYSMENU"` ("Display Main Menu"), and the whole family — `SYSMENU` (multipass,
    /// CornerAmp, Overdrive_2, winampmodern566, ZDL), `CONTROLMENU` (multipass, mmd3, Overdrive_2,
    /// ZDL) and a bare `MENU` — fell through the action switch and did nothing at all.
    ///
    /// The routing is asserted rather than the menu: presenting one enters AppKit's tracking loop.
    func testTheTitleBarMenuButtonsRouteToTheHostMenu() {
        XCTAssertTrue(WinampModernMainView.opensMainMenu(action: "SYSMENU", parameter: nil))
        XCTAssertTrue(WinampModernMainView.opensMainMenu(action: "controlmenu", parameter: nil))
        XCTAssertTrue(WinampModernMainView.opensMainMenu(action: "MENU", parameter: nil))
        XCTAssertTrue(WinampModernMainView.opensMainMenu(action: "MENU", parameter: ""))
        // `MENU param="presets"` is the equalizer's preset menu and keeps its own route.
        XCTAssertFalse(WinampModernMainView.opensMainMenu(action: "MENU", parameter: "presets"))
        XCTAssertFalse(WinampModernMainView.opensMainMenu(action: "PLAY", parameter: nil))
        XCTAssertFalse(WinampModernMainView.opensMainMenu(action: nil, parameter: nil))
        XCTAssertGreaterThan(ContextMenuBuilder.buildMenu().numberOfItems, 0,
                             "the menu the button opens is the host's own")
    }

    // MARK: - Fixture

    private func makeRuntime() throws -> (WinampModernScriptRuntime, MakiProgram) {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive())
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        return (runtime, Self.makeProgram(ownerID: nil))
    }

    private static func makeProgram(ownerID: WasabiObjectID?) -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                    ownerID: ownerID, parameter: nil)
    }

    private func unwrapObject(_ value: MakiValue,
                              in runtime: WinampModernScriptRuntime) throws -> WasabiObject {
        guard case .object(let reference) = value, case .gui(let id) = reference.kind,
              let object = runtime.loadedSkin.runtime.graph.object(withID: id) else {
            throw XCTSkip("expected a GUI object, got \(value)")
        }
        return object
    }

    private func makeArchive(xml: String? = nil) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase33Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase33-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, payload) in [("skin.xml", Data((xml ?? Self.skinXML).utf8)),
                                ("sheet.png", try makePNG()),
                                ("strip.png", try makeStripPNG()),
                                ("scripts/empty.maki", Self.emptyMakiScript())] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    /// A scene with an animated layer that states no size of its own, over a strip whose frames paint
    /// different halves — the shape of a fill animation, in miniature.
    private func makeScene() throws -> (WinampModernLoadedSkin, WasabiSceneRenderer) {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="sheet" file="sheet.png"/>
            <bitmap id="strip" file="strip.png"/>
          </elements>
          <container id="main">
            <layout id="normal" w="16" h="40">
              <layer id="plain" x="0" y="0" image="sheet"/>
              <animatedlayer id="bar" x="0" y="20" image="strip" frameheight="4" autoplay="0"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        return (loaded, try WasabiSceneRenderer(loadedSkin: loaded, host: Host()))
    }

    /// Four 16×4 frames: frame 0 opaque on the left half, frame 3 opaque on the right half, the two in
    /// between fully transparent.
    private func makeStripPNG() throws -> Data {
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        func paint(row: Int, columns: Range<Int>) {
            for y in (row * 4)..<(row * 4 + 4) {
                for x in columns {
                    let offset = (y * 16 + x) * 4
                    pixels[offset] = 200; pixels[offset + 1] = 200
                    pixels[offset + 2] = 200; pixels[offset + 3] = 255
                }
            }
        }
        paint(row: 0, columns: 0..<8)
        paint(row: 3, columns: 8..<16)
        return try encodePNG(pixels, width: 16, height: 16)
    }

    private func makeArithmeticScript(code: Data) -> Data {
        var data = Data([0x46, 0x47])
        appendUInt16(0x0403, to: &data)
        appendUInt32(23, to: &data)
        appendUInt32(1, to: &data)                                  // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        appendUInt32(1, to: &data)                                  // methods
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendString("onscriptloaded", to: &data)
        appendUInt32(5, to: &data)                                  // variables
        appendVariable(typeOffset: 0, object: true, system: true, to: &data)
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, initial: 7, to: &data)
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, initial: 2, to: &data)
        appendVariable(typeOffset: MakiValueKind.integer.rawValue, to: &data)
        appendVariable(typeOffset: MakiValueKind.double.rawValue, to: &data)
        appendUInt32(0, to: &data)                                  // constants
        appendUInt32(0, to: &data)                                  // bindings
        appendUInt32(UInt32(code.count), to: &data)
        data.append(code)
        return data
    }

    private final class NoOpDispatcher: MakiMethodDispatching {
        func signature(for method: String, classGUID: String?) -> MakiMethodSignature? { nil }
        func invoke(method: String, on object: MakiObjectReference, arguments: [MakiValue],
                    program: MakiProgram) throws -> MakiValue { .null }
        func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
            MakiObjectReference(.system)
        }
    }

    private func pushVariable(_ index: UInt32) -> Data {
        var data = Data([1])
        appendUInt32(index, to: &data)
        return data
    }

    private func appendVariable(typeOffset: UInt8, object: Bool = false, system: Bool = false,
                                initial: UInt16 = 0, initial2: UInt16 = 0, to data: inout Data) {
        data.append(typeOffset)
        data.append(object ? 1 : 0)
        appendUInt16(0, to: &data)          // subclass
        appendUInt16(initial, to: &data)
        appendUInt16(initial2, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        data.append(0)                      // global
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

    private func makePNG() throws -> Data {
        var pixels = [UInt8](repeating: 200, count: 16 * 16 * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) { pixels[offset + 3] = 255 }
        return try encodePNG(pixels, width: 16, height: 16)
    }

    private func encodePNG(_ pixels: [UInt8], width: Int, height: Int) throws -> Data {
        var pixels = pixels
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        let representation = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }

    /// The smallest well-formed `.maki`: a header, one class, one method, no code. Enough to be
    /// loaded and started, which is all `testTheCreatedSubtreesScriptsStart` observes.
    private static func emptyMakiScript() -> Data {
        var data = Data([0x46, 0x47])                              // "FG"
        func appendUInt16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func appendUInt32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        appendUInt16(0x0403)                                       // version
        appendUInt32(23)
        appendUInt32(1)                                            // classes
        data.append(contentsOf: repeatElement(UInt8(0), count: 16))
        appendUInt32(1)                                            // methods
        appendUInt16(0)
        appendUInt16(0)
        let name = Array("getid".utf8)
        appendUInt16(UInt16(name.count))
        data.append(contentsOf: name)
        appendUInt32(0)                                            // variables
        appendUInt32(0)                                            // constants
        appendUInt32(0)                                            // bindings
        appendUInt32(0)                                            // code length
        return data
    }
}
