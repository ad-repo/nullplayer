import AppKit

/// The Art window's own fullscreen (F): the window grows to cover its screen above everything and
/// goes back to where it was. One copy for the classic and modern controllers.
struct ArtWindowFullscreen {
    private var saved: (frame: NSRect, level: NSWindow.Level)?

    var isActive: Bool { saved != nil }

    /// `setContentFullscreen` lets the view drop its chrome before the window grows, and put it back
    /// before the window shrinks.
    mutating func toggle(_ window: NSWindow, setContentFullscreen: (Bool) -> Void) {
        if let saved {
            self.saved = nil
            window.level = saved.level
            NSApp.presentationOptions = []
            setContentFullscreen(false)
            WindowManager.shared.withProgrammaticWindowFrameChange(animationDuration: 0.45) {
                window.setFrame(saved.frame, display: true, animate: true)
            }
        } else {
            guard let screen = window.screen ?? NSScreen.main else { return }
            saved = (window.frame, window.level)
            setContentFullscreen(true)
            window.level = .screenSaver
            WindowManager.shared.withProgrammaticWindowFrameChange(animationDuration: 0.45) {
                window.setFrame(screen.frame, display: true, animate: true)
            }
            NSCursor.setHiddenUntilMouseMoves(true)
            NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        }
    }
}
