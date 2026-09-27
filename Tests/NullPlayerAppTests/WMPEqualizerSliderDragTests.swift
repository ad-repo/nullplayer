import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// W256 — *"an equaliser slider cannot be dragged"*, reported live 2026-09-22 against `elvis` and
/// `anemone`, with the reporter's own correction as the whole of the row: *"manual control of the
/// sliders are the problem, not the eq function"*.
///
/// Driven in the debug build, the two skins turned out to be **three** defects, one of them in
/// every skin's equaliser and none of them visible to a render sweep — a dump draws the settled
/// default state and never drags. All three are asserted below.
///
/// 1. **A handler on an element the markup never named is handed nothing.** `anemone`'s ten bands
///    are `<SLIDER value_onchange="eq.gainLevel1=value;">` with no `id`, and both the bound `value`
///    global and the handler's own `with` scope (W216) were keyed on the authored id. The handler
///    ran, `value` resolved to the undefined global, and `eq.gainLevel1 = value` wrote **null**:
///    the band never moved and the thumb settled straight back onto the host's unchanged gain.
///    **70 `value_onchange` handlers across 35 of 184 archives** author no `id`; the wider class —
///    any handler on an unnamed element, which also lost its scope — is 1,667 nodes / 101 archives.
/// 2. **A slider's region is the track it authored, not the artwork drawn in it.** `elvis`'s eight
///    bands are `<slider width="10" height="75">` with a `thumbImage` and no track sprite, so "a
///    control is its artwork" read the 11x12 knob and four fifths of each band rejected the
///    pointer — the press fell through to the tray's `<buttonGroup>` behind it and *dragged the
///    window*. **448 sliders across 41 of 184 archives** paint a thumb and no track.
/// 3. **The name a skin gave its `<EQUALIZERSETTINGS>` is another spelling of `eq`.** `eq` is a
///    bound global on the *path* `eq`, so `<equalizerSettings id="ElvisEQS">` was an ordinary
///    element: `ElvisEQS.gainLevel1 = value` landed in its own property bag, changed no audio, and
///    the slider bound to `wmpprop:ElvisEQS.gainLevel1` — which resolves from the *host* — never
///    moved however far it was dragged. **7 of the 184 measured archives** name it something else:
///    `elvis` (`ElvisEQS`), `TDK` (`eqsettings`) and `Gorillaz`/`Navigator`/`Ursula`/`robbie`/
///    `v2_underworld` (`equal`). Reproduce by matching `<equalizerSettings …>` and its `id` in every
///    `.wms`, reading the bytes rather than grepping: half the corpus's definitions are cp1252 with
///    a `0xA9` in the copyright header, so `grep` calls the file binary and prints nothing while
///    exiting 0 — which is how the backlog row came to claim `anemone` had no `<EQUALIZERSETTINGS>`
///    and no slider at all when it has both.
final class WMPEqualizerSliderDragTests: XCTestCase {

    // MARK: - Fixtures

