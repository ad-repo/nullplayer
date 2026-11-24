import AppKit
import XCTest
@testable import NullPlayer

/// The shared playlist / library / equaliser route (`SkinSurfaceRouter`): each family's router must
/// answer exactly what its old family-specific route answered in `WindowManager`.
@MainActor
final class SkinSurfaceRoutingTests: XCTestCase {

    // MARK: - `.wal`

    /// What the coordinator asked of its environment.
    private final class WALCalls {
        var visible: [String: Bool] = [:]
        var revealed: [WinampModernComponentKind] = []
        var concealed: [WinampModernComponentKind] = []
        var classic: [(WinampModernComponentKind, Bool)] = []
    }

    private func walCoordinator(_ catalog: WinampModernSurfaceCatalog, windows: [String: NSWindow] = [:],
                                pageShown: @escaping () -> Bool = { false },
                                calls: WALCalls) -> WinampModernSurfaceCoordinator {
        WinampModernSurfaceCoordinator(catalog: catalog, environment: .init(
            revealEmbedded: { kind, _, _ in calls.revealed.append(kind); return true },
            concealEmbedded: { calls.concealed.append($0) },
            isMainWindowVisible: { true },
            showsEmbedded: { _ in pageShown() },
            showsEmbeddedEqualizer: { false },
            window: { windows[$0] },
            setVisible: { id, visible in
                calls.visible[id] = visible
                if visible { windows[id]?.orderFront(nil) } else { windows[id]?.orderOut(nil) }
            },
            closeCarriedOver: { _ in },
            classicFallback: { kind, show in calls.classic.append((kind, show)) },
            redraw: {}))
    }

    /// A declared and a synthesized container: the router opens the skin's window, gives it the
    /// restored frame, toggles it, and answers visibility from it; the surface it does not own is
    /// NullPlayer's, and the router never reaches the classic provider for it.
    func testWALContainerSurfacesRouteThroughTheirWindows() throws {
        let playlistWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                      styleMask: [.borderless], backing: .buffered, defer: true)
        defer { playlistWindow.orderOut(nil) }
        let catalog = WinampModernSurfaceCatalog(playlist: .declaredContainer(id: "Pledit"),
                                                 equalizer: .classicFallback(reason: "none"),
                                                 library: .synthesizedContainer(id: "nullplayer.library"),
                                                 video: .classicFallback(reason: "none"),
                                                 visualization: .classicFallback(reason: "none"))
        let calls = WALCalls()
        let router: SkinSurfaceRouter = walCoordinator(catalog, windows: ["Pledit": playlistWindow], calls: calls)

        XCTAssertTrue(router.drawsSurface(.playlist))
        XCTAssertTrue(router.drawsSurface(.library))
        XCTAssertFalse(router.drawsSurface(.equalizer), "a classic fallback is NullPlayer's window")
        XCTAssertFalse(router.drawsSurface(.video), "video keeps `.wal`'s own path")
        XCTAssertTrue(router.toggleClosesSurface(.playlist))
        XCTAssertFalse(router.isShowingSurface(.playlist))

        let restored = NSRect(x: 40, y: 60, width: 300, height: 200)
        router.revealSurface(.playlist, toggle: false, restoredFrame: restored)
        XCTAssertEqual(calls.visible["Pledit"], true)
        XCTAssertEqual(playlistWindow.frame, restored, "a skin-owned window keeps its saved geometry")
        XCTAssertTrue(router.isShowingSurface(.playlist))

        router.revealSurface(.playlist, toggle: true, restoredFrame: nil)
        XCTAssertEqual(calls.visible["Pledit"], false, "a toggle of an open container window closes it")
        XCTAssertFalse(router.isShowingSurface(.playlist))

