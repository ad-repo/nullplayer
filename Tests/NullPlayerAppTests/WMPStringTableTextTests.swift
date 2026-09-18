import Foundation
import XCTest
@testable import NullPlayer

/// **W68/W111 — a `<TEXT>` that states no text and no box is a string table, not a starved node.**
///
/// The Skins Factory house style declares one `<subview id="locSub">` per view holding a
/// `<text id="locShowPl" toolTip="Show Playlist" />` for every string its script needs, and reads
/// them back as `locShowPl.toolTip`. Nothing can give such a node a size — there is no `value` to
/// measure and no artwork to fall back on — so every one was recorded `unresolved`, which is the
/// numerator `starved.tsv` ranks the whole corpus on.
///
/// That was **733 of the 1,183 unresolved nodes** across the 184-archive sweep, in **87 archives**,
/// and it put two skins at the very top of the ranking that are not starved at all:
/// `Batman Begins/mainView` and `Alienware Invader/mainView` both scored 0.90 and both draw their
/// whole player once their intro animation has run — Batman's is 154 frames off its own timer, and
/// `WMP_RENDER_SETTLE=160` takes it from `2 nodes, 0 commands` to `40 nodes, 29 commands, 27 hits`.
/// Ranking a phantom is the defect `isNonLayout` was written for; this is the same rule for a third
/// kind of node that was never a box.
///
/// Corpus effect, measured as a `wmp_skin_census.sh` pair over 184 archives at rev `bc1b777f`:
/// unresolved nodes **1,181 → 456**, the `text` class **786 → 61**, `starved(>=50%)` **14 views /
/// 14 skins → 2 / 2**, and **no other tag moved by a single node**. 553 of 553 rendered views are
/// byte-identical; the one exception is `Scooby-Doo_2/infoView`, which picks its character at
/// random and differs between two runs of the same binary.
///
/// The three guards below are what keeps the rule from swallowing a node that really is starved,
/// and each is a population in the corpus rather than a hypothetical.
final class WMPStringTableTextTests: XCTestCase {

    private func load(wms: String) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]))
    }

    private func scene(_ wms: String) async throws -> WMPScene {
        try await WMPSceneBuilder(loadedSkin: try await load(wms: wms)).build(viewID: "main")
    }

    private func unresolvedIDs(_ scene: WMPScene) -> Set<String> {
        Set(scene.unresolved.compactMap(\.nodeID))
    }

    // MARK: - The rule

    /// `Batman Begins`'s `locSub`, to scale. Seventeen of these are why that skin ranked first.
    func testAStringTableTextIsNotCountedAsStarved() async throws {
        let scene = try await scene("""
        <THEME><VIEW id="main" width="40" height="40">
            <SUBVIEW id="locSub">
                <TEXT id="locShowPl" toolTip="Show Playlist"/>
                <TEXT id="timeElapsed" toolTip="Click to show remaining time"/>
            </SUBVIEW>
        </VIEW></THEME>
        """)

        XCTAssertEqual(unresolvedIDs(scene).intersection(["locShowPl", "timeElapsed"]), [],
                       "a text node with no value and no box was never going to draw a pixel")
    }

    /// The node still exists in the graph, because the whole point of the idiom is that the script
    /// reads an attribute off it. Not counting it as starved must not make it unreachable.
    func testTheStringTableIsStillReadableByScript() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="40" height="40">
            <SUBVIEW id="locSub"><TEXT id="timeElapsed" toolTip="Click to show remaining time"/></SUBVIEW>
        </VIEW></THEME>
        """)
        let node = skin.graph.allNodes.first { $0.xmlID?.lowercased() == "timeelapsed" }

        XCTAssertEqual(try XCTUnwrap(node).attribute(named: "toolTip")?.rawValue,
                       "Click to show remaining time",
                       "the string table is the node's attributes; the geometry was never the point")
    }

    // MARK: - The guards

    /// **A placeholder the script fills is not a string table.** `Batman Begins`'s own `metadata`
    /// is `<TEXT id="metadata" left="127" top="200" width="87" height="30"/>` — empty at load and
    /// written by `updateMetadata()`. It authors a box, so it resolves and is not in this class at
    /// all; a rule keyed on "text with no value" rather than on "text with no value *and* no box"
    /// would have dropped every one of them.
    func testATextWithAnAuthoredBoxStillResolves() async throws {
        let scene = try await scene("""
        <THEME><VIEW id="main" width="40" height="40">
            <TEXT id="metadata" left="12" top="20" width="20" height="8"/>
        </VIEW></THEME>
        """)

        XCTAssertEqual(unresolvedIDs(scene).intersection(["metadata"]), [],
                       "an authored box resolves on its own")
        XCTAssertTrue(scene.geometries.values.contains { $0.localFrame.width == 20 },
                      "and it is a real 20x8 box, not a node the rule quietly skipped")
    }

    /// **A `value` the markup binds rather than states is still text.** `literalString` answers nil
    /// for a `wmpprop:`/`jscript:` attribute exactly as it does for an absent one, so the raw
    /// attribute has to be tested too — otherwise a bound readout with no authored size would be
    /// classified as a string table and stop being reported.
    func testABoundValueIsNotAStringTable() async throws {
        let scene = try await scene("""
        <THEME><VIEW id="main" width="40" height="40">
            <TEXT id="bound" value="wmpprop:player.currentMedia.name"/>
        </VIEW></THEME>
        """)

        XCTAssertTrue(unresolvedIDs(scene).contains("bound"),
                      "a node with text it cannot measure yet is genuinely unresolved")
    }

    /// **Only `.text` qualifies.** `<STATUSTEXT>`, `<CURRENTPOSITIONTEXT>` and `<DURATIONTEXT>`
    /// take their content from the player rather than from an attribute, so one with no box has
    /// nowhere to draw and is a real starved node — 7 `statusText` in the corpus sweep, all of
    /// which stayed counted across this change.
    func testAStatusTextWithNoBoxIsStillStarved() async throws {
        let scene = try await scene("""
        <THEME><VIEW id="main" width="40" height="40">
            <STATUSTEXT id="status"/>
        </VIEW></THEME>
        """)

        XCTAssertTrue(unresolvedIDs(scene).contains("status"),
                      "the player fills it, so an unsized one has nowhere to put the text")
    }
}
