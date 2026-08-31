import AppKit
import Foundation
import XCTest
@testable import NullPlayer

@MainActor
final class WMPPhase3Tests: XCTestCase {
    func testUnskinnedControllerIsDedicatedFactoryRouteAndTeardownIsIdempotent() {
        let controller = WindowManager.makeMainWindowController(for: .wmp)
        XCTAssertTrue(controller is WMPMainWindowController)
        XCTAssertTrue(controller.window?.contentView is WMPUnskinnedMainView)
        XCTAssertFalse(controller is MainWindowController)
        XCTAssertFalse(controller is ModernMainWindowController)
        controller.prepareForUITeardown()
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    func testTwentyClassicModernMetalWMPFactoryTeardownCyclesStayExplicit() {
        let cycle: [PlayerUIMode] = [.classic, .modern, .metal, .wmp, .classic]
        let expected: [PlayerUIControllerFamily] = [.classic, .nullPlayerModern, .nullPlayerModern, .wmp, .classic]
        for _ in 0..<20 {
            XCTAssertEqual(cycle.map(\.controllerFamily), expected)
            for mode in cycle {
                autoreleasepool {
                    let controller = WindowManager.makeMainWindowController(for: mode)
                    switch mode.controllerFamily {
                    case .classic: XCTAssertTrue(controller is MainWindowController)
                    case .nullPlayerModern: XCTAssertTrue(controller is ModernMainWindowController)
                    case .wmp: XCTAssertTrue(controller is WMPMainWindowController)
                    }
                    controller.prepareForUITeardown()
                    controller.window?.close()
                }
            }
        }
    }

    func testDebugCapabilityExposesDistinctWMPMenu() {
        XCTAssertTrue(AppCapabilities.supports(.wmpSkinMode))
        XCTAssertEqual(PlayerUIMode.debugArgumentOverride(from: ["uiMode": "wmp"]), .wmp)
        XCTAssertNil(PlayerUIMode.debugArgumentOverride(from: ["uiMode": "unknown"]))
        XCTAssertFalse(ContextMenuBuilder.supportsSkinnedAuxiliaryWindows(for: .wmp))
        XCTAssertTrue(ContextMenuBuilder.supportsSkinnedAuxiliaryWindows(for: .classic))
        XCTAssertTrue(ContextMenuBuilder.supportsSkinnedAuxiliaryWindows(for: .modern))
        let uiMenu = ContextMenuBuilder.buildMenuBarUIMenu()
        let wmpItem = uiMenu.items.first { $0.title == PlayerUIMode.wmp.displayName }
        XCTAssertNotNil(wmpItem)
        XCTAssertNotNil(wmpItem?.submenu?.items.first { $0.title == "Load WMZ Skin…" })
        XCTAssertNotNil(wmpItem?.submenu?.items.first { $0.title == "Unskinned Default Player" })
        XCTAssertNotNil(wmpItem?.submenu?.items.first { $0.title == "Open WMP Skins Folder…" })
    }

    func testMissingAndCorruptSelectionsRemainInDedicatedUnskinnedController() async throws {
        let root = try WMPSkinTestSupport.temporaryDirectory()
        let suite = "WMPPhase3Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("Missing", forKey: WMPSkinImporter.selectedSkinNameKey)
        var controller: WMPMainWindowController? = WMPMainWindowController(
            importer: WMPSkinImporter(directoryURL: root, defaults: defaults))
        try await waitUntil { controller?.lastLoadDiagnostic != nil }
        XCTAssertTrue(controller?.window?.contentView is WMPUnskinnedMainView)
        XCTAssertTrue(controller?.lastLoadDiagnostic?.contains("no longer installed") == true)
        controller?.prepareForUITeardown()
        controller?.window?.close()

        let corrupt = root.appendingPathComponent("Corrupt.wmz")
        try Data("not a zip".utf8).write(to: corrupt)
        defaults.set("Corrupt", forKey: WMPSkinImporter.selectedSkinNameKey)
        controller = WMPMainWindowController(importer: WMPSkinImporter(directoryURL: root, defaults: defaults))
        try await waitUntil { controller?.lastLoadDiagnostic != nil }
        XCTAssertTrue(controller?.window?.contentView is WMPUnskinnedMainView)
        controller?.prepareForUITeardown()
        controller?.window?.close()
    }

    func testValidInstalledSkinTransitionsFromFallbackToStaticWMPView() async throws {
        let root = try WMPSkinTestSupport.temporaryDirectory()
        let suite = "WMPPhase3Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let importer = WMPSkinImporter(directoryURL: root, defaults: defaults)
        let source = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="120" height="80">
              <SUBVIEW left="0" top="0" width="120" height="80" backgroundColor="#224466"/>
            </VIEW></THEME>
            """.utf8))
        ], filename: "Static.wmz")
        _ = try await importer.importSkin(from: source)

        let controller = WMPMainWindowController(importer: importer)
        try await waitUntil { controller.window?.contentView is WMPMainView }
        XCTAssertEqual(controller.window?.frame.size, NSSize(width: 120, height: 80))
        XCTAssertNil(controller.lastLoadDiagnostic)
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    func testRestorePolicyPreservesSafeTopLeftAndClampsOffscreenFrames() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let safe = WMPWindowRestorePolicy.safeFrame(
            NSRect(x: 100, y: 200, width: 400, height: 300), screens: [screen])
        XCTAssertEqual(safe, NSRect(x: 100, y: 200, width: 400, height: 300))

        let repaired = WMPWindowRestorePolicy.safeFrame(
            NSRect(x: 2000, y: 1600, width: 400, height: 300), screens: [screen])
        XCTAssertLessThanOrEqual(repaired.maxY, screen.maxY)
        XCTAssertLessThanOrEqual(repaired.minX, screen.maxX - 24)
    }

    func testFrameRestoreRequiresExactWMPSelectionIdentity() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WMPPhase3Identity-\(UUID().uuidString)", isDirectory: true)
        let suite = "WMPPhase3Identity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = WMPMainWindowController(
            importer: WMPSkinImporter(directoryURL: root, defaults: defaults))
        let original = controller.window!.frame
        controller.restoreFrame(NSRect(x: 40, y: 60, width: 700, height: 500),
                                skinName: "Different Skin", viewID: nil)
        XCTAssertEqual(controller.window!.frame, original)

        controller.restoreFrame(NSRect(x: 40, y: 60, width: 700, height: 500),
                                skinName: nil, viewID: nil)
        XCTAssertEqual(controller.window!.frame.size, WMPMainWindowController.unskinnedSize)
        XCTAssertNotEqual(controller.window!.frame.origin, original.origin)
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    func testWMPStateFieldsRoundTripAndOlderStateDecodesWithoutThem() throws {
        let state = makeState(wmpSkinName: "Nine Series", wmpViewID: "vPlayer")
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppStateManager.AppState.self, from: encoded)
        XCTAssertEqual(decoded.wmpSkinName, "Nine Series")
        XCTAssertEqual(decoded.wmpViewID, "vPlayer")
        XCTAssertEqual(decoded.stateVersion, 4)

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "wmpSkinName")
        legacyObject.removeValue(forKey: "wmpViewID")
        legacyObject["stateVersion"] = 3
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder().decode(AppStateManager.AppState.self, from: legacyData)
        XCTAssertNil(legacy.wmpSkinName)
        XCTAssertNil(legacy.wmpViewID)
        XCTAssertEqual(legacy.stateVersion, 3)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor @escaping () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { XCTFail("Timed out waiting for WMP controller state"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeState(wmpSkinName: String?, wmpViewID: String?) -> AppStateManager.AppState {
        AppStateManager.AppState(
            isPlaylistVisible: false,
            isEqualizerVisible: false,
            isPlexBrowserVisible: false,
            isProjectMVisible: false,
            mainWindowFrame: NSStringFromRect(NSRect(x: 10, y: 20, width: 120, height: 80)),
            playlistWindowFrame: nil,
            equalizerWindowFrame: nil,
            plexBrowserWindowFrame: nil,
            projectMWindowFrame: nil,
            volume: 0.75,
            balance: 0,
            shuffleEnabled: false,
            repeatEnabled: false,
            gaplessPlaybackEnabled: true,
            volumeNormalizationEnabled: false,
            sweetFadeEnabled: false,
            sweetFadeDuration: 5,
            eqEnabled: false,
            eqAutoEnabled: false,
            eqPreamp: 0,
            eqBands: Array(repeating: 0, count: 10),
            playlistTracks: [],
            currentTrackIndex: -1,
            playbackPosition: 0,
            wasPlaying: false,
            timeDisplayMode: TimeDisplayMode.elapsed.rawValue,
            isAlwaysOnTop: false,
            wmpSkinName: wmpSkinName,
            wmpViewID: wmpViewID,
            uiMode: PlayerUIMode.wmp.rawValue
        )
    }
}
