import XCTest
@testable import NullPlayer

/// **A frame may name Winamp's stock `library.content.group` without defining it (B369).**
/// WinPlain's `ml` window does, and opened as an empty frame; the host now supplies the group the
/// skins that do define it all write: one Media Library component filling it.
final class WinampModernStockLibraryGroupTests: XCTestCase {
    private let location = WalSourceLocation(path: "/Skins/TestSkin/xml/library.xml")

    func testAnUndefinedStockLibraryGroupIsSuppliedWithTheLibraryComponent() {
        let groups = stockGroups(after: [libraryWindow()])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.children.first?.attribute("param"),
                       "guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}")
    }

    func testTheSkinsOwnDefinitionIsKept() {
        let own = WalXMLNode(name: "groupdef", attributes: ["id": "library.content.group"],
                             location: location)
        XCTAssertEqual(stockGroups(after: [own, libraryWindow()]).map { $0 === own }, [true])
    }

    func testNothingIsSuppliedWhenNoWindowNamesTheGroup() {
        XCTAssertTrue(stockGroups(after: []).isEmpty)
    }

    private func libraryWindow() -> WalXMLNode {
        let frame = WalXMLNode(name: "Wasabi:StandardFrame:Status",
                               attributes: ["content": "library.content.group"], location: location)
        let layout = WalXMLNode(name: "layout", attributes: ["id": "normal"], location: location,
                                children: [frame])
        return WalXMLNode(name: "container", attributes: ["id": "ml", "name": "Media Library"],
                          location: location, children: [layout])
    }

    private func stockGroups(after roots: [WalXMLNode]) -> [WalXMLNode] {
        let document = WalExpandedXMLDocument(roots: roots, visitedPaths: [], diagnostics: [])
        let result = WasabiSurfaceSynthesizer.synthesize(
            document: document, inventory: WinampModernSurfaceInventory.build(document: document))
        return result.document.roots.filter {
            $0.name == "groupdef" && $0.attribute("id") == WasabiSurfaceSynthesizer.stockLibraryGroupIdentifier
        }
    }
}
