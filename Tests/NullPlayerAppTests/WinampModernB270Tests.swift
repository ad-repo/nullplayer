import XCTest
@testable import NullPlayer

/// B270 — a `<container>` re-declared inside itself. Official_Zwan_Skin's `player.xml` opens
/// `<container id="main">` around an include that declares `main` again around its only player
/// layouts; the outer container kept no layout and the skin had no player window.
final class WinampModernB270Tests: XCTestCase {

    func testANestedSameIDContainerContributesItsLayoutsToTheOuterOne() throws {
        let player = """
        <container id="main" name="Main Window">
          <include file="player-normal.xml"/>
        </container>
        <container id="pl"><container id="other"><layout id="x"/></container></container>
        """
        let normal = """
        <container id="MAIN" name="Inner">
          <layout id="normal"/><layout id="shade"/>
        </container>
        """
        let provider = try WalMemoryResourceProvider(resources: [
            "skin.xml": Data(player.utf8), "player-normal.xml": Data(normal.utf8),
        ])
        let vfs = try WalVirtualFileSystem(skinName: "Synthetic", skin: provider)
        let roots = try WalXMLDocumentLoader(vfs: vfs).load(entryPath: "/Skins/Synthetic/skin.xml").roots

        let main = try XCTUnwrap(roots.first)
        XCTAssertEqual(main.children.map { $0.attribute("id") }, ["normal", "shade"])
        XCTAssertEqual(main.attribute("name"), "Main Window", "the outer container's attributes stand")
        XCTAssertEqual(roots[1].children.first?.attribute("id"), "other",
                       "a nested container with another id is left alone")
    }
}
