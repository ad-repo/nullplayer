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
}
