import XCTest
@testable import NullPlayer

/// W193 — `view.size(corner)`, the only resize a borderless `.wmz` window has.
///
/// The gesture itself is a window drag and cannot be measured without one; what is pinned here is
/// the mapping every one of the corpus's 235 calls goes through, and the axis convention it has to
/// agree with. `WMPMainView.edges(at:)` reads the view's *flipped* y — a point at the visual bottom
/// inserts `.bottom` — and `dragWindowResize` moves the window origin for `.left` and `.bottom`, so
/// a skin's `bottomright` has to mean the visually-bottom-right corner and not the screen's.
final class WMPScriptResizeTests: XCTestCase {

    /// Every spelling the 88 archives author, with its count in the installed corpus.
    func testEveryAuthoredCornerResolvesToItsOwnEdges() {
        let cases: [(String, WMPWindowEdges)] = [
            ("bottomright", [.bottom, .right]),   // 86 archives
            ("topright", [.top, .right]),         // 4
            ("right", [.right]),                  // 3
            ("bottom", [.bottom]),                // 2
            ("bottomleft", [.bottom, .left]),     // 2
            ("left", [.left]),                    // 2
            ("topleft", [.top, .left]),           // 2
        ]
        for (corner, expected) in cases {
            XCTAssertEqual(WMPMainView.edges(forCorner: corner), expected, "corner \(corner)")
        }
    }

    /// `Compact` writes `view.size( 'bottomright' )` and `Revert` `view.size("TopLeft")`: the
    /// argument is a string literal a skin author typed, so case and stray space are not signals.
    func testCornerMatchingIgnoresCaseAndSurroundingSpace() {
        XCTAssertEqual(WMPMainView.edges(forCorner: "BottomRight"), [.bottom, .right])
        XCTAssertEqual(WMPMainView.edges(forCorner: " TopLeft "), [.top, .left])
    }

    /// An empty or unrecognised corner arms nothing. `beginScriptResize` refuses on an empty set
    /// rather than falling back to a default edge: a drag the skin did not ask for is worse than
    /// the dead call this row replaced.
    func testAnUnknownCornerArmsNoEdge() {
        for corner in ["", "middle", "centre", "sizenwse"] {
            XCTAssertTrue(WMPMainView.edges(forCorner: corner).isEmpty, "corner \(corner)")
        }
    }

    // MARK: W227 — naming the grip the window edge should raise

    private func loadSkin(wms: String) async throws -> WMPLoadedSkin {
        let entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    /// **The shape 233 of the corpus's 234 calls are spelled in**: straight into the handler
    /// attribute, alongside whatever the skin does after the call.
    func testAGripSpelledIntoTheHandlerAttributeIsFound() async throws {
        let skin = try await loadSkin(wms: """
        <THEME><VIEW id="main" width="320" height="240">
            <BUTTON id="size" left="300" top="220" image="g.bmp"
                    onMouseDown="view.size( 'bottomright' );saveVidSize()"/>
        </VIEW></THEME>
        """)
        let grips = WMPResizeGrip.grips(in: skin.views[0].node, scriptSources: [:])
        XCTAssertEqual(grips.count, 1)
        XCTAssertEqual(grips.first?.nodeID, "size")
        XCTAssertEqual(grips.first?.corner, "bottomright")
    }

    /// **The one that is not, and it is the archive the whole bracket exists for.** `Compact` writes
    /// `onMouseDown="DoSize()"` with the call inside a function in `compact.js`, so a literal-only
    /// match finds every grip in the corpus except the only one whose tail does more than save a
    /// preference. One hop resolves it; deeper than one hop is authored nowhere.
    func testAGripReachedThroughAFunctionIsFound() async throws {
        let skin = try await loadSkin(wms: """
        <THEME><VIEW id="main" width="320" height="240">
            <BUTTON id="size" left="300" top="220" image="g.bmp" onMouseDown="DoSize();"/>
        </VIEW></THEME>
        """)
        let scripts = ["compact.js": """
        function DoSize()
        {
            if (movingDrawer == 0)
            {
                settingsDrawer.verticalAlignment = "bottom";
                view.size( 'bottomright' );
                settingsDrawer.verticalAlignment = "top";
            }
        }
        """]
        let grips = WMPResizeGrip.grips(in: skin.views[0].node, scriptSources: scripts)
        XCTAssertEqual(grips.first?.nodeID, "size")
        XCTAssertEqual(grips.first?.corner, "bottomright")
    }

    /// A control that moves or plays something is not a grip, however it is drawn. The edge band
    /// raises a grip's handler, so naming the wrong node would fire a skin's transport on a resize.
    func testAnOrdinaryControlIsNotAGrip() async throws {
        let skin = try await loadSkin(wms: """
        <THEME><VIEW id="main" width="320" height="240">
            <BUTTON id="play" left="10" top="10" image="p.bmp" onClick="player.controls.play();"/>
            <BUTTON id="mover" left="20" top="10" image="m.bmp" onMouseDown="view.dragMove();"/>
        </VIEW></THEME>
        """)
        XCTAssertTrue(WMPResizeGrip.grips(in: skin.views[0].node, scriptSources: [:]).isEmpty)
    }

}
