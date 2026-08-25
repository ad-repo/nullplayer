import AppKit
import XCTest
@testable import NullPlayer

final class WindowRestoreGeometryTests: XCTestCase {
    func testSkinSwitchPreservesVisibleDetachedWindowFrame() {
        let floatingFrame = NSRect(x: 1420, y: 630, width: 420, height: 180)

        let preserved = WindowManager.detachedFrameForSkinSwitch(
            floatingFrame,
            isVisible: true,
            isDetached: true
        )

        XCTAssertEqual(preserved, floatingFrame)
    }

    func testSkinSwitchLetsDockedOrHiddenWindowsUseTargetLayout() {
        let frame = NSRect(x: 100, y: 300, width: 275, height: 116)

        XCTAssertNil(
            WindowManager.detachedFrameForSkinSwitch(
                frame,
                isVisible: true,
                isDetached: false
            )
        )
        XCTAssertNil(
            WindowManager.detachedFrameForSkinSwitch(
                frame,
                isVisible: false,
                isDetached: true
            )
        )
    }

    func testSkinSwitchTreatsEveryAuxiliaryAsDetachedWhileCompactWindowHidesMain() {
        XCTAssertTrue(
            WindowManager.isDetachedForSkinSwitch(
                isMainWindowVisible: false,
                isConnectedToMainWindow: false
            )
        )
        XCTAssertTrue(
            WindowManager.isDetachedForSkinSwitch(
                isMainWindowVisible: true,
                isConnectedToMainWindow: false
            )
        )
        XCTAssertFalse(
            WindowManager.isDetachedForSkinSwitch(
                isMainWindowVisible: true,
                isConnectedToMainWindow: true
            )
        )
    }

    func testGeometryRestoreRequiresExactUIModeMatch() {
        XCTAssertTrue(
            AppStateManager.shouldRestoreGeometry(savedMode: .classic, runningMode: .classic)
        )
        XCTAssertTrue(
            AppStateManager.shouldRestoreGeometry(savedMode: .modern, runningMode: .modern)
        )
        XCTAssertTrue(
            AppStateManager.shouldRestoreGeometry(savedMode: .metal, runningMode: .metal)
        )
        XCTAssertFalse(
            AppStateManager.shouldRestoreGeometry(savedMode: .classic, runningMode: .modern)
        )
        XCTAssertFalse(
            AppStateManager.shouldRestoreGeometry(savedMode: .modern, runningMode: .metal)
        )
        XCTAssertFalse(
            AppStateManager.shouldRestoreGeometry(savedMode: .metal, runningMode: .modern)
        )
    }

    func testUnknownSavedModeFallsBackToLegacyModernAndDoesNotMatchMetal() {
        let restoredMode = AppStateManager.restoredUIMode(
            rawValue: "studio",
            savedInModernMode: true
        )

        XCTAssertEqual(restoredMode, .modern)
        XCTAssertFalse(
            AppStateManager.shouldRestoreGeometry(
                savedMode: restoredMode,
                runningMode: .metal
            )
        )
    }

    func testModernRestorePreservesSideDockedEqualizerPosition() {
        let savedEQFrame = NSRect(x: 375, y: 500, width: 275, height: 116)

        let restored = WindowManager.normalizedModernCenterStackRestoredFrame(
            savedEQFrame,
            kind: .equalizer,
            mainWidth: 275,
            minimumWidth: 275,
            targetHeight: 116,
            peppyMeterFloor: 203,
            peppyMeterLegacyDoubleHeight: 232
        )

        XCTAssertEqual(restored.minX, savedEQFrame.minX, accuracy: 0.001)
        XCTAssertEqual(restored.width, 275, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedEQFrame.maxY, accuracy: 0.001)
    }

    func testModernRestorePreservesStretchablePlaylistWidthAndPosition() {
        let savedPlaylistFrame = NSRect(x: 100, y: 384, width: 550, height: 116)

        let restored = WindowManager.normalizedModernCenterStackRestoredFrame(
            savedPlaylistFrame,
            kind: .playlist,
            mainWidth: 275,
            minimumWidth: 275,
            targetHeight: 116,
            peppyMeterFloor: 203,
            peppyMeterLegacyDoubleHeight: 232
        )

        XCTAssertEqual(restored.minX, savedPlaylistFrame.minX, accuracy: 0.001)
        XCTAssertEqual(restored.width, savedPlaylistFrame.width, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedPlaylistFrame.maxY, accuracy: 0.001)
    }

    func testModernRestorePreservesStretchableSpectrumWidth() {
        let savedSpectrumFrame = NSRect(x: 100, y: 268, width: 550, height: 140)

        let restored = WindowManager.normalizedModernCenterStackRestoredFrame(
            savedSpectrumFrame,
            kind: .spectrum,
            mainWidth: 275,
            minimumWidth: 275,
            targetHeight: 116,
            peppyMeterFloor: 203,
            peppyMeterLegacyDoubleHeight: 232
        )

        XCTAssertEqual(restored.width, savedSpectrumFrame.width, accuracy: 0.001)
        XCTAssertEqual(restored.height, savedSpectrumFrame.height, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedSpectrumFrame.maxY, accuracy: 0.001)
    }

