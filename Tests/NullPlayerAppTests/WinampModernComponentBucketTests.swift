import XCTest
@testable import NullPlayer

/// B34 — Winamp's **thinger**: `<componentbucket>` draws a strip of installed-component icons, the
/// `<text display="componentbucket">` beside it names the focused one, and the `CB_*` buttons scroll
/// it. Every bucket in the corpus drew an empty box until the engine published an icon set, because
/// in Winamp the icons come from the *components* and no `.wal` ships any.
///
/// The pieces asserted here are the pure ones — the published set, the box arithmetic, and the strip
/// state — measured against the boxes real skins actually declare. Drawing and hit testing are the
/// renderer's, and the live check (mmd3's in-body circle, the Nullsoft SP4 Lite Thinger window's full
/// five-icon strip) is what confirmed those.
final class WinampModernComponentBucketTests: XCTestCase {

    private func makeBucket(_ attributes: [String: String]) -> WasabiObject {
        let graph = WasabiObjectGraph()
        addTeardownBlock { graph.teardown() }
        return graph.makeObject(typeName: "componentbucket", attributes: attributes,
                                source: WalSourceLocation(path: "test", line: 0, column: 0))
    }

    private func layout(_ attributes: [String: String], _ frame: CGRect)
        -> WinampModernComponentBucketLayout {
        WinampModernComponentBucketLayout(object: makeBucket(attributes), frame: frame)
    }

    // MARK: - The published set

    /// Only surfaces `routeComponentToggle` can actually open. A bucket is a launcher, and an icon
    /// that opens nothing is worse than no icon — `.other` is deliberately not in it.
    func testTheIconSetIsTheComponentsTheHostCanOpen() {
        let kinds = WinampModernComponentBucketCatalog.icons.map(\.kind)
        XCTAssertEqual(kinds, [.playlist, .equalizer, .library, .visualization, .video])
        XCTAssertFalse(kinds.contains(.other))
        for icon in WinampModernComponentBucketCatalog.icons {
            XCTAssertFalse(icon.title.isEmpty, "every icon needs a name for the caption to read")
        }
    }

    // MARK: - The box

    /// Styx's thinger: 160×35, `spacing="2"`, 8px margins each side — 144 usable, so four icons at
    /// Winamp's 32px cap rather than four 35px ones stretched to the box.
    func testAWideBucketShowsSeveralIcons() {
        let styx = layout(["spacing": "2", "leftmargin": "8", "rightmargin": "8"],
                          CGRect(x: 20, y: 70, width: 160, height: 35))
        XCTAssertEqual(styx.iconExtent, 32, "icons are capped at Winamp's own 32px")
        XCTAssertEqual(styx.visibleCount, 4)
        XCTAssertEqual(styx.iconRect(slot: 0).minX, 28)
        XCTAssertEqual(styx.iconRect(slot: 1).minX, 28 + 32 + 2, "spacing sits between icons")
    }

    /// Lobe's is 40×25 with 3/5 margins — narrower than one icon plus its margins. It must still show
    /// one: showing nothing there is the empty strip this feature replaces.
    func testABucketNarrowerThanOneIconStillShowsOne() {
        let lobe = layout(["leftmargin": "3", "rightmargin": "5"],
                          CGRect(x: 28, y: 21, width: 40, height: 25))
        XCTAssertEqual(lobe.iconExtent, 25, "square, from the cross axis")
        XCTAssertEqual(lobe.visibleCount, 1)
    }

    /// `vertical="1"` (Lobe's switch layout, S7Reflex's config drawer): the strip runs down the box
    /// and `leftmargin`/`rightmargin` run along **that** axis, as they do in Wasabi.
    func testAVerticalBucketStacksItsIconsAndKeepsItsMarginsOnTheScrollAxis() {
        let box = CGRect(x: 32, y: 20, width: 25, height: 39)
        let vertical = layout(["vertical": "1", "leftmargin": "3", "rightmargin": "5"], box)
        XCTAssertEqual(vertical.iconExtent, 25)
        XCTAssertEqual(vertical.axisLength, 39 - 3 - 5)
        XCTAssertEqual(vertical.iconRect(slot: 0).minY, 23)
        XCTAssertEqual(vertical.iconRect(slot: 0).minX, 32, "centred on the cross axis")
    }

    /// mmd3's shade buckets declare `leftmargin="-3" rightmargin="-6"` on purpose — the strip is
    /// pulled out past its box. A clamp to zero would move icons the skin placed deliberately.
    func testNegativeMarginsAreHonouredRatherThanClamped() {
        let shade = layout(["spacing": "2", "leftmargin": "-3", "rightmargin": "-6"],
                           CGRect(x: 63, y: 16, width: 37, height: 36))
        XCTAssertEqual(shade.iconRect(slot: 0).minX, 60)
        XCTAssertEqual(shade.axisLength, 37 + 3 + 6)
    }

