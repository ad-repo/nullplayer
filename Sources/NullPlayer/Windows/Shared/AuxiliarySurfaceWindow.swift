import AppKit

/// A center-stack feature window built from one `AuxiliarySurfaceView` in a borderless window
/// (Sonos Rooms, Stream Ripper). Owns the window setup and the delegate plumbing every such
/// window shares; the surface owns its content.
class AuxiliarySurfaceWindowController: NSWindowController, ModeDependentWindow, NSWindowDelegate {
    let surface: AuxiliarySurfaceView
    private var observers: [NSObjectProtocol] = []
    private(set) var wasDockedWhenHidden = false

    /// `close` runs from the chrome's close button: the window's toggle, which tears the surface
    /// down and closes the stack gap.
    init(surface: AuxiliarySurfaceView, title: String, size: NSSize, minSize: NSSize,
         accessibilityID: String, accessibilityLabel: String, close: @escaping () -> Void) {
        self.surface = surface
        let window = BorderlessWindow(contentRect: NSRect(origin: .zero, size: size),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = title
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasSkinShadow = true
        window.minSize = minSize
        window.allowedResizeEdges = [.bottom, .left, .right]
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.delegate = self
        window.closeAction = close
        window.setAccessibilityIdentifier(accessibilityID)
        window.setAccessibilityLabel(accessibilityLabel)
        surface.frame = NSRect(origin: .zero, size: window.frame.size)
        surface.autoresizingMask = [.width, .height]
        window.contentView = surface
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                guard let self, let window = self.window else { return }
                if window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible) {
                    self.surface.resume()
                } else { self.surface.suspend() }
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()
        surface.resume()
    }

    func prepareForUITeardown() {
        if let window, window.isVisible { wasDockedWhenHidden = WindowManager.shared.isWindowDocked(window) }
        surface.suspend()
    }

    func skinDidChange() { surface.needsLayout = true; surface.needsDisplay = true }

    func windowWillClose(_ notification: Notification) {
        if let window { WindowManager.shared.handleCenterStackWindowWillClose(window) }
        prepareForUITeardown()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }

    func windowDidResize(_ notification: Notification) {
        surface.needsLayout = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        surface.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowDidResignKey(_ notification: Notification) { surface.needsDisplay = true }
}

/// The content of an auxiliary window: drawn inside `AuxiliaryWindowChrome` in its own window, or
/// hosted in a `.wal` skin's container. Owns the chrome, the palette, dragging and the close
/// button; a subclass lays out and refreshes its controls inside `contentArea`.
class AuxiliarySurfaceView: NSView, WinampModernHostedSurface {
    private let chromeTitle: String
    private(set) var hostedContext: WinampModernHostedSurfaceContext?
    private(set) var hostedStyle: WinampModernSurfaceStyle?
    private var hostedDrag = WinampModernHostedWindowDrag()
    private var dragStart: NSPoint?
    private var closePressed = false

    var controlScale: CGFloat { WindowManager.shared.uiScaleLevel.scaleFactor }
    var chrome: AuxiliaryWindowChrome { AuxiliaryWindowChrome(window: window, title: chromeTitle) }
    var textColor: NSColor { hostedStyle?.text ?? chrome.textColor }
    /// Where the controls go: inside the chrome, or the whole view when a skin hosts it.
    var contentArea: NSRect { hostedContext == nil ? chrome.contentRect(bounds) : bounds }

    init(frame: NSRect, chromeTitle: String) {
        self.chromeTitle = chromeTitle
        super.init(frame: frame)
        wantsLayer = true
        for name in [Notification.Name.windowLayoutDidChange, ModernSkinEngine.skinDidChangeNotification,
                     .doubleSizeDidChange, .connectedWindowHighlightDidChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(layoutChanged), name: name, object: nil)
        }
        // A `.wmz` palette arrives after the player renders, so the window first draws before it exists.
        NotificationCenter.default.addObserver(self, selector: #selector(hostedSurfaceStyleDidChange),
                                               name: .hostedSurfaceStyleDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func layoutChanged() { needsLayout = true; needsDisplay = true }
    @objc private func hostedSurfaceStyleDidChange() {
        guard [.wmp, .winampModern].contains(WindowManager.shared.uiMode.controllerFamily) else { return }
        layoutChanged()
        paletteDidChange()
    }

    /// The `.wmz` palette changed; a surface whose controls take its colours refreshes them.
    func paletteDidChange() {}

    /// Redraws the controls from the model. The base picks a light or dark control appearance to
    /// suit the background; a subclass calls it first.
    func refresh() {
        let background = (hostedStyle?.background ?? chrome.backgroundColor).usingColorSpace(.deviceRGB) ?? .black
        let brightness = 0.299 * background.redComponent + 0.587 * background.greenComponent + 0.114 * background.blueComponent
        let appearanceName: NSAppearance.Name = brightness < 0.5 ? .darkAqua : .aqua
        if appearance?.name != appearanceName { appearance = NSAppearance(named: appearanceName) }
    }

    /// Ends a subclass's `layout()`: in its own window, the title bar follows the chrome.
    func finishLayout() {
        if hostedContext == nil { (window as? BorderlessWindow)?.titleBarHeight = chrome.titleHeight }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let hostedStyle {
            hostedStyle.background.setFill()
            bounds.fill()
        } else { chrome.draw(bounds, closePressed: closePressed) }
    }

    // MARK: - Window dragging and close

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// A titleless WMP window's close sits over the content, so it has to win against it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        if hostedContext == nil, SkinnedSurfaceChrome.hidesPaletteTitleBar,
           chrome.closeRect(bounds).contains(local) { return self }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) {
        if let hostedContext { hostedDrag.prime(event, context: hostedContext); return }
        let point = convert(event.locationInWindow, from: nil)
        if chrome.closeRect(bounds).contains(point) { closePressed = true; needsDisplay = true; return }
        dragStart = event.locationInWindow
        if let window { WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true) }
    }
    override func mouseDragged(with event: NSEvent) {
        if hostedContext != nil { hostedDrag.drag(event); return }
        guard let start = dragStart, let window else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: NSPoint(x: mouse.x - start.x, y: mouse.y - start.y)))
    }
    override func mouseUp(with event: NSEvent) {
        if hostedContext != nil { hostedDrag.end(); return }
        if closePressed && chrome.closeRect(bounds).contains(convert(event.locationInWindow, from: nil)) {
            (window as? BorderlessWindow)?.performCloseAction()
        }
        closePressed = false
        if dragStart != nil, let window { WindowManager.shared.windowDidFinishDragging(window) }
        dragStart = nil
        needsDisplay = true
    }

    // MARK: - WinampModernHostedSurface

    var view: NSView { self }
    func configureForHostedSurface(context: WinampModernHostedSurfaceContext) {
        hostedContext = context
        autoresizingMask = [.width, .height]
    }
    func applyPalette(_ style: WinampModernSurfaceStyle) {
        hostedStyle = style
        needsLayout = true
        refresh()
    }
    func applySkinScale(_ scale: CGFloat) { needsLayout = true; needsDisplay = true }
    /// Starts following the model: lays out, refreshes, and attaches whatever keeps it current.
    func resume() {
        needsLayout = true
        layoutSubtreeIfNeeded()
        refresh()
    }
    /// Detaches from the model while nothing shows the surface.
    func suspend() {}
    func unmountFromHolder() { suspend(); removeFromSuperview() }
    func prepareForUITeardown() { suspend(); hostedContext = nil; removeFromSuperview() }
}