    func testModernRestorePreservesStretchableNetworkMonitorHeight() {
        let savedNetworkMonitorFrame = NSRect(x: 100, y: 252, width: 275, height: 132)

        let restored = WindowManager.normalizedModernCenterStackRestoredFrame(
            savedNetworkMonitorFrame,
            kind: .networkMonitor,
            mainWidth: 275,
            minimumWidth: 275,
            targetHeight: 116,
            peppyMeterFloor: 203,
            peppyMeterLegacyDoubleHeight: 232
        )

        XCTAssertEqual(restored.height, savedNetworkMonitorFrame.height, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedNetworkMonitorFrame.maxY, accuracy: 0.001)
    }

    func testModernRestoreClampsShortNetworkMonitorHeightToBaseline() {
        let savedNetworkMonitorFrame = NSRect(x: 100, y: 280, width: 275, height: 90)

        let restored = WindowManager.normalizedModernCenterStackRestoredFrame(
            savedNetworkMonitorFrame,
            kind: .networkMonitor,
            mainWidth: 275,
            minimumWidth: 275,
            targetHeight: 116,
            peppyMeterFloor: 203,
            peppyMeterLegacyDoubleHeight: 232
        )

        XCTAssertEqual(restored.height, 116, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedNetworkMonitorFrame.maxY, accuracy: 0.001)
    }

    func testClassicRestorePreservesStretchableNetworkMonitorHeight() {
        let savedNetworkMonitorFrame = NSRect(x: 650, y: 420, width: 275, height: 132)

        let restored = WindowManager.normalizedClassicNetworkMonitorRestoredFrame(
            savedNetworkMonitorFrame,
            minimumHeight: 116
        )

        XCTAssertEqual(restored.height, savedNetworkMonitorFrame.height, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedNetworkMonitorFrame.maxY, accuracy: 0.001)
    }

    func testClassicRestoreClampsShortNetworkMonitorHeightToMinimum() {
        let savedNetworkMonitorFrame = NSRect(x: 650, y: 440, width: 275, height: 90)

        let restored = WindowManager.normalizedClassicNetworkMonitorRestoredFrame(
            savedNetworkMonitorFrame,
            minimumHeight: 116
        )

        XCTAssertEqual(restored.height, 116, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, savedNetworkMonitorFrame.maxY, accuracy: 0.001)
    }

    // MARK: - A `.wal` main frame belongs to the skin that saved it

    /// The reported case, with its real numbers: Big Bento Modern's main layout is 1536×878 and
    /// winampmodern566's is 354×280. `mainWindowFrame` is one global key, so Bento's size was
    /// restored onto 566 — and 566 declares `max=16384x16384`, so the restore clamp had nothing to
    /// catch. Its top-anchored titlebar and bottom-anchored player bar ended up at opposite ends of a
    /// near-fullscreen window, which reads on screen as the skin having split into two windows.
    func testAWalFrameSavedUnderAnotherSkinKeepsTheLoadedSkinsSize() {
        let bentoFrame = NSRect(x: 97, y: 99, width: 1536, height: 878)

        let restored = AppStateManager.mainFrameForRestore(
            saved: bentoFrame,
            ownSize: NSSize(width: 354, height: 280),
            savedUnderSkin: "Big Bento Modern",
            loadedSkin: "winampmodern566",
            isWinampModern: true
        )

        XCTAssertEqual(restored.size, NSSize(width: 354, height: 280))
        // The position is the user's, not the skin's, so it survives — anchored at the same top-left,
        // the corner Winamp resizes a window around.
        XCTAssertEqual(restored.minX, bentoFrame.minX, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, bentoFrame.maxY, accuracy: 0.001)
    }

    /// The same skin coming back is the ordinary case, and a size the user dragged must survive it.
    func testAWalFrameSavedUnderTheSameSkinRestoresVerbatim() {
        let dragged = NSRect(x: 200, y: 300, width: 900, height: 500)

        XCTAssertEqual(
            AppStateManager.mainFrameForRestore(
                saved: dragged,
                ownSize: NSSize(width: 354, height: 280),
                savedUnderSkin: "winampmodern566",
                loadedSkin: "winampmodern566",
                isWinampModern: true
            ),
            dragged
        )
    }

    /// Every state written before the skin name was recorded decodes as `nil`. That never matches a
    /// loaded skin, so an old state falls back to the skin's own size — which is how the stale Bento
    /// frame already sitting in a user's preferences gets corrected on the next launch.
    func testAStateFromBeforeTheSkinNameWasRecordedFallsBackToTheSkinsSize() {
        let restored = AppStateManager.mainFrameForRestore(
            saved: NSRect(x: 97, y: 99, width: 1536, height: 878),
            ownSize: NSSize(width: 354, height: 280),
            savedUnderSkin: nil,
            loadedSkin: "winampmodern566",
            isWinampModern: true
        )

        XCTAssertEqual(restored.size, NSSize(width: 354, height: 280))
    }

