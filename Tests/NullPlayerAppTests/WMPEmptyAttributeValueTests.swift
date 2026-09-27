import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **W241: an attribute authored with an empty value was dropped, and it was taking whole control
/// groups with it.**
///
/// `<attr>=""` is authored **970 times across 135 of the 182 measured archives** (decoder-faithful
/// scan, 2026-09-20; reconciled against `scripts/wmp_markup_census.sh`'s flat files, both sides
/// 970/135). Almost none of that is a defect — `tooltip=""` (299 uses) and `value=""` (101) are
/// authored absences whose outcome was already right, and the resource path has implemented this
/// rule for itself since `WMPArchive.resolve` started returning nil for an empty path.
///
/// **The geometry share was the whole of it.** Every "did the skin state this dimension?" test in
/// `WMPSceneBuilder` is `attribute(named:) == nil`, so a *present-but-empty* `height` closed the
/// intrinsic-size gate that an *absent* `height` opens: the node resolved no size, was recorded
/// unresolved, and was never painted. `Beck` is the case that made it legible — `eq1`…`eq10` each
/// author `left`, `top`, `height=""` and no `width` at all, over a real `foregroundImage` — and its
/// equalizer tray drew ten empty slots. `Beck/view-2` went 12 unresolved to 1.
///
/// **The fix is not a coercion of `""` to zero**, which the backlog row ruled out before the work
/// started and which would be exactly as invisible as the unresolved node it replaced. It says the
/// dimension was never stated, so the ambient default answers it — 0 for an origin, the artwork's
/// own size for an extent. `WMPNode.statedAttribute(named:)` is the seam, and the tests below are
/// written against the *distinction* rather than against the accessor, because the defect was never
/// that `""` parsed wrong: it parsed fine and then counted as a statement.
final class WMPEmptyAttributeValueTests: XCTestCase {
    private func load(_ wms: String,
                      _ extra: [WMPTestArchiveEntry] = []) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))] + extra))
    }

    private func build(_ skin: WMPLoadedSkin, _ size: WMPSize) async throws -> WMPScene {
        try await WMPSceneBuilder(loadedSkin: skin, imageStore: WMPImageStore(provider: skin.archive))
            .build(viewID: "main", requestedSize: size, overrides: .empty)
    }

    /// A solid 10x134 bitmap — `Beck`'s `eqbck.gif` reduced to its size, which is the only thing
    /// about it the layout reads.
    private func track() throws -> WMPTestArchiveEntry {
        let rgba = [UInt8](repeating: 0xFF, count: 10 * 134 * 4)
        return WMPTestArchiveEntry("track.png",
            data: try WMPSkinTestSupport.encodedImage(width: 10, height: 134, rgba: rgba))
    }

    private func widget(_ id: String, in scene: WMPScene) -> WMPRect? {
        scene.widgets.first { $0.nodeID == id }?.frame
    }

    /// `scene.geometries` is keyed by `stableID`, so a node is reached through the graph rather
    /// than by its authored id.
    private func geometry(_ id: String, in scene: WMPScene, of skin: WMPLoadedSkin) -> WMPRect? {
        guard let node = skin.graph.allNodes.first(where: { $0.xmlID == id }) else { return nil }
        return scene.geometries[node.stableID]?.absoluteFrame
    }

    // MARK: - The extent

    /// **`Beck`'s equalizer, reduced to two bands.** Both author `height=""` and no `width`, and
    /// both have a bitmap that states the size. Before the fix neither resolved and the tray drew
    /// empty slots; the pitch assertion is what says they are a *row* rather than a stack.
    func testAnEmptyHeightTakesTheArtworksSizeTheWayAnAbsentOneDoes() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <SLIDER id="eq1" left="19" top="42" height="" foregroundImage="track.png"/>
            <SLIDER id="eq2" left="41" top="42" height="" foregroundImage="track.png"/>
        </VIEW></THEME>
        """, [try track()])
        let scene = try await build(skin, WMPSize(width: 300, height: 200))

        let first = try XCTUnwrap(widget("eq1", in: scene),
            "an empty height is an unstated height; the band is placed, not dropped")
        let second = try XCTUnwrap(widget("eq2", in: scene))
        XCTAssertEqual(first.height, 134,
            "the artwork's own height answers the dimension the skin never stated — 0 would be as "
            + "invisible as the unresolved node it replaced")
        XCTAssertEqual(first.width, 10, "width was absent outright and has always been answered")
        XCTAssertEqual(first.x, 19, "the authored origin is untouched")
        XCTAssertEqual(second.x - first.x, 22, "adjacent bands keep the authored pitch")
        XCTAssertEqual(scene.unresolved.count, 0, "neither band is recorded unresolved any more")
    }

    /// The same node with **no** `height` attribute at all must land in exactly the same place.
    /// That equality is the whole claim of the fix, and it is the one an assertion on `134` alone
    /// would not make.
    func testAnEmptyExtentAndAnAbsentExtentProduceTheSameFrame() async throws {
        let markup = { (attribute: String) in """
        <THEME><VIEW id="main" width="300" height="200">
            <SLIDER id="band" left="19" top="42" \(attribute) foregroundImage="track.png"/>
        </VIEW></THEME>
        """ }
        let empty = try await build(try await load(markup("height=\"\""), [try track()]),
                                    WMPSize(width: 300, height: 200))
        let absent = try await build(try await load(markup(""), [try track()]),
                                     WMPSize(width: 300, height: 200))

        XCTAssertEqual(widget("band", in: empty), widget("band", in: absent),
                       "an attribute authored with an empty value is not an attribute")
    }

    /// **A whitespace-only value is the same authoring.** The corpus scan counted `=""` exactly,
    /// so this case is untested by the number that ranked the row — it is here because the seam
    /// trims, and a rule that treated `" "` as a statement would be a second empty-value class.
    func testAWhitespaceOnlyExtentIsAlsoUnstated() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <SLIDER id="band" left="19" top="42" height="   " foregroundImage="track.png"/>
        </VIEW></THEME>
        """, [try track()])
        let scene = try await build(skin, WMPSize(width: 300, height: 200))

        XCTAssertEqual(try XCTUnwrap(widget("band", in: scene)).height, 134)
    }

    // MARK: - The origin

    /// **`WWC`'s `introAnim`**, which authors `left="207" top=""` over a background image and was
    /// the second archive the corpus sweep moved. An origin defaults to 0 when unauthored, so the
    /// empty one must default too — the node had never drawn at all, and with it the skin's whole
    /// intro animation.
    func testAnEmptyOriginFallsToZeroTheWayAnAbsentOneDoes() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <SUBVIEW id="introAnim" left="207" top="" backgroundImage="track.png"/>
        </VIEW></THEME>
        """, [try track()])
        let scene = try await build(skin, WMPSize(width: 300, height: 200))

        let frame = try XCTUnwrap(geometry("introAnim", in: scene, of: skin),
            "the subview is placed rather than dropped")
        XCTAssertEqual(frame.y, 0, "an unstated origin is 0, which is what WMP does")
        XCTAssertEqual(frame.x, 207, "the authored half is unchanged")
    }

    // MARK: - What the rule must not reach

    /// **The rule is deliberately geometry-only.** `tooltip=""` is 299 of the corpus's 970 empty
    /// values and `value=""` is 101, and both are authored absences that already behaved
    /// correctly — a node carrying one must be unchanged by this fix, or the row's 970 becomes the
    /// blast radius instead of its denominator.
    func testAnEmptyStringAttributeIsStillAnEmptyString() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <TEXT id="label" left="4" top="4" width="80" height="12" value="" tooltip=""/>
        </VIEW></THEME>
        """)
        let node = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "label" })

        XCTAssertNotNil(node.attribute(named: "value"),
            "the attribute is still in the graph; only the geometry gates ask the other question")
        XCTAssertNotNil(node.attribute(named: "tooltip"))
        XCTAssertNil(node.statedAttribute(named: "value"),
            "the accessor answers the statedness question for anyone who asks it")
    }

    /// An **authored zero** is a statement and must keep outranking the artwork. This is the
    /// failure mode a coercion of `""` to zero would have hidden in reverse: if `0` and `""` are
    /// the same value, then a skin that deliberately collapses a pane gets its bitmap stamped back
    /// over it — the `corona` compact-view case `WMPSceneBuilder` already carries a comment for.
    func testAnAuthoredZeroIsStillAStatementAndStillBeatsTheArtwork() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <SUBVIEW id="pane" left="0" top="0" width="10" height="0" backgroundImage="track.png"/>
        </VIEW></THEME>
        """, [try track()])
        let scene = try await build(skin, WMPSize(width: 300, height: 200))

        let frame = try XCTUnwrap(geometry("pane", in: scene, of: skin))
        XCTAssertEqual(frame.height, 0,
            "height=\"0\" is an answer the skin computed; the bitmap's 134 must not replace it")
    }

    /// A **malformed** value is not an empty one and must still be reported. `height="abc"` states
    /// something the engine cannot resolve, and quietly answering it with the artwork would turn
    /// every authoring error into a silent guess.
    func testAnUnresolvableExtentIsStillRecordedUnresolved() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="300" height="200">
            <SUBVIEW id="pane" left="0" top="0" height="abc" backgroundImage="track.png"/>
        </VIEW></THEME>
        """, [try track()])
        let scene = try await build(skin, WMPSize(width: 300, height: 200))

        XCTAssertTrue(scene.unresolved.contains { $0.nodeID == "pane" },
            "a value the engine cannot read is a finding, not an absence")
    }
}
