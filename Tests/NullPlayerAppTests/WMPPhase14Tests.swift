import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// The 2026-09-09 reports on `Cablemusic` — "broken all over", then "still many problems", then
/// "when you mouse over the compact button there is a huge overlay" — which were nine unrelated
/// engine defects wearing each other's symptoms. The skin's dossier is
/// `skills/wmp-skin-guide/reference/skins/cablemusic.md`; the rows are W107-W116 in
/// `docs/wmp-skin/wmp-backlog-archive.md` § *Phase 14*.
///
/// Each test pins the **mechanism**, because every one of these was invisible in the picture until
/// something else was fixed first — and four of them were invisible to every headless probe, which
/// is why the ones that can be pinned here are pinned here.
final class WMPPhase14Tests: XCTestCase {

    private func load(wms: String, js: String? = nil,
                      resources: [String: Data] = [:]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        if let js { entries.append(WMPTestArchiveEntry("s.js", data: Data(js.utf8))) }
        for (name, data) in resources.sorted(by: { $0.key < $1.key }) {
            entries.append(WMPTestArchiveEntry(name, data: data))
        }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPPhase14Tests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults)),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func stableID(_ skin: WMPLoadedSkin, _ id: String) throws -> Int {
        try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
    }

    /// A flat opaque sheet, used wherever a test only needs *an* image of a known size.
    private func sheet(_ width: Int, _ height: Int,
                       _ colour: (UInt8, UInt8, UInt8) = (0, 0, 0)) throws -> Data {
        try WMPSkinTestSupport.encodedImage(width: width, height: height,
            rgba: (0..<(width * height)).flatMap { _ in [colour.0, colour.1, colour.2, 255] })
    }

    // MARK: - W107: a `<TEXT>`'s own artwork is its glyphs

    /// **1,441 `<TEXT>` nodes across 127 of the 179 archives resolve no size in the default state**,
    /// 1,058 of them missing width *and* height, because WMP sizes a text from the face and the
    /// string and a skin therefore never states it. `Cablemusic`'s script lays out ten readouts with
    /// `top`/`left`/`width`/`fontSize` and no `height` — there is nothing to set in WMP — and the
    /// whole show/clip/author/copyright block had no frame and never drew.
    func testATextIsSizedByItsOwnGlyphsWhenTheMarkupStatesNoSize() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="100">
            <TEXT id="label" left="10" top="10" fontSize="10" value="Author:"/>
        </VIEW></THEME>
        """)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let frame = try XCTUnwrap(scene.geometries[try stableID(skin, "label")]?.absoluteFrame,
                                  "a text with a value resolves a frame from its own glyphs")
        XCTAssertTrue(scene.unresolved.isEmpty, "nothing is left unresolved: \(scene.unresolved)")
        XCTAssertEqual(frame.height,
                       WMPTextMetrics.lineHeight(fontName: "Arial", fontSize: 10,
                                                 bold: false, italic: false),
                       "the height is one line of the authored face")
        XCTAssertEqual(frame.width,
                       WMPTextMetrics.width(of: "Author:", fontName: "Arial", fontSize: 10,
                                            bold: false, italic: false).rounded(.up),
                       "the width is the measured string — WMP's box grows with its text")
        XCTAssertTrue(scene.commands.contains { if case .text = $0.paint { return true } else { return false } },
                      "and it reaches the command list")
    }

    /// The artwork fallback answers an *unstated* dimension and never outranks one the skin gave.
    func testAnAuthoredTextDimensionOutranksItsGlyphs() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="100">
            <TEXT id="label" left="10" top="10" width="180" height="40" fontSize="10" value="Author:"/>
        </VIEW></THEME>
        """)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let frame = try XCTUnwrap(scene.geometries[try stableID(skin, "label")]?.absoluteFrame)
        XCTAssertEqual(frame.width, 180)
        XCTAssertEqual(frame.height, 40)
    }

    /// An empty value is honestly zero-wide — there is nothing to draw — and it starts drawing on
    /// the transaction that gives it one, because a script write to `value` rebuilds the scene.
    func testAnEmptyTextIsZeroWideUntilItHasAValue() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="100">
            <TEXT id="label" left="10" top="10" fontSize="10" value=""/>
        </VIEW></THEME>
        """)
        let builder = WMPSceneBuilder(loadedSkin: skin)
        let empty = try await builder.build(viewID: "main")
        XCTAssertEqual(empty.geometries[try stableID(skin, "label")]?.absoluteFrame.width, 0)

        var overrides = WMPSceneOverrides.empty
        overrides.properties[.init(stableID: try stableID(skin, "label"), property: "value")] =
            .string("Author:")
        let filled = try await builder.build(viewID: "main", overrides: overrides)
        let width = try XCTUnwrap(filled.geometries[try stableID(skin, "label")]?.absoluteFrame.width)
        XCTAssertGreaterThan(width, 0, "the box grows with the string the script just wrote")
    }

    // MARK: - W108: a `<BUTTONGROUP>` is sized by its mapping image

    /// **31 groups across 16 of the 179 archives resolve no size.** The group's normal state is
    /// usually the window's own background artwork, so the skin authors no `image` and no geometry
    /// at all — and with no frame the group registered no hit target while the artwork beneath
    /// still drew the buttons. That is "most buttons don't work", for every control in six groups.
    func testAButtonGroupWithOnlyAMappingImageIsSizedAndHittable() async throws {
        let map = try WMPSkinTestSupport.encodedImage(width: 4, height: 2,
            rgba: [255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255,
                   255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255])
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="40" height="40">
            <BUTTONGROUP id="group" mappingImage="map.png" hoverImage="hover.png">
                <BUTTONELEMENT id="left" mappingColor="#FF0000" onClick="a();"/>
                <BUTTONELEMENT id="right" mappingColor="#0000FF" onClick="b();"/>
            </BUTTONGROUP>
        </VIEW></THEME>
        """, resources: ["map.png": map, "hover.png": try sheet(4, 2)])
        let store = WMPImageStore(provider: skin.archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store).build(viewID: "main")

        let frame = try XCTUnwrap(scene.geometries[try stableID(skin, "group")]?.absoluteFrame,
                                  "the mapping image is the group's own pixel grid")
        XCTAssertEqual(frame.width, 4)
        XCTAssertEqual(frame.height, 2)
        let groupID = try stableID(skin, "group")
        let hit = try XCTUnwrap(scene.hits.first { $0.stableID == groupID },
                                "a group with a frame registers a hit target")
        XCTAssertEqual(Set(hit.mappingTargets.compactMap(\.nodeID)), ["left", "right"])
        XCTAssertEqual(WMPHitTester(hits: scene.hits).hitTest(WMPPoint(x: 0, y: 0))?.nodeID, "left",
                       "and its colour regions are reachable")
    }

    /// **Two children may declare the same `mappingColor`, and `Dictionary(uniqueKeysWithValues:)`
    /// traps the process.** `Cablemusic` authors `bnpb6` and `bnpb7` both `#00C0FF` — one preset too
    /// many for the eight regions its `map.gif` has. Nothing had ever reached this code for that
    /// skin because its groups resolved no frame, so W108 turned a dead control into a crash on
    /// load. WMP takes the first in document order and draws it; so does this.
    func testTwoChildrenMayDeclareTheSameMappingColour() async throws {
        let map = try WMPSkinTestSupport.encodedImage(width: 2, height: 1,
            rgba: [255, 0, 0, 255, 255, 0, 0, 255])
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="20" height="20">
            <BUTTONGROUP id="group" mappingImage="map.png">
                <BUTTONELEMENT id="first" mappingColor="#FF0000" onClick="a();"/>
                <BUTTONELEMENT id="second" mappingColor="#FF0000" onClick="b();"/>
            </BUTTONGROUP>
        </VIEW></THEME>
        """, resources: ["map.png": map])
        let scene = try await WMPSceneBuilder(loadedSkin: skin,
            imageStore: WMPImageStore(provider: skin.archive)).build(viewID: "main")
        let groupID = try stableID(skin, "group")
        let hit = try XCTUnwrap(scene.hits.first { $0.stableID == groupID })
        XCTAssertEqual(hit.mappingTargets.compactMap(\.nodeID), ["first"],
                       "the duplicate collapses to the first declaration rather than trapping")
    }

    // MARK: - W116: a group's state artwork is only ever painted through its mask

    /// `hoverImage`/`downImage` are the *entire* group redrawn with one control lit. The normal
    /// `image` used to be required before the mask ran at all, so a group that authors none fell
    /// through to the generic single-image path and painted the whole sheet over the window — on
    /// `Cablemusic` a 593x600 bitmap with a dark green surround, over any hover, in six groups.
    ///
    /// **No corpus sweep can see this**: a default-state capture never enters a hover, and the
    /// 535-image sweep across the fix is byte-identical (W73).
    func testAGroupWithNoNormalImageMasksItsHoverArtwork() async throws {
        let map = try WMPSkinTestSupport.encodedImage(width: 2, height: 1,
            rgba: [255, 0, 0, 255, 0, 0, 255, 255])
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="20" height="20">
            <BUTTONGROUP id="group" mappingImage="map.png" hoverImage="hover.png">
                <BUTTONELEMENT id="left" mappingColor="#FF0000" onClick="a();"/>
                <BUTTONELEMENT id="right" mappingColor="#0000FF" onClick="b();"/>
            </BUTTONGROUP>
        </VIEW></THEME>
        """, resources: ["map.png": map, "hover.png": try sheet(2, 1)])
        let builder = WMPSceneBuilder(loadedSkin: skin,
                                      imageStore: WMPImageStore(provider: skin.archive))
        let groupID = try stableID(skin, "group")
        let hovered = try stableID(skin, "left")
        let resting = try await builder.build(viewID: "main")
        let group = try XCTUnwrap(resting.hits.first { $0.stableID == groupID })

        var hoverState = WMPInteractionState()
        _ = hoverState.move(over: group.mappingTargets.first { $0.nodeID == "left" })
        let hoveredScene = try await builder.build(viewID: "main", interactionState: hoverState)

        let sheets = hoveredScene.commands.compactMap { command -> WMPSceneImage? in
            guard case let .image(image) = command.paint,
                  image.resourcePath.hasSuffix("hover.png") else { return nil }
            return image
        }
        XCTAssertEqual(sheets.count, 1, "the hover sheet is drawn once")
        XCTAssertNotNil(sheets.first?.mappingMask,
                        "and only through the mask — an unmasked sheet is the whole group painted "
                        + "over everything beneath it")
        XCTAssertEqual(sheets.first?.mappingMask?.nodeIDs, [hovered],
                       "restricted to the region actually under the pointer")
    }

    // MARK: - W109: WMP spells every transport control twice

    /// The table had `playElement` but no `playButton`, `pauseButton` but no `pauseElement`, and so
    /// on for every pair, so half the vocabulary fell to `.unknown` — which still paints its
    /// `image` and is not interactive. A click on `Cablemusic`'s Play answered `hit=ffw`, the
    /// neighbour whose frame overlapped it. Measured with `scripts/wmp_markup_census.sh` over 172
    /// archives: `PAUSEELEMENT` 80 uses / 69 skins, `PLAYBUTTON` 50 / 45, `PREVBUTTON` 50 / 45,
    /// `NEXTBUTTON` 49 / 44, `STOPBUTTON` 48 / 42, `MUTEBUTTON` 10 / 9, `REPEATBUTTON` 5 / 4.
    func testBothSpellingsOfEveryTransportControlAreKindsAndCarryTheirAction() throws {
        let pairs: [(String, String, WMPTransportAction)] = [
            ("PLAYELEMENT", "PLAYBUTTON", .play),
            ("PAUSEELEMENT", "PAUSEBUTTON", .pause),
            ("STOPELEMENT", "STOPBUTTON", .stop),
            ("PREVELEMENT", "PREVBUTTON", .previous),
            ("NEXTELEMENT", "NEXTBUTTON", .next),
            ("REWELEMENT", "REWBUTTON", .beginScan(.reverse)),
            ("FFWDELEMENT", "FFWDBUTTON", .beginScan(.forward))
        ]
        for (element, button, action) in pairs {
            for tag in [element, button] {
                let kind = WMPElementKind(tagName: tag)
                if case .unknown = kind { XCTFail("\(tag) is not an element kind") ; continue }
                let node = WMPNode(stableID: 1, xml: WMPXMLNode(name: tag, attributes: [],
                                                                location: WMPSourceLocation(path: "skin.wms")))
                XCTAssertEqual(WMPTransportAction.authoredAction(for: node), action,
                               "\(tag) carries \(action)")
            }
        }
        for (tag, action) in [("MUTEBUTTON", WMPTransportAction.toggleMute),
                              ("REPEATBUTTON", .toggleRepeat),
                              ("SHUFFLEBUTTON", .toggleShuffle)] {
            let node = WMPNode(stableID: 1, xml: WMPXMLNode(name: tag, attributes: [],
                                                            location: WMPSourceLocation(path: "skin.wms")))
            XCTAssertEqual(WMPTransportAction.authoredAction(for: node), action, "\(tag)")
        }
    }

    /// A `mappingColor` **under a `BUTTONGROUP`** is a colour region, not a box: 494 of the corpus's
    /// 2,380 unresolved nodes across ~90 skins were transport elements walked as controls. The test
    /// is that pair and not the attribute alone — `polygon` puts a `mappingColor` on a `<SUBVIEW>`
    /// with real geometry as a self-mask, and exempting it dropped its panel.
    func testAMappingRegionIsNotLaidOutButASelfMaskedSubviewStillIs() async throws {
        let map = try WMPSkinTestSupport.encodedImage(width: 2, height: 1,
            rgba: [255, 0, 0, 255, 0, 0, 255, 255])
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="60" height="60">
            <BUTTONGROUP id="group" mappingImage="map.png">
                <PLAYELEMENT id="play" mappingColor="#FF0000"/>
            </BUTTONGROUP>
            <SUBVIEW id="toggle" left="20" top="20" width="18" height="18"
                     mappingImage="map.png" mappingColor="#FF0000" backgroundColor="#00FF00"/>
        </VIEW></THEME>
        """, resources: ["map.png": map])
        let scene = try await WMPSceneBuilder(loadedSkin: skin,
            imageStore: WMPImageStore(provider: skin.archive)).build(viewID: "main")

        XCTAssertNil(scene.geometries[try stableID(skin, "play")],
                     "a group's colour region is never laid out — it has no box to fail to find")
        XCTAssertFalse(scene.unresolved.contains { $0.nodeID == "play" },
                       "and therefore never counts as a starved node")
        let toggle = try XCTUnwrap(scene.geometries[try stableID(skin, "toggle")]?.absoluteFrame,
                                   "a self-masked subview with real geometry still lays out")
        XCTAssertEqual(toggle.x, 20)
        XCTAssertEqual(toggle.width, 18)
    }

    // MARK: - W110: an origin the markup never stated

    /// `left`/`top` default to 0 when unauthored, and the check was `attribute == nil ? 0 : resolve`
    /// — short-circuiting *before* the scene overrides were consulted. Size never had the bug, so a
    /// script-positioned element came out the right size in the wrong place: `Cablemusic`'s two
    /// drawers are seventeen station rows each, laid out entirely by `InitPrograms()` writing
    /// `pr<N>.top`, and all thirty-four drew on top of one another in the drawer's corner.
    func testAScriptCanPositionAnElementTheMarkupNeverPlaced() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="200">
            <TEXT id="row" width="100" height="12" fontSize="10" value="Country"/>
        </VIEW></THEME>
        """)
        let identifier = try stableID(skin, "row")
        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: identifier, property: "left")] = 40
        overrides.geometry[.init(stableID: identifier, property: "top")] = 75
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: overrides)
        let frame = try XCTUnwrap(scene.geometries[identifier]?.absoluteFrame)
        XCTAssertEqual(frame.x, 40)
        XCTAssertEqual(frame.y, 75, "the override is read before the default, not after it")
    }

    // MARK: - W112: a tween's endpoint is not readable by the rest of its handler

    private func drawerSkin() -> String {
        """
        <THEME><VIEW id="main" width="400" height="200" scriptFile="s.js">
            <SUBVIEW id="drawer" left="100" top="0" width="100" height="100"/>
            <SUBVIEW id="list" left="0" top="0" width="10" height="10" visible="true"/>
            <BUTTON id="tab" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """
    }

    /// WMP animates over the duration argument, so `left` still answers where the element *is* for
    /// the remaining statements — and skins are written against exactly that. `Cablemusic`'s
    /// playlist tab is `onClick="PlayListMove();HidePlist();"`, and `HidePlist()` reads
    /// `subPlayList.left` to decide whether the drawer just opened or shut. Reading the destination
    /// meant closing the drawer never hid the playlist: "the playlist is always showing".
    func testATweenEndpointIsNotReadableByTheRestOfItsHandler() async throws {
        let skin = try await load(wms: drawerSkin(), js: """
        function Move() { drawer.moveTo(300, drawer.top, 400); }
        function Hide() { if (drawer.left == 300) { list.visible = false; } }
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 400, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "tab", handlers: ["Move();Hide();"]))

        XCTAssertEqual(output.overrides.geometry[.init(stableID: try stableID(skin, "drawer"),
                                                       property: "left")], 300,
                       "the endpoint still lands in this transaction (W38)")
        XCTAssertNil(output.overrides.properties[.init(stableID: try stableID(skin, "list"),
                                                       property: "visible")],
                     "but `drawer.left` still read 100 inside the handler, so the guard did not fire")
    }

    /// A duration of zero is not a tween: it is an instant move, and a later read in the same
    /// handler must see it. `movePlayButton()` toggles on exactly that.
    func testAZeroDurationMoveIsVisibleToTheRestOfTheHandler() async throws {
        let skin = try await load(wms: drawerSkin(), js: """
        function Move() { drawer.moveTo(300, drawer.top, 0); }
        function Hide() { if (drawer.left == 300) { list.visible = false; } }
        """)
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 400, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "tab", handlers: ["Move();Hide();"]))
        XCTAssertEqual(output.overrides.properties[.init(stableID: try stableID(skin, "list"),
                                                         property: "visible")], .bool(false),
                       "an instant move is readable immediately")
    }

    /// Deferring the endpoint must not cost W55: `onEndMove` is still raised from it, after the
    /// handler that started the tween has returned.
    func testADeferredTweenStillRaisesItsCompletionHandler() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="400" height="200" scriptFile="s.js">
            <SUBVIEW id="drawer" left="100" top="0" width="100" height="100"
                     onEndMove="list.visible = true;"/>
            <SUBVIEW id="list" left="0" top="0" width="10" height="10" visible="false"/>
            <BUTTON id="tab" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """, js: "function Move() { drawer.moveTo(300, drawer.top, 400); }")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 400, height: 200),
            snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "tab", handlers: ["Move();"]))
        XCTAssertEqual(output.overrides.properties[.init(stableID: try stableID(skin, "list"),
                                                         property: "visible")], .bool(true))
    }

    // MARK: - W113: a script resizing its own window

    private func compactSkin() -> String {
        """
        <THEME><VIEW id="main" width="593" height="600" scriptFile="s.js">
            <SUBVIEW id="body" left="0" top="0" width="100" height="100"/>
            <BUTTON id="shrink" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """
    }

    /// The view root used to read its markup ahead of its overrides — alone among nodes — so a
    /// `<VIEW width="593">` could never be resized by its own script, and `SwitchSmall()`'s
    /// 475x373 compact player drew inside the full-size window with two hundred empty pixels
    /// around it. Reported as "when you click the compact button there is a large overlay".
    func testAScriptAssignedViewSizeBecomesTheCanvas() async throws {
        let skin = try await load(wms: compactSkin(), js: "")
        let view = try XCTUnwrap(skin.views.first { $0.id == "main" }?.node.stableID)
        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: view, property: "width")] = 475
        overrides.geometry[.init(stableID: view, property: "height")] = 373
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: overrides)
        XCTAssertEqual(scene.canvasSize, WMPSize(width: 475, height: 373),
                       "the authored literal no longer clamps the script's own answer")
    }

    /// **The size a script assigns is not the size alignment is measured from.** `LostPlanet`'s
    /// `onLoadInfo` opens with `view.width = view.minWidth`; letting that replace the authored size
    /// collapsed every child's delta to zero, and its stretch tiles stopped covering the 61 px they
    /// had been covering — holes through the window frame, and the sweep's 10 lost images.
    func testAScriptAssignedViewSizeDoesNotCollapseAlignmentDeltas() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100">
            <SUBVIEW id="edge" left="90" top="0" width="10" height="10"
                     horizontalAlignment="right" backgroundColor="#FF0000"/>
        </VIEW></THEME>
        """)
        let view = try XCTUnwrap(skin.views.first { $0.id == "main" }?.node.stableID)
        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: view, property: "width")] = 160
        overrides.geometry[.init(stableID: view, property: "height")] = 100
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: overrides)
        XCTAssertEqual(scene.canvasSize.width, 160)
        XCTAssertEqual(scene.geometries[try stableID(skin, "edge")]?.absoluteFrame.x, 150,
                       "the right-aligned child moves by canvas − *authored* width, so it stays "
                       + "against the edge instead of leaving a 60 px hole")
    }

    /// Keyed off the **mutations**, not off the committed overrides: an expression-driven
    /// `<VIEW width="jscript:…">` re-resolves every transaction and already read the window's
    /// current size — it is a layout, not a request to resize. And a non-positive result is the
    /// store-thumbnail collapse (34 skins), which is a view saying it has no window at all.
    func testOnlyAnExplicitAssignmentIsAResizeRequest() async throws {
        let skin = try await load(wms: compactSkin(), js: "")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        let size = WMPSize(width: 593, height: 600)

        let untouched = await runtime.transact(
            skin: skin, viewID: "main", size: size, snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "shrink", handlers: ["body.left = 5;"]))
        XCTAssertNil(untouched.viewSize, "a transaction that never assigns the view's size asks for none")

        let resized = await runtime.transact(
            skin: skin, viewID: "main", size: size, snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "shrink",
                                   handlers: ["view.width = 475; view.height = 373;"]))
        XCTAssertEqual(resized.viewSize, WMPSize(width: 475, height: 373))

        let collapsed = await runtime.transact(
            skin: skin, viewID: "main", size: size, snapshot: WMPHostSnapshot(),
            event: WMPJScriptEvent(name: "click", targetID: "shrink",
                                   handlers: ["view.width = 0; view.height = 0;"]))
        XCTAssertNil(collapsed.viewSize, "a collapse to 0x0 is not a smaller window")
    }

    // MARK: - W114: a number a script writes has to reach the drawing

    /// `WMPSceneBuilder.literal(_:_:)` reads the attribute and nothing else — geometry has
    /// `parseDimension`, a slider has `sliderMetrics`, and the rest had nothing. `Cablemusic` lays
    /// its readouts out with `txtShowLabel.fontSize = 7` over a markup that says `fontSize="10"`,
    /// so every label was measured *and* drawn three points too large and "Copyright:" ran out of
    /// its 55 px box and off the left edge of the LCD it belongs in.
    func testAScriptFontSizeReachesBothTheMeasurementAndTheDrawing() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="200" height="100">
            <TEXT id="label" left="10" top="10" fontSize="10" value="Copyright:"/>
        </VIEW></THEME>
        """)
        let identifier = try stableID(skin, "label")
        var overrides = WMPSceneOverrides.empty
        overrides.properties[.init(stableID: identifier, property: "fontsize")] = .number(7)
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: overrides)

        let drawn = try XCTUnwrap(scene.commands.compactMap { command -> WMPSceneText? in
            guard command.stableID == identifier, case let .text(text) = command.paint else { return nil }
            return text
        }.first)
        XCTAssertEqual(drawn.fontSize, 7, "the drawing uses the size the script wrote")
        XCTAssertEqual(scene.geometries[identifier]?.absoluteFrame.height,
                       WMPTextMetrics.lineHeight(fontName: "Arial", fontSize: 7,
                                                 bold: false, italic: false),
                       "and so does the box measured around it")
    }

    /// `justification` is **788 authored uses across 150 of the 172 archives the markup census can
    /// read**, and it is rendered — so a script write has to commit as a mutation rather than be
    /// stored inert. It only reached the scene where the markup happened to author it too.
    func testTheRenderedTextPropertiesAreScriptable() throws {
        for name in ["justification", "fontface", "fontstyle", "fontsize"] {
            XCTAssertTrue(WMPObjectModel.standardElementProperties.contains(name),
                          "\(name) is read by the builder's text path, so a write must commit")
        }
    }

    /// The baseline was `max(fontSize, (height + fontSize) / 2)` measured from the box's bottom —
    /// fine while every `<TEXT>` had a generously tall authored box, and four pixels *above* the box
    /// once a text is sized by its own glyphs (W107). `Cablemusic`'s label column drew above the LCD
    /// it belongs in, over the bezel.
    func testATextNeverDrawsAboveItsOwnBox() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="120" height="60" backgroundColor="#000000">
            <TEXT id="label" left="10" top="20" fontSize="7" foregroundColor="#FFFFFF" value="Show:"/>
        </VIEW></THEME>
        """)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let frame = try XCTUnwrap(scene.geometries[try stableID(skin, "label")]?.absoluteFrame)
        let image = try await WMPRenderer(imageStore: WMPImageStore(provider: skin.archive))
            .render(scene: scene).image

        func rowHasInk(_ y: Int) -> Bool {
            (Int(frame.x)..<Int(frame.maxX)).contains {
                WMPSkinTestSupport.rgba(image, x: $0, yFromTop: y)[0] > 0
            }
        }
        for y in 0..<Int(frame.y) {
            XCTAssertFalse(rowHasInk(y), "nothing is drawn above the box's own top edge (row \(y))")
        }
        XCTAssertTrue((Int(frame.y)..<Int(frame.maxY)).contains(where: rowHasInk),
                      "and the readout is drawn inside it")
    }

    // MARK: - W115: two members that abort the handler filling every readout

    /// Neither was findable headlessly — no sweep here has a host snapshot, so nothing reaches a
    /// `psPlaying` branch. `INPUT script-diag` named `player.network.bitrate` in one launch and,
    /// once that was closed, `player.currentmedia.sourceurl` behind it. `Cablemusic`'s
    /// `handlePlayStateChange` reaches `UpdateBitrate()` and then `GenericProgramInfoBig()`, whose
    /// third statement is the `sourceURL` read, so one missing member cost every readout.
    func testTheHostAnswersSourceURLAndBitRate() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="100" height="100" scriptFile="s.js">
            <TEXT id="out" left="0" top="0" width="90" height="12" fontSize="10" value=""/>
            <BUTTON id="go" left="0" top="0" width="10" height="10"/>
        </VIEW></THEME>
        """, js: "")
        let (runtime, cleanup) = try runtime()
        defer { cleanup() }
        var snapshot = WMPHostSnapshot()
        snapshot.metadata = WMPMediaMetadata(title: "Hells Bells", artist: "AC/DC", album: "Back in Black",
                                             sourceURL: "http://example.test/stream.flac")
        snapshot.bitrate = 970_000

        let output = await runtime.transact(
            skin: skin, viewID: "main", size: WMPSize(width: 100, height: 100), snapshot: snapshot,
            event: WMPJScriptEvent(name: "click", targetID: "go", handlers: [
                "out.value = player.currentMedia.sourceURL + '|' + player.network.bitRate;"
            ]))
        XCTAssertTrue(output.diagnostics.isEmpty, "the handler runs to the end: \(output.diagnostics)")
        XCTAssertEqual(output.overrides.properties[.init(stableID: try stableID(skin, "out"),
                                                         property: "value")],
                       .string("http://example.test/stream.flac|970000"))
    }

    /// The static demand tally is derived from the object model rather than restated, so a member
    /// the runtime answers must never still be counted as unimplemented demand.
    func testTheDemandTallyAgreesWithTheObjectModel() {
        XCTAssertTrue(WMPJScriptCompatibility.supports(object: "media", member: "sourceURL"))
        XCTAssertTrue(WMPJScriptCompatibility.supports(object: "network", member: "bitRate"))
        for tag in ["playbutton", "pauseelement", "stopbutton", "prevbutton", "nextbutton",
                    "mutebutton", "repeatbutton", "effects", "customslider"] {
            if case .unknown = WMPElementKind(tagName: tag) {
                XCTFail("\(tag) is implemented, so it must not fall to .unknown and rank as demand")
            }
        }
    }
}
