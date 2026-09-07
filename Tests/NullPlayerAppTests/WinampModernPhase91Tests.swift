import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 91 — cPro2 Dark Aluminum, the corpus's only ClassicPro engine-"two" skin, measured and
/// driven for the first time (it graded *did not load* until B93 the day before).
///
/// Five defects, each of which hid the next. All five are silent by nature: every element parsed,
/// every script ran, and nothing reported a failure — the skin simply drew wrong.
///
/// 1. `System.onShowLayout` was never dispatched anywhere. Engine two lays its whole player out from
///    that event and from nowhere else.
/// 2. `isVisible()` on a *layout* answered for the window, so `normal` and `shade` both read visible
///    and the cold start's `!shade.isVisible()` guard never opened.
/// 3. `autoheightsource` was honoured only for `<Wasabi:TitleBox>`, so the transport band resolved
///    0 tall — and a zero-height group is not a resize target.
/// 4. A **declared-empty** group fell back to its parent's clip, so a `w="0"` progress-reveal window
///    showed all of its artwork at once.
/// 5. `parser_onCallback` handed its attributes alphabetically, and ClassicPro's `<Style>` reader
///    keys its apply loop on reaching `id` — so everything sorted before `id` was dropped.
///
/// Plus the play clock, which posted `onPostedPosition` only to stock Winamp Modern's own
/// `HiddenSeek` id, and the four `getCurApp*` reads.
final class WinampModernPhase91Tests: XCTestCase {

    // MARK: - 1. The cold-start layout event

    /// The event exists at all. Engine two's entire info + transport band is placed from it.
    func testStartAnnouncesTheMainPlayersLayout() throws {
        let runtime = try makeRuntime(xml: Self.twoLayoutSkin)
        runtime.recordsDispatchedEventsForTesting = true
        try runtime.start()
        let shown = runtime.dispatchedSystemEventsForTesting.filter { $0.event == "onshowlayout" }
        XCTAssertEqual(shown.count, 1, "the main player's layout is announced exactly once")
    }

    /// Only the main player. Every other container opens on request, and telling a skin that a window
    /// it has not been asked to show is on screen is a worse answer than silence.
    func testAnAuxiliaryContainerIsNotAnnounced() throws {
        let runtime = try makeRuntime(xml: Self.twoLayoutSkin)
        runtime.recordsDispatchedEventsForTesting = true
        try runtime.start()
        // One event, and its argument is a layout belonging to `main` — not to `notifier`.
        let shown = try XCTUnwrap(runtime.dispatchedSystemEventsForTesting.first { $0.event == "onshowlayout" })
        let object = try XCTUnwrap(objectArgument(shown.arguments.first, in: runtime))
        XCTAssertEqual(object.xmlID?.lowercased(), "normal")
        XCTAssertEqual(object.parent?.xmlID, "main", "and it belongs to the player, not the notifier")
    }

    // MARK: - 2. One layout is visible at a time

    /// A container shows exactly one layout, so `normal` and `shade` must never both report visible —
    /// that is a state no Winamp skin can be in. Engine two's cold start is gated on it.
    func testANonActiveLayoutIsNotVisible() throws {
        let runtime = try makeRuntime(xml: Self.twoLayoutSkin)
        let normal = try XCTUnwrap(layout(named: "normal", in: runtime))
        let shade = try XCTUnwrap(layout(named: "shade", in: runtime))
        XCTAssertTrue(try isVisible(normal, in: runtime), "the active layout is on screen")
        XCTAssertFalse(try isVisible(shade, in: runtime), "the layout that is not showing is not")
    }

    /// Answered from the graph rather than from the host, so it holds headlessly — where no container
    /// visibility is reported at all and both layouts used to read visible.
    func testTheAnswerDoesNotNeedAHostToReportWindowVisibility() throws {
        let runtime = try makeRuntime(xml: Self.twoLayoutSkin)
        XCTAssertNil(runtime.containerVisibilityQuery, "no host is installed in this fixture")
        let shade = try XCTUnwrap(layout(named: "shade", in: runtime))
        XCTAssertFalse(try isVisible(shade, in: runtime))
    }

    // MARK: - 3. `autoheightsource` on a plain group

