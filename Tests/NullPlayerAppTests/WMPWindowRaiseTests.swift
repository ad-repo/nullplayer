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
