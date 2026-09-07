import XCTest
@testable import NullPlayer

final class WMPGeometryTests: XCTestCase {
    func testNestedOffsetsAlignmentStretchClippingAndExpressions() async throws {
        let xml = """
        <THEME><VIEW id="main" width="100" height="80" minWidth="80" minHeight="60">
          <SUBVIEW id="clip" left="10" top="10" width="40" height="30" backgroundColor="#110000">
            <SUBVIEW id="nested" left="5" top="6" width="50" height="30" backgroundColor="#220000"/>
          </SUBVIEW>
          <SUBVIEW id="right" left="70" top="2" width="20" height="5"
                   horizontalAlignment="right" backgroundColor="#330000"/>
          <SUBVIEW id="stretch" left="4" top="70" width="80" height="5"
                   horizontalAlignment="stretch" backgroundColor="#440000"/>
          <SUBVIEW id="dynamic" left="0" top="0" width="JScript:view.width-4;" height="5"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: url)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(
            viewID: "main", requestedSize: WMPSize(width: 120, height: 80))

        let byID = Dictionary(uniqueKeysWithValues: skin.graph.allNodes.compactMap { node in
            node.xmlID.map { ($0, node.stableID) }
        })
        XCTAssertEqual(scene.canvasSize, WMPSize(width: 120, height: 80))
        XCTAssertEqual(scene.geometries[byID["nested"]!]?.absoluteFrame,
                       WMPRect(x: 15, y: 16, width: 50, height: 30))
        XCTAssertEqual(scene.geometries[byID["nested"]!]?.visibleFrame,
                       WMPRect(x: 15, y: 16, width: 35, height: 24))
        XCTAssertEqual(scene.geometries[byID["right"]!]?.absoluteFrame.x, 90)
        XCTAssertEqual(scene.geometries[byID["stretch"]!]?.absoluteFrame.width, 100)
        XCTAssertEqual(scene.geometries[byID["dynamic"]!]?.absoluteFrame,
                       WMPRect(x: 0, y: 0, width: 116, height: 5))
        XCTAssertTrue(scene.unresolved.isEmpty)
        XCTAssertEqual(scene.metrics.visibleBounds, WMPRect(x: 4, y: 2, width: 106, height: 73))
    }

    func testInitialLayoutExpressionsResolveReferencesAliasesForwardReadsAndRejectCode() async throws {
        let xml = """
        <THEME><VIEW id="main" width="100" height="80">
          <SUBVIEW id="forward" left="JScript:tail.left-tail.width;" top="(height-4)/2"
                   width="wmpprop:tail.width" height="4" backgroundColor="#110000"/>
          <SUBVIEW id="tail" left="90" top="0" width="10" height="8"/>
          <SUBVIEW id="code" left="JScript:danger();" top="0" width="5" height="5"/>
          <SUBVIEW id="cycleA" left="JScript:cycleB.left" top="0" width="1" height="1"/>
          <SUBVIEW id="cycleB" left="JScript:cycleA.left" top="0" width="1" height="1"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8))])
        let skin = try await WMPSkinLoader().load(from: url)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let byID = Dictionary(uniqueKeysWithValues: skin.graph.allNodes.compactMap { node in
            node.xmlID.map { ($0, node.stableID) }
        })

        XCTAssertEqual(scene.geometries[byID["forward"]!]?.absoluteFrame,
                       WMPRect(x: 80, y: 0, width: 10, height: 4))
        XCTAssertNil(scene.geometries[byID["code"]!])
        XCTAssertNil(scene.geometries[byID["cycleA"]!])
        XCTAssertEqual(Set(scene.unresolved.compactMap(\.nodeID)), Set(["code", "cycleA", "cycleB"]))
        XCTAssertTrue(scene.unresolved.contains {
            $0.nodeID == "code" && ($0.authoredValue.contains("unexpected trailing input")
                || $0.authoredValue.contains("unsupported token"))
        })
        XCTAssertTrue(scene.unresolved.contains { $0.authoredValue.contains("cyclic geometry dependency") })
    }

    func testSiblingZIndexControlsDrawOrderWithoutFlatteningHierarchy() async throws {
        let xml = """
        <THEME><VIEW id="main" width="20" height="20">
          <SUBVIEW id="front" left="0" top="0" width="10" height="10" zIndex="2" backgroundColor="#FF0000"/>
          <SUBVIEW id="back" left="0" top="0" width="10" height="10" zIndex="1" backgroundColor="#0000FF"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8))])
        let skin = try await WMPSkinLoader().load(from: url)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertEqual(scene.commands.compactMap(\.nodeID), ["back", "front"])
    }

    func testGeometryReferencesResolveIDsWithinTheActiveView() async throws {
        let xml = """
        <THEME>
          <VIEW id="full" width="100" height="40">
            <SUBVIEW id="bar" left="0" top="0" width="80" height="12"/>
            <SUBVIEW id="art" left="0" top="0" width="80" height="JScript:bar.height;"/>
          </VIEW>
          <VIEW id="tiny" width="60" height="20">
            <SUBVIEW id="bar" left="0" top="0" width="50" height="7"/>
            <SUBVIEW id="art" left="0" top="0" width="50" height="JScript:bar.height;"/>
          </VIEW>
        </THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: url)
        let full = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "full")
        let tiny = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "tiny")
        let fullArt = try XCTUnwrap(skin.views.first { $0.id == "full" }?.node.children.first { $0.xmlID == "art" })
        let tinyArt = try XCTUnwrap(skin.views.first { $0.id == "tiny" }?.node.children.first { $0.xmlID == "art" })

        XCTAssertEqual(full.geometries[fullArt.stableID]?.absoluteFrame.height, 12)
        XCTAssertEqual(tiny.geometries[tinyArt.stableID]?.absoluteFrame.height, 7)
        XCTAssertFalse(full.unresolved.contains { $0.nodeID == "art" })
        XCTAssertFalse(tiny.unresolved.contains { $0.nodeID == "art" })
    }

    func testSeekSliderUsesForegroundArtworkForImplicitSizeAndHitTarget() async throws {
        let track = try WMPSkinTestSupport.encodedImage(width: 120, height: 13,
            rgba: [UInt8](repeating: 255, count: 120 * 13 * 4), type: .bmp)
        let xml = """
        <THEME><VIEW id="main" width="160" height="40">
          <SEEKSLIDER id="seek" left="20" top="10" foregroundImage="track.bmp"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8)),
            WMPTestArchiveEntry("track.bmp", data: track)
        ])
        let skin = try await WMPSkinLoader().load(from: url)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let hit = try XCTUnwrap(scene.hits.first { $0.nodeID == "seek" })

        XCTAssertEqual(hit.frame, WMPRect(x: 20, y: 10, width: 120, height: 13))
        XCTAssertEqual(hit.action, .seek)
        XCTAssertEqual(WMPHitTester(hits: scene.hits).hitTest(WMPPoint(x: 80, y: 16))?.action, .seek)
    }

    /// W7. `image=""` is an omission, not an escape, and it must cost that one image and nothing
    /// else. It used to throw out of the scene walk and take the whole view with it: 39 views across
    /// 36 corpus skins, six of which (`Beck`, `Melvin`, `MSN`, `Spider-man`, `springflower`,
    /// `tubeframe`) drew literally nothing as a result. The warning was never missing — the loader
    /// has always emitted `WMP0023 Optional image resource is empty` — only the survival was.
    func testAnEmptyResourceAttributeCostsOneImageAndNotTheView() async throws {
        let art = try WMPSkinTestSupport.encodedImage(width: 8, height: 8,
            rgba: [UInt8](repeating: 255, count: 8 * 8 * 4), type: .bmp)
        let xml = """
        <THEME><VIEW id="main" width="100" height="80" backgroundImage="">
          <SUBVIEW id="blank" left="0" top="0" width="20" height="20" backgroundImage=""/>
          <SUBVIEW id="drawn" left="30" top="30" width="8" height="8" backgroundImage="art.bmp"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8)),
            WMPTestArchiveEntry("art.bmp", data: art)
        ])
        let skin = try await WMPSkinLoader().load(from: url)
        XCTAssertTrue(skin.diagnostics.contains {
            $0.code == .resourceMissing && $0.severity == .warning
                && $0.message.contains("is empty")
        }, "the empty attribute must still be reported: \(skin.diagnostics)")

        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        let byID = Dictionary(uniqueKeysWithValues: skin.graph.allNodes.compactMap { node in
            node.xmlID.map { ($0, node.stableID) }
        })
        XCTAssertEqual(scene.geometries[byID["blank"]!]?.absoluteFrame,
                       WMPRect(x: 0, y: 0, width: 20, height: 20))
        XCTAssertEqual(scene.geometries[byID["drawn"]!]?.absoluteFrame,
                       WMPRect(x: 30, y: 30, width: 8, height: 8))
        XCTAssertTrue(scene.commands.contains { $0.stableID == byID["drawn"]! },
                      "the sibling with real artwork must still be drawn")
    }
    /// A script's `visible` outranks the markup. Corona's `SetPane` switches its video and
    /// visualization panes purely by writing `vid.visible` / `vis.visible`, and a builder reading
    /// only the authored attribute drew whichever pane the author happened to leave on — which is
    /// how an opaque video pane ended up over the artwork as soon as playback started.
    func testAScriptVisibleOverrideOutranksTheAuthoredAttribute() async throws {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="40" height="20">
              <SUBVIEW id="shown" left="0" top="0" width="10" height="10" backgroundColor="#FF0000"/>
              <SUBVIEW id="hidden" left="10" top="0" width="10" height="10" visible="false"
                       backgroundColor="#00FF00"/>
            </VIEW></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let shown = try XCTUnwrap(skin.graph.nodes(id: "shown").first)
        let hidden = try XCTUnwrap(skin.graph.nodes(id: "hidden").first)
        var overrides = WMPSceneOverrides.empty
        overrides.properties[.init(stableID: shown.stableID, property: "visible")] = .bool(false)
        overrides.properties[.init(stableID: hidden.stableID, property: "visible")] = .bool(true)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main", overrides: overrides)
        XCTAssertFalse(scene.commands.contains { $0.stableID == shown.stableID },
                       "a script hid this element and it was still drawn")
        XCTAssertTrue(scene.commands.contains { $0.stableID == hidden.stableID },
                      "a script revealed this element and it was not drawn")
    }

    /// The natural size of a background bitmap fills in an *unstated* dimension. It must never
    /// overwrite one the skin computed: Corona's compact view collapses `svVideo` to height 0
    /// through its own timer, and the bitmap kept stamping its own height back over it, leaving a
    /// black panel across the window.
    func testIntrinsicArtworkSizeDoesNotOutrankAScriptResolvedDimension() async throws {
        let bmp = try WMPSkinTestSupport.encodedImage(width: 4, height: 4,
            rgba: Array(repeating: UInt8(255), count: 64), type: .bmp)
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="20" height="20">
              <SUBVIEW id="pane" left="0" top="0" backgroundImage="pane.bmp"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("pane.bmp", data: bmp)
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let store = WMPImageStore(provider: skin.archive)
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        let intrinsic = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store).build(viewID: "main")
        XCTAssertEqual(intrinsic.geometries[pane.stableID]?.localFrame.height, 4)

        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: pane.stableID, property: "height")] = 0
        let collapsed = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
            .build(viewID: "main", overrides: overrides)
        XCTAssertEqual(collapsed.geometries[pane.stableID]?.localFrame.height, 0)
        XCTAssertFalse(collapsed.commands.contains { $0.stableID == pane.stableID },
                       "a collapsed pane was still painted at its artwork's height")
    }

    /// A `<VIEW>` with no authored width or height is sized by its own background artwork — the
    /// window *is* the bitmap. Rejecting those was the largest cause of a skin that loaded and then
    /// drew nothing (W6): 89 views across 48 skins, 12 of which produced no layout at all.
    func testViewWithoutAuthoredSizeTakesItsBackgroundArtworkSize() async throws {
        let bmp = try WMPSkinTestSupport.encodedImage(width: 24, height: 9,
            rgba: Array(repeating: UInt8(255), count: 24 * 9 * 4), type: .bmp)
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" backgroundImage="back.bmp">
              <SUBVIEW id="pane" left="1" top="2" width="4" height="3" backgroundColor="#110000"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("back.bmp", data: bmp)
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let pane = try XCTUnwrap(skin.graph.nodes(id: "pane").first)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")

        XCTAssertEqual(scene.canvasSize, WMPSize(width: 24, height: 9))
        XCTAssertEqual(scene.geometries[pane.stableID]?.absoluteFrame,
                       WMPRect(x: 1, y: 2, width: 4, height: 3))
    }

    /// A view with no size and no artwork of its own is sized by the content it can place: `iconic`
    /// hangs its whole player off one `<SUBVIEW backgroundImage="base.gif">` and was a total
    /// blackout until the union was the last fallback (W6). The union descends into a container
    /// whose own size is unknown, and ignores `visible` — a skin authors every wrapper hidden and
    /// turns one on in `onLoad`.
    func testViewWithoutSizeOrArtworkIsSizedByItsContent() async throws {
        let bmp = try WMPSkinTestSupport.encodedImage(width: 24, height: 9,
            rgba: Array(repeating: UInt8(255), count: 24 * 9 * 4), type: .bmp)
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" backgroundColor="#000000">
              <SUBVIEW id="wrapper">
                <SUBVIEW id="art" left="6" top="1" backgroundImage="back.bmp" visible="false"/>
              </SUBVIEW>
              <SUBVIEW id="small" left="0" top="0" width="4" height="3" backgroundColor="#110000"/>
            </VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("back.bmp", data: bmp)
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        XCTAssertEqual(scene.canvasSize, WMPSize(width: 30, height: 10))
    }

    /// The artwork is only the last resort: an authored literal wins, and a script-supplied override
    /// outranks the bitmap for a view whose size its own `.js` computes.
    func testViewSizePrefersAuthoredLiteralThenScriptOverrideOverArtwork() async throws {
        let bmp = try WMPSkinTestSupport.encodedImage(width: 24, height: 9,
            rgba: Array(repeating: UInt8(255), count: 24 * 9 * 4), type: .bmp)
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME>
              <VIEW id="literal" width="40" height="30" backgroundImage="back.bmp"/>
              <VIEW id="computed" backgroundImage="back.bmp"/>
            </THEME>
            """.utf8)),
            WMPTestArchiveEntry("back.bmp", data: bmp)
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let literalScene = try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "literal")
        XCTAssertEqual(literalScene.canvasSize, WMPSize(width: 40, height: 30))

        let computed = try XCTUnwrap(skin.graph.nodes(id: "computed").first)
        var overrides = WMPSceneOverrides.empty
        overrides.geometry[.init(stableID: computed.stableID, property: "width")] = 100
        overrides.geometry[.init(stableID: computed.stableID, property: "height")] = 60
        let scripted = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "computed", overrides: overrides)
        XCTAssertEqual(scripted.canvasSize, WMPSize(width: 100, height: 60))
    }

    /// A view with neither an authored size nor background artwork still has no size to invent, and
    /// the builder never guesses one.
    func testViewWithNoSizeAndNoArtworkIsStillRejected() async throws {
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" backgroundColor="#000000"/></THEME>
            """.utf8))
        ])
        let skin = try await WMPSkinLoader().load(from: archive)
        let code = await WMPSkinTestSupport.failureCode {
            try await WMPSceneBuilder(loadedSkin: skin).build(viewID: "main")
        }
        XCTAssertEqual(code, .invalidGeometry)
    }

}
