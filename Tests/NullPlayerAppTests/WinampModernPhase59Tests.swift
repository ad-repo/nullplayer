import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 59 — BB19, the settings pages could not be scrolled.
///
/// Big Bento Modern's nine settings pages are each an empty `<GroupList>` plus an `SC:VScrollBar`,
/// with `config_vscrollbars.maki` declared once per page. Anything past the fold was unreachable
/// because **the mouse wheel never reached the skin at all**: `onMouseWheelUp`/`onMouseWheelDown`
/// were absent from `dispatchableEventArity`, and `WinampModernMainView.scrollWheel` handled only
/// NullPlayer's own surfaces (the colour-theme list and the playlist holder) before falling through
/// to `super`.
///
/// Two measured facts shape the fix, and both are easy to get wrong:
///
/// - **The arity is two, not one.** Read off two independent skins' bytecode — Big Bento's
///   `config_vscrollbars` at `@638` and cPro-Bento's `centro.multidrawer` at `@1091` both open with
///   two `op3` stores. One skin is an anecdote; two unrelated ones are the language.
/// - **The binding is on the layout, not on a control.** All 84 `onMouseWheel*` bindings across the
///   five corpus skins that declare them land on `layout#normal` or `layout#shade`; each script then
///   decides whether the turn was meant for it with `isMouseOverRect()`. Dispatching to the object
///   under the pointer would reach none of them.
final class WinampModernPhase59Tests: XCTestCase {

    /// Without an arity the interpreter cannot unwind the stack, so the event is not dispatchable at
    /// all — and a *wrong* arity is worse than none, because it desynchronises everything after the
    /// call rather than failing closed.
    func testTheWheelEventsAreDeclaredWithTwoArguments() throws {
        let runtime = try makeRuntime()
        for event in ["onMouseWheelUp", "onMouseWheelDown"] {
            let signature = try XCTUnwrap(runtime.signature(for: event, classGUID: nil),
                                          "\(event) must be dispatchable")
            XCTAssertEqual(signature.argumentCount, 2, "\(event) takes (clicks, lines)")
            XCTAssertEqual(signature.returnKind, .null)
        }
    }

