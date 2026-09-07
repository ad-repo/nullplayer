import AppKit

final class CavaView: NSView {
    weak var controller: CavaWindowController?

    private let presenter = CavaPresenter()
    private var pressedButton: SkinRenderer.ProjectMButtonType?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private var isHighlighted = false
    private var cachedRenderer: SkinRenderer?
    private var hostedContext: WinampModernHostedSurfaceContext?
    /// The window drag the body keeps while the skin's frame owns the chrome (B57).
    private var hostedDrag = WinampModernHostedWindowDrag()
    private var hostedStyle: WinampModernSurfaceStyle?

    private var chromeLayout: SkinElements.SpectrumWindow.Layout.Type {
        SkinElements.SpectrumWindow.Layout.self
    }

    /// Cached `SkinRenderer`, rebuilt only when the skin changes — not allocated per frame.
    private func currentRenderer() -> SkinRenderer {
        if let cachedRenderer { return cachedRenderer }
        let skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        let renderer = SkinRenderer(skin: skin)
        cachedRenderer = renderer
        return renderer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    deinit {
        presenter.stop()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupView() {
        wantsLayer = true
        setAccessibilityIdentifier("cavaView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("NullPlayer Cava Spectrum")

        presenter.onNeedsDisplay = { [weak self] in
            guard let self else { return }
            self.setNeedsDisplay(self.contentAreaRect())
        }
        presenter.onClose = { [weak self] in self?.window?.close() }

        applySkinDefaultColors()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectedWindowHighlightDidChange(_:)),
            name: .connectedWindowHighlightDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(self, selector: #selector(winampModernThemeDidChange),
                                               name: .winampModernThemeDidChange, object: nil)
    }

    func startRendering() {
        presenter.start()
    }

    func stopRendering() {
        presenter.stop()
    }

    func skinDidChange() {
        cachedRenderer = nil
        applySkinDefaultColors()
        needsDisplay = true
    }

    /// Reset cleared the standalone Cava keys: re-read tuning and re-derive skin colors.
    func refreshAfterReset() {
        presenter.settingsDidChange()
        skinDidChange()
    }

    /// Classic Cava follows the classic palette: green (like the Winamp spectrum). Only affects the
    /// default — a user-picked color scheme overrides it (see CavaSettings.hasCustomColors).
    private func applySkinDefaultColors() {
        if let green = CavaSettings.scheme(named: "Winamp Green") {
            CavaSettings.setSkinDefaultColors(low: green.low, high: green.high)
        }
    }

    private func contentAreaRect() -> NSRect {
        if hostedContext != nil { return bounds }
        let titleHeight = WindowManager.shared.hideTitleBars ? 0 : chromeLayout.titleBarHeight
        return NSRect(
            x: chromeLayout.leftBorder + 2,
            y: chromeLayout.bottomBorder,
            width: max(0, bounds.width - chromeLayout.leftBorder - chromeLayout.rightBorder - 4),
            height: max(0, bounds.height - titleHeight - chromeLayout.bottomBorder)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let contentRect = contentAreaRect()

        if hostedContext != nil {
            NSColor.black.setFill()
            bounds.fill()
            drawCavaContent(in: bounds)
            return
        }

        // Content-only fast path for 60 Hz animation ticks: `onNeedsDisplay` only dirties the content
        // rect, so repaint just the bars and skip re-resolving the skin, allocating a SkinRenderer,
        // and redrawing the whole chrome. Mirrors ModernCavaView's animation-rect early-out.
        if !isHighlighted, contentRect.contains(dirtyRect) {
            NSColor.black.setFill()
            contentRect.fill()
            drawCavaContent(in: contentRect)
            return
        }

        NSColor.black.setFill()
        bounds.fill()

        drawCavaContent(in: contentRect)

        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        if WindowManager.shared.hideTitleBars {
            context.translateBy(x: 0, y: -chromeLayout.titleBarHeight)
        }
        if let style = WindowManager.shared.winampModernSurfaceStyle {
            WinampModernChrome(style: style).drawSpectrumFamilyWindow(
                in: context,
                bounds: bounds,
                metrics: .spectrumFamily,
                isActive: window?.isKeyWindow ?? true,
                isClosePressed: pressedButton == .close,
                controlScale: WindowManager.shared.playlistChromeScale,
                title: "CAVA",
                fillBackground: false
            )
        } else {
            currentRenderer().drawSpectrumAnalyzerWindowChromeOverlay(
                in: context,
                bounds: bounds,
                isActive: window?.isKeyWindow ?? true,
                pressedButton: pressedButton,
                controlScale: WindowManager.shared.playlistChromeScale,
                title: "CAVA"
            )
        }
        context.restoreGState()

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    private func drawCavaContent(in contentRect: NSRect) {
        CavaDrawing.draw(
            in: contentRect,
            barArrays: presenter.barArrays,
            lowColor: presenter.lowGradientColor,
            highColor: presenter.highGradientColor,
            mode: presenter.mode
        )
    }

    @objc private func winampModernThemeDidChange() {
        needsDisplay = true
    }

    private func convertToSkinCoordinates(_ point: NSPoint) -> NSPoint {
        var skinPoint = NSPoint(x: point.x, y: bounds.height - point.y)
        if WindowManager.shared.hideTitleBars {
            skinPoint.y += chromeLayout.titleBarHeight
        }
        return skinPoint
    }

    private func hitTestTitleBar(at point: NSPoint) -> Bool {
        if WindowManager.shared.hideTitleBars {
            return point.y >= chromeLayout.titleBarHeight && point.y < chromeLayout.titleBarHeight + 6
        }
        return point.y < chromeLayout.titleBarHeight && point.x < bounds.width - 25
    }

    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        guard !WindowManager.shared.hideTitleBars else { return false }
        return NSRect(x: bounds.width - 25, y: 0, width: 25, height: chromeLayout.titleBarHeight).contains(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = convertToSkinCoordinates(viewPoint)

        if hostedContext == nil, hitTestCloseButton(at: point) {
            pressedButton = .close
            needsDisplay = true
            return
        }

        if event.clickCount == 2 {
            presenter.toggleMode()
            return
        }

        if hostedContext != nil {
            hostedDrag.prime(event, context: hostedContext)
            return
        }

        if hitTestTitleBar(at: point) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
            return
        }

        isDraggingWindow = true
        windowDragStartPoint = event.locationInWindow
        if let window {
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: WindowManager.shared.hideTitleBars)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if hostedContext != nil {
            hostedDrag.drag(event)
            return
        }
        guard isDraggingWindow, let window else { return }
        let currentPoint = event.locationInWindow
        var origin = window.frame.origin
        origin.x += currentPoint.x - windowDragStartPoint.x
        origin.y += currentPoint.y - windowDragStartPoint.y
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: origin))
    }

    override func mouseUp(with event: NSEvent) {
        if hostedContext != nil {
            hostedDrag.end()
            return
        }
        let point = convertToSkinCoordinates(convert(event.locationInWindow, from: nil))
        if isDraggingWindow, let window {
            isDraggingWindow = false
            WindowManager.shared.windowDidFinishDragging(window)
        }
        if pressedButton == .close, hitTestCloseButton(at: point) {
            window?.close()
        }
        pressedButton = nil
        needsDisplay = true
    }

    func configureForHostedSurface(context: WinampModernHostedSurfaceContext) {
        hostedContext = context
        autoresizingMask = [.width, .height]
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        presenter.buildMenu(showTransparency: false)   // classic Cava is always opaque
    }

    @objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
        let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
        let newValue = highlighted.contains { $0 === window }
        if newValue != isHighlighted {
            isHighlighted = newValue
            needsDisplay = true
        }
    }
}

extension CavaView: WinampModernHostedCavaSurface {
    var view: NSView { self }

    func applyPalette(_ style: WinampModernSurfaceStyle) {
        hostedStyle = style
        needsDisplay = true
    }

    func applySkinScale(_ scale: CGFloat) { needsDisplay = true }
    func resume() { startRendering() }
    func suspend() { stopRendering() }
    func unmountFromHolder() { removeFromSuperview() }
    func prepareForUITeardown() {
        stopRendering()
        removeFromSuperview()
        hostedContext = nil
    }
}
