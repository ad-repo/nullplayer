import AppKit
import XCTest
@testable import NullPlayer

/// Scrolling a skin-declared `<PLAYLIST>`, which is one hosted view shared by **174 of the 182
/// measured archives** — 161 declare `PLAYLIST`, 13 declare `ITEMSPLAYLIST` and none of those 13
/// declares a `PLAYLIST` beside it (`scripts/wmp_markup_census.sh`, 2026-09-20).
///
/// Reported live on `Xbox Live Skin` as *"a large playlist cannot be scrolled properly"* (W246),
/// and it was two defects under one symptom:
///
/// - **The list was pinned to the playing track.** `update` ran `scrollSelectionIntoView` from
///   every host refresh — one arrives ~12 times a second whether or not anything moved — and that
///   method clamps the scroll position into `selected - visibleRows + 1 ... selected`. A wheel
///   gesture moved the list and the next refresh put it back within ~85 ms. Measured on screen
///   with a 200-row playlist: 70 wheel events down reached row 19 and stopped, 40 back up reached
///   row 2 and stopped. Rows 20-200 could not be reached at all.
/// - **The wheel read only the sign of `scrollingDeltaY`**, so every event moved exactly one row
///   and a trackpad flick carrying hundreds of points of precise delta moved one row.
///
/// The rule these tests pin is that **scrolling to the selection is an event, not a state**: a
/// track change scrolls, a keystroke scrolls, and a refresh that changed nothing only clamps the
/// position into the list.
final class WMPPlaylistScrollTests: XCTestCase {

    /// 18 points a row, so a 198-point view draws 11 rows — `Xbox Live Skin`'s own `playlist1`
    /// geometry, rounded to a whole row.
    private let visibleRows = 11

    @MainActor
    private func surface() -> WMPPlaylistSurfaceView {
        WMPPlaylistSurfaceView(frame: NSRect(x: 0, y: 0, width: 312, height: 198))
    }

    private func snapshot(count: Int, playing: Int) -> WMPHostSnapshot {
        var snapshot = WMPHostSnapshot()
        snapshot.state = .playing
        snapshot.playlistCount = count
        snapshot.playlistIndex = playing
        snapshot.playlistItems = (0..<count).map {
            WMPPlaylistItemSnapshot(title: String(format: "Row %03d", $0 + 1),
                                    artist: "W246 Fixture", duration: 6)
        }
        return snapshot
    }