    func testAPointBetweenIconsHitsNothing() {
        let box = CGRect(x: 0, y: 0, width: 160, height: 35)
        let strip = layout(["spacing": "6", "leftmargin": "0", "rightmargin": "0"], box)
        XCTAssertEqual(strip.slot(at: CGPoint(x: 5, y: 17)), 0)
        XCTAssertNil(strip.slot(at: CGPoint(x: 34, y: 17)), "the gap between two icons")
        XCTAssertEqual(strip.slot(at: CGPoint(x: 40, y: 17)), 1)
        XCTAssertNil(strip.slot(at: CGPoint(x: 300, y: 17)), "outside the box")
    }

    // MARK: - The strip

    func testScrollingStopsAtBothEndsOfTheStrip() {
        let state = WinampModernComponentBucketState()
        XCTAssertEqual(state.offset, 0)
        XCTAssertFalse(state.scroll(by: -1, visibleCount: 1), "already at the first icon")
        XCTAssertTrue(state.scroll(by: 1, visibleCount: 1))
        XCTAssertEqual(state.offset, 1)
        for _ in 0..<10 { state.scroll(by: 1, visibleCount: 1) }
        XCTAssertEqual(state.offset, state.icons.count - 1, "the last icon stays on screen")
        XCTAssertFalse(state.scroll(by: 1, visibleCount: 1))
    }

    /// A bucket showing three at once cannot scroll past the last screenful, or the strip would end
    /// with empty slots where icons should be.
    func testTheLastScreenfulIsTheEnd() {
        let state = WinampModernComponentBucketState()
        state.scroll(by: 5, visibleCount: 3)
        XCTAssertEqual(state.offset, state.icons.count - 3)
    }

    /// `CB_NEXTPAGE` moves a whole screenful; `CB_NEXT` one icon. Both clamp the same way.
    func testAPageIsAScreenfulAndAStepIsOneIcon() {
        let step = WinampModernComponentBucketState()
        step.scroll(by: 1, visibleCount: 2)
        XCTAssertEqual(step.offset, 1)
        let page = WinampModernComponentBucketState()
        page.scroll(by: 2, visibleCount: 2)
        XCTAssertEqual(page.offset, 2)
    }

    /// A `CB_*` button is pressed with no pointer on the strip, so the caption has to follow the
    /// scroll — otherwise the name beside the thinger describes an icon that has scrolled away.
    func testScrollingMovesTheCaptionWithIt() {
        let state = WinampModernComponentBucketState()
        XCTAssertEqual(state.focusedTitle, "Playlist Editor")
        state.scroll(by: 2, visibleCount: 1)
        XCTAssertEqual(state.focusedIndex, 2)
        XCTAssertEqual(state.focusedTitle, "Media Library")
    }

    func testHoverFocusIgnoresAnIndexOffTheStrip() {
        let state = WinampModernComponentBucketState()
        XCTAssertTrue(state.focus(3))
        XCTAssertEqual(state.focusedTitle, "Visualization")
        XCTAssertFalse(state.focus(3), "no change, no repaint")
        XCTAssertFalse(state.focus(99))
        XCTAssertEqual(state.focusedIndex, 3)
    }

    // MARK: - The caption

    /// `<text display="componentbucket">` resolves through the same provider seam `PE_Info` uses, so
    /// a caption in a different container than its bucket still follows the strip.
    func testTheCaptionReadsTheFocusedIconThroughItsProvider() {
        let state = WinampModernComponentBucketState()
        WasabiTextMetrics.componentBucketTextProvider = { state.focusedTitle }
        addTeardownBlock { WasabiTextMetrics.componentBucketTextProvider = nil }
        let caption = makeBucketCaption()
        XCTAssertEqual(WasabiTextMetrics.content(of: caption, host: StubHost()),
                       "Playlist Editor")
        state.focus(4)
        XCTAssertEqual(WasabiTextMetrics.content(of: caption, host: StubHost()), "Video")
    }

    /// With no skin loaded the caption reads empty rather than a stale name from the last one.
    func testTheCaptionIsEmptyWithNoProviderInstalled() {
        WasabiTextMetrics.componentBucketTextProvider = nil
        XCTAssertEqual(WasabiTextMetrics.content(of: makeBucketCaption(),
                                                 host: StubHost()), "")
    }

    private func makeBucketCaption() -> WasabiObject {
        let graph = WasabiObjectGraph()
        addTeardownBlock { graph.teardown() }
        return graph.makeObject(typeName: "text", attributes: ["display": "componentbucket"],
                                source: WalSourceLocation(path: "test", line: 0, column: 0))
    }

    private final class StubHost: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }

    // MARK: - The actions

    /// The four `CB_*` were `.inert` until the icon set existed. They decode to real scrolls now, and
    /// case-insensitively — skins spell them `CB_NEXT`, `cb_nextpage` and `Cb_Prev` alike.
    func testTheScrollActionsDecode() {
        XCTAssertEqual(WinampModernHostAction(action: "CB_NEXT"),
                       .componentBucketScroll(delta: 1, page: false))
        XCTAssertEqual(WinampModernHostAction(action: "Cb_Prev"),
                       .componentBucketScroll(delta: -1, page: false))
        XCTAssertEqual(WinampModernHostAction(action: "cb_nextpage"),
                       .componentBucketScroll(delta: 1, page: true))
        XCTAssertEqual(WinampModernHostAction(action: "CB_PREVPAGE"),
                       .componentBucketScroll(delta: -1, page: true))
    }
}
