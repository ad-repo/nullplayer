import AppKit
import XCTest
@testable import NullPlayer

/// **W273 — clicking one window raises all of them, a `.wmz` skin's own panels included.**
///
/// `bringAllWindowsToFront` raises a fixed list of NullPlayer's controllers, and a skin's
/// `theme.openView` panels are not controllers, so clicking the player left `WoW`'s EQ, vis and info
/// panels behind whatever other app covered them. The list is shared by every mode, so the panels
/// join it only in `.wmz` — and a `.wal` skin's containers and hosted windows only in `.wal` — and
/// every other mode must raise exactly what it did before.
///
/// The ordering itself — deferred a turn, `orderFrontRegardless` — needs a window server and was
/// verified live; `wmp-skin-guide/reference/windows/placement.md` § *Raising the skin's windows together*.
@MainActor
final class WMPWindowRaiseTests: XCTestCase {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless],
                 backing: .buffered, defer: true)
    }

    /// The skin's windows follow the app's windows, in order; with none (every family but `.wmz`'s
    /// and `.wal`'s, whose `skinOwnedWindowsProvider` is nil) the app's own windows are raised as they
    /// were.
    func testTheSkinsWindowsFollowTheAppsWindows() {
        let player = window(), equalizer = window()
        let appWindows: [NSWindow?] = [player, nil, equalizer]
        let panels = [window(), window()]
        let ids = { (windows: [NSWindow?]) in windows.map { $0.map(ObjectIdentifier.init) } }
        XCTAssertEqual(ids(WindowManager.raiseOrder(appWindows, skinWindows: panels)), ids(appWindows + panels.map { $0 }))
        XCTAssertEqual(ids(WindowManager.raiseOrder(appWindows, skinWindows: [])), ids(appWindows))
    }

    /// Which families have skin-owned windows, and which controllers hand them over: no other family
    /// even looks for a skin's own windows (`skinOwnedWindowsProvider` asks the family first).
    func testOnlyWMPAndWinampModernHaveSkinOwnedWindows() {
        let families: [PlayerUIControllerFamily] = [.classic, .nullPlayerModern, .winampModern, .wmp, .audion, .sonique]
        XCTAssertEqual(families.filter(\.hasSkinOwnedWindows), [.winampModern, .wmp])
        let controllers: [(AnyClass, Bool)] = [(WMPMainWindowController.self, true), (WinampModernMainWindowController.self, true),
                                               (MainWindowController.self, false), (ModernMainWindowController.self, false),
                                               (AudionFaceMainWindowController.self, false), (SoniqueSkinMainWindowController.self, false)]
        for (type, provides) in controllers {
            XCTAssertEqual(type is SkinOwnedWindowsProviding.Type, provides, "\(type)")
        }
    }
}
