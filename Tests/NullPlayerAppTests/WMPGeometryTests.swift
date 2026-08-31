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
        XCTAssertEqual(scene.unresolved.map(\.attribute), ["width"])
        XCTAssertEqual(scene.diagnostics.last?.code, .unresolvedGeometry)
        XCTAssertEqual(scene.metrics.visibleBounds, WMPRect(x: 4, y: 2, width: 106, height: 73))
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
}
