import XCTest
@testable import NullPlayer

final class WMPXMLTests: XCTestCase {
    func testPreservesAuthoredSpellingHierarchyAttributesAndLocations() throws {
        let xml = """
        <?xml version="1.0"?>
        <THEME Name="Synthetic">
          <VIEW id="main"><SubView Left="4"><TEXT value="hello"/></SubView></VIEW>
        </THEME>
        """
        let document = try WMPXMLParser().parse(xml, path: "Theme.wms")
        let theme = try XCTUnwrap(document.roots.first)
        XCTAssertEqual(theme.name, "THEME")
        XCTAssertEqual(theme.attribute("name"), "Synthetic")
        XCTAssertEqual(theme.children.first?.name, "VIEW")
        XCTAssertEqual(theme.children.first?.children.first?.name, "SubView")
        XCTAssertEqual(theme.children.first?.children.first?.attribute("left"), "4")
        XCTAssertEqual(theme.location.path, "Theme.wms")
        XCTAssertGreaterThan(theme.location.line, 0)
        XCTAssertEqual(document.nodeCount, 4)
    }

    func testRejectsMalformedDepthAndNodeLimit() throws {
        XCTAssertEqual(code("<THEME><VIEW></THEME>"), .malformedXML)
        var limits = WMPXMLLimits.production
        limits.maximumNestingDepth = 2
        XCTAssertEqual(code("<THEME><VIEW><TEXT/></VIEW></THEME>", limits: limits), .xmlDepthExceeded)
        limits = .production; limits.maximumNodeCount = 2
        XCTAssertEqual(code("<THEME><VIEW/><VIEW/></THEME>", limits: limits), .expandedNodeLimitExceeded)
    }

    func testDoesNotResolveExternalEntities() {
        let xml = "<!DOCTYPE THEME [<!ENTITY secret SYSTEM \"file:///etc/passwd\">]><THEME value=\"&secret;\"/>"
        XCTAssertEqual(code(xml), .malformedXML)
    }

    func testDecodedUTF16DeclarationDoesNotMakeParserReinterpretUTF8Bytes() throws {
        let source = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><THEME name=\"Café\"/>"
        let decoded = try WMPTextDecoder.decode(
            WMPSkinTestSupport.utf16(source, littleEndian: true), path: "utf16.wms")
        let document = try WMPXMLParser().parse(decoded.string, path: "utf16.wms")
        XCTAssertEqual(document.roots.first?.attribute("name"), "Café")
    }

    private func code(_ xml: String, limits: WMPXMLLimits = .production) -> WMPDiagnosticCode? {
        WMPSkinTestSupport.failureCode { try WMPXMLParser(limits: limits).parse(xml, path: "fixture.wms") }
    }
}