        router.revealSurface(.library, toggle: false, restoredFrame: restored)
        XCTAssertEqual(calls.visible["nullplayer.library"], true)
        XCTAssertTrue(calls.classic.isEmpty)
        XCTAssertFalse(router.deferUntilSkinLoads(.playlist) { XCTFail("`.wal` never defers") })
    }

    /// An embedded page is revealed inside the player, never fed a frame, and a toggle of a page the
    /// skin shows asks the skin to put it away (B350).
    func testWALEmbeddedSurfaceRevealsInsideThePlayer() throws {
        let catalog = WinampModernSurfaceCatalog(playlist: .embedded(containerID: WasabiObjectID(rawValue: 1)),
                                                 equalizer: .classicFallback(reason: "none"),
                                                 library: .classicFallback(reason: "none"),
                                                 video: .classicFallback(reason: "none"),
                                                 visualization: .classicFallback(reason: "none"))
        let calls = WALCalls()
        var pageShown = false
        let router: SkinSurfaceRouter = walCoordinator(catalog, pageShown: { pageShown }, calls: calls)

        router.revealSurface(.playlist, toggle: false, restoredFrame: NSRect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertEqual(calls.revealed, [.playlist])
        XCTAssertTrue(calls.visible.isEmpty, "an embedded surface has no window")
        XCTAssertFalse(router.isShowingSurface(.playlist))

        pageShown = true
        XCTAssertTrue(router.isShowingSurface(.playlist))
        router.revealSurface(.playlist, toggle: true, restoredFrame: nil)
        XCTAssertEqual(calls.concealed, [.playlist])
        XCTAssertFalse(router.drawsSurface(.library))
    }

    // MARK: - `.wmz`

    private func wmpController(wms: String, filename: String) async throws
        -> (WMPMainWindowController, () -> Void) {
        let root = try WMPSkinTestSupport.temporaryDirectory()
        let suite = "SkinSurfaceRoutingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let importer = WMPSkinImporter(directoryURL: root, defaults: defaults)
        let source = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))],
                                                        filename: filename)
        _ = try await importer.importSkin(from: source)
        let controller = WMPMainWindowController(importer: importer)
        return (controller, {
            controller.prepareForUITeardown()
            controller.window?.close()
            defaults.removePersistentDomain(forName: suite)
        })
    }

    private func waitUntil(_ condition: @MainActor @escaping () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            if ContinuousClock.now >= deadline { XCTFail("Timed out waiting for controller state"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A skin with a playlist view and no equaliser or video: the router draws the playlist only,
    /// never the library; a toggle of a shown playlist is a reveal (nothing to close), which the
    /// router says so the View menu leaves the item inert; and an open asked for during the launch
    /// hold is replayed once, when the skin has loaded.
    func testWMPRouterAnswersFromTheSkinsDeclaredSurfaces() async throws {
        let (controller, cleanup) = try await wmpController(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW left="0" top="0" width="120" height="80" backgroundColor="#224466"/>
          </VIEW>
          <VIEW id="playlist" width="140" height="90">
            <PLAYLIST id="rows" left="0" top="0" width="140" height="70"/>
          </VIEW>
        </THEME>
        """, filename: "SurfaceRouting.wmz")
        defer { cleanup() }
        let router = WMPSkinSurfaceRouter(controller: controller)

        var replays = 0
        XCTAssertTrue(router.deferUntilSkinLoads(.playlist) { replays += 1 }, "held until the skin says")
        try await waitUntil { controller.selectedViewID == "main" }
        try await waitUntil { replays == 1 }
        XCTAssertFalse(router.deferUntilSkinLoads(.playlist) { XCTFail("no hold once loaded") })

        XCTAssertTrue(router.drawsSurface(.playlist))
        XCTAssertFalse(router.drawsSurface(.equalizer), "no `<EQUALIZERSETTINGS>`: NullPlayer's EQ")
        XCTAssertFalse(router.drawsSurface(.library))
        XCTAssertFalse(router.drawsSurface(.video), "no `<VIDEO>`: NullPlayer's video window")
        XCTAssertFalse(router.toggleClosesSurface(.playlist))
        XCTAssertFalse(router.isShowingSurface(.playlist))

        router.revealSurface(.playlist, toggle: true, restoredFrame: nil)
        try await waitUntil { controller.openViewIDs == ["main", "playlist"] }
        XCTAssertTrue(router.isShowingSurface(.playlist))
        router.revealSurface(.playlist, toggle: true, restoredFrame: nil)
        XCTAssertEqual(controller.openViewIDs, ["main", "playlist"], "a toggle never closes the skin's panel")
        XCTAssertEqual(replays, 1)
    }

    // MARK: - Sonique

    /// The navigator's drawer is the equaliser in every skin: a toggle goes to the navigator and opens
    /// it, a second toggle closes it, and a show (the restore path) never changes the mode the user
    /// left. The playlist and the library are NullPlayer's.
    func testSoniqueRoutesTheEqualizerToTheNavigatorDrawer() throws {
        let saved = UserDefaults.standard.object(forKey: SoniqueSkinMainWindowController.modeKey)
        defer { UserDefaults.standard.set(saved, forKey: SoniqueSkinMainWindowController.modeKey) }
        let controller = SoniqueSkinMainWindowController()
        defer { controller.prepareForUITeardown(); controller.window?.close() }
        let router: SkinSurfaceRouter = controller

        XCTAssertTrue(router.drawsSurface(.equalizer))
        XCTAssertFalse(router.drawsSurface(.playlist))
        XCTAssertFalse(router.drawsSurface(.library))

        controller.mode = .small
        router.revealSurface(.equalizer, toggle: false, restoredFrame: nil)
        XCTAssertEqual(controller.mode, .small, "a show keeps the mode")
        XCTAssertFalse(router.isShowingSurface(.equalizer))

        router.revealSurface(.equalizer, toggle: true, restoredFrame: nil)
        XCTAssertEqual(controller.mode, .navigator)
        XCTAssertTrue(router.isShowingSurface(.equalizer))
        router.revealSurface(.equalizer, toggle: true, restoredFrame: nil)
        XCTAssertFalse(router.isShowingSurface(.equalizer))
        XCTAssertFalse(router.deferUntilSkinLoads(.equalizer) { XCTFail("Sonique never defers") })
    }
}
