import AppKit
import XCTest
@testable import NullPlayer

@MainActor
final class LibraryArtLensTests: XCTestCase {
    private struct Row: LibraryArtRow {
        let id: String
        var indentLevel = 0
        var hasChildren = false
        var isArtItem = true
        var isAlbumItem = false
        var isVideoContainer = false
    }

    private var rows: [Row] = []
    private var expanded: Set<String> = []
    private var played: [String] = []
    private var menus: [String] = []
    private var savedMode: LibraryViewMode = .list

    override func setUp() {
        savedMode = LibraryViewMode.saved
        LibraryViewMode.saved = .list
        // An artist with two albums, and a second artist; plus a playlist row that has no art.
        rows = [Row(id: "artist-a", hasChildren: true), Row(id: "artist-b", hasChildren: true),
                Row(id: "playlist", isArtItem: false)]
        expanded = []
        played = []
        menus = []
    }

    override func tearDown() { LibraryViewMode.saved = savedMode }

    private func makeLens(container: NSView = NSView()) -> LibraryArtLens<Row> {
        LibraryArtLens(container: container, host: .init(
            rows: { [unowned self] in rows },
            isSearch: { false },
            selectedIndex: { nil },
            isBlocked: { false },
            style: { .fallback },
            item: { LibraryArtItem(id: $0.id, title: $0.id, subtitle: "", cachedArtwork: { nil }, art: nil) },
            isExpanded: { [unowned self] in expanded.contains($0.id) },
            toggleExpand: { [unowned self] row in
                // Expanding inserts the children below the row, as the browsers do.
                expanded.insert(row.id)
                let index = rows.firstIndex { $0.id == row.id }! + 1
                let children = row.id == "artist-a"
                    ? [Row(id: "album-1", indentLevel: 1, hasChildren: true, isAlbumItem: true),
                       Row(id: "album-2", indentLevel: 1, hasChildren: true, isAlbumItem: true)]
                    : [Row(id: "\(row.id)-track-1", indentLevel: 2), Row(id: "\(row.id)-track-2", indentLevel: 2)]
                rows.insert(contentsOf: children, at: index)
            },
            play: { [unowned self] in played.append($0.id) },
            menu: { [unowned self] row, _ in menus.append(row.id) },
            albumInfo: { _ in nil },
            loadNextPage: {}
        ))
    }

    private func shownIds(_ lens: LibraryArtLens<Row>) -> [String] {
        switch lens.view {
        case let flow as CoverFlowView: return flow.items.map(\.id)
        case let tiles as ArtTileGridView: return tiles.items.map(\.id)
        case let album as ArtAlbumView: return album.items.map(\.id)
        default: return []
        }
    }

    func testDrillInBackAndPlayWalkTheTree() throws {
        let lens = makeLens()
        lens.mode = .flow
        XCTAssertEqual(shownIds(lens), ["artist-a", "artist-b"])

        lens.activate(at: 0)
        XCTAssertEqual(expanded, ["artist-a"])
        XCTAssertEqual(shownIds(lens), [LibraryArtItem.back.id, "album-1", "album-2"])
        XCTAssertEqual(lens.view?.centerIndex, 1, "a drill-in centres the first child")

        lens.activate(at: 2)
        XCTAssertTrue(lens.view is ArtAlbumView, "an album opens its own screen")
        XCTAssertEqual(shownIds(lens), [LibraryArtItem.back.id, "album-2-track-1", "album-2-track-2"])

        lens.activate(at: 2)
        XCTAssertEqual(played, ["album-2-track-2"], "a track plays on its own")
        lens.view?.onMenu?(1, NSEvent())
        XCTAssertEqual(menus, ["album-2-track-1"], "right-click shows the row's own menu")

        lens.activate(at: 0)
        XCTAssertTrue(lens.view is CoverFlowView, "Back leaves the album screen for the mode's view")
        XCTAssertEqual(lens.view?.centerIndex, 2, "…centred on the album it left")

        lens.activate(at: 0)
        XCTAssertEqual(shownIds(lens), ["artist-a", "artist-b"])
        XCTAssertEqual(lens.view?.centerIndex, 0, "Back re-centres on the container it left")
    }

    func testSwitchingFlowToTilesKeepsLevelAndItem() throws {
        let lens = makeLens()
        lens.mode = .flow
        lens.activate(at: 0)
        lens.view?.setCenterIndex(2, animated: false)

        lens.mode = .tiles
        XCTAssertTrue(lens.view is ArtTileGridView)
        XCTAssertEqual(shownIds(lens), [LibraryArtItem.back.id, "album-1", "album-2"])
        XCTAssertEqual(lens.view?.centerIndex, 2)
        XCTAssertEqual(LibraryViewMode.saved, .tiles)

        lens.mode = .list
        XCTAssertNil(lens.view)
        XCTAssertTrue(lens.focusStack.isEmpty)
    }

    func testKeyboardFocusFollowsTheAlbumScreenInAndOut() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let lens = makeLens(container: window.contentView!)
        lens.mode = .tiles
        XCTAssertTrue(window.firstResponder === lens.view)

        lens.activate(at: 0)
        lens.activate(at: 1)
        XCTAssertTrue(lens.view is ArtAlbumView)
        XCTAssertTrue(window.firstResponder === lens.view, "opening an album keeps the keyboard")

        lens.activate(at: 0)
        XCTAssertTrue(lens.view is ArtTileGridView)
        XCTAssertTrue(window.firstResponder === lens.view, "…and so does Back")
    }

    func testListWithoutArtRowsPresentsTheList() {
        rows = [Row(id: "playlist", isArtItem: false)]
        let lens = makeLens()
        lens.mode = .tiles
        XCTAssertFalse(lens.isPresenting)
        XCTAssertEqual(lens.view?.isHidden, true)
    }

    func testAlbumLengthReadsInMinutesThenHours() {
        XCTAssertNil(LibraryAlbumInfo.length(seconds: 0))
        XCTAssertEqual(LibraryAlbumInfo.length(seconds: 20), "1 min")
        XCTAssertEqual(LibraryAlbumInfo.length(seconds: 42 * 60 + 10), "42 min")
        XCTAssertEqual(LibraryAlbumInfo.length(seconds: 65 * 60), "1 hr 5 min")
    }
}
