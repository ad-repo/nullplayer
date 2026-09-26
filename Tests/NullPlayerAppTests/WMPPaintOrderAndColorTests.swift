import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// Three rules the reported `Colorchooser` defects turned out to be, none of which is about that
/// skin: what a `<VIEW>` does with background artwork that is not its declared size (W164), where a
/// colour comes from when the markup is not the only one who states it (W165), and who owns paint
/// order once a script has written `zIndex` (W166).
///
/// See `skills/wmp-skin-guide/reference/skins/colorchooser.md`.
final class WMPPaintOrderAndColorTests: XCTestCase {

    private func load(_ entries: [WMPTestArchiveEntry]) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    /// An opaque single-colour PNG of an exact size, so a background image's *intrinsic* size is
    /// the thing under test rather than anything the decoder infers.
    private func image(width: Int, height: Int, rgba: (UInt8, UInt8, UInt8)) throws -> Data {
        var bytes: [UInt8] = []
        for _ in 0..<(width * height) { bytes += [rgba.0, rgba.1, rgba.2, 255] }
        return try WMPSkinTestSupport.encodedImage(width: width, height: height, rgba: bytes)
    }

    private func fill(of scene: WMPScene, id: String) -> WMPColor? {
        for command in scene.commands where command.nodeID?.caseInsensitiveCompare(id) == .orderedSame {
            if case let .fill(color) = command.paint { return color }
        }
        return nil
    }

    private func frame(of scene: WMPScene, stableID: Int) -> WMPRect? {
        scene.commands.first { $0.stableID == stableID }?.frame
    }

    // MARK: W164 — a view's own artwork is anchored, never stretched to a size it does not have

