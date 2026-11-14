import AppKit

/// The screen-filling window a `.wal` skin's visualization goes fullscreen in, and the two ways out
/// of it that Winamp's own fullscreen visualization has: **Esc** (or `f`) and a **double-click**.
///
/// A skin's windows are borderless, so `NSWindow.toggleFullScreen` does nothing on them; fullscreen
/// here always means *moving the view* into one of these and back.
final class WinampModernFullscreenWindow: NSWindow {
    var onExit: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Fullscreen is where the keyboard matters most — there are no buttons on screen at all — so the
    /// whole map goes to the surface, not just the two ways out.
    var onKeyDown: ((NSEvent) -> Bool)?

    /// A borderless, black, `.screenSaver`-level window over all of `screen`, with an empty black
    /// content view to put the fullscreen view in. `.screenSaver` is the level the visualization
    /// window's own custom fullscreen uses, and the GL view reads it as "presenting fullscreen".
    static func covering(_ screen: NSScreen) -> WinampModernFullscreenWindow {
        let window = WinampModernFullscreenWindow(contentRect: screen.frame, styleMask: [.borderless],
                                                  backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .screenSaver
        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = host
        return window
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        // A view that passes its clicks through (`hitTest` returns nil) leaves them to this window.
        if event.clickCount >= 2 { onExit?() }
    }
}

/// Fullscreen for a NullPlayer window a `.wal` skin hosts in its own frame (the visualization,
/// spectrum, PeppyMeter, Art): the surface's view moves into a `WinampModernFullscreenWindow` and back
/// to the holder it came from. One at a time, as the screen allows.
@MainActor
final class WinampModernHostedFullscreen {
    private var window: WinampModernFullscreenWindow?
    private var origin: (surface: WinampModernHostedSurface, superview: NSView, frame: NSRect,
                         mask: NSView.AutoresizingMask, holderWindow: NSWindow?)?

    func toggle(_ surface: WinampModernHostedSurface) {
        if window != nil { exit() } else { enter(surface) }
    }

    private func enter(_ surface: WinampModernHostedSurface) {
        let view = surface.view
        guard let superview = view.superview,
              let screen = view.window?.screen ?? NSScreen.main else { return }
        origin = (surface, superview, view.frame, view.autoresizingMask, view.window)
        let fullscreen = WinampModernFullscreenWindow.covering(screen)
        fullscreen.onExit = { [weak self] in self?.exit() }
        // Only what the surface left unanswered reaches the window; the surface's own Esc exits
        // only a fullscreen it owns, so the way out is here.
        fullscreen.onKeyDown = { [weak self] event in
            guard event.keyCode == 53 else { return false }
            self?.exit()
            return true
        }
        guard let host = fullscreen.contentView else { return }
        view.frame = host.bounds
        view.autoresizingMask = [.width, .height]
        host.addSubview(view)
        fullscreen.makeKeyAndOrderFront(nil)
        fullscreen.makeFirstResponder(view)
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        NSCursor.setHiddenUntilMouseMoves(true)
        surface.resumeAfterWindowTransition()
        window = fullscreen
    }

    /// Back to the holder. Also the teardown path: a hosted window hidden or a skin unloaded while
    /// its view is fullscreen gets the view back first, so the holder's unmount finds it in place.
    func exit() {
        guard let fullscreen = window, let origin else { return }
        window = nil
        self.origin = nil
        NSApp.presentationOptions = []
        origin.surface.view.frame = origin.frame
        origin.surface.view.autoresizingMask = origin.mask
        origin.superview.addSubview(origin.surface.view)
        fullscreen.orderOut(nil)
        origin.surface.resumeAfterWindowTransition()
        origin.holderWindow?.makeKeyAndOrderFront(nil)
        origin.holderWindow?.makeFirstResponder(origin.surface.view)
    }
}
