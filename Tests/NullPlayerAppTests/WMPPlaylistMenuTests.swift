import AppKit
import XCTest
@testable import NullPlayer

/// A skin's `<PLAYLIST>` pane answers a right-click with NullPlayer's own playlist menu (W272).
///
/// WMP skins author no playlist controls — WMP's own menus supplied them — so the pane, shared by
/// every `.wmz` that declares one, offered only Delete and Option+↑/↓. Reported live on `WoW` as
/// "there are no controls to manage the playlist". The menu is `PlaylistMenuBuilder`'s, the one the
/// Modern playlist shows, and the pane gained Shift/Cmd-click so Remove, Crop and Invert have a
/// selection of more than one row to act on.
final class WMPPlaylistMenuTests: XCTestCase {

    private let rowHeight: CGFloat = 18

    @MainActor
    private func surface(count: Int = 20, playing: Int = 0) -> (WMPPlaylistSurfaceView, NSWindow) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 312, height: 198),
                              styleMask: .borderless, backing: .buffered, defer: true)
        let view = WMPPlaylistSurfaceView(frame: NSRect(x: 0, y: 0, width: 312, height: 198))
        window.contentView?.addSubview(view)
        view.update(snapshot(count: count, playing: playing))
        return (view, window)
    }

    private func snapshot(count: Int, playing: Int) -> WMPHostSnapshot {
        var snapshot = WMPHostSnapshot()
        snapshot.state = .playing
        snapshot.playlistCount = count
        snapshot.playlistIndex = playing
        snapshot.playlistItems = (0..<count).map {
            WMPPlaylistItemSnapshot(title: "Row \($0 + 1)", artist: "W272 Fixture", duration: 6)
        }
        return snapshot
    }

    /// A mouse event on `row`, in the window coordinates AppKit delivers.
    @MainActor
    private func event(_ type: NSEvent.EventType, row: Int, in view: NSView,
                       modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let point = view.convert(NSPoint(x: 20, y: CGFloat(row) * rowHeight + rowHeight / 2), to: nil)
        return try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: modifiers, timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1))
    }

    @MainActor
    private func click(_ row: Int, _ view: NSView, _ modifiers: NSEvent.ModifierFlags = []) throws {
        view.mouseDown(with: try event(.leftMouseDown, row: row, in: view, modifiers: modifiers))
    }

    @MainActor
    private func menu(at row: Int, _ view: NSView) throws -> NSMenu {
        try XCTUnwrap(view.menu(for: try event(.rightMouseDown, row: row, in: view)))
    }

    private func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        for item in menu.items {
            if item.title == title { return item }
            if let sub = item.submenu, let found = sub.items.first(where: { $0.title == title }) { return found }
        }
        return try XCTUnwrap(nil as NSMenuItem?, "no menu row \(title)")
    }

    // MARK: - The menu

    /// The pane's right-click is the host playlist menu, in the Modern playlist's order.
    @MainActor
    func testARightClickShowsTheHostPlaylistMenu() throws {
        let (view, _) = surface()
        let menu = try menu(at: 3, view)
        XCTAssertEqual(menu.items.map(\.title),
                       ["Play", "", "Remove Selected", "Clear Playlist", "Remove Dead Files", "",
                        "Selection", "Sort", "", "File Info..."])
        XCTAssertEqual(menu.items[6].submenu?.items.map(\.title),
                       ["Select All", "Select None", "Invert Selection", "Crop Selection"])
        XCTAssertEqual(menu.items[7].submenu?.items.map(\.title),
                       ["Sort by Title", "Sort by Artist", "Sort by Album", "Sort by Filename",
                        "Sort by Path", "", "Reverse", "Randomize"])
        XCTAssertTrue(menu.items.filter { !$0.isSeparatorItem }.allSatisfy(\.isEnabled))
        XCTAssertTrue(menu.items.compactMap(\.submenu).allSatisfy { !$0.autoenablesItems },
                      "a disabled row on the pane must stay disabled")
    }

    /// A right-click on a row outside the selection selects that row alone; on a selected row it
    /// keeps the selection, so the menu acts on every row the user picked.
    @MainActor
    func testARightClickSelectsAnUnselectedRowButKeepsASelectionItLandsIn() throws {
        let (view, _) = surface()
        try click(2, view); try click(5, view, .shift)
        _ = try menu(at: 4, view)
        XCTAssertEqual(view.selectedRows, Set(2...5))
        _ = try menu(at: 9, view)
        XCTAssertEqual(view.selectedRows, [9])
    }

    /// File Info reads one track, so it needs exactly one selected row.
    @MainActor
    func testFileInfoIsDisabledForMoreThanOneRow() throws {
        let (view, _) = surface()
        try click(1, view); try click(4, view, .command)
        XCTAssertFalse(try item("File Info...", in: try menu(at: 1, view)).isEnabled)
    }

    /// A library playlist shown in the pane (W136) is read-only: the rows that edit the queue are
    /// disabled, while Play and the selection rows still apply to what the pane shows.
    @MainActor
    func testALibraryPreviewDisablesEveryRowThatEditsTheQueue() throws {
        let (view, _) = surface()
        let items = (0..<6).map { WMPPlaylistItemSnapshot(title: "Library \($0)", artist: "", duration: 6) }
        view.update(libraryRows: .init(reference: "playlistCollection:0", items: items, tracks: Array(0..<6)))
        let menu = try menu(at: 1, view)
        for title in ["Remove Selected", "Clear Playlist", "Remove Dead Files", "Crop Selection",
                      "Sort by Title", "Sort by Artist", "Sort by Album", "Sort by Filename",
                      "Sort by Path", "Reverse", "Randomize", "File Info..."] {
            XCTAssertFalse(try item(title, in: menu).isEnabled, title)
        }
        for title in ["Play", "Select All", "Select None", "Invert Selection"] {
            XCTAssertTrue(try item(title, in: menu).isEnabled, title)
        }
    }

    // MARK: - Selection

    @MainActor
    func testShiftClickSelectsARangeAndCommandClickTogglesARow() throws {
        let (view, _) = surface()
        try click(3, view)
        try click(6, view, .shift)
        XCTAssertEqual(view.selectedRows, Set(3...6))
        try click(4, view, .command)
        XCTAssertEqual(view.selectedRows, [3, 5, 6])
        try click(10, view, .command)
        XCTAssertEqual(view.selectedRows, [3, 5, 6, 10])
        try click(8, view)
        XCTAssertEqual(view.selectedRows, [8])
    }

    /// The selection rows act on the pane without touching the queue.
    @MainActor
    func testSelectAllNoneAndInvert() throws {
        let (view, _) = surface(count: 8)
        view.selectAll(nil)
        XCTAssertEqual(view.selectedRows, Set(0..<8))
        view.selectNone(nil)
        XCTAssertEqual(view.selectedRows, [])
        try click(2, view)
        view.invertSelection(nil)
        XCTAssertEqual(view.selectedRows, Set(0..<8).subtracting([2]))
    }

    /// One highlighted row still follows the playing track (the `nvidia` rule, W224); a selection
    /// of several is the user's and survives the track change, or Remove would act on one row.
    @MainActor
    func testATrackChangeMovesOneSelectedRowButNotSeveral() throws {
        let (view, _) = surface(count: 20, playing: 0)
        try click(4, view)
        view.update(snapshot(count: 20, playing: 1))
        XCTAssertEqual(view.selectedRows, [1])

        try click(3, view); try click(7, view, .shift)
        view.update(snapshot(count: 20, playing: 2))
        XCTAssertEqual(view.selectedRows, Set(3...7))
    }

    /// Select None survives the clock: an empty selection is not re-seeded from the playing row
    /// by the next host refresh.
    @MainActor
    func testSelectNoneSurvivesAHostRefresh() throws {
        let (view, _) = surface(count: 20, playing: 5)
        view.selectNone(nil)
        for _ in 0..<12 { view.update(snapshot(count: 20, playing: 5)) }
        XCTAssertEqual(view.selectedRows, [])
    }

    /// A queue that shrinks under the selection drops the rows that are gone.
    @MainActor
    func testASelectionIsClampedWhenTheQueueShrinks() throws {
        let (view, _) = surface(count: 20, playing: 0)
        try click(2, view); try click(15, view, .shift)
        view.update(snapshot(count: 10, playing: 0))
        XCTAssertEqual(view.selectedRows, Set(2...9))
    }

    /// Delete removes every selected row, highest index first so the lower indices stay valid.
    @MainActor
    func testDeleteRemovesEverySelectedRowFromTheBottomUp() throws {
        let (view, _) = surface()
        var removed: [Int] = []
        view.onAction = { action, _ in
            if case let .removePlaylistItem(index) = action { removed.append(index) }
        }
        try click(2, view); try click(4, view, .command); try click(9, view, .command)
        let delete = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
            isARepeat: false, keyCode: 51))
        view.keyDown(with: delete)
        XCTAssertEqual(removed, [9, 4, 2])
    }

    // MARK: - The Modern playlist keeps its menu

    /// The Modern playlist never validated these rows, so AppKit has always shown them enabled;
    /// the builder keeps that default for it rather than changing its behaviour.
    @MainActor
    func testTheBuilderKeepsAutoenablingByDefault() {
        let (view, _) = surface()
        let menu = PlaylistMenuBuilder.menu(target: view, state: .init(selectionCount: 0, hasTracks: true))
        XCTAssertTrue(menu.autoenablesItems)
        XCTAssertTrue(menu.items.compactMap(\.submenu).allSatisfy(\.autoenablesItems))
    }
}
