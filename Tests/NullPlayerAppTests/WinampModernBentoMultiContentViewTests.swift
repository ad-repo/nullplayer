import XCTest
@testable import NullPlayer

/// BB9 — Big Bento Modern's Multi Content View, laid out side by side.
///
/// The skin's Visualization page is exclusive: the stretched pane is declared the full width of the
/// holder and `mcvcore`'s page routine hides everything behind it — then a 700 ms one-shot in the
/// script's *second* `System.onScriptLoaded()` shows the file-info panes back over it with no
/// reference to which page is current. What is wanted is neither the overlap nor the exclusivity but
/// a row: the album art (or the mini visualization pane, which shares its slot) beside a narrowed
/// spectrum, with the file-info text lines hidden.
///
/// The layout is measured here; that it reaches the screen was verified in the running app, which is
/// the only place a `{0000000A}` holder has a live surface at all.
final class WinampModernBentoMultiContentViewTests: XCTestCase {

    private let graph = WasabiObjectGraph()

    /// The holder and its five panes, in the markup's own order.
    private func makeHolder(stretchedVisible: Bool = true) throws -> [String: WasabiObject] {
        let holder = object("info.component.holder")
        var panes: [String: WasabiObject] = ["info.component.holder": holder]
        for id in ["info.component.cover", "info.component.vis", "info.component.vis.full",
                   "info.component.infodisplay", "info.component.songinfodisplay"] {
            let pane = object(id, visible: id == "info.component.vis.full" && !stretchedVisible
                              ? "0" : nil)
            try holder.appendChild(pane)
            panes[id] = pane
        }
        return panes
    }

    private func object(_ id: String, visible: String? = nil) -> WasabiObject {
        var attributes = ["id": id]
        if let visible { attributes["visible"] = visible }
        return graph.makeObject(typeName: "group", attributes: attributes,
                                source: WalSourceLocation(path: "/player-normal-mcv.xml"))
    }

    /// The holder's box at the skin's own declared layout width.
    private let holderFrame = CGRect(x: 444, y: 47, width: 1080, height: 186)

    private func reader(mini: Bool) -> WinampModernBentoMultiContentView.SettingReader {
        { section, key in
            guard section == WinampModernBentoMultiContentView.fileInfoComponentsSection,
                  key == WinampModernBentoMultiContentView.miniVisKey else { return nil }
            return mini
        }
    }

    // MARK: - Visibility

    /// The file-info text lines are what the one-shot brings back over the bars, and the one thing
    /// this page has no room for. They stay hidden while the spectrum is up — whatever the skin's
    /// own `visible` attribute says by then.
    func testFileInfoTextIsHiddenWhileTheStretchedPaneIsUp() throws {
        let panes = try makeHolder()
        for id in ["info.component.infodisplay", "info.component.songinfodisplay"] {
            XCTAssertEqual(WinampModernBentoMultiContentView.forcedVisibility(
                of: panes[id]!, reading: reader(mini: false)), false, id)
        }
    }

    /// The cover comes back beside the spectrum whatever the skin's page routine did with it, and
    /// **whatever `Album Art` says** — that setting is one half of an either/or with the mini pane,
    /// so honouring it left the row empty for anyone who had picked the mini pane, and the spectrum
    /// took the whole width again. The mini pane still follows its own check box, which is how all
    /// three come to sit side by side.
    func testCoverIsAlwaysShownAndTheMiniPaneFollowsItsSetting() throws {
        let panes = try makeHolder()
        for mini in [true, false] {
            XCTAssertEqual(WinampModernBentoMultiContentView.forcedVisibility(
                of: panes["info.component.cover"]!, reading: reader(mini: mini)), true,
                "mini=\(mini)")
            XCTAssertEqual(WinampModernBentoMultiContentView.forcedVisibility(
                of: panes["info.component.vis"]!, reading: reader(mini: mini)), mini)
        }
    }

    /// With the Visualization page closed the holder is the skin's own again, and nothing here
    /// applies — including the file-info lines, which are the page's whole content then.
    func testNothingIsForcedWhileTheStretchedPaneIsHidden() throws {
        let panes = try makeHolder(stretchedVisible: false)
        for (id, pane) in panes where id != "info.component.holder" {
            XCTAssertNil(WinampModernBentoMultiContentView.forcedVisibility(
                of: pane, reading: reader(mini: false)), id)
        }
    }

    /// The stretched pane itself is never forced either way: whether the page is open is the skin's
    /// decision, and this whole override is conditional on it.
    func testTheStretchedPaneItselfIsNeverForced() throws {
        let panes = try makeHolder()
        XCTAssertNil(WinampModernBentoMultiContentView.forcedVisibility(
            of: panes["info.component.vis.full"]!, reading: reader(mini: false)))
    }

    /// Scoped by id: an object that is not one of the holder's panes is left alone even when it sits
    /// beside them.
    func testUnrelatedObjectsAreLeftAlone() throws {
        let panes = try makeHolder()
        let other = object("player.seek.bg")
        try panes["info.component.holder"]!.appendChild(other)
        XCTAssertNil(WinampModernBentoMultiContentView.forcedVisibility(
            of: other, reading: reader(mini: false)))
    }

    // MARK: - Geometry