    /// The band is `<group autoheightsource="…">` with no `h`. Resolved 0 tall it is not a resize
    /// target, so the script that centres the transport strip never runs.
    func testAPlainGroupTakesItsHeightFromAutoHeightSource() throws {
        let renderer = try makeRenderer(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <group id="band" x="0" y="10" w="0" relatw="1" autoheightsource="inner">
                <layer id="inner" x="0" y="0" w="0" h="30" relatw="1"/>
              </group>
            </layout>
          </container>
        </WasabiXML>
        """)
        let band = try XCTUnwrap(renderer.layoutNodesForTesting().first { $0.object.xmlID == "band" })
        XCTAssertEqual(band.frame.height, 30, "sized to the named child's bottom, not left at zero")
        XCTAssertTrue(renderer.resizeTargets().contains { $0.object.xmlID == "band" },
                      "and is therefore a resize target")
    }

    // MARK: - 4. A declared-empty group is a reveal window

    /// `w="0"` on a group whose box the skin declared is the answer, not a missing one: it is the
    /// aperture the artwork inside shows through.
    func testADeclaredEmptyGroupClipsItsChildrenToNothing() throws {
        let renderer = try makeRenderer(xml: Self.seekerSkin)
        let lit = try XCTUnwrap(renderer.layoutNodesForTesting().first { $0.object.xmlID == "fill" })
        XCTAssertTrue(lit.clip.isEmpty, "the 550px fill is revealed 0px wide, not across the band")
    }

    /// The guard that keeps this narrow. A group whose height we inferred keeps the inherited clip —
    /// clipping children to a guess erases content that is really there.
    func testAGroupThatDeclaresNoBoxKeepsTheInheritedClip() throws {
        let renderer = try makeRenderer(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <group id="undeclared" x="0" y="0">
                <layer id="child" x="0" y="0" w="40" h="20"/>
              </group>
            </layout>
          </container>
        </WasabiXML>
        """)
        let child = try XCTUnwrap(renderer.layoutNodesForTesting().first { $0.object.xmlID == "child" })
        XCTAssertFalse(child.clip.isEmpty, "an inferred box must not erase its subtree")
    }

    // MARK: - 5. Parser callback attribute order

    /// ClassicPro reads a `<Style>` as two parallel lists and keys its apply loop on reaching `id`,
    /// so everything before `id` is skipped by construction — and the skin writes `id` first.
    /// Sorting the list alphabetically dropped `display`, `fontsize`, `forcefixed` and `h`.
    func testParsedAttributesKeepDocumentOrder() throws {
        let node = try XCTUnwrap(WalLenientXMLParser().parse(
            #"<Style id="normal.info.timebig.text" y="-7" display="4" h="34" forcefixed="1" fontsize="26"/>"#,
            path: "/Skins/Synthetic/ClassicPro.xml").roots.first)
        XCTAssertEqual(node.orderedAttributes.map(\.key),
                       ["id", "y", "display", "h", "forcefixed", "fontsize"])
    }

    /// A node assembled in code rather than parsed has no recorded order; sorted is the stable
    /// fallback rather than an empty list.
    func testAnUnparsedNodeFallsBackToSortedOrder() {
        let node = WalXMLNode(name: "Style", attributes: ["y": "-7", "id": "x", "h": "34"],
                              location: WalSourceLocation(path: "/Skins/Synthetic/made-up.xml"))
        XCTAssertEqual(node.orderedAttributes.map(\.key), ["h", "id", "y"])
    }

    // MARK: - The play clock and the window box

    /// The clock used to post only to stock Winamp Modern's `HiddenSeek`. A skin that names its seek
    /// slider anything else — engine two's is `two.info.seeker.slider.0` — never advanced, while
    /// dragging it still worked, because a drag is the user's own value change.
    func testEverySeekSliderIsAPositionListener() throws {
        let runtime = try makeRuntime(xml: Self.seekerSkin)
        let ids = Set(runtime.loadedSkin.runtime.graph.roots
            .flatMap { Self.descendants(of: $0) }
            .filter { $0.typeName.caseInsensitiveCompare("slider") == .orderedSame
                      && $0.attributes["action"]?.lowercased() == "seek" }
            .compactMap(\.xmlID))
        XCTAssertEqual(ids, ["two.info.seeker.slider.0"],
                       "identified by action=SEEK, not by a hard-coded id")
    }

    /// All four exist. `presetpos.m` calls them in one expression, so a missing width or height kills
    /// `saveFramePos()` on its third call and nothing is ever stored.
    func testAllFourCurrentAppReadsAreDeclared() throws {
        let runtime = try makeRuntime(xml: Self.twoLayoutSkin)
        for method in ["getcurappleft", "getcurapptop", "getcurappwidth", "getcurappheight"] {
            let signature = try XCTUnwrap(runtime.signature(for: method, classGUID: nil),
                                          "\(method) is declared")
            XCTAssertEqual(signature.argumentCount, 0, "\(method) takes no arguments")
        }
    }

