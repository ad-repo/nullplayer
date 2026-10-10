import AppKit

/// What frames an `ArtView` in a window of its own: Classic's `ArtWindowView`, Original's
/// `ModernArtWindowView`.
protocol ArtWindowChrome: NSView {
    var artView: ArtView { get }
    /// The width and height the frame around the art takes, as laid out now.
    var chromeSize: CGSize { get }
    /// Drop the chrome for fullscreen, or put it back.
    func setFullscreen(_ enabled: Bool)
    func skinDidChange()
}

/// The Art window, for every family that gives it a window of its own. A family supplies only the
/// window and its chrome (`ArtWindowController.classic()`, `.modern()`).
final class ArtWindowController: NSWindowController, ModeDependentWindow {
    private let chrome: ArtWindowChrome
    /// Where the window goes back to when it leaves fullscreen (F).
    private var preFullscreen: (frame: NSRect, level: NSWindow.Level)?

    init(window: NSWindow, chrome: ArtWindowChrome) {
        self.chrome = chrome
        super.init(window: window)
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasSkinShadow = true
        window.title = "NullPlayer Art"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.setAccessibilityLabel("NullPlayer Art Window")
        chrome.autoresizingMask = [.width, .height]
        window.contentView = chrome
        window.initialFirstResponder = chrome.artView
        chrome.artView.host = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(chrome.artView)
    }

    /// Stop the VIS timers and the spectrum feed.
    func tearDown() {
        chrome.artView.tearDown()
    }

    func prepareForUITeardown() { tearDown() }

    func skinDidChange() {
        chrome.skinDidChange()
    }

    // MARK: - Size

    /// Docked under the player at the native default width, its height cut to the cover.
    func resetToDefaultFrame() {
        guard let window, let mainWindow = WindowManager.shared.mainWindowController?.window else { return }
        let width = WindowManager.shared.nativeWindowDefaultWidth
        let height = defaultHeight(forWidth: width)
        window.setFrame(NSRect(x: mainWindow.frame.minX, y: mainWindow.frame.minY - height,
                               width: width, height: height),
                        display: false)
    }

    /// The height at which the cover fills the art at `width`, never below the window's minimum.
    func defaultHeight(forWidth width: CGFloat) -> CGFloat {
        max(window?.minSize.height ?? 0, ArtView.windowHeight(forWidth: width, chrome: chrome.chromeSize))
    }

    // MARK: - Fullscreen

    var isFullscreen: Bool { preFullscreen != nil }

    /// The window grows to cover its screen above everything, and goes back to where it was. The
    /// chrome goes before the window grows and comes back before it shrinks.
    func toggleFullscreen() {
        guard let window else { return }
        if let saved = preFullscreen {
            preFullscreen = nil
            window.level = saved.level
            NSApp.presentationOptions = []
            chrome.setFullscreen(false)
            WindowManager.shared.withProgrammaticWindowFrameChange(animationDuration: 0.45) {
                window.setFrame(saved.frame, display: true, animate: true)
            }
        } else {
            guard let screen = window.screen ?? NSScreen.main else { return }
            preFullscreen = (window.frame, window.level)
            chrome.setFullscreen(true)
            window.level = .screenSaver
            WindowManager.shared.withProgrammaticWindowFrameChange(animationDuration: 0.45) {
                window.setFrame(screen.frame, display: true, animate: true)
            }
            NSCursor.setHiddenUntilMouseMoves(true)
            NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        }
    }
}

extension ArtWindowController: ArtViewHost {
    var isArtFullscreen: Bool { isFullscreen }
    func toggleArtFullscreen() { toggleFullscreen() }
    func closeArt() { window?.close() }
}

extension ArtWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let window, !isFullscreen else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
    }

    func windowDidResize(_ notification: Notification) {
        chrome.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        chrome.needsDisplay = true
        if !isFullscreen {
            WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        chrome.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        if isFullscreen { toggleFullscreen() }
        if let window {
            WindowManager.shared.handleCenterStackWindowWillClose(window)
        }
        tearDown()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }
}
