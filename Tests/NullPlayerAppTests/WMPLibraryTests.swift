import AppKit
import Foundation
import XCTest
@testable import NullPlayer

/// What a `.wmz` script can see of the library (W136): `player.playlistCollection`,
/// `player.mediaCollection`, the `<LISTBOX>` a skin fills from them, and the `<PLAYLIST>` it points
/// at the result. The library is the browser's selected source, read-only; these tests hand the
/// runtime a catalog directly, so they pin the object model and not a source.
final class WMPLibraryTests: XCTestCase {
    private func runtime(_ name: String = #function) throws -> (WMPScriptRuntime, () -> Void) {
        let suite = "WMPLibraryTests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(name.utf8),
                                                                 defaults: defaults),
                                 executionSeconds: 5),
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func load(_ wms: String) async throws -> WMPLoadedSkin {
        try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]))
    }

    private let chooser = """
    <THEME><VIEW id="main" width="200" height="200">
      <LISTBOX id="box" left="0" top="0" width="100" height="100"/>
      <PLAYLIST id="pl" left="100" top="0" width="100" height="100"/>
      <SUBVIEW id="pane" left="0" top="150" width="10" height="10"/>
    </VIEW></THEME>
    """

    /// Three tracks and two playlists. `B` holds tracks 1 and 2.
    private func catalog(loaded: Bool = true, complete: Bool = true) -> WMPLibraryCatalog {
        var catalog = WMPLibraryCatalog()
        catalog.sourceID = complete ? "local" : "jellyfin:test"
        catalog.isComplete = complete
        catalog.tracks = ["One", "Two", "Three"].map {
            .init(title: $0, artist: "Artist", album: "Album", genre: "Rock",
                  sourceURL: "C:\\\($0).flac", duration: 60, isVideo: false)
        }
        catalog.libraryTracks = [0, 1, 2]
        catalog.playlists = [.init(id: "a", name: "A", tracks: loaded ? [0] : [], loaded: loaded),
                             .init(id: "b", name: "B", tracks: loaded ? [1, 2] : [], loaded: loaded)]
        catalog.indexPlaylists()
        return catalog
    }

    private func transact(_ runtime: WMPScriptRuntime, _ skin: WMPLoadedSkin, _ handler: String,
                          snapshot: WMPHostSnapshot = WMPHostSnapshot()) async -> WMPScriptOutput {
        await runtime.transact(skin: skin, viewID: "main", size: .init(width: 200, height: 200),
                               snapshot: snapshot,
                               event: .init(name: "click", targetID: "main", handlers: [handler]))
    }

    private func stableID(_ skin: WMPLoadedSkin, _ id: String) throws -> Int {
        try XCTUnwrap(skin.graph.nodes(id: id).first?.stableID)
    }

    /// The chooser `WoW`'s `fillListBox()` builds: `deleteAll`, a "Now Playing" row, then one row
    /// per playlist from `playlistCollection.getAll()` titled by `getItemInfo("Title")`.
    func testAPlaylistChooserFillsFromThePlaylistCollection() async throws {
        let skin = try await load(chooser)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        await session.setLibrary(catalog())
        let output = await transact(session, skin, """
            box.deleteAll(); box.appendItem('Now Playing');
            var all = player.playlistCollection.getAll();
            for (var i = 0; i < all.count; i++) box.appendItem(all.item(i).getItemInfo('Title'));
            """)
        XCTAssertEqual(output.listItems[try stableID(skin, "box")], ["Now Playing", "A", "B"])
        await session.teardown()
    }

    /// **A chooser's fill is a list of names, and asks the server for nothing (W274).** Resolving
    /// any member of an unloaded server playlist used to demand its tracks, so the fill loop over
    /// Jellyfin's 1,850 playlists queued 1,850 serial fetches. Only `count` needs them.
    func testAChooserFillOverAServerDemandsNoPlaylistTracks() async throws {
        let skin = try await load(chooser)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let demands = DemandLog()
        await session.setLibraryDemandHandler { set, _, _ in demands.record(set) }
        await session.setLibrary(catalog(loaded: false, complete: false))
        let output = await transact(session, skin, """
            box.deleteAll(); box.appendItem('Now Playing');
            var all = player.playlistCollection.getAll();
            for (var i = 0; i < all.count; i++) box.appendItem(all.item(i).getItemInfo('Title'));
            """)
        XCTAssertEqual(output.listItems[try stableID(skin, "box")], ["Now Playing", "A", "B"])
        XCTAssertFalse(demands.all.contains { $0.hasPrefix("playlist:") },
                       "naming a playlist must not fetch its tracks: \(demands.all)")
        _ = await transact(session, skin, "var n = player.playlistCollection.getAll().item(1).count;")
        XCTAssertEqual(demands.all, ["playlist:b"], "a playlist's count is its tracks")
        await session.teardown()
    }

    /// **`CdromMediaChange` is the chooser skins' refill, and the host raises it (W274).** All nine
    /// `<LISTBOX>` skins author `CdromMediaChange="onCdRomChange()"` on their `<PLAYER>`; the name
    /// has to be classified as a handler or the dispatcher never finds it.
    @MainActor
    func testCdromMediaChangeIsAHandlerTheHostCanRaise() async throws {
        let skin = try await load("""
            <THEME><VIEW id="main" width="200" height="200">
              <PLAYER id="p" CdromMediaChange="onCdRomChange()"/>
            </VIEW></THEME>
            """)
        XCTAssertEqual(WMPMainWindowController.handlers(in: skin, event: "cdrommediachange",
                                                        targetID: nil, viewID: "main"),
                       ["onCdRomChange()"])
    }

    /// `player.currentPlaylist = <playlist>` replaces the queue with the playlist's tracks —
    /// carried as catalog indices, since the skin's `sourceURL` is WMP's spelling, not a location.
    func testAssigningALoadedPlaylistLoadsItsTracksAndPlays() async throws {
        let skin = try await load(chooser)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        await session.setLibrary(catalog())
        let output = await transact(session, skin, """
            player.currentPlaylist = player.playlistCollection.getByName('B').item(0);
            player.controls.play();
            """)
        XCTAssertEqual(output.hostCommands.first { $0.action == "loadLibraryTracks" }?.value?.string,
                       "1,2")
        XCTAssertTrue(output.hostCommands.contains { $0.action == "play" })
        await session.teardown()
    }

    /// **The reported defect: a playlist still loading played the previous queue.** A server
    /// playlist has no tracks until its fetch lands; the assignment used to adopt it anyway and the
    /// `play()` after it played whatever was queued. Now the play is withheld and asked for later.
    func testAnUnloadedPlaylistWithholdsPlayAndAsksToPlayWhenItArrives() async throws {
        let skin = try await load(chooser)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let demands = DemandLog()
        await session.setLibraryDemandHandler { set, _, _ in demands.record(set) }
        await session.setLibrary(catalog(loaded: false, complete: false))
        let output = await transact(session, skin, """
            player.currentPlaylist = player.playlistCollection.getByName('B').item(0);
            player.controls.play();
            """)
        XCTAssertFalse(output.hostCommands.contains { $0.action == "play" },
                       "the play() after an assignment that cannot play yet must be withheld")
        XCTAssertFalse(output.hostCommands.contains { $0.action == "loadLibraryTracks" })
        XCTAssertTrue(demands.all.contains("playlist:b"))
        XCTAssertTrue(demands.all.contains("play:library.playlist:b"))
        await session.teardown()
    }

    /// A pane pointed at a library playlist shows it — and goes back to the live queue the moment
    /// the queue changes from anywhere, so an artist added from the browser is never hidden.
    func testAPaneShowsItsLibraryPlaylistUntilTheQueueChanges() async throws {
        let skin = try await load(chooser)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        await session.setLibrary(catalog())
        let pl = try stableID(skin, "pl")
        let shown = await transact(session, skin,
            "pl.playlist = player.playlistCollection.getByName('B').item(0);")
        XCTAssertEqual(shown.widgetState.playlists[pl]?.items.map(\.title), ["Two", "Three"])

        var changed = WMPHostSnapshot()
        changed.playlistItems = [.init(title: "Added", artist: "", duration: 1)]
        let after = await transact(session, skin, "pane.left = 1;", snapshot: changed)
        XCTAssertNil(after.widgetState.playlists[pl], "a queue change puts the live queue back")
        await session.teardown()
    }

    /// A host object stored on an element reads back as that object: `WoW` keeps its selection in
    /// `playlist1.playlist` and plays it from there in a later transaction.
    func testAPlaylistStoredOnAnElementReadsBackAsThePlaylist() async throws {
        let skin = try await load(chooser)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        await session.setLibrary(catalog())
        let output = await transact(session, skin, """
            pl.playlist = player.playlistCollection.getByName('B').item(0);
            pane.left = pl.playlist.count;
            """)
        XCTAssertEqual(output.overrides.geometry[.init(stableID: try stableID(skin, "pane"),
                                                       property: "left")], 2)
        await session.teardown()
    }

    /// **Search on a server** (W136). A skin's search is `mediaCollection.getAll()` filtered in
    /// script; a server cannot hand over its whole library, so `getAll()` answers with the server's
    /// search for the text in the view's search box. The first answer is empty and demands the
    /// search; once the host has put the results in the catalog, the same code sees them.
    func testGetAllOnAServerIsTheSearchForTheSearchBoxText() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="200" height="200">
          <EDITBOX id="q" left="0" top="0" width="100" height="20" value="Rush"/>
          <SUBVIEW id="pane" left="0" top="150" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let demands = DemandLog()
        await session.setLibraryDemandHandler { set, _, _ in demands.record(set) }
        var library = catalog(complete: false)
        await session.setLibrary(library)
        let pane = try stableID(skin, "pane")
        let first = await transact(session, skin, "pane.left = player.mediaCollection.getAll().count + 10;")
        XCTAssertEqual(first.overrides.geometry[.init(stableID: pane, property: "left")], 10)
        XCTAssertTrue(demands.all.contains("query:search:rush"))

        library.queryResults["search:rush"] = [2]
        await session.setLibrary(library)
        let second = await transact(session, skin, "pane.left = player.mediaCollection.getAll().count + 10;")
        XCTAssertEqual(second.overrides.geometry[.init(stableID: pane, property: "left")], 11,
                       "the second run of the same search sees the server's results")
        await session.teardown()
    }

    /// **Only the user's own act is a search.** A skin's `onLoad`, a timer or the refresh after a
    /// source switch that reads `getAll()` with an old term still in the box must not run that
    /// search again — the reported "the search keeps coming back when I switch sources".
    func testGetAllOutsideAUserEventIsNotASearch() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="200" height="200">
          <EDITBOX id="q" left="0" top="0" width="100" height="20" value="Rush"/>
          <SUBVIEW id="pane" left="0" top="150" width="10" height="10"/>
        </VIEW></THEME>
        """)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let demands = DemandLog()
        await session.setLibraryDemandHandler { set, _, _ in demands.record(set) }
        var library = catalog(complete: false)
        library.libraryTracks = []
        await session.setLibrary(library)
        for name in ["load", "timer", "librarychange"] {
            _ = await session.transact(skin: skin, viewID: "main", size: .init(width: 200, height: 200),
                snapshot: WMPHostSnapshot(),
                event: .init(name: name, targetID: "main",
                             handlers: ["pane.left = player.mediaCollection.getAll().count;"]))
        }
        XCTAssertTrue(demands.all.isEmpty, "no search may be asked for outside a user event")
        await session.teardown()
    }

    /// A search result is a list of the old catalog's track numbers, so a source switch drops it.
    func testSwitchingSourceDropsSearchResults() async throws {
        let skin = try await load(chooser)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        await session.setLibrary(catalog())
        let pl = try stableID(skin, "pl")
        let searched = await transact(session, skin, """
            var found = player.newPlaylist('', '');
            found.appendItem(player.mediaCollection.getAll().item(2));
            pl.playlist = found;
            """)
        XCTAssertEqual(searched.widgetState.playlists[pl]?.items.map(\.title), ["Three"])
        await session.setLibrary(catalog(complete: false))
        let after = await transact(session, skin, "pane.left = 1;")
        XCTAssertNil(after.widgetState.playlists[pl])
        await session.teardown()
    }

    /// Local Files is held whole, so its `getAll()` is the library and search is the skin's filter.
    func testGetAllOnLocalFilesIsTheWholeLibrary() async throws {
        let skin = try await load(chooser)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        await session.setLibrary(catalog())
        let output = await transact(session, skin,
                                    "pane.left = player.mediaCollection.getAll().count;")
        XCTAssertEqual(output.overrides.geometry[.init(stableID: try stableID(skin, "pane"),
                                                       property: "left")], 3)
        await session.teardown()
    }

    /// A `<LISTBOX>` selection reaches the view only in the transaction that *wrote* it. Reported
    /// as state on every transaction, one that started before a fast click put the old row back.
    func testAListBoxSelectionIsReportedOnlyWhenTheScriptWritesIt() async throws {
        let skin = try await load(chooser)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        let box = try stableID(skin, "box")
        let wrote = await transact(session, skin,
                                   "box.appendItem('x'); box.appendItem('y'); box.selectedItem = 1;")
        XCTAssertEqual(wrote.widgetState.listSelections[box], 1)
        let later = await transact(session, skin, "pane.left = 1;")
        XCTAssertNil(later.widgetState.listSelections[box])
        await session.teardown()
    }

    /// A different source is a different library: a pane pointed at the old one's playlist goes
    /// back to the live queue rather than naming a playlist the new source does not have.
    func testSwitchingSourceReleasesAPanesLibraryPlaylist() async throws {
        let skin = try await load(chooser)
        let (session, cleanup) = try runtime(); defer { cleanup() }
        await session.setLibrary(catalog())
        _ = await transact(session, skin, "pl.playlist = player.playlistCollection.getByName('A').item(0);")
        await session.setLibrary(catalog(complete: false))
        let after = await transact(session, skin, "pane.left = 1;")
        XCTAssertNil(after.widgetState.playlists[try stableID(skin, "pl")])
        await session.teardown()
    }
}

/// The library demands a runtime reported, collected across its actor.
private final class DemandLog: @unchecked Sendable {
    private let lock = NSLock()
    private var demands: Set<String> = []
    func record(_ set: Set<String>) { lock.lock(); demands.formUnion(set); lock.unlock() }
    var all: Set<String> { lock.lock(); defer { lock.unlock() }; return demands }
}

/// The two hosted surfaces W136 taught to follow the script.
@MainActor
final class WMPLibrarySurfaceTests: XCTestCase {
    /// A double-click hands over the row under the pointer. `onDblClick` used to read
    /// `selectedItem`, which a refill had just reset to "Now Playing", and played the old queue.
    func testAListBoxDoubleClickCarriesTheClickedRow() throws {
        let list = WMPListBoxSurfaceView(frame: NSRect(x: 0, y: 0, width: 100, height: 140))
        list.update(items: ["Now Playing", "A", "B"])
        var played: Int?
        list.onDoubleClick = { played = $0 }
        let window = NSWindow(contentRect: list.frame, styleMask: [], backing: .buffered, defer: true)
        window.contentView = list
        for clicks in 1...2 {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: 10, y: 140 - 14 * 2 - 7),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: clicks, pressure: 1))
            list.mouseDown(with: event)
        }
        XCTAssertEqual(played, 2)
    }

    /// **A widget hosted after its rows arrived starts with them (W274).** The transaction path
    /// hands over the rows and then presents, and the present is where a widget is first created:
    /// `NVIDIA`'s chooser and search box appear in the very frame that sizes them, and were
    /// created empty with nothing left to fill them.
    func testAWidgetHostedAfterItsRowsArrivedStartsWithThem() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8,
                                              bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let view = WMPMainView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        view.updateListItems([1: ["Now Playing", "A"]])
        var state = WMPWidgetScriptState()
        state.editValues[2] = "Search for"
        view.updateWidgetState(state)
        let widgets = [
            WMPWidget(stableID: 1, nodeID: "box", kind: .listBox,
                      frame: .init(x: 0, y: 0, width: 100, height: 60), clipRect: nil,
                      label: "Box", toolTip: nil, minimumValue: nil, maximumValue: nil),
            WMPWidget(stableID: 2, nodeID: "search", kind: .editBox,
                      frame: .init(x: 0, y: 70, width: 100, height: 20), clipRect: nil,
                      label: "Search", toolTip: nil, minimumValue: nil, maximumValue: nil)]
        let size = WMPSize(width: 200, height: 100)
        view.present(try XCTUnwrap(context.makeImage()), scene: WMPScene(
            viewID: "main", canvasSize: size, resizeLimits: .init(minimum: size, maximum: size),
            commands: [], hits: [], widgets: widgets, geometries: [:], unresolved: [],
            diagnostics: [], dirtyBounds: nil,
            metrics: .init(resolvedNodeCount: 2, unresolvedNodeCount: 0, visibleBounds: nil),
            wasBuiltOnMainThread: false))
        let list = try XCTUnwrap(view.hostedWidgetViews.compactMap { $0 as? WMPListBoxSurfaceView }.first)
        let edit = try XCTUnwrap(view.hostedWidgetViews.compactMap { $0 as? WMPEditBoxSurfaceView }.first)
        XCTAssertEqual(list.items, ["Now Playing", "A"])
        XCTAssertEqual(edit.stringValue, "Search for")
    }

    /// A refill is a different list: it starts at the top with nothing selected, and a script
    /// selection outside the rows is ignored.
    func testAListBoxRefillResetsSelectionAndIgnoresAnOutOfRangeRow() {
        let list = WMPListBoxSurfaceView(frame: NSRect(x: 0, y: 0, width: 100, height: 28))
        list.update(items: ["a", "b"])
        list.update(selection: 1)
        XCTAssertEqual(list.selected, 1)
        list.update(items: ["c", "d", "e"])
        XCTAssertEqual(list.selected, -1, "a refill starts unselected")
        list.update(selection: 9)
        XCTAssertEqual(list.selected, -1, "a row the list does not have is ignored")
    }

    /// A `<PLAYLIST>` showing a library playlist plays *that* playlist from the chosen row, and
    /// hands delete to nothing — a skin may not edit the library.
    func testAPlaylistPaneShowingALibraryPlaylistPlaysItFromTheRow() {
        let pane = WMPPlaylistSurfaceView(frame: NSRect(x: 0, y: 0, width: 200, height: 90))
        pane.update(WMPHostSnapshot())
        pane.update(libraryRows: .init(reference: "library.playlist:b",
                                       items: [.init(title: "Two", artist: "", duration: 1),
                                               .init(title: "Three", artist: "", duration: 1)],
                                       tracks: [1, 2]))
        var played: (String, Int)?
        var actions: [WMPTransportAction] = []
        pane.onPlayLibrary = { played = ($0.reference, $1) }
        pane.onAction = { action, _ in actions.append(action) }
        pane.keyDown(with: key(125))
        pane.keyDown(with: key(125))
        pane.keyDown(with: key(36))
        pane.keyDown(with: key(51))
        XCTAssertEqual(played?.0, "library.playlist:b")
        XCTAssertEqual(played?.1, 1)
        XCTAssertTrue(actions.isEmpty, "neither play nor delete may touch the queue directly")
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                         isARepeat: false, keyCode: code)!
    }
}
