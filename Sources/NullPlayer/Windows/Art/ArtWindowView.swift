import AppKit

/// The classic Art window: spectrum-family chrome around an `ArtView`. The same view is what a
/// `.wal` skin hosts (the skin's frame then draws the chrome) and what wears a `.wmz` skin's
/// borrowed frame.
final class ArtWindowView: NSView {
    weak var controller: ArtWindowController?

    let artView = ArtView(frame: .zero)
    private var pressedClose = false
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private var isHighlighted = false
    private(set) var isFullscreen = false
    private var hostedContext: WinampModernHostedSurfaceContext?
    /// The window drag the body keeps while the skin's frame owns the chrome (B57).
    private var hostedDrag = WinampModernHostedWindowDrag()

    /// The classic constants, unless the hosting skin lends a window frame of its own (see
    /// `PeppyMeterView.chromeLayout`).
    private var chromeLayout: SkinnedSurfaceChrome.Metrics {
        SkinnedSurfaceChrome.metrics(for: bounds, fallback: .spectrumFamily)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityIdentifier("artWindowView")
        addSubview(artView)
        artView.onToggleFullscreen = { [weak self] in self?.toggleFullscreen() }
        artView.onClose = { [weak self] in self?.close() }
        artView.isFullscreen = { [weak self] in
            guard let self else { return false }
            if let hostedContext = self.hostedContext {
                return hostedContext.nativeWindow()?.styleMask.contains(.fullScreen) ?? false
            }
            return self.isFullscreen
        }
        NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                               name: .connectedWindowHighlightDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hostedSurfaceStyleDidChange),
                                               name: .hostedSurfaceStyleDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func contentAreaRect() -> NSRect {
        if isFullscreen || hostedContext != nil { return bounds }
        let titleHeight = WindowManager.shared.hideTitleBars ? 0 : chromeLayout.titleBarHeight
        return NSRect(
            x: chromeLayout.leftBorder,
            y: chromeLayout.bottomBorder,
            width: max(0, bounds.width - chromeLayout.leftBorder - chromeLayout.rightBorder),
            height: max(0, bounds.height - titleHeight - chromeLayout.bottomBorder)
        )
    }

    override func layout() {
        super.layout()
        artView.frame = contentAreaRect()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hostedContext == nil, !isFullscreen,
              let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.setFill()
        SkinnedSurfaceChrome.hostedGroundRect(in: bounds).fill()

        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        if WindowManager.shared.hideTitleBars {
            context.translateBy(x: 0, y: -chromeLayout.titleBarHeight)
        }
        if let style = WindowManager.shared.hostedSurfaceStyle {
            WinampModernChrome(style: style,
                               artwork: WindowManager.shared.hostedSurfaceFrameArtwork(for: bounds.size))
                .drawSpectrumFamilyWindow(
                    in: context,
                    bounds: bounds,
                    metrics: .spectrumFamily,
                    isActive: window?.isKeyWindow ?? true,
                    isClosePressed: pressedClose,
                    controlScale: WindowManager.shared.playlistChromeScale,
                    title: "ART",
                    fillBackground: false
                )
        } else {
            let skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
            SkinRenderer(skin: skin).drawSpectrumAnalyzerWindowChromeOverlay(
                in: context,
                bounds: bounds,
                isActive: window?.isKeyWindow ?? true,
                pressedButton: pressedClose ? .close : nil,
                controlScale: WindowManager.shared.playlistChromeScale,
                title: "ART"
            )
        }
        context.restoreGState()

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    func skinDidChange() {
        needsLayout = true
        needsDisplay = true
    }

    /// A borrowed frame moves the content hole, which is a layout, not a repaint (W220).
    @objc private func hostedSurfaceStyleDidChange() {
        needsLayout = true
        needsDisplay = true
    }

    func setFullscreen(_ enabled: Bool) {
        isFullscreen = enabled
        pressedClose = false
        isDraggingWindow = false
        needsLayout = true
        needsDisplay = true
    }

    func toggleFullscreen() {
        if let hostedContext { hostedContext.requestFullscreen() } else { controller?.toggleFullscreen() }
    }

    private func close() {
        if let hostedContext { hostedContext.requestClose() } else { window?.close() }
    }

    // MARK: - Mouse

    private func convertToSkinCoordinates(_ point: NSPoint) -> NSPoint {
        var skinPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        if WindowManager.shared.hideTitleBars {
            skinPoint.y += chromeLayout.titleBarHeight
        }
        return skinPoint
    }

    /// The close box, from the one place that decides where it goes (W178).
    private var closeButtonRect: NSRect {
        SkinnedSurfaceChrome.closeButtonRect(in: bounds, captionHeight: chromeLayout.titleBarHeight)
    }

    private func hitTestTitleBar(at point: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars {
            return point.y >= chromeLayout.titleBarHeight && point.y < chromeLayout.titleBarHeight + 6
        }
        return point.y < chromeLayout.titleBarHeight && point.x < closeButtonRect.minX
    }

    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        guard !WindowManager.shared.hideTitleBars else { return false }
        return closeButtonRect.contains(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isFullscreen else { return }
        if hostedContext != nil {
            hostedDrag.prime(event, context: hostedContext)
            return
        }
        let point = convertToSkinCoordinates(convert(event.locationInWindow, from: nil))
        if hitTestCloseButton(at: point) {
            pressedClose = true
            needsDisplay = true
            return
        }
        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: hitTestTitleBar(at: point))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isFullscreen else { return }
        if hostedContext != nil {
            hostedDrag.drag(event)
            return
        }
        guard isDraggingWindow, let window else { return }
        var origin = window.frame.origin
        origin.x += event.locationInWindow.x - windowDragStartPoint.x
        origin.y += event.locationInWindow.y - windowDragStartPoint.y
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: origin))
    }

    override func mouseUp(with event: NSEvent) {
        guard !isFullscreen else { return }
        if hostedContext != nil {
            hostedDrag.end()
            return
        }
        let point = convertToSkinCoordinates(convert(event.locationInWindow, from: nil))
        if isDraggingWindow, let window {
            isDraggingWindow = false
            WindowManager.shared.windowDidFinishDragging(window)
        }
        if pressedClose, hitTestCloseButton(at: point) {
            window?.close()
        }
        pressedClose = false
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        artView.menu(for: event)
    }

    @objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
        let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
        let newValue = highlighted.contains { $0 === window }
        if newValue != isHighlighted {
            isHighlighted = newValue
            needsDisplay = true
        }
    }

    func configureForHostedSurface(context: WinampModernHostedSurfaceContext) {
        hostedContext = context
        autoresizingMask = [.width, .height]
        needsLayout = true
        needsDisplay = true
    }
}

extension ArtWindowView: WinampModernHostedFullscreenSurface {
    var view: NSView { self }
    func applyPalette(_ style: WinampModernSurfaceStyle) { needsDisplay = true }
    func applySkinScale(_ scale: CGFloat) { needsDisplay = true }
    func resume() { needsLayout = true }
    func suspend() { artView.tearDown() }
    func unmountFromHolder() { removeFromSuperview() }
    func prepareForUITeardown() {
        artView.tearDown()
        hostedContext = nil
        removeFromSuperview()
    }
}