    /// The event reaches handlers bound to the **layout**, which is the only place the corpus binds
    /// them. A synthetic skin ships no MAKI, so this asserts the dispatch is addressed and accepted
    /// rather than counting handlers.
    func testTheWheelIsDispatchedAtTheLayout() throws {
        let runtime = try makeRuntime()
        runtime.recordsDispatchedEventsForTesting = true
        let layout = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "normal").first)
        _ = try runtime.dispatch(object: layout, event: "onmousewheelup",
                                 arguments: [.integer(1), .integer(3)])
        XCTAssertTrue(runtime.dispatchedEventsForTesting
            .contains { $0.object == "normal" && $0.event == "onmousewheelup" })
    }

    // MARK: - `scrollToPercent` actually moves something

    /// The half that mattered most: the wheel reaching the skin was necessary and **not sufficient**,
    /// because `scrollToPercent` was an accepted no-op. Every route a user has — the scrollbar drag
    /// (`onSetPosition`), its up/down buttons (`cscrollbar.maki` nudges the slider by 5) and the
    /// wheel — ends at this one call, so while it did nothing, nothing scrolled by any means.
    func testScrollToPercentOffsetsTheChildren() throws {
        let (runtime, renderer, program) = try makeScrollFixture()
        let page = try object(runtime, "page")
        // Four 100pt rows in a 200pt box: the last two start out below the fold and are culled from
        // the scene entirely, which is the state the user was stuck in.
        XCTAssertNil(renderer.sceneNodes().first { $0.object.xmlID == "row.bottom" },
                     "the last row is out of the clip to begin with")

        _ = try runtime.invoke(method: "scrollToPercent", on: reference(page),
                               arguments: [.integer(100)], program: program)
        // Content is 400 tall in a 200 box, so the travel is 200 and the last row comes up to y=100.
        let scrolled = try XCTUnwrap(renderer.sceneNodes().first { $0.object.xmlID == "row.bottom" })
        XCTAssertEqual(scrolled.frame.minY, 100, accuracy: 0.5)
    }

    /// Halfway is halfway, and `0` puts it back.
    func testScrollIsProportionalAndReversible() throws {
        let (runtime, renderer, program) = try makeScrollFixture()
        let page = try object(runtime, "page")
        _ = try runtime.invoke(method: "scrollToPercent", on: reference(page),
                               arguments: [.integer(50)], program: program)
        // Half the 200pt travel: the third row (declared at y=200) sits at y=100.
        XCTAssertEqual(try XCTUnwrap(renderer.sceneNodes()
            .first { $0.object.xmlID == "row2" }).frame.minY, 100, accuracy: 0.5)

        _ = try runtime.invoke(method: "scrollToPercent", on: reference(page),
                               arguments: [.integer(0)], program: program)
        XCTAssertEqual(try XCTUnwrap(renderer.sceneNodes()
            .first { $0.object.xmlID == "row1" }).frame.minY, 100, accuracy: 0.5)
        XCTAssertNil(renderer.sceneNodes().first { $0.object.xmlID == "row.bottom" },
                     "back to the top, so the last row is below the fold again")
    }

    /// Out-of-range percentages are clamped rather than flinging the content off the page.
    func testPercentIsClamped() throws {
        let (runtime, _, program) = try makeScrollFixture()
        let page = try object(runtime, "page")
        _ = try runtime.invoke(method: "scrollToPercent", on: reference(page),
                               arguments: [.integer(-40)], program: program)
        XCTAssertEqual(page.attributes[WasabiSceneRenderer.scrollPercentKey], "0.0")
        _ = try runtime.invoke(method: "scrollToPercent", on: reference(page),
                               arguments: [.integer(400)], program: program)
        XCTAssertEqual(page.attributes[WasabiSceneRenderer.scrollPercentKey], "100.0")
    }

    /// A page whose content fits never moves, however hard a skin scrolls it — which is what lets one
    /// rule serve a long settings page and a short one with no per-page configuration.
    func testContentThatFitsDoesNotMove() throws {
        let (runtime, renderer, program) = try makeScrollFixture(rowHeight: 40)
        let page = try object(runtime, "page")
        let before = try XCTUnwrap(renderer.sceneNodes().first { $0.object.xmlID == "row.bottom" }).frame
        _ = try runtime.invoke(method: "scrollToPercent", on: reference(page),
                               arguments: [.integer(100)], program: program)
        let after = try XCTUnwrap(renderer.sceneNodes().first { $0.object.xmlID == "row.bottom" }).frame
        XCTAssertEqual(before.minY, after.minY, accuracy: 0.5)
    }

    // MARK: - The scrollbar itself

    /// Skins spell the axis both ways and mean the same thing. Testing only for the long spelling
    /// made 49 slider declarations across 8 skins *horizontal*: their thumbs drew along the wrong
    /// axis, and a drag read its value from the pointer's **x** across a 16px-wide bar, so it snapped
    /// to an end instead of tracking the mouse. That is what stopped Big Bento's scrollbar being
    /// draggable at all, and it reaches Anexa, Enkera, Lobe and the Nokia 5220 as well.
    func testOrientationIsVerticalSpelledEitherWay() throws {
        let runtime = try makeRuntime()
        let layout = try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: "normal").first)
        func orientation(_ value: String?) -> Bool {
            _ = layout.setAttribute("orientation", value: value)
            return WasabiSceneRenderer.isVerticalOrientation(layout)
        }
        XCTAssertTrue(orientation("v"))
        XCTAssertTrue(orientation("V"))
        XCTAssertTrue(orientation("vertical"))
        XCTAssertTrue(orientation("VERTICAL"))
        XCTAssertFalse(orientation("horizontal"))
        XCTAssertFalse(orientation("h"), "only the vertical spellings are in the corpus")
        XCTAssertFalse(orientation(nil))
    }

    /// `embed_xui` means the wrapper *is* the control, so the range declared on the wrapper is the
    /// embedded slider's range — otherwise it falls back to Winamp's 0…255 and every number the skin
    /// reads is on the wrong scale.
    func testEmbedXUIForwardsTheDeclaredRangeToTheEmbeddedControl() throws {
        let (_, inner, _, _) = try makeScrollbarFixture()
        XCTAssertEqual(inner.attributes["low"], "0")
        XCTAssertEqual(inner.attributes["high"], "100")
    }

    /// A vertical slider driving nothing of its own starts at the **top** of its travel. Read as 0,
    /// Big Bento's pages opened by computing `scrollToPercent(99 - 0)` — 99%, their own bottom.
    func testAVerticalSliderWithNothingDrivingItStartsAtTheTop() throws {
        let (_, inner, _, _) = try makeScrollbarFixture()
        XCTAssertEqual(inner.attributes["value"], "100")
    }

    /// The wrapper and the embedded control must be **one** value, not two. The skin's buttons move
    /// the inner slider and its page reads the wrapper; kept apart they drift permanently and the
    /// page reads 0 however far the bar has been dragged.
    func testTheWrapperReadsAndWritesTheEmbeddedControlsPosition() throws {
        let (wrapper, inner, runtime, program) = try makeScrollbarFixture()
        XCTAssertEqual(try runtime.invoke(method: "getPosition", on: reference(wrapper),
                                          arguments: [], program: program).integerValue, 100)

        _ = try runtime.invoke(method: "setPosition", on: reference(wrapper),
                               arguments: [.integer(40)], program: program)
        XCTAssertEqual(inner.attributes["value"], "40", "the write lands on the embedded control")
        XCTAssertEqual(try runtime.invoke(method: "getPosition", on: reference(wrapper),
                                          arguments: [], program: program).integerValue, 40)
    }

    /// Clamped to the declared range. Every scrollbar in the corpus steps its slider relative to
    /// itself (`setPosition(getPosition() + 5)`), so without this the up button walks off the end —
    /// measured live at 113 → 118 → 123 → 128 against a `high` of 100, which made the page's
    /// `99 - position` negative on every press and pinned it to the top.
    func testSetPositionIsClampedToTheDeclaredRange() throws {
        let (wrapper, inner, runtime, program) = try makeScrollbarFixture()
        _ = try runtime.invoke(method: "setPosition", on: reference(wrapper),
                               arguments: [.integer(140)], program: program)
        XCTAssertEqual(inner.attributes["value"], "100")
        _ = try runtime.invoke(method: "setPosition", on: reference(wrapper),
                               arguments: [.integer(-20)], program: program)
        XCTAssertEqual(inner.attributes["value"], "0")
    }

    /// A slider that declares no range keeps whatever it is given — Anaheim's brightness slider runs
    /// −4096…4096 and nothing may quietly fence it into 0…255.
    func testASliderWithNoDeclaredRangeIsNotClamped() throws {
        let (runtime, _, program) = try makeScrollFixture()
        let bare = try object(runtime, "page")
        _ = try runtime.invoke(method: "setPosition", on: reference(bare),
                               arguments: [.integer(9000)], program: program)
        XCTAssertEqual(bare.attributes["value"], "9000")
    }

    /// The value event has to cross the seam too, or the page never learns the bar moved.
    func testTheEmbeddedControlsPositionEventReachesTheWrapper() throws {
        let (wrapper, inner, runtime, program) = try makeScrollbarFixture()
        runtime.recordsDispatchedEventsForTesting = true
        _ = try runtime.invoke(method: "setPosition", on: reference(inner),
                               arguments: [.integer(30)], program: program)
        let events = runtime.dispatchedEventsForTesting.filter { $0.event == "onsetposition" }
        XCTAssertTrue(events.contains { $0.object == wrapper.xmlID },
                      "a script bound to the wrapper must hear the embedded control move")
    }

    /// A wrapper with two `SC:VScrollBar` instances gives each its own value — the seam is per
    /// instance, not per groupdef.
    private func makeScrollbarFixture()
        throws -> (WasabiObject, WasabiObject, WinampModernScriptRuntime, MakiProgram) {
        let xml = """
        <WasabiXML>
          <groupdef id="sc.xui.vscrollbar" xuitag="SC:VScrollBar" embed_xui="slider">
            <slider id="slider" x="0" y="20" w="16" h="-40" relath="1" orientation="v"/>
            <button id="up" x="0" y="0" w="16" h="20"/>
          </groupdef>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <SC:VScrollBar id="vscroll" x="0" y="0" w="16" h="200" low="0" high="100"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let wrapper = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "vscroll").first)
        let inner = try XCTUnwrap(descendant(of: wrapper, xmlID: "slider"))
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [],
                                  bindings: [], instructions: [],
                                  source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        return (wrapper, inner, runtime, program)
    }

    // MARK: - The whole chain, against the real skin

    /// Opt-in, because nothing third-party is committed. Point `WINAMP_MODERN_WAL` at
    /// `Big Bento Modern.wal` and this drives the settings scrollbar exactly as a user does and
    /// checks the page actually moved.
    ///
    /// It exercises the seam the synthetic tests cannot: `SC:VScrollBar` is a
    /// `<groupdef embed_xui="slider">`, the up/down buttons nudge the **inner** `<slider>`
    /// (`cscrollbar.maki`), and the settings page binds its `onSetPosition` to the **outer**
    /// `vscroll`. Three separate things had to be true for a scroll to happen, and each was broken on
    /// its own: the value event has to cross the `embed_xui` seam, `scrollToPercent` has to do
    /// something, and the wheel has to reach the layout.
    func testTheRealScrollbarScrollsTheRealSettingsPage() throws {
        guard let path = ProcessInfo.processInfo.environment["WINAMP_MODERN_WAL"],
              path.lowercased().contains("bento") else {
            throw XCTSkip("Set WINAMP_MODERN_WAL to Big Bento Modern.wal for this one.")
        }
        let loaded = try WinampModernSkinLoader().load(from: URL(fileURLWithPath: path))
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        defer { scripts.teardown(); renderer.teardown(); loaded.teardown() }
        try scripts.start()

        // The default settings page and its two halves: the scrolled `GroupList` and the scrollbar.
        let page = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "optionsgroup.appearance").first)
        let list = try XCTUnwrap(descendant(of: page, xmlID: "grplst"))
        let bar = try XCTUnwrap(descendant(of: page, xmlID: "vscroll"))
        let inner = try XCTUnwrap(descendant(of: bar, xmlID: "slider"),
                                  "SC:VScrollBar embeds the slider the buttons actually move")
        // The page parks itself at the top during startup, so a value is already present; what this
        // measures is whether moving the bar *changes* it.
        let before = Double(list.attributes[WasabiSceneRenderer.scrollPercentKey] ?? "") ?? 0

        // Move the inner slider, which is what `cscrollbar.maki`'s up/down buttons do.
        let program = try XCTUnwrap(scripts.programs.first)
        _ = try scripts.invoke(method: "setPosition",
                               on: MakiObjectReference(.gui(inner.stableID)),
                               arguments: [.integer(40)], program: program)

        let after = try XCTUnwrap(Double(try XCTUnwrap(
            list.attributes[WasabiSceneRenderer.scrollPercentKey],
            "the page's onSetPosition must have reached scrollToPercent")))
        XCTAssertNotEqual(after, before, accuracy: 0.001,
                          "moving the inner slider must cross the embed_xui seam to the page")
    }

    private func descendant(of object: WasabiObject, xmlID: String) -> WasabiObject? {
        if object.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame { return object }
        for child in object.children {
            if let found = descendant(of: child, xmlID: xmlID) { return found }
        }
        return nil
    }

    // MARK: - Fixture

    private func reference(_ object: WasabiObject) -> MakiObjectReference {
        MakiObjectReference(.gui(object.stableID))
    }

    private func object(_ runtime: WinampModernScriptRuntime, _ id: String) throws -> WasabiObject {
        try XCTUnwrap(runtime.loadedSkin.runtime.graph.objects(xmlID: id).first)
    }

    /// A 200×200 sized group (so it clips, as Big Bento's page group does) holding four rows. At the
    /// default 100pt row height the content is 400 tall, so the travel is 200.
    private func makeScrollFixture(rowHeight: Int = 100)
        throws -> (WinampModernScriptRuntime, WasabiSceneRenderer, MakiProgram) {
        let rows = (0..<4).map { index in
            let id = index == 3 ? "row.bottom" : "row\(index)"
            return "<layer id=\"\(id)\" x=\"0\" y=\"\(index * rowHeight)\" w=\"200\" h=\"\(rowHeight)\" rectrgn=\"1\"/>"
        }.joined(separator: "\n")
        let xml = """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <group id="page" x="0" y="0" w="200" h="200">
        \(rows)
              </group>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), containerID: "main")
        addTeardownBlock { renderer.teardown() }
        let program = MakiProgram(version: 0x0403, classes: [], methods: [], variables: [],
                                  bindings: [], instructions: [],
                                  source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"),
                                  ownerID: nil, parameter: nil)
        return (runtime, renderer, program)
    }

    private func makeRuntime() throws -> WinampModernScriptRuntime {
        let xml = """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <layer id="bg" x="0" y="0" w="200" h="200"/>
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase59Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase59-\(UUID().uuidString).wal")
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
