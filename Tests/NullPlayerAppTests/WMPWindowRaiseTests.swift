import AppKit
import XCTest
@testable import NullPlayer

/// **W273 — clicking one window raises all of them, a `.wmz` skin's own panels included.**
///
/// `bringAllWindowsToFront` raises a fixed list of NullPlayer's controllers, and a skin's
/// `theme.openView` panels are not controllers, so clicking the player left `WoW`'s EQ, vis and info
/// panels behind whatever other app covered them. The list is shared by every mode, so the panels
/// join it only in `.wmz`, and every other mode must raise exactly what it did before.
///
/// The ordering itself — deferred a turn, `orderFrontRegardless` — needs a window server and was
/// verified live; `wmp-skin-guide/reference/windows/placement.md` § *Raising the skin's windows together*.
@MainActor
final class WMPWindowRaiseTests: XCTestCase {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless],
                 backing: .buffered, defer: true)
    }

    func testOnlyWMPAppendsTheSkinsPanels() {
        let player = window(), equalizer = window()
        let appWindows: [NSWindow?] = [player, nil, equalizer]
        let panels = [window(), window()]

        let families: [PlayerUIControllerFamily] = [.classic, .nullPlayerModern, .winampModern, .wmp]
        for family in families {
            var asked = false
            let order = WindowManager.raiseOrder(appWindows, family: family, wmpPanels: {
                asked = true
                return panels
            })
            if family == .wmp {
                XCTAssertEqual(order.map { $0.map(ObjectIdentifier.init) },
                               (appWindows + panels.map { $0 }).map { $0.map(ObjectIdentifier.init) },
                               "the panels follow the app's windows, in the order the skin opened them")
            } else {
                XCTAssertEqual(order.map { $0.map(ObjectIdentifier.init) },
                               appWindows.map { $0.map(ObjectIdentifier.init) },
                               "\(family) must raise exactly the app's own windows")
                XCTAssertFalse(asked, "\(family) must not even look for a .wmz controller's panels")
            }
        }
    }
}