    /// A wheel event AppKit will answer for. `units: .pixel` is what makes it a precise
    /// (trackpad) delta; `.line` is a mouse wheel, whose `scrollingDeltaY` is a line count.
    private func wheel(deltaY: Int32, precise: Bool) throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil,
                                          units: precise ? .pixel : .line,
                                          wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0))
        if precise { event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1) }
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }

    // MARK: - The report

    /// The defect itself: scroll away from the playing track, then let the clock tick.
    @MainActor
    func testAHostRefreshDoesNotPullTheListBackToTheSelection() throws {
        let view = surface()
        view.update(snapshot(count: 200, playing: 4))
        for _ in 0..<70 { view.scrollWheel(with: try wheel(deltaY: -1, precise: false)) }
        XCTAssertEqual(view.firstVisibleIndex, 70, "70 events, one row each, from row 0")

        // The same snapshot again, twelve times — one second of a playing clock.
        for _ in 0..<12 { view.update(snapshot(count: 200, playing: 4)) }
        XCTAssertEqual(view.firstVisibleIndex, 70,
                       "a refresh that changed nothing must not move the scroll position")
    }

    /// The other half of the pin: scrolling *up* past the selection was clamped too, which is why
    /// row 1 became unreachable once the playing index passed the view's height.
    @MainActor
    func testTheListScrollsBackAboveThePlayingTrack() throws {
        let view = surface()
        view.update(snapshot(count: 200, playing: 120))
        XCTAssertEqual(view.firstVisibleIndex, 120 - visibleRows + 1, "the track change scrolled it")

        for _ in 0..<200 { view.scrollWheel(with: try wheel(deltaY: 1, precise: false)) }
        view.update(snapshot(count: 200, playing: 120))
        XCTAssertEqual(view.firstVisibleIndex, 0, "row 1 is reachable from anywhere in the list")
    }

    /// The end of a long list is reachable, and nothing overscrolls past it.
    @MainActor
    func testScrollingClampsAtBothEndsOfTheList() throws {
        let view = surface()
        view.update(snapshot(count: 200, playing: 0))
        for _ in 0..<400 { view.scrollWheel(with: try wheel(deltaY: -1, precise: false)) }
        XCTAssertEqual(view.firstVisibleIndex, 200 - visibleRows,
                       "the last row sits in the last slot, with no blank rows under it")

        for _ in 0..<400 { view.scrollWheel(with: try wheel(deltaY: 1, precise: false)) }
        XCTAssertEqual(view.firstVisibleIndex, 0)
    }

    // MARK: - What the wheel is worth

    /// A trackpad delivers points, not detents. 180 points of precise delta is ten 18-point rows.
    @MainActor
    func testAPreciseDeltaMovesTheRowsItIsWorth() throws {
        let view = surface()
        view.update(snapshot(count: 200, playing: 0))
        view.scrollWheel(with: try wheel(deltaY: -180, precise: true))
        XCTAssertEqual(view.firstVisibleIndex, 10)
    }

    /// Sub-row deltas accumulate instead of rounding away, so slow trackpad scrolling still moves
    /// the list: six 3-point events are one row, not nothing and not six.
    @MainActor
    func testSubRowPreciseDeltasAccumulate() throws {
        let view = surface()
        view.update(snapshot(count: 200, playing: 0))
        for _ in 0..<5 { view.scrollWheel(with: try wheel(deltaY: -3, precise: true)) }
        XCTAssertEqual(view.firstVisibleIndex, 0, "15 of the 18 points a row costs")
        view.scrollWheel(with: try wheel(deltaY: -3, precise: true))
        XCTAssertEqual(view.firstVisibleIndex, 1)
    }

    /// A mouse wheel reports lines, and the system's own acceleration is already in that number —
    /// a three-line event is three rows, where it used to be one.
    @MainActor
    func testALineDeltaMovesOneRowPerLine() throws {
        let view = surface()
        view.update(snapshot(count: 200, playing: 0))
        view.scrollWheel(with: try wheel(deltaY: -3, precise: false))
        XCTAssertEqual(view.firstVisibleIndex, 3)
    }

    // MARK: - What still scrolls the list

    /// The `nvidia` behaviour (W224) is unchanged: the playing row is still brought into view when
    /// the track changes, which is what WMP's own playlist does. Only the *refresh* stopped doing
    /// it.
    @MainActor
    func testATrackChangeStillScrollsThePlayingRowIntoView() throws {
        let view = surface()
        view.update(snapshot(count: 200, playing: 4))
        for _ in 0..<70 { view.scrollWheel(with: try wheel(deltaY: -1, precise: false)) }
        XCTAssertEqual(view.firstVisibleIndex, 70)

        view.update(snapshot(count: 200, playing: 150))
        XCTAssertEqual(view.firstVisibleIndex, 150 - visibleRows + 1,
                       "the shortest pull that puts the new track on screen")
    }

    /// Arrow-key navigation moves the highlight, and the list follows it off the bottom edge.
    @MainActor
    func testKeyboardNavigationStillScrollsTheSelectionIntoView() throws {
        let view = surface()
        view.update(snapshot(count: 200, playing: 0))
        let down = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                  timestamp: 0, windowNumber: 0, context: nil,
                                                  characters: "", charactersIgnoringModifiers: "",
                                                  isARepeat: false, keyCode: 125))
        for _ in 0..<20 { view.keyDown(with: down) }
        XCTAssertEqual(view.firstVisibleIndex, 20 - visibleRows + 1)
    }

    /// A playlist that shrinks under the scroll position pulls it back into the list rather than
    /// leaving the view on rows that are gone — the half of the old per-refresh call that a
    /// refresh is still entitled to run.
    @MainActor
    func testAShrinkingPlaylistPullsTheScrollPositionBackIntoIt() throws {
        let view = surface()
        view.update(snapshot(count: 200, playing: 0))
        for _ in 0..<150 { view.scrollWheel(with: try wheel(deltaY: -1, precise: false)) }
        XCTAssertEqual(view.firstVisibleIndex, 150)

        view.update(snapshot(count: 20, playing: 0))
        XCTAssertEqual(view.firstVisibleIndex, 20 - visibleRows)
    }

    /// A list shorter than the view has nowhere to scroll to, in either direction.
    @MainActor
    func testAShortPlaylistDoesNotScroll() throws {
        let view = surface()
        view.update(snapshot(count: 4, playing: 0))
        for _ in 0..<10 { view.scrollWheel(with: try wheel(deltaY: -1, precise: false)) }
        XCTAssertEqual(view.firstVisibleIndex, 0)
    }
}
