import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// **W240: a geometry value the grammar cannot read at all was counted as a statement of size, so
/// the node it was on took zero instead of its bitmap's size.**
///
/// This is `WMPEmptyAttributeValueTests`' rule one step further out. W241 said an attribute
/// authored with an *empty* value states nothing; the corpus then said the same is true of a value
/// the static geometry grammar rejects outright. `XBOX`'s `xLogo` is the whole of it:
///
/// ```xml
/// <subview id="xLogo" zIndex="7" backgroundImage="x_logo.jpg"
///          width="jsa:centerBox.width" height="jsa:centerBox.height"
///          horizontalAlignment="center" verticalAlignment="center"/>
/// ```
///
/// where the `<video>` two lines above it in the same container writes `jscript:`. `jsa:` is **6
/// uses across 3 archives, all the Xbox family, all this one node, never in script text** — WMP
/// cannot parse it either and falls back to the ambient default, so the logo draws at
/// `x_logo.jpg`'s own size centred in the video box. Matching the typo would be less faithful, not
/// more, exactly as with `scrollingAmmount`; answering it is not the same as implementing it.
///
/// **The whole corpus is one node.** Re-measured 2026-09-20 over the 185 installed archives
/// (`WMP_RENDER_UNRESOLVED=1`, against a pre-W241 baseline in a worktree): 446 unresolved nodes, 16
/// naming a bitmap, 13 of those naming one that cannot resolve (`res://wmploc` resources, or a file
/// absent from its own archive), and two of the remaining three — `Age_of_Mythology`'s `shutterSub`
/// — clearing their own `backgroundImage` from script in `initShutter()`. The backlog's wider
/// *33 of 458* was a miscount rather than a ceiling: 18 bitmap lines plus 15 `bg=` *empty* lines,
/// read with a pattern that captured the next field when the value was empty.
///
/// **The rule is extents only, and that boundary is load-bearing.** An origin has no
/// content-derived default to fall back to, so an unreadable `left` stays a rejection — which is
/// what keeps `left="JScript:danger();"` out of the scene instead of drawing it at 0.
/// `WMPGeometryTests.testInitialLayoutExpressionsResolveReferencesAliasesForwardReadsAndRejectCode`
/// is the test that caught the first, wider version of this fix, and the last case below is here so
/// that boundary is stated positively too.
final class WMPUnreadableGeometryValueTests: XCTestCase {
    private func load(_ wms: String,
                      _ extra: [WMPTestArchiveEntry] = []) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))] + extra))
    }

    private func build(_ skin: WMPLoadedSkin, _ size: WMPSize) async throws -> WMPScene {
        try await WMPSceneBuilder(loadedSkin: skin, imageStore: WMPImageStore(provider: skin.archive))
            .build(viewID: "main", requestedSize: size, overrides: .empty)
    }

    /// A solid 167x153 bitmap — `XBOX`'s `x_logo.jpg` reduced to its size, which is the only thing
    /// about it the layout reads.
    private func logo() throws -> WMPTestArchiveEntry {
        let rgba = [UInt8](repeating: 0xFF, count: 167 * 153 * 4)
        return WMPTestArchiveEntry("logo.png",
            data: try WMPSkinTestSupport.encodedImage(width: 167, height: 153, rgba: rgba))
    }

    /// `scene.geometries` is keyed by `stableID`, so a node is reached through the graph rather
    /// than by its authored id.
    private func geometry(_ id: String, in scene: WMPScene, of skin: WMPLoadedSkin) -> WMPRect? {
        guard let node = skin.graph.allNodes.first(where: { $0.xmlID == id }) else { return nil }
        return scene.geometries[node.stableID]?.absoluteFrame
    }

    // MARK: - The extent

    /// **`XBOX`'s `xLogo`, reduced to its container and its typo.** The corpus case renders as
    /// `frame=116,81 167x153` inside a `centerBox` of `46,47 307x221`; the arithmetic here is the
    /// same and the centring is what says the node was *placed* rather than merely sized.
    func testAnUnreadableExtentTakesTheArtworksSizeTheWayAnAbsentOneDoes() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="398" height="400">
            <SUBVIEW id="centerBox" left="46" top="47" width="307" height="221">
                <SUBVIEW id="xLogo" width="jsa:centerBox.width" height="jsa:centerBox.height"
                         horizontalAlignment="center" verticalAlignment="center"
                         backgroundImage="logo.png"/>
            </SUBVIEW>
        </VIEW></THEME>
        """, [try logo()])
        let scene = try await build(skin, WMPSize(width: 398, height: 400))

        let frame = try XCTUnwrap(geometry("xLogo", in: scene, of: skin),
            "a value the geometry grammar cannot read states no size; the node is placed, not dropped")
        XCTAssertEqual(frame.width, 167,
            "the artwork's own size answers the dimension the skin never managed to state")
        XCTAssertEqual(frame.height, 153)
        XCTAssertEqual(frame.x, 116, "centred in centerBox: 46 + (307 - 167) / 2")
        XCTAssertEqual(frame.y, 81, "centred in centerBox: 47 + (221 - 153) / 2")
        XCTAssertEqual(scene.unresolved.count, 0,
            "the node resolves, so it must not also be reported as one the scene failed to place")
    }

    /// The same node with **no** `width`/`height` at all must land in exactly the same place. That
    /// equality is the whole claim of the fix, and it is the one an assertion on `167x153` alone
    /// would not make.
    func testAnUnreadableExtentAndAnAbsentExtentProduceTheSameFrame() async throws {
        let markup = { (attributes: String) in """
        <THEME><VIEW id="main" width="398" height="400">
            <SUBVIEW id="centerBox" left="46" top="47" width="307" height="221">
                <SUBVIEW id="xLogo" \(attributes)
                         horizontalAlignment="center" verticalAlignment="center"
                         backgroundImage="logo.png"/>
            </SUBVIEW>
        </VIEW></THEME>
        """ }
        let size = WMPSize(width: 398, height: 400)
        let typoSkin = try await load(
            markup("width=\"jsa:centerBox.width\" height=\"jsa:centerBox.height\""), [try logo()])
        let absentSkin = try await load(markup(""), [try logo()])
        let typo = try await build(typoSkin, size)
        let absent = try await build(absentSkin, size)

        XCTAssertEqual(geometry("xLogo", in: typo, of: typoSkin),
                       geometry("xLogo", in: absent, of: absentSkin),
                       "a value the grammar rejects is not a statement of size")
    }

    /// **An unreadable extent with nothing to fall back to is still unresolved.** The rule hands
    /// the dimension to the ambient default; it does not invent one. This is the half that keeps
    /// the fix from quietly turning starved nodes into 0x0 ones that draw nothing and report
    /// nothing — `STALKER`'s `vidBack` is the corpus's shape of this, and it stays counted.
    func testAnUnreadableExtentWithNoArtworkStaysUnresolved() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="398" height="400">
            <SUBVIEW id="bare" left="10" top="10" width="jsa:main.width" height="jsa:main.height"/>
        </VIEW></THEME>
        """)
        let scene = try await build(skin, WMPSize(width: 398, height: 400))

        XCTAssertNil(geometry("bare", in: scene, of: skin),
                     "no artwork means no ambient size, exactly as in WMP")
        XCTAssertEqual(scene.unresolved.count, 1,
            "and the node is still reported, once, as one the scene could not place")
        XCTAssertTrue(try XCTUnwrap(scene.unresolved.first).authoredValue.contains("missing literal geometry"),
            "recorded by the size guard rather than per attribute, so the report names the node once")
    }

    // MARK: - What the rule must not reach

    /// **A well-formed expression whose references are not known yet stays stated.** This is the
    /// distinction the fix turns on: `jsa:` can never resolve, while `jscript:sibling.width` may be
    /// satisfied by a later script write. Stamping the bitmap's size over the second one is the
    /// regression `WMPSceneBuilder`'s own intrinsic-size comment warns about — `corona`'s compact
    /// view collapses `svVideo` through its timer and the background bitmap kept stamping 241 back
    /// over it, leaving a black panel across the whole window.
    func testAnUnsatisfiedButWellFormedExtentDoesNotTakeTheArtworksSize() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="398" height="400">
            <SUBVIEW id="pending" left="10" top="10"
                     width="jscript:missingSibling.width" height="jscript:missingSibling.height"
                     backgroundImage="logo.png"/>
        </VIEW></THEME>
        """, [try logo()])
        let scene = try await build(skin, WMPSize(width: 398, height: 400))

        XCTAssertNil(geometry("pending", in: scene, of: skin),
            "the skin did state this size; it is the dependency that is missing, and a script may "
            + "still supply it")
        XCTAssertTrue(scene.unresolved.contains { $0.nodeID == "pending" },
                      "so the node is reported unresolved, as it was before")
    }

    /// **An unreadable *origin* is still a rejection.** There is no ambient default to take a
    /// position from, and the engine's refusal to evaluate code in a geometry slot is the reason
    /// this boundary exists rather than a consequence of where it fell.
    func testAnUnreadableOriginIsNotAnsweredByTheArtwork() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="398" height="400">
            <SUBVIEW id="code" left="JScript:danger();" top="0" backgroundImage="logo.png"/>
        </VIEW></THEME>
        """, [try logo()])
        let scene = try await build(skin, WMPSize(width: 398, height: 400))

        XCTAssertNil(geometry("code", in: scene, of: skin),
                     "code in a geometry slot is refused, not defaulted to 0")
        XCTAssertTrue(scene.unresolved.contains { $0.nodeID == "code" },
                      "and it is reported, which is how the refusal is visible at all")
    }
}