    /// `NSApp` is nil until an `NSApplication` exists, so the obvious implementation *traps* headlessly
    /// rather than answering. This path was unreachable until `onShowLayout` began to be dispatched.
    func testTheWindowBoxAnswersZeroWithNoHostRatherThanTrapping() throws {
        let runtime = try makeRuntime(xml: Self.twoLayoutSkin)
        for method in ["getcurappleft", "getcurapptop", "getcurappwidth", "getcurappheight"] {
            let value = try runtime.invoke(method: method, on: MakiObjectReference(.system),
                                           arguments: [], program: emptyProgram())
            XCTAssertEqual(value.integerValue, 0, "\(method) answers 0 with no window")
        }
    }

    // MARK: - Restoring a window frame the skin cannot render

    /// The existing guard, pinned because the new rule sits directly behind it: a frame saved under a
    /// **different** skin already keeps the current skin's own size. What it does *not* catch is a
    /// frame saved under the same skin in a session where that skin failed to load — the cPro2 case —
    /// and that is handled in `restoreWindowFrames`, where the clamp result is the signal.
    func testAFrameSavedUnderAnotherSkinKeepsTheCurrentSkinsSize() {
        let saved = NSRect(x: 241, y: 614, width: 275, height: 116)
        let kept = AppStateManager.mainFrameForRestore(saved: saved, ownSize: NSSize(width: 800, height: 600),
                                                       savedUnderSkin: "some-other-skin",
                                                       loadedSkin: "cpro2_dark_aluminum",
                                                       isWinampModern: true)
        XCTAssertEqual(kept.size, NSSize(width: 800, height: 600))
        XCTAssertEqual(kept.minX, saved.minX, "position is still the user's")
    }

    /// And Classic/Original are untouched by any of it: their windows are not sized by a skin's
    /// layout, so the saved frame is returned verbatim.
    func testOutsideWinampModernTheSavedFrameIsUsedVerbatim() {
        let saved = NSRect(x: 241, y: 614, width: 275, height: 116)
        XCTAssertEqual(AppStateManager.mainFrameForRestore(saved: saved, ownSize: NSSize(width: 800, height: 600),
                                                           savedUnderSkin: "a", loadedSkin: "b",
                                                           isWinampModern: false),
                       saved)
    }

    // MARK: - Fixtures

    /// Two layouts in one container, the shape engine two's cold-start guard reads.
    private static let twoLayoutSkin = """
    <WasabiXML>
      <container id="main">
        <layout id="normal" w="200" h="200"><layer id="a" x="0" y="0" w="10" h="10"/></layout>
        <layout id="shade" w="200" h="22"><layer id="b" x="0" y="0" w="10" h="10"/></layout>
      </container>
      <container id="notifier">
        <layout id="normal" w="128" h="80"><layer id="c" x="0" y="0" w="10" h="10"/></layout>
      </container>
    </WasabiXML>
    """

    /// The seek construct: a declared-empty reveal window over a full-width lit layer, with the
    /// `action="SEEK"` slider laid over both.
    private static let seekerSkin = """
    <WasabiXML>
      <container id="main">
        <layout id="normal" w="800" h="40">
          <group id="two.info.seeker" x="10" y="0" w="-20" h="40" relatw="1">
            <group id="two.info.seeker.active" x="0" y="0" w="0" h="40">
              <group id="fill" x="0" y="0" w="550" h="40"/>
            </group>
            <slider id="two.info.seeker.slider.0" x="0" y="0" w="0" h="40" relatw="1" action="SEEK"/>
          </group>
        </layout>
      </container>
    </WasabiXML>
    """

    // MARK: - Helpers

    private static func descendants(of object: WasabiObject) -> [WasabiObject] {
        [object] + object.children.flatMap(descendants(of:))
    }

    private func layout(named id: String, in runtime: WinampModernScriptRuntime) -> WasabiObject? {
        runtime.loadedSkin.runtime.graph.roots
            .first { $0.xmlID == "main" }?
            .children.first { $0.xmlID == id }
    }

    private func isVisible(_ object: WasabiObject, in runtime: WinampModernScriptRuntime) throws -> Bool {
        try runtime.invoke(method: "isvisible", on: MakiObjectReference(.gui(object.stableID)),
                           arguments: [], program: emptyProgram()).truthy
    }

    private func objectArgument(_ value: MakiValue?,
                                in runtime: WinampModernScriptRuntime) -> WasabiObject? {
        guard case .object(let reference)? = value, case .gui(let id) = reference.kind else { return nil }
        return runtime.loadedSkin.runtime.graph.object(withID: id)
    }

    private func makeRuntime(xml: String) throws -> WinampModernScriptRuntime {
        let loaded = try load(xml: xml)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: BareHost())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func makeRenderer(xml: String) throws -> WasabiSceneRenderer {
        let loaded = try load(xml: xml)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: BareHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase91Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase91-\(UUID().uuidString).wal")
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

    private func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    private final class BareHost: WinampModernHost {
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
