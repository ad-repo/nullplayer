import XCTest
@testable import NullPlayer

/// Phase 60 — BB9's holder routing and BB21's splitter, the two decisions that can be measured
/// without a window.
///
/// Both were reported as "the skin does X" and were in fact policy of ours:
///
/// - `{0000000A-000C-0010-FF7B-01014263450C}` is Winamp's visualization **plugin host**, whose
///   default content is Winamp's own spectrum analyzer. We mounted the host's engine over every such
///   holder unconditionally, so an analyzer in that slot was unreachable by construction.
/// - A splitter claimed a press only when nothing interactive sat under it. Big Bento Modern covers
///   every pixel of its window with an alpha-0 `move="1"` layer, so its divider never claimed one —
///   the cursor promised a resize and the press dragged the window.
///
/// The rest of both fixes lives in the view layer and the renderer's draw path, which need a window
/// and real artwork; what is asserted here is the decision each of them turns on.
final class WinampModernPhase60Tests: XCTestCase {

    // MARK: - BB9: which holder gets the engine

    private func holder(_ id: String, _ frame: CGRect,
                        graph: WasabiObjectGraph) -> WinampModernComponentHolder {
        let object = graph.makeObject(typeName: "component", attributes: ["id": id],
                                      source: WalSourceLocation(path: "/test.xml"))
        return WinampModernComponentHolder(object: object,
                                           surfaceID: .component(.visualization), frame: frame)
    }

    /// A letterbox strip is an analyzer's shape, and never takes the engine. The three placements
    /// Big Bento declares measure 7.3, 1.0 and about 2.5, so the 3:1 boundary separates exactly the
    /// one the user sees an analyzer in from the two they do not.
    func testLetterboxHolderPrefersTheAnalyzer() {
        // The stretched pane: 1074 × 147.
        XCTAssertTrue(WinampModernVisualizationHolder.prefersAnalyzer(
            frame: CGRect(x: 0, y: 0, width: 1074, height: 147)))
        // The mini pane: 186 × 185.
        XCTAssertFalse(WinampModernVisualizationHolder.prefersAnalyzer(
            frame: CGRect(x: 0, y: 0, width: 186, height: 185)))
        // The Visualization tab.
        XCTAssertFalse(WinampModernVisualizationHolder.prefersAnalyzer(
            frame: CGRect(x: 0, y: 0, width: 1074, height: 430)))
    }

    /// A holder with no height yet — the first layout pass, before geometry resolves — must not be
    /// classified from a division by zero.
    func testZeroHeightHolderIsNotClassifiedAsLetterbox() {
        XCTAssertFalse(WinampModernVisualizationHolder.prefersAnalyzer(
            frame: CGRect(x: 0, y: 0, width: 1074, height: 0)))
    }

    /// The bridge vends one surface per skin, so exactly one holder can hold the picture. It goes to
    /// the largest eligible box — "Big Component View" over the album-art-sized mini — and the
    /// letterbox strip is not eligible at all.
    func testEngineGoesToTheLargestNonLetterboxHolder() {
        let graph = WasabiObjectGraph()
        let stretched = holder("vis.full", CGRect(x: 0, y: 0, width: 1074, height: 147), graph: graph)
        let mini = holder("vis.mini", CGRect(x: 0, y: 0, width: 186, height: 185), graph: graph)
        let tab = holder("vis.tab", CGRect(x: 0, y: 0, width: 1074, height: 430), graph: graph)

        XCTAssertEqual(WinampModernVisualizationHolder.engineHolder(among: [stretched, mini, tab]),
                       tab.object.stableID)
        // Without the tab open, the mini takes it — and the stretched pane still does not.
        XCTAssertEqual(WinampModernVisualizationHolder.engineHolder(among: [stretched, mini]),
                       mini.object.stableID)
    }

    /// Every holder a letterbox strip means no engine at all, and the caller falls back to drawing
    /// the analyzer in each of them rather than mounting a surface nowhere.
    func testAllLetterboxHoldersLeaveTheEngineUnmounted() {
        let graph = WasabiObjectGraph()
        let wide = holder("a", CGRect(x: 0, y: 0, width: 1074, height: 147), graph: graph)
        let wider = holder("b", CGRect(x: 0, y: 0, width: 900, height: 100), graph: graph)
        XCTAssertNil(WinampModernVisualizationHolder.engineHolder(among: [wide, wider]))
    }

    /// Ties keep the earliest holder in scene order. A layout pass that reported the same two boxes
    /// in a different order must not move the picture between them.
    func testEqualAreaTieKeepsTheFirstHolder() {
        let graph = WasabiObjectGraph()
        let first = holder("first", CGRect(x: 0, y: 0, width: 200, height: 200), graph: graph)
        let second = holder("second", CGRect(x: 0, y: 0, width: 200, height: 200), graph: graph)
        XCTAssertEqual(WinampModernVisualizationHolder.engineHolder(among: [first, second]),
                       first.object.stableID)
        XCTAssertEqual(WinampModernVisualizationHolder.engineHolder(among: [second, first]),
                       second.object.stableID)
    }

    /// Only visualization holders are candidates: a playlist or library holder in the same scene is
    /// not something the visualization engine may be mounted into.
    func testNonVisualizationHoldersAreNeverCandidates() {
        let graph = WasabiObjectGraph()
        let library = WinampModernComponentHolder(
            object: graph.makeObject(typeName: "component", attributes: ["id": "lib"],
                                     source: WalSourceLocation(path: "/test.xml")),
            surfaceID: .component(.library),
            frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertNil(WinampModernVisualizationHolder.engineHolder(among: [library]))
    }

    // MARK: - BB21: the id index behind the playback tick

    /// `objects(xmlID:)` used to scan every object and sort the result on every call, on the playback
    /// tick. The index has to answer the same thing — including several objects sharing an id, in
    /// stable order — and has to notice a script renaming one.
    func testXMLIDIndexAnswersLikeAScanAndFollowsRenames() {
        let graph = WasabiObjectGraph()
        let source = WalSourceLocation(path: "/test.xml")
        let first = graph.makeObject(typeName: "layer", attributes: ["id": "HiddenVolume"], source: source)
        let second = graph.makeObject(typeName: "layer", attributes: ["id": "hiddenvolume"], source: source)
        _ = graph.makeObject(typeName: "layer", attributes: ["id": "other"], source: source)

        // Case-insensitive, and in stable id order.
        XCTAssertEqual(graph.objects(xmlID: "HIDDENVOLUME").map(\.stableID),
                       [first.stableID, second.stableID])
        XCTAssertTrue(graph.objects(xmlID: "missing").isEmpty)

        // A newly created object must appear without anything else invalidating the index.
        let third = graph.makeObject(typeName: "layer", attributes: ["id": "HiddenVolume"], source: source)
        XCTAssertEqual(graph.objects(xmlID: "hiddenvolume").map(\.stableID),
                       [first.stableID, second.stableID, third.stableID])

        // And a rename must move it, rather than answering under the old name.
        _ = second.setAttribute("id", value: "renamed")
        XCTAssertEqual(graph.objects(xmlID: "HiddenVolume").map(\.stableID),
                       [first.stableID, third.stableID])
        XCTAssertEqual(graph.objects(xmlID: "renamed").map(\.stableID), [second.stableID])
    }
}
