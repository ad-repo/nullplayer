import XCTest
@testable import NullPlayer

/// B116 — `inherit_group` used to **append** the base's template children to the derived group's, so
/// a derived group that redeclared one of them got both.
///
/// Found by inspection while investigating WMP11-BlueVU (2026-09-04). That skin's
/// `<groupdef id="wasabi.standardframe.my" inherit_group="wasabi.standardframe.nostatusbar">`
/// redeclares `wasabi.frame.layout` at `h="-69"` to leave room for its 69px panel, where the base
/// declares `h="-12"`. `RENDER_PROBE main/normal` showed **both** — 354x135 and 354x78 — each
/// dragging a duplicate `frame.top.middle` subtree (edge strips, titlebar, caption buttons) drawn
/// every frame. The duplicates landed mostly on top of each other, so it read as wasted draw work
/// rather than a visible defect.
///
/// The rule is the one the attribute merge beside it already followed: the derived group wins. A
/// derived child with an inherited `id` **replaces** that child, and a base child the derived group
/// does not redeclare still draws — WMP11 never redeclares `frame.bottom`, and its bottom border is
/// meant to stay. Getting that second half wrong removes a border, which is just as subtle on screen
/// as doubling one.
final class WinampModernB116Tests: XCTestCase {

    /// The defect in one assertion: one `frame.layout`, at the derived height.
    func testADerivedChildReplacesTheInheritedChildOfTheSameID() throws {
        let frame = try instantiateDerivedFrame()
        let layouts = frame.children.filter { $0.xmlID == "frame.layout" }
        XCTAssertEqual(layouts.count, 1, "the redeclared child replaces the inherited one")
        XCTAssertEqual(layouts.first?.attributes["h"], "-69", "and it is the derived group's version")
    }

    /// The load-bearing half: a base child the derived group is silent about still draws.
    func testAnInheritedChildTheDerivedGroupDoesNotRedeclareSurvives() throws {
        let frame = try instantiateDerivedFrame()
        XCTAssertEqual(frame.children.filter { $0.xmlID == "frame.bottom" }.count, 1,
                       "WMP11 does not redeclare its bottom border, and it is meant to stay")
    }

    /// A replacement keeps the **base's** slot, so the layering the base composed is preserved: the
    /// derived `frame.layout` still draws between the border above it and the one below.
    func testAReplacementKeepsTheInheritedDrawOrder() throws {
        let frame = try instantiateDerivedFrame()
        XCTAssertEqual(frame.children.compactMap(\.xmlID),
                       ["frame.top", "frame.layout", "frame.bottom", "my.panel"])
    }

    // MARK: - Helpers

    /// WMP11-BlueVU's shape, reduced: a base frame of three children, a derived frame that
    /// redeclares the middle one and adds a panel of its own.
    private func instantiateDerivedFrame() throws -> WasabiObject {
        let xml = """
        <WasabiXML>
          <elements>
            <groupdef id="base.frame">
              <layer id="frame.top" h="12"/>
              <group id="frame.layout" relatw="1" relath="1" h="-12"/>
              <layer id="frame.bottom" h="12" relaty="1" y="-12"/>
            </groupdef>
            <groupdef id="derived.frame" inherit_group="base.frame">
              <group id="frame.layout" relatw="1" relath="1" h="-69"/>
              <layer id="my.panel" h="69" relaty="1" y="-69"/>
            </groupdef>
          </elements>
          <container id="main">
            <layout id="normal" w="354" h="147"><group id="derived.frame"/></layout>
          </container>
        </WasabiXML>
        """
        let provider = try WalMemoryResourceProvider(resources: ["skin.xml": Data(xml.utf8)])
        let vfs = try WalVirtualFileSystem(skinName: "Synthetic", skin: provider)
        let document = try WalXMLDocumentLoader(vfs: vfs).load(entryPath: "/Skins/Synthetic/skin.xml")
        let runtime = try WasabiSkinInitializer(vfs: vfs).initialize(document: document)
        return try XCTUnwrap(runtime.graph.objects(xmlID: "derived.frame").first)
    }
}
