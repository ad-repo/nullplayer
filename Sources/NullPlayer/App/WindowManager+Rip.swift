import AppKit

/// The Stream Ripper window: a center-stack feature window, opened like Sonos Rooms.
extension WindowManager {
    var isRipVisible: Bool { isCenterStackWindowVisible(.rip) }

    /// Opens the Rip window; `focusURL` focuses its URL field, pre-filled from the clipboard
    /// (Output → Streaming → Rip URL…).
    func showRip(at restoredFrame: NSRect? = nil, focusURL: Bool = false) {
        if routeWinampModernHostedWindow(.rip, toggle: false, restoredFrame: restoredFrame) { return }
        let created = ripWindowController == nil
        if created { ripWindowController = RipWindowController() }
        guard let window = ripWindowController?.window else { return }
        markModeDependentWindow(window)
        if !isRunningModernUI {
            let scale = uiScaleLevel.scaleFactor
            window.minSize = NSSize(width: 300 * scale, height: 300 * scale)
        }
        applyCenterStackSizingConstraints(window, kind: .rip)
        if let restoredFrame, restoredFrame != .zero {
            applyRestoredCenterStackFrame(restoredFrame, to: window, kind: .rip)
        } else if reopensWhereLeft(window) {
            // A free-floating family reopens it where the user left it: nothing to place.
        } else if created {
            window.setContentSize(nativeWindowDefaultSize(for: window) ?? NSSize(width: 380, height: 400))
            if isRunningModernUI { applyDefaultCenterStackFrameForCurrentHT(window, kind: .rip) }
            positionSubWindow(window)
        } else if !window.isVisible, ripWindowController?.wasDockedWhenHidden == true {
            positionSubWindow(window)
        }
        presizeHostedWindow(window)
        ripWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(window)
        notifyMainWindowVisibilityChanged()
        postLayoutChangeNotification()
        updateDockedChildWindows()
        if focusURL { ripWindowController?.ripView.focusURLField() }
    }

    func toggleRip() {
        if routeWinampModernHostedWindow(.rip, toggle: true) { return }
        if let window = ripWindowController?.window, window.isVisible {
            let frame = window.frame
            ripWindowController?.prepareForUITeardown()
            window.orderOut(nil)
            slideUpWindowsBelow(closingFrame: frame)
        } else { showRip() }
        notifyMainWindowVisibilityChanged()
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }
}