    /// With the album art beside it, the spectrum starts where the cover ends. The margin and pitch
    /// are `mcvcore`'s own: the cover alone sits at `x=6`, and a 186-wide pane plus a 6px gutter puts
    /// the spectrum at 198.
    func testSpectrumStartsAfterTheCover() throws {
        let panes = try makeHolder()
        let read = reader(mini: false)
        let cover = WinampModernBentoMultiContentView.correctedFrame(
            for: panes["info.component.cover"]!, parentFrame: holderFrame,
            resolved: CGRect(x: 450, y: 54, width: 0, height: 186), reading: read)
        XCTAssertEqual(cover?.minX, 450)
        // The width as well as the x: the skin animates the cover's width to zero when it hides it.
        XCTAssertEqual(cover?.width, 186)

        let stretched = WinampModernBentoMultiContentView.correctedFrame(
            for: panes["info.component.vis.full"]!, parentFrame: holderFrame,
            resolved: holderFrame, reading: read)
        XCTAssertEqual(stretched?.minX, 444 + 198)
        XCTAssertEqual(stretched?.maxX, holderFrame.maxX - 3)
    }

    /// With the mini pane ticked all three sit in a row, in `mcvcore`'s own both-ticked positions:
    /// the mini pane at 3, the cover at 195, and the spectrum after them.
    func testAllThreeLayOutInARow() throws {
        let panes = try makeHolder()
        let read = reader(mini: true)
        let cover = WinampModernBentoMultiContentView.correctedFrame(
            for: panes["info.component.cover"]!, parentFrame: holderFrame,
            resolved: CGRect(x: 450, y: 54, width: 189, height: 186), reading: read)
        XCTAssertEqual(cover?.minX, 444 + 195)
        let stretched = WinampModernBentoMultiContentView.correctedFrame(
            for: panes["info.component.vis.full"]!, parentFrame: holderFrame,
            resolved: holderFrame, reading: read)
        XCTAssertEqual(stretched?.minX, 444 + 387)
    }

    /// The spectrum is never the whole holder while this page is up: the cover always takes its
    /// slot, so there is always something beside it. That is the regression the `Album Art` read
    /// caused — with the mini pane picked, the pair turned the cover off and the row vanished.
    func testTheSpectrumNeverTakesTheWholeHolder() throws {
        let panes = try makeHolder()
        for mini in [true, false] {
            let stretched = WinampModernBentoMultiContentView.correctedFrame(
                for: panes["info.component.vis.full"]!, parentFrame: holderFrame,
                resolved: holderFrame, reading: reader(mini: mini))
            XCTAssertNotNil(stretched)
            XCTAssertGreaterThan(stretched!.minX, holderFrame.minX + 190, "mini=\(mini)")
            XCTAssertLessThan(stretched!.width, holderFrame.width - 190)
        }
    }

    /// A holder too narrow to seat the row leaves the skin's own frame rather than returning a
    /// negative box, which the renderer drops along with the pane's whole subtree.
    func testTooNarrowAHolderLeavesTheFrameAlone() throws {
        let panes = try makeHolder()
        let narrow = CGRect(x: 444, y: 47, width: 120, height: 186)
        XCTAssertNil(WinampModernBentoMultiContentView.correctedFrame(
            for: panes["info.component.vis.full"]!, parentFrame: narrow,
            resolved: narrow, reading: reader(mini: false)))
    }

    /// Without a script runtime to read from — the pixel tests build the renderer that way — the
    /// mini pane falls back to the default the skin's own `newAttribute` call declares, and the
    /// cover is unconditional as everywhere else.
    func testNoSettingReaderFallsBackToTheSkinsOwnDefaults() throws {
        let panes = try makeHolder()
        XCTAssertEqual(WinampModernBentoMultiContentView.forcedVisibility(
            of: panes["info.component.cover"]!, reading: nil), true)
        XCTAssertEqual(WinampModernBentoMultiContentView.forcedVisibility(
            of: panes["info.component.vis"]!, reading: nil), false)
    }

    // MARK: - Which pane draws the analyzer

    /// The stretched pane is the spectrum whatever its box measures. Narrowing it to seat the row
    /// takes it under the 3:1 letterbox ratio `WinampModernVisualizationHolder` routes on, and a
    /// holder under that ratio claims the engine — which is the one placement BB9 settled is an
    /// analyzer. Its declared box is the whole holder, so the routing asks the pane, not the box.
    func testNarrowedStretchedPaneStillPrefersTheAnalyzer() throws {
        let panes = try makeHolder()
        let component = graph.makeObject(typeName: "component", attributes: ["id": "vis"],
                                         source: WalSourceLocation(path: "/player-normal-mcv.xml"))
        try panes["info.component.vis.full"]!.appendChild(component)
        // 345 × 147 — what the pane measures once the cover sits beside it. 2.3:1, well under the
        // boundary, and it would take the engine on shape alone.
        let holder = WinampModernComponentHolder(
            object: component, surfaceID: .component(.visualization),
            frame: CGRect(x: 0, y: 0, width: 345, height: 147))
        XCTAssertFalse(WinampModernVisualizationHolder.prefersAnalyzer(frame: holder.frame))
        XCTAssertTrue(WinampModernVisualizationHolder.prefersAnalyzer(holder: holder))
        XCTAssertNil(WinampModernVisualizationHolder.engineHolder(among: [holder]))
    }

    /// The mini pane in the same holder is not the stretched one, so it is routed on its box exactly
    /// as before and still takes the engine.
    func testTheMiniPaneStillTakesTheEngine() throws {
        let panes = try makeHolder()
        let component = graph.makeObject(typeName: "component", attributes: ["id": "vis"],
                                         source: WalSourceLocation(path: "/player-normal-mcv.xml"))
        try panes["info.component.vis"]!.appendChild(component)
        let holder = WinampModernComponentHolder(
            object: component, surfaceID: .component(.visualization),
            frame: CGRect(x: 0, y: 0, width: 186, height: 185))
        XCTAssertFalse(WinampModernVisualizationHolder.prefersAnalyzer(holder: holder))
        XCTAssertEqual(WinampModernVisualizationHolder.engineHolder(among: [holder]),
                       component.stableID)
    }
}