    // MARK: - A live UI-mode switch gives the main window the incoming mode's size (B49)

    /// The reported case, with its real numbers: `.wal` (Ebonite, 197×297) → Classic left the
    /// classic player drawing its 275×116 skin scaled down inside a 197×297 window, because the
    /// rebuild stamped the *outgoing* frame onto the freshly created target-mode window.
    func testModeSwitchGivesTheMainWindowTheIncomingModesOwnSize() {
        let ebonite = NSRect(x: 420, y: 300, width: 197, height: 297)

        let switched = WindowManager.mainFrameForModeSwitch(
            outgoing: ebonite,
            ownSize: NSSize(width: 275, height: 116)
        )

        XCTAssertEqual(switched.size, NSSize(width: 275, height: 116))
    }

    /// The position is the user's, not the mode's, so it survives the switch — anchored at the same
    /// top-left, the corner `applyDoubleSize` resizes around.
    func testModeSwitchKeepsTheOutgoingWindowsTopLeft() {
        let ebonite = NSRect(x: 420, y: 300, width: 197, height: 297)

        let switched = WindowManager.mainFrameForModeSwitch(
            outgoing: ebonite,
            ownSize: NSSize(width: 275, height: 116)
        )

        XCTAssertEqual(switched.minX, ebonite.minX, accuracy: 0.001)
        XCTAssertEqual(switched.maxY, ebonite.maxY, accuracy: 0.001)
    }

    /// The rule is unconditional, so it has to hold in the growing direction too — the pair the
    /// bug report did not cover. Classic (275×116) → Ebonite must not leave the `.wal` skin's
    /// 197×297 layout inside a 275×116 box.
    func testModeSwitchAppliesInTheGrowingDirectionToo() {
        let classic = NSRect(x: 120, y: 640, width: 275, height: 116)

        let switched = WindowManager.mainFrameForModeSwitch(
            outgoing: classic,
            ownSize: NSSize(width: 197, height: 297)
        )

        XCTAssertEqual(switched.size, NSSize(width: 197, height: 297))
        XCTAssertEqual(switched.minX, classic.minX, accuracy: 0.001)
        XCTAssertEqual(switched.maxY, classic.maxY, accuracy: 0.001)
    }

    /// Modern → Classic differ in height alone (145 vs 116). A same-width pair is exactly where a
    /// width-only or "resize when it looks wrong" guard would quietly do nothing.
    func testModeSwitchCorrectsAHeightOnlyDifference() {
        let modern = NSRect(x: 300, y: 500, width: 275, height: 145)

        let switched = WindowManager.mainFrameForModeSwitch(
            outgoing: modern,
            ownSize: NSSize(width: 275, height: 116)
        )

        XCTAssertEqual(switched.height, 116, accuracy: 0.001)
        XCTAssertEqual(switched.maxY, modern.maxY, accuracy: 0.001)
    }

    /// Two modes that happen to agree on a size must come out of the switch unmoved and unresized.
    func testModeSwitchIsAnIdentityWhenBothModesShareASize() {
        let frame = NSRect(x: 250, y: 410, width: 275, height: 116)

        XCTAssertEqual(
            WindowManager.mainFrameForModeSwitch(
                outgoing: frame,
                ownSize: NSSize(width: 275, height: 116)
            ),
            frame
        )
    }

    /// The switch rule and the launch-restore rule are the same rule, so a `.wal` frame put through
    /// either path has to land in the same place. If they ever diverge, a switch and a relaunch
    /// would leave the window somewhere different.
    func testModeSwitchAgreesWithTheLaunchRestoreRule() {
        let bentoFrame = NSRect(x: 97, y: 99, width: 1536, height: 878)
        let ownSize = NSSize(width: 354, height: 280)

        XCTAssertEqual(
            WindowManager.mainFrameForModeSwitch(outgoing: bentoFrame, ownSize: ownSize),
            AppStateManager.mainFrameForRestore(
                saved: bentoFrame,
                ownSize: ownSize,
                savedUnderSkin: "Big Bento Modern",
                loadedSkin: "winampmodern566",
                isWinampModern: true
            )
        )
    }

    /// Classic and modern windows are the app's own, not a skin's, so the rule must not touch them —
    /// their saved size is the only size they have.
    func testANonWalModeRestoresItsSavedFrameUntouched() {
        let saved = NSRect(x: 625, y: 768, width: 344, height: 145)

        XCTAssertEqual(
            AppStateManager.mainFrameForRestore(
                saved: saved,
                ownSize: NSSize(width: 275, height: 116),
                savedUnderSkin: nil,
                loadedSkin: "winampmodern566",
                isWinampModern: false
            ),
            saved
        )
    }
}