    /// `Colorchooser` declares `width="300" height="200"` over a 246x202 `colorBack.bmp`. Stretched
    /// to the canvas its drawn frame lands at x=87…299 while `mainBackground` — the opaque panel
    /// that belongs *inside* the box the artwork draws — stays at the authored 77…241, and the
    /// frame and its contents are visibly out of register. Three more corpus views author the same
    /// disagreement: `Cubist` (508x189 art in a 508x350 view), `Radio` (265x128 in 265x167) and
    /// `Tomb Raider 2` (343x351 in 543x551).
    func testAViewDrawsBackgroundArtworkAtItsOwnSizeWhenTheMarkupDisagrees() async throws {
        let skin = try await load([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="300" height="200" backgroundImage="back.png"/></THEME>
            """.utf8)),
            WMPTestArchiveEntry("back.png", data: try image(width: 246, height: 202, rgba: (10, 20, 30)))
        ])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertEqual(scene.canvasSize.width, 300, "the window is the size the markup asked for")
        XCTAssertEqual(scene.canvasSize.height, 200)
        let artwork = try XCTUnwrap(scene.commands.first)
        XCTAssertEqual(artwork.frame.x, 0, "anchored at the origin")
        XCTAssertEqual(artwork.frame.y, 0)
        XCTAssertEqual(artwork.frame.width, 246, "and drawn at its own width, not the canvas's")
        XCTAssertEqual(artwork.frame.height, 202)
    }

    /// The scope of the rule, and the half that keeps every resizable skin as it was: the mismatch
    /// has to be one the **markup** states. Where the authored size and the artwork agree, a canvas
    /// a user drag or a script grew still stretches the background exactly as before — which is
    /// what the corpus's other 13 views with both a literal size and a resolvable background image
    /// rely on. Resizable, because a fixed view grown by its own script anchors its art instead
    /// (`gadget`'s drawer).
    func testAViewWhoseArtworkMatchesItsAuthoredSizeStillStretchesWithTheCanvas() async throws {
        let skin = try await load([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="200" height="100" maxWidth="400" resizAble="true"
                         backgroundImage="back.png"/></THEME>
            """.utf8)),
            WMPTestArchiveEntry("back.png", data: try image(width: 200, height: 100, rgba: (10, 20, 30)))
        ])
        let builder = WMPSceneBuilder(loadedSkin: skin)

        let resting = try await builder.build(viewID: "main")
        XCTAssertEqual(resting.commands.first?.frame.width, 200)

        let grown = try await builder.build(viewID: "main",
                                            requestedSize: WMPSize(width: 320, height: 100))
        XCTAssertEqual(grown.canvasSize.width, 320)
        XCTAssertEqual(grown.commands.first?.frame.width, 320,
                       "artwork authored at the view's own size still fills a resized window")
    }

    /// The other half: a view the user cannot resize changes size only because its own script
    /// asked, and that is W164's statement made at runtime. `gadget` opens its drawer with
    /// `view.height = 333` over a 336x246 `base_unit.bmp`; stretched, the player grew 35% taller,
    /// and its black `backgroundColor` — no longer keyed once the art missed the frame — filled
    /// the whole window. The art stays at its own size and the fill stays inside it.
    func testAFixedViewItsScriptGrewKeepsItsArtworkAndItsFillAtTheArtworksSize() async throws {
        let skin = try await load([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="200" height="100" backgroundImage="back.png"
                         backgroundColor="#000000" clippingColor="#FF0000"/></THEME>
            """.utf8)),
            WMPTestArchiveEntry("back.png", data: try image(width: 200, height: 100, rgba: (10, 20, 30)))
        ])
        let grown = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", requestedSize: WMPSize(width: 200, height: 160))

        XCTAssertEqual(grown.canvasSize.height, 160, "the window is the size the script asked for")
        let artwork = try XCTUnwrap(grown.commands.first {
            if case .image = $0.paint { return true } else { return false }
        })
        XCTAssertEqual(artwork.frame.height, 100, "the art is not stretched into the drawer's rows")
        let backdrop = try XCTUnwrap(grown.commands.first {
            if case .fill = $0.paint { return true } else { return false }
        })
        XCTAssertEqual(backdrop.inheritedClipMasks.map(\.frame),
                       [WMPRect(x: 0, y: 0, width: 200, height: 100)],
                       "the fill is keyed with the art where the art is drawn, and nowhere past it")
    }

    // MARK: W165 — a colour has three sources and the markup is only one of them

    /// `wmpprop:<element>.<property>` on a colour, which `Colorchooser` is the only archive in the
    /// corpus to author — three of them, measured across the installed `.wmz` corpus.
    ///
    /// Its caption takes `foregroundColor="wmpprop:style.foregroundColor"` from an invisible
    /// `<TEXT id="style">` held purely as a palette, so reading the markup alone drew it in the
    /// unset-colour default on a white panel and the only affordance the skin has was invisible.
    func testAColourMirrorsAnotherElementsAuthoredValue() async throws {
        let skin = try await load([WMPTestArchiveEntry("skin.wms", data: Data("""
        <THEME><VIEW id="main" width="200" height="100">
          <TEXT id="style" foregroundColor="#204060"/>
          <SUBVIEW id="strip" left="0" top="0" width="200" height="20"
                   backgroundColor="wmpprop:panel.backgroundColor"/>
          <SUBVIEW id="panel" left="0" top="20" width="200" height="80" backgroundColor="#FFEEDD"/>
        </VIEW></THEME>
        """.utf8))])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertEqual(fill(of: scene, id: "panel"), WMPColor(red: 0xFF, green: 0xEE, blue: 0xDD))
        XCTAssertEqual(fill(of: scene, id: "strip"), WMPColor(red: 0xFF, green: 0xEE, blue: 0xDD),
                       "a wmpprop: colour is the value the named element holds")
    }

    /// A `<TEXT>` that states no colour anywhere draws black. `Colorchooser`'s `red`/`green`/`blue`
    /// labels author none over a white panel, and a white default drew them invisible.
    func testAnUncolouredTextDrawsBlack() async throws {
        let skin = try await load([WMPTestArchiveEntry("skin.wms", data: Data("""
        <THEME><VIEW id="main" width="200" height="100">
          <TEXT id="label" left="10" top="10" value="red"/>
        </VIEW></THEME>
        """.utf8))])
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let text = scene.commands.compactMap { command -> WMPSceneText? in
            guard command.nodeID == "label", case let .text(text) = command.paint else { return nil }
            return text
        }.first
        XCTAssertEqual(try XCTUnwrap(text).color, WMPColor(red: 0, green: 0, blue: 0))
    }

    /// The other two sources, together, because `Colorchooser` needs them together: its three RGB
    /// sliders assign `mainBackground.backgroundColor` from script, and the transport strip mirrors
    /// that same property. A mirror that reads only markup leaves the strip behind whenever the
    /// user moves a slider.
    func testAScriptAssignedColourPaintsAndAMirrorFollowsIt() async throws {
        let skin = try await load([WMPTestArchiveEntry("skin.wms", data: Data("""
        <THEME><VIEW id="main" width="200" height="100">
          <SUBVIEW id="strip" left="0" top="0" width="200" height="20"
                   backgroundColor="wmpprop:panel.backgroundColor"/>
          <SUBVIEW id="panel" left="0" top="20" width="200" height="80" backgroundColor="#FFFFFF"/>
        </VIEW></THEME>
        """.utf8))])
        let panel = try XCTUnwrap(skin.graph.nodes(id: "panel").first)
        var overrides = WMPSceneOverrides.empty
        overrides.properties[WMPScenePropertyAddress(stableID: panel.stableID,
                                                     property: "backgroundcolor")] = .string("#112233")
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main", overrides: overrides)

        XCTAssertEqual(fill(of: scene, id: "panel"), WMPColor(red: 0x11, green: 0x22, blue: 0x33),
                       "the value a handler assigned is what the element draws with")
        XCTAssertEqual(fill(of: scene, id: "strip"), WMPColor(red: 0x11, green: 0x22, blue: 0x33),
                       "and the mirror follows it rather than the markup it replaced")
    }

    /// A write the colour parser cannot read is **no answer**, not black. `theme.loadPreference`
    /// answers WMP's `--` sentinel for a key that was never saved, and a skin that stores a colour
    /// in a preference assigns whatever came back without checking — so an unparseable override
    /// must leave the authored colour standing rather than paint the element out.
    func testAnUnparseableColourOverrideLeavesTheAuthoredValueStanding() async throws {
        let skin = try await load([WMPTestArchiveEntry("skin.wms", data: Data("""
        <THEME><VIEW id="main" width="200" height="100">
          <SUBVIEW id="panel" left="0" top="0" width="200" height="100" backgroundColor="#FFFFFF"/>
        </VIEW></THEME>
        """.utf8))])
        let panel = try XCTUnwrap(skin.graph.nodes(id: "panel").first)
        for junk in ["", "--", "wmpprop:nothing.here"] {
            var overrides = WMPSceneOverrides.empty
            overrides.properties[WMPScenePropertyAddress(stableID: panel.stableID,
                                                         property: "backgroundcolor")] = .string(junk)
            let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main",
                                                                          overrides: overrides)
            XCTAssertEqual(fill(of: scene, id: "panel"),
                           WMPColor(red: 0xFF, green: 0xFF, blue: 0xFF),
                           "'\(junk)' is not a colour and must not paint one")
        }
    }

    // MARK: W166 — a script owns paint order as much as the markup does

    /// The `Colorchooser` shape, reduced: a visualizer authored behind everything, an opaque panel
    /// declared after it, and the handler that brings the visualizer out in front by writing
    /// `zIndex`. With paint order read from the markup alone the panel counts as artwork *above* a
    /// windowed surface and `windowedEffectsRects` punches it out — which on a non-opaque window is
    /// a transparent, click-through hole for as long as a track plays.
    ///
    /// The assertion is on the **split index**, because that is the fact the punch is derived from:
    /// once the effects node sorts last, nothing is hosted above it and there is nothing to clear.
    func testAScriptAssignedZIndexReordersTheSceneAndKeepsTheWindowBacked() async throws {
        let skin = try await load([WMPTestArchiveEntry("skin.wms", data: Data("""
        <THEME><VIEW id="main" width="200" height="200" backgroundColor="none">
          <EFFECTS id="viz" zIndex="-5" left="20" top="40" width="160" height="120" windowed="true"/>
          <SUBVIEW id="panel" left="10" top="10" width="180" height="180" backgroundColor="#FFFFFF"/>
        </VIEW></THEME>
        """.utf8))])
        let viz = try XCTUnwrap(skin.graph.nodes(id: "viz").first)
        let panel = try XCTUnwrap(skin.graph.nodes(id: "panel").first)
        let builder = WMPSceneBuilder(loadedSkin: skin)

        let authored = try await builder.build(viewID: "main")
        let authoredSplit = try XCTUnwrap(authored.effectsCommandSplitIndex)
        let panelIndex = try XCTUnwrap(authored.commands.firstIndex { $0.stableID == panel.stableID })
        XCTAssertGreaterThanOrEqual(panelIndex, authoredSplit,
                                    "at the authored -5 the panel is hosted above the surface")

        var overrides = WMPSceneOverrides.empty
        overrides.properties[WMPScenePropertyAddress(stableID: viz.stableID,
                                                     property: "zindex")] = .number(5)
        let raised = try await builder.build(viewID: "main", overrides: overrides)
        let raisedSplit = try XCTUnwrap(raised.effectsCommandSplitIndex)
        let raisedPanel = try XCTUnwrap(raised.commands.firstIndex { $0.stableID == panel.stableID })
        XCTAssertLessThan(raisedPanel, raisedSplit,
                          "the handler brought the surface forward, so the panel is behind it")
        XCTAssertEqual(raisedSplit, raised.commands.count,
                       "nothing is hosted above the surface, so the punch-out clears nothing")
    }

    /// The same write on an ordinary control, so the rule is not read as an `<EFFECTS>` special
    /// case. Six other corpus archives assign `zIndex` from script — `Beck`, `Cablemusic`,
    /// `Charlies_Angels_Full_Throttle`, `Plus! Professional`, `Spider-man` and `cyberchannel`, 50
    /// assignments between them — and none of them is about a visualizer.
    func testAScriptAssignedZIndexReordersOrdinarySiblings() async throws {
        let skin = try await load([WMPTestArchiveEntry("skin.wms", data: Data("""
        <THEME><VIEW id="main" width="100" height="100">
          <SUBVIEW id="under" left="0" top="0" width="100" height="100" backgroundColor="#111111"/>
          <SUBVIEW id="over" left="0" top="0" width="100" height="100" backgroundColor="#222222"/>
        </VIEW></THEME>
        """.utf8))])
        let over = try XCTUnwrap(skin.graph.nodes(id: "over").first)
        let under = try XCTUnwrap(skin.graph.nodes(id: "under").first)
        let builder = WMPSceneBuilder(loadedSkin: skin)

        let authored = try await builder.build(viewID: "main")
        XCTAssertEqual(authored.commands.compactMap(\.nodeID), ["under", "over"],
                       "equal zIndex keeps document order")

        var overrides = WMPSceneOverrides.empty
        overrides.properties[WMPScenePropertyAddress(stableID: over.stableID,
                                                     property: "zindex")] = .number(-1)
        let swapped = try await builder.build(viewID: "main", overrides: overrides)
        XCTAssertEqual(swapped.commands.compactMap(\.nodeID), ["over", "under"],
                       "a handler that sends a sibling behind is what the scene draws")
        XCTAssertNotNil(frame(of: swapped, stableID: under.stableID))
    }
}
