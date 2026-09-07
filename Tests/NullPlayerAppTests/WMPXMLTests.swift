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

    /// The four archives that made this parser necessary — Alpine7618_v09, anemone,
    /// Official_Xbox_XP and The Unit — each repeat an attribute on a tag, and libxml2 aborted the
    /// whole document on it (`NSXMLParserErrorDomain 111`) before any delegate ran. Collapsing
    /// last-wins with a warning is what took the corpus from 10/14 to 14/14.
    func testDuplicateAttributeCollapsesLastWinsWithAWarningInsteadOfFailing() throws {
        let document = try WMPXMLParser().parse(
            #"<THEME><SLIDER min="-127" direction="vertical" min="7"/></THEME>"#, path: "dup.wms")
        let slider = try XCTUnwrap(document.roots.first?.children.first)
        XCTAssertEqual(slider.attribute("min"), "7")
        XCTAssertEqual(slider.attributes.map(\.name), ["min", "direction"],
                       "the surviving value keeps the slot the first spelling claimed")
        let warning = try XCTUnwrap(document.diagnostics.first)
        XCTAssertEqual(warning.code, .duplicateAttribute)
        XCTAssertEqual(warning.severity, .warning)
        XCTAssertTrue(warning.message.contains("\"-127\""),
                      "the discarded value is named so a case where they differ is visible")
    }

    /// Alphabetising these is not cosmetic. The `.wal` engine sorted them once, which put `id` at
    /// position 4 of 10, silently dropped four style properties and mislaid cPro2's clock.
    func testAttributesKeepDocumentOrderAndAuthoredSpelling() throws {
        let document = try WMPXMLParser().parse(
            ##"<VIEW zIndex="2" id="main" Left="4" backgroundColor="#FF0000"/>"##, path: "order.wms")
        let view = try XCTUnwrap(document.roots.first)
        XCTAssertEqual(view.attributes.map(\.name), ["zIndex", "id", "Left", "backgroundColor"])
    }

    /// WMP loads a file that ends before it closes what it opened; the tree is already complete
    /// because a node is attached when it *opens*. Degrade with a diagnostic, never fail the skin.
    func testUnclosedTagAtEndOfFileIsAWarningAndKeepsItsChildren() throws {
        let document = try WMPXMLParser().parse("<THEME><VIEW><TEXT value=\"hi\"/>", path: "open.wms")
        let theme = try XCTUnwrap(document.roots.first)
        XCTAssertEqual(theme.children.first?.children.first?.attribute("value"), "hi")
        XCTAssertEqual(document.diagnostics.map(\.code), [.unclosedTag])
    }

    func testUnescapesNamedAndNumericEntitiesAndKeepsUnknownOnesVerbatim() throws {
        let document = try WMPXMLParser().parse(
            #"<TEXT a="1 &lt; 2 &amp;&amp; 3" b="&#67;af&#xe9;" c="a &bogus; b"/>"#, path: "e.wms")
        let text = try XCTUnwrap(document.roots.first)
        XCTAssertEqual(text.attribute("a"), "1 < 2 && 3")
        XCTAssertEqual(text.attribute("b"), "Café")
        XCTAssertEqual(text.attribute("c"), "a &bogus; b")
    }

    /// A `JScript:` geometry expression routinely contains `>` and `<`, and 13 of 14 corpus skins lay
    /// themselves out with these. Stopping the tag at the first unquoted `>` is the only reading that
    /// keeps them intact.
    func testAngleBracketsInsideAQuotedValueDoNotEndTheTag() throws {
        let document = try WMPXMLParser().parse(
            #"<SUBVIEW left="jscript:(view.width > 320) ? 8 : 0;" top="4"/>"#, path: "expr.wms")
        let subview = try XCTUnwrap(document.roots.first)
        XCTAssertEqual(subview.attribute("left"), "jscript:(view.width > 320) ? 8 : 0;")
        XCTAssertEqual(subview.attribute("top"), "4")
    }

    private func code(_ xml: String, limits: WMPXMLLimits = .production) -> WMPDiagnosticCode? {
        WMPSkinTestSupport.failureCode { try WMPXMLParser(limits: limits).parse(xml, path: "fixture.wms") }
    }
}
