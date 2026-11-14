import AppKit

/// Fullscreen for a `.wal` skin's visualization: the skin's own AVS window (`VIS_FS`, F) and the
/// NullPlayer windows a skin hosts in its frame (visualization, spectrum, PeppyMeter, Art).
///
/// A skin's windows are borderless, so `NSWindow.toggleFullScreen` does nothing on them; fullscreen
/// here always **moves the view** into a screen-filling window and back to where it came from. One
/// at a time, as the screen allows: entering while another view is up puts that one back first.
@MainActor
final class WinampModernFullscreen {
    static let shared = WinampModernFullscreen()

    private var window: WinampModernFullscreenWindow?
    private var origin: (view: NSView, superview: NSView, frame: NSRect, mask: NSView.AutoresizingMask,
                         holderWindow: NSWindow?, didMove: () -> Void)?

    func isPresenting(_ view: NSView) -> Bool { origin?.view === view }

    /// `didMove` runs after each move, both ways: whatever the view pinned to its old window (a GL
    /// context, a display link) starts again in the new one. `keyDown` gets the keys the view leaves
    /// unanswered — a view that takes no keys of its own (the GL engine view) passes them all.
    func toggle(_ view: NSView, keyDown: ((NSEvent) -> Bool)? = nil, didMove: @escaping () -> Void) {
        if isPresenting(view) { exit() } else { enter(view, keyDown: keyDown, didMove: didMove) }
    }

    private func enter(_ view: NSView, keyDown: ((NSEvent) -> Bool)?, didMove: @escaping () -> Void) {
        exit()
        guard let superview = view.superview, let screen = view.window?.screen ?? NSScreen.main else { return }
        origin = (view, superview, view.frame, view.autoresizingMask, view.window, didMove)
        let fullscreen = WinampModernFullscreenWindow(covering: screen)
        fullscreen.onExit = { [weak self] in self?.exit() }
        fullscreen.onKeyDown = { [weak self] event in
            if keyDown?(event) == true { return true }
            guard event.keyCode == 53 else { return false }   // Esc
            self?.exit()
            return true
        }
        view.frame = fullscreen.host.bounds
        view.autoresizingMask = [.width, .height]
        fullscreen.host.addSubview(view)
        fullscreen.makeKeyAndOrderFront(nil)
        fullscreen.makeFirstResponder(view)
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        NSCursor.setHiddenUntilMouseMoves(true)
        window = fullscreen
        didMove()
    }

    /// Back to where the view came from. Also the teardown path: a window hidden or a skin unloaded
    /// while its view is fullscreen gets the view back first, so the holder's unmount finds it.
    func exit() {
        guard let fullscreen = window, let origin else { return }
        window = nil
        self.origin = nil
        NSApp.presentationOptions = []
        origin.view.frame = origin.frame
        origin.view.autoresizingMask = origin.mask
        origin.superview.addSubview(origin.view)
        fullscreen.orderOut(nil)
        origin.didMove()
        origin.holderWindow?.makeKeyAndOrderFront(nil)
        origin.holderWindow?.makeFirstResponder(origin.view)
    }

    /// `exit()`, only when `view` is the one up.
    func exit(presenting view: NSView) {
        if isPresenting(view) { exit() }
    }
}

/// The borderless, black, `.screenSaver`-level window over a whole screen that `WinampModernFullscreen`
/// moves a view into, and the ways out of it that Winamp's own fullscreen visualization has: **Esc**
/// (and whatever the view's own keys add, such as `f`) and a **double-click**. `.screenSaver` is the
/// level the visualization window's own custom fullscreen uses, and the GL view reads it as
/// "presenting fullscreen".
private final class WinampModernFullscreenWindow: NSWindow {
    /// The black view the fullscreen view goes in.
    let host: NSView
    var onExit: (() -> Void)?
    /// The keys the view in it leaves unanswered.
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(covering screen: NSScreen) {
        host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = true
        backgroundColor = .black
        level = .screenSaver
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        contentView = host
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
