import XCTest
@testable import NullPlayer

/// B365 (intake #6, group 2).
final class WinampModernB365Tests: XCTestCase {
    /// B365: past a group that declares no size, a press and `getLeft()` are both measured from the
    /// nearest sized ancestor, so `x - getLeft()` is still the object's own pixels and `x` is the
    /// layout's (Honda Element's volume arc samples a layout-sized map with it). A sized group is
    /// still a space of its own.
    func testAPressAndGetLeftShareTheSpacePastASizelessGroup() throws {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML><container id="main"><layout id="normal" w="300" h="200">
          <group id="loose" x="58" y="100"><layer id="arc" x="0" y="0" w="70" h="42"/></group>
          <group id="boxed" x="30" y="20" w="50" h="50"><layer id="knob" x="5" y="5" w="10" h="10"/></group>
        </layout></container></WasabiXML>
        """)
        let host = WinampModernStubHost()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        addTeardownBlock { renderer.teardown() }
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        addTeardownBlock { scripts.teardown() }
        scripts.hooks.resolvedGeometryRequested = { renderer.resolvedGeometry(of: $0) }
        let arc = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "arc").first)
        let knob = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "knob").first)
        func press(_ object: WasabiObject, _ point: CGPoint) -> CGPoint {
            scripts.pointInEventSpace(of: object, event: "onleftbuttondown", canvasPoint: point, renderer: renderer)
        }

        XCTAssertEqual(press(arc, CGPoint(x: 64, y: 129)), CGPoint(x: 64, y: 129))
        XCTAssertEqual(scripts.parentOffsetInCoordinateSpace(of: arc), CGPoint(x: 58, y: 100))
        XCTAssertEqual(press(knob, CGPoint(x: 40, y: 30)), CGPoint(x: 10, y: 10))
        XCTAssertEqual(scripts.parentOffsetInCoordinateSpace(of: knob), .zero)
    }
}
