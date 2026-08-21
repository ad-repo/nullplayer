import XCTest
@testable import NullPlayer

/// Phase 50 (B29) — a re-include of an identical definition is not a redefinition.
///
/// A skin that shares an elements file between two containers includes it twice, which is ordinary
/// Winamp practice: LOBE includes `player-elements.xml` from both `player.xml` and `eq.xml`, and
/// `components-elements.xml` from both `about.xml` and `components.xml`. Every resource and
/// `<groupdef>` in those files was therefore registered twice and warned about twice — **198 of the
/// skin's 233 findings**, which is what pushed its compatibility level to `degraded` and made the
/// level say nothing at all about the skin.
///
/// The warning now fires on what the definition *is*, not on how many times it was read. Corpus
/// delta over the 30 loadable installed skins: **1343 → 851 diagnostic occurrences**, LOBE 233 → 38
/// findings, with every differing redefinition still reported (cPro-Bento keeps 34, Styx 15).
final class WinampModernPhase50Tests: XCTestCase {

    // MARK: - Resources

    func testTheSameResourceReadTwiceIsSilent() {
        let registry = WalResourceRegistry()
        registry.register(bitmap(id: "player.bg", file: "player/bg.png", from: "/player.xml"))
        registry.register(bitmap(id: "player.bg", file: "player/bg.png", from: "/eq.xml"))
        XCTAssertTrue(registry.diagnostics.isEmpty)
        XCTAssertEqual(registry.definition(identifier: "player.bg")?.logicalFile, "player/bg.png")
    }

    func testADifferentResourceUnderTheSameIdStillWarns() {
        let registry = WalResourceRegistry()
        registry.register(bitmap(id: "player.bg", file: "player/bg.png", from: "/player.xml"))
        registry.register(bitmap(id: "player.bg", file: "player/other.png", from: "/eq.xml"))
        XCTAssertEqual(registry.diagnostics.count, 1)
        XCTAssertEqual(registry.diagnostics.first?.code, .duplicateIdentifier)
        XCTAssertEqual(registry.definition(identifier: "player.bg")?.logicalFile, "player/other.png",
                       "the later definition still wins — only the warning changed")
    }

    /// Same file, different framing: a `<bitmap>` whose region moved is a real redefinition.
    func testAChangedAttributeIsADifference() {
        let registry = WalResourceRegistry()
        registry.register(bitmap(id: "b", file: "a.png", from: "/one.xml", extra: ["x": "0"]))
        registry.register(bitmap(id: "b", file: "a.png", from: "/two.xml", extra: ["x": "4"]))
        XCTAssertEqual(registry.diagnostics.count, 1)
    }

    // MARK: - Group definitions

    func testTheSameGroupdefReadTwiceIsSilent() {
        let registry = WasabiTypeRegistry()
        registry.register(group(from: "/player.xml"))
        registry.register(group(from: "/eq.xml"))
        XCTAssertTrue(registry.diagnostics.isEmpty)
    }

    func testAGroupdefWhoseTemplateChangedStillWarns() {
        let registry = WasabiTypeRegistry()
        registry.register(group(from: "/player.xml"))
        registry.register(group(from: "/eq.xml", childAttributes: ["x": "10"]))
        XCTAssertEqual(registry.diagnostics.count, 1)
        XCTAssertEqual(registry.diagnostics.first?.code, .duplicateIdentifier)
    }

    func testAGroupdefWithADifferentXUITagStillWarns() {
        let registry = WasabiTypeRegistry()
        registry.register(group(from: "/player.xml", xuiTag: "Skin:Thing"))
        registry.register(group(from: "/eq.xml", xuiTag: "Skin:Other"))
        // The redefinition itself, and the tag moving off the first definition's own tag.
        XCTAssertEqual(registry.diagnostics.count, 1)
    }

    /// The XUI-tag warning is about a tag moving between *groups*; re-reading one group keeps its own
    /// tag, and saying it was "reassigned from itself" is noise.
    func testATagIsNotReassignedToTheGroupThatAlreadyHasIt() {
        let registry = WasabiTypeRegistry()
        registry.register(group(from: "/player.xml", xuiTag: "Skin:Thing"))
        registry.register(group(from: "/eq.xml", xuiTag: "Skin:Thing"))
        XCTAssertTrue(registry.diagnostics.isEmpty)
    }

    // MARK: - The comparison itself

    func testStructuralEqualityIgnoresWhereANodeWasRead() {
        let a = node("group", ["id": "x"], from: "/one.xml", children: [node("layer", ["id": "l"])])
        let b = node("group", ["id": "x"], from: "/two.xml", children: [node("layer", ["id": "l"])])
        let c = node("group", ["id": "x"], from: "/two.xml", children: [node("layer", ["id": "m"])])
        let d = node("group", ["id": "x"], from: "/two.xml")
        XCTAssertTrue(a.isStructurallyEqual(to: b))
        XCTAssertFalse(a.isStructurallyEqual(to: c))
        XCTAssertFalse(a.isStructurallyEqual(to: d), "a missing child is a difference")
    }

    // MARK: - Fixture

    private func bitmap(id: String, file: String, from path: String,
                        extra: [String: String] = [:]) -> WalResourceDefinition {
        WalResourceDefinition(kind: "bitmap", identifier: id, logicalFile: file,
                              attributes: ["id": id, "file": file].merging(extra) { _, new in new },
                              source: WalSourceLocation(path: path))
    }

    private func group(from path: String, xuiTag: String? = nil,
                       childAttributes: [String: String] = ["x": "0"]) -> WasabiGroupDefinition {
        WasabiGroupDefinition(identifier: "player.body", xuiTag: xuiTag, inheritedGroup: nil,
                              embeddedXUITag: nil, defaultAttributes: ["w": "300"],
                              templateChildren: [node("layer", childAttributes, from: path)],
                              source: WalSourceLocation(path: path))
    }

    private func node(_ name: String, _ attributes: [String: String],
                      from path: String = "/x.xml", children: [WalXMLNode] = []) -> WalXMLNode {
        WalXMLNode(name: name, attributes: attributes,
                   location: WalSourceLocation(path: path), children: children)
    }
}