    private func load(wms: String, images: [String: Data] = [:]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        entries += images.map { WMPTestArchiveEntry($0.key, data: $0.value) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private func stableID(_ skin: WMPLoadedSkin, _ id: String) throws -> Int {
        try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
    }

    /// The one node in the fixture that carries no `id`, which is the case under test.
    private func unnamedNode(_ skin: WMPLoadedSkin, kind: WMPElementKind) throws -> Int {
        try XCTUnwrap(skin.graph.allNodes.first { $0.kind == kind && $0.xmlID == nil }?.stableID)
    }

    private func runtime() throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPEqualizerSliderDragTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = WMPPreferenceStore(skinData: Data(), defaults: defaults)
        return (WMPScriptRuntime(preferences: store),
                { defaults.removePersistentDomain(forName: suite) })
    }

    /// An opaque square, which is all a thumb sprite has to be for a coverage walk.
    private func opaqueSquare(_ side: Int) throws -> Data {
        try WMPSkinTestSupport.encodedImage(
            width: side, height: side,
            rgba: Array(repeating: [UInt8](arrayLiteral: 0, 0, 0, 255),
                        count: side * side).flatMap { $0 })
    }

    // MARK: - 1: a handler on an element the markup never named

    /// `anemone`'s band, verbatim in shape: no `id`, `value` bound to the host and written back by
    /// the handler the drag raises. The assertion is the **argument**, not that the handler ran —
    /// it always ran, and it always wrote null.
    func testAnUnnamedElementsHandlerIsHandedItsOwnValue() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <EQUALIZERSETTINGS id="eq" enabled="true"/>
            <SLIDER direction="vertical" left="10" top="10" width="6" height="49"
                    min="-14" max="14" value="wmpprop:eq.gainLevel1"
                    value_onchange="eq.gainLevel1=value;"/>
        </VIEW></THEME>
        """)
        let band = try unnamedNode(skin, kind: .slider)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        // The view is loaded before it is dragged, which is the transaction that installs the
        // elements and settles the band's binding on the host's gain.
        _ = await runtime.transact(skin: skin, viewID: "main", size: .init(width: 100, height: 100),
                                   snapshot: WMPHostSnapshot(), event: nil)
        // The pointer is on the control, exactly as `onSliderCaptureChanged` puts it there: a
        // held element's `value` is the user's and the host does not settle it back (W151).
        await runtime.holdElement(stableID: band)
        await runtime.setWidgetValue(stableID: band, value: 9, viewID: "main")
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: .init(width: 100, height: 100),
            snapshot: WMPHostSnapshot(),
            event: .init(name: "change", targetID: nil, targetStableID: band,
                         handlers: ["eq.gainLevel1=value;"]))

        XCTAssertEqual(output.hostCommands.map(\.action), ["setEQBand:0"])
        XCTAssertEqual(output.hostCommands.first?.value, .number(9),
                       "the band the pointer left the control at, not the undefined global")
    }

    /// The control for the assertion above, and the shape of the defect: with no address for the
    /// element there is nothing to bind, and the write reaches the host carrying null. This is what
    /// every dispatch did before the event learned to carry a stable id.
    func testWithoutAnAddressTheSameHandlerWritesNull() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <EQUALIZERSETTINGS id="eq" enabled="true"/>
            <SLIDER direction="vertical" left="10" top="10" width="6" height="49"
                    min="-14" max="14" value="wmpprop:eq.gainLevel1"
                    value_onchange="eq.gainLevel1=value;"/>
        </VIEW></THEME>
        """)
        let band = try unnamedNode(skin, kind: .slider)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        _ = await runtime.transact(skin: skin, viewID: "main", size: .init(width: 100, height: 100),
                                   snapshot: WMPHostSnapshot(), event: nil)
        await runtime.holdElement(stableID: band)
        await runtime.setWidgetValue(stableID: band, value: 9, viewID: "main")
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: .init(width: 100, height: 100),
            snapshot: WMPHostSnapshot(),
            event: .init(name: "change", targetID: nil, handlers: ["eq.gainLevel1=value;"]))

        XCTAssertEqual(output.hostCommands.first?.value, .null,
                       "the measured defect: a band write with nothing in it")
    }

    /// The other half the address buys back: W216's scope, which was keyed on the same id. A bare
    /// name in a handler on an unnamed element used to fall through to the globals and throw.
    func testAnUnnamedElementsHandlerResolvesBareNamesAgainstItself() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <SUBVIEW left="0" top="0" width="100" height="100" backgroundColor="#224466"
                     alphaBlend="128"
                     onClick="theme.savePreference('alpha',String(alphaBlend));"/>
        </VIEW></THEME>
        """)
        let pane = try unnamedNode(skin, kind: .subview)
        let suite = "WMPEqualizerSliderDragTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(),
                                                                       defaults: defaults))

        _ = await runtime.transact(
            skin: skin, viewID: "main", size: .init(width: 100, height: 100),
            snapshot: WMPHostSnapshot(),
            event: .init(name: "click", targetID: nil, targetStableID: pane,
                         handlers: ["theme.savePreference('alpha',String(alphaBlend));"]))

        var written: String?
        for (name, value) in defaults.dictionaryRepresentation() where name.hasPrefix("wmp.preferences.") {
            if let values = value as? [String: String], let stored = values["alpha"] { written = stored }
        }
        XCTAssertEqual(written, "128",
                       "a bare name is the element's own property even where the markup named none")
    }

    // MARK: - 2: a slider's region is its track

    /// `elvis`'s band over `elvis`'s tray: a slider whose only artwork is its thumb, drawn over a
    /// node that fills the whole view. Every point down the track must answer the slider — the
    /// press that reached the backdrop instead is the one that dragged the window.
    func testASliderWithOnlyAThumbIsHittableDownItsWholeTrack() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="60" height="100">
            <BUTTON id="tray" left="0" top="0" width="60" height="100" image="tray.png"/>
            <SLIDER id="eq1" direction="vertical" left="20" top="10" width="10" height="75"
                    min="-14" max="14" thumbImage="knob.png"/>
        </VIEW></THEME>
        """, images: ["tray.png": try opaqueSquare(60), "knob.png": try opaqueSquare(8)])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let tester = WMPHitTester(hits: scene.hits)

        for y in stride(from: CGFloat(11), through: 84, by: 8) {
            XCTAssertEqual(tester.hitTest(WMPPoint(x: 25, y: y))?.nodeID, "eq1",
                           "the skin authored a 10x75 box because that is the box it wants pressed")
        }
        XCTAssertEqual(tester.hitTest(WMPPoint(x: 5, y: 50))?.nodeID, "tray",
                       "and it claims nothing outside its own frame")
    }

    // MARK: - 3: the skin's own name for the equaliser

    /// `elvis`'s band write, which used to round-trip through the element's property bag and reach
    /// no audio at all. The read is the other half and is what moves the thumb: the control is
    /// bound to `wmpprop:ElvisEQS.gainLevel1`, which resolves from the host.
    func testANamedEqualizerSettingsReachesTheEqualizer() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <equalizerSettings id="ElvisEQS" enable="true"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        var snapshot = WMPHostSnapshot()
        snapshot.equalizer.gains[2] = 6

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: .init(width: 100, height: 100), snapshot: snapshot,
            event: .init(name: "click", targetID: "go", handlers: [
                "ElvisEQS.gainLevel1 = 9; theme.savePreference('read', String(ElvisEQS.gainLevel3));"
            ]))

        XCTAssertEqual(output.hostCommands.map(\.action), ["setEQBand:0"])
        XCTAssertEqual(output.hostCommands.first?.value, .number(9))
        XCTAssertTrue(output.calls.contains { $0.path == "elviseqs.gainlevel3" && $0.recognised },
                      "the read answers from the host, which is where the thumb's binding reads")
    }

    /// `elvis`'s reset button is `onclick="ElvisEQS.Reset(); balance.Reset();"`. The method has to
    /// answer on the element or the handler dies on its first statement and takes the balance
    /// reset with it — the shape W216 already showed costs a skin everything after the throw.
    func testANamedEqualizerSettingsAnswersTheEqualizersOwnMethods() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <equalizerSettings id="ElvisEQS" enable="true"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: .init(width: 100, height: 100),
            snapshot: WMPHostSnapshot(),
            event: .init(name: "click", targetID: "go",
                         handlers: ["ElvisEQS.Reset(); theme.savePreference('after','yes');"]))

        XCTAssertEqual(output.hostCommands.map(\.action),
                       (0..<10).map { "setEQBand:\($0)" }, "reset flattens all ten bands")
        XCTAssertFalse(output.diagnostics.contains { $0.code == "handler-error" },
                       "and the statement after it still runs")
    }

    /// **The three the element keeps.** `enableSplineTension`, `splineTension` and `bypass` are
    /// bookkeeping this engine has no DSP for and whose authored value a skin reads straight back
    /// (W134). Routing them to the equaliser as well would answer the session's defaults over the
    /// markup, which is a named `<EQUALIZERSETTINGS>` losing its own attributes.
    func testANamedEqualizerSettingsKeepsItsOwnInertBookkeeping() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <equalizerSettings id="ElvisEQS" enableSplineTension="true" splineTension="7"/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: .init(width: 100, height: 100),
            snapshot: WMPHostSnapshot(),
            event: .init(name: "click", targetID: "go", handlers: [
                "theme.savePreference('t', ElvisEQS.enableSplineTension + '|' + ElvisEQS.splineTension);"
            ]))

        XCTAssertTrue(output.calls.filter { $0.path.hasPrefix("elviseqs.") }
                        .allSatisfy { $0.resolution == .inert },
                      "the element's own bookkeeping stays inert and stays the element's")
        XCTAssertTrue(output.hostCommands.isEmpty, "spline tension applies nothing")
    }

    /// The scene half, and the one the reporter actually sees: the thumb's position comes from the
    /// binding, which resolves through `WMPObservablePropertyRegistry` and not the object model. A
    /// path this engine cannot answer commits the empty string, so the band drew wherever the
    /// markup left it however far it was dragged.
    func testABindingOnTheSkinsOwnEqualizerNameSettlesFromTheHost() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <equalizerSettings id="ElvisEQS" enable="true"/>
            <slider id="eq1" direction="vertical" left="0" top="0" width="10" height="75"
                    min="-14" max="14" value="wmpprop:ElvisEQS.gainLevel1"/>
        </VIEW></THEME>
        """)
        let address = WMPScenePropertyAddress(stableID: try stableID(skin, "eq1"), property: "value")
        var registry = WMPObservablePropertyRegistry(graph: skin.graph)
        var snapshot = WMPHostSnapshot()
        snapshot.equalizer.gains[0] = 9

        XCTAssertEqual(registry.changes(for: snapshot).first { $0.address == address }?.value,
                       .number(9), "the thumb follows the gain the band was dragged to")
        snapshot.equalizer.gains[0] = -14
        XCTAssertEqual(registry.changes(for: snapshot).first { $0.address == address }?.value,
                       .number(-14), "and settles again rather than sticking where it opened")
    }

    // MARK: - 4: a band subview tied with its tray's artwork

    /// `Plus! HueShifter`'s drawer: the band subview first and the tray's opaque artwork after it,
    /// both `zIndex="2"`. Document order alone put the tray on top — no thumbs drawn, every press
    /// taken by the tray — and the skin's own `hueshifter_final.jpg` shows WMP drawing the bands
    /// over it. `Plus! SlimLine` authors the same drawer the other way round; both must agree.
    func testASubviewWinsAZIndexTieWithItsSiblingsInEitherOrder() async throws {
        let band = """
            <SUBVIEW id="bands" zIndex="2" left="10" top="10" width="40" height="80">
                <SLIDER id="eq1" direction="vertical" left="10" top="0" width="10" height="75"
                        min="-14" max="14" thumbImage="knob.png"/>
            </SUBVIEW>
            """
        let tray = #"<BUTTON id="tray" zIndex="2" left="0" top="0" width="60" height="100" image="tray.png"/>"#
        for (label, children) in [("band first", band + tray), ("tray first", tray + band)] {
            let skin = try await load(wms: """
            <THEME><VIEW id="main" width="60" height="100">\(children)</VIEW></THEME>
            """, images: ["tray.png": try opaqueSquare(60), "knob.png": try opaqueSquare(8)])
            let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
            let order = scene.commands.compactMap(\.nodeID)
            let thumb = try XCTUnwrap(order.lastIndex(of: "eq1"), label)
            let artwork = try XCTUnwrap(order.lastIndex(of: "tray"), label)
            XCTAssertGreaterThan(thumb, artwork, "\(label): the band paints over the tray")
            XCTAssertEqual(WMPHitTester(hits: scene.hits).hitTest(WMPPoint(x: 25, y: 50))?.nodeID,
                           "eq1", "\(label): and the press reaches it")
        }
    }

    // MARK: - 5: an id declared twice in one view

    /// `The_Sentinel_v.1.0`'s shape: EQ drawer panels `eq1`…`eq3`, then band sliders reusing the
    /// same ids. The skin's `eq1.moveTo(…)` opens the drawer, so a script name reaches the **first**
    /// declaration — and a write must land on the node the read came from. Last-wins here sent the
    /// drawer's move to the slider, the drawer never opened, and all ten bands stayed buried.
    func testAScriptNameDeclaredTwiceWritesTheNodeItReads() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <SUBVIEW id="eq1" left="0" top="0" width="100" height="30"/>
            <SLIDER id="eq1" direction="vertical" left="10" top="40" width="6" height="49"
                    min="-14" max="14"/>
        </VIEW></THEME>
        """)
        let panel = try XCTUnwrap(skin.graph.nodes(id: "eq1").first?.stableID)
        XCTAssertEqual(WMPScriptViewPlan(skin: skin, viewID: "main").idToStableID["eq1"], panel)
    }

    /// The other half of the same skin: dragging the band that lost its name to the panel. The
    /// handler must be handed the slider's value and scoped to the slider, not to the panel the id
    /// resolves to — otherwise `eq.gainLevel1 = value` writes the panel's (absent) value, which is
    /// the 0 dB that snapped Sentinel's first three bands back on every drag.
    func testADuplicateNamedSlidersHandlerIsHandedItsOwnValue() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <EQUALIZERSETTINGS id="eq" enabled="true"/>
            <SUBVIEW id="eq1" left="0" top="0" width="100" height="30"/>
            <SLIDER id="eq1" direction="vertical" left="10" top="40" width="6" height="49"
                    min="-14" max="14" value="wmpprop:eq.gainLevel1"
                    value_onchange="eq.gainLevel1=value;"/>
        </VIEW></THEME>
        """)
        let band = try XCTUnwrap(skin.graph.nodes(id: "eq1").last?.stableID)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }

        _ = await runtime.transact(skin: skin, viewID: "main", size: .init(width: 100, height: 100),
                                   snapshot: WMPHostSnapshot(), event: nil)
        await runtime.holdElement(stableID: band)
        await runtime.setWidgetValue(stableID: band, value: 9, viewID: "main")
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: .init(width: 100, height: 100),
            snapshot: WMPHostSnapshot(),
            event: .init(name: "change", targetID: "eq1", targetStableID: band,
                         handlers: ["eq.gainLevel1=value;"]))

        XCTAssertEqual(output.hostCommands.map(\.action), ["setEQBand:0"])
        XCTAssertEqual(output.hostCommands.first?.value, .number(9),
                       "the slider the pointer is on, not the panel that holds its id")
    }
}
