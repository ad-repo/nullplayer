import AppKit

final class ModernCavaView: NSView {
    /// Smallest reliably nonzero alpha in an 8-bit window backing surface.
    /// It is visually imperceptible but keeps clear content in the WindowServer mouse mask.
    static let transparentInteractionAlpha: CGFloat = 1.0 / 255.0

    weak var controller: ModernCavaWindowController?

    private let presenter = CavaPresenter()
    private var renderer: ModernSkinRenderer!
    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty
    private var isHighlighted = false
    private var pressedButton: String?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero

    private var scale: CGFloat { ModernSkinElements.scaleFactor }
    private var borderWidth: CGFloat { ModernSkinElements.spectrumBorderWidth }
    private var titleBarHeight: CGFloat {
        let hide = WindowManager.shared.effectiveHideTitleBars(for: window)
        return hide ? borderWidth : ModernSkinElements.titleBarBaseHeight * scale
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        presenter.stop()
        NotificationCenter.default.removeObserver(self)
    }

    private func commonInit() {
        wantsLayer = true
        layer?.isOpaque = false
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)

        presenter.onNeedsDisplay = { [weak self] in
            guard let self else { return }
            self.setNeedsDisplay(self.contentAnimationRect(from: self.contentAreaRect()))
        }
        presenter.onNeedsFullDisplay = { [weak self] in self?.needsDisplay = true }
        presenter.onClose = { [weak self] in self?.window?.close() }

        NotificationCenter.default.addObserver(self, selector: #selector(modernSkinDidChange),
                                               name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(doubleSizeChanged),
                                               name: .doubleSizeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowLayoutDidChange),
                                               name: .windowLayoutDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                               name: .connectedWindowHighlightDidChange, object: nil)
        updateCornerMask()
        applySkinDefaultColors(skin)
    }

    func startRendering() {
        presenter.start()
    }

    func stopRendering() {
        presenter.stop()
    }

    func skinDidChange() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        updateCornerMask()
        applySkinDefaultColors(skin)
        needsDisplay = true
    }

    /// Reset cleared the standalone Cava keys: re-read tuning and re-derive skin colors.
    func refreshAfterReset() {
        presenter.settingsDidChange()
        skinDidChange()
    }

    /// Modern Cava follows the active skin's palette: short bars use the skin's primary accent,
    /// tall bars its highlight accent. Only sets the default — a user color pick overrides it.
    private func applySkinDefaultColors(_ skin: ModernSkin) {
        let palette = skin.config.palette
        CavaSettings.setSkinDefaultColors(low: palette.resolvedPrimary(), high: palette.resolvedAccent())
    }

    @objc private func modernSkinDidChange() { skinDidChange() }
    @objc private func doubleSizeChanged() { skinDidChange() }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let contentRect = contentAreaRect()
        let animationRect = contentAnimationRect(from: contentRect)

        if !isHighlighted && animationRect.contains(dirtyRect) {
            drawCavaContent(in: contentRect, clippedTo: animationRect)
            return
        }

        renderer.drawWindowBackground(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            backgroundOpacity: effectiveBackgroundOpacity
        )

        drawCavaContent(in: contentRect, clippedTo: contentRect)

        renderer.drawWindowBorder(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            occlusionSegments: edgeOcclusionSegments
        )

        if !WindowManager.shared.effectiveHideTitleBars(for: window) {
            renderer.drawTitleBar(
                in: ModernSkinElements.spectrumTitleBar.defaultRect,
                title: "CAVA",
                prefix: "spectrum_",
                context: context
            )
            let closeState = (pressedButton == "spectrum_btn_close") ? "pressed" : "normal"
            renderer.drawWindowControlButton(
                "spectrum_btn_close",
                state: closeState,
                in: ModernSkinElements.spectrumBtnClose.defaultRect,
                context: context
            )
        }

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    private func contentAreaRect() -> NSRect {
        let rect = NSRect(
            x: borderWidth,
            y: borderWidth,
            width: max(0, bounds.width - borderWidth * 2),
            height: max(0, bounds.height - titleBarHeight - borderWidth)
        )
        let joinedRect = rect.expandingThroughJoinedEdges(
            in: bounds,
            borderWidth: borderWidth,
            adjacentEdges: adjacentEdges
        )
        return joinedRect.alignedContentRectForOneXDisplay(in: self)
    }

    private func contentAnimationRect(from contentRect: NSRect) -> NSRect {
        guard adjacentEdges.contains(.bottom) else { return contentRect }
        let bottomGuard = max(1, borderWidth)
        return NSRect(
            x: contentRect.minX,
            y: contentRect.minY + bottomGuard,
            width: contentRect.width,
            height: max(0, contentRect.height - bottomGuard)
        )
    }

    /// Opaque by default; the Transparent Background setting drops it to the skin's window opacity
    /// (the metal/translucent look). Cava does NOT inherit the spectrum window's transparency.
    private var effectiveBackgroundOpacity: CGFloat {
        CavaSettings.transparentBackground ? renderer.skin.spectrumWindowBackgroundOpacity : 1.0
    }

    private func drawCavaContent(in contentRect: NSRect, clippedTo clipRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: clipRect).setClip()
        if CavaSettings.transparentBackground {
            if let context = NSGraphicsContext.current?.cgContext {
                Self.drawTransparentContentBacking(
                    in: bounds,
                    clippedTo: clipRect,
                    renderer: renderer,
                    adjacentEdges: adjacentEdges,
                    sharpCorners: sharpCorners,
                    context: context
                )
            }
        } else {
            // Repaint the opaque content background here too so timer-driven
            // (animation-rect only) redraws do not clear it between frames.
            renderer.skin.backgroundColor.setFill()
            clipRect.fill()
        }
        CavaDrawing.draw(
            in: contentRect,
            barArrays: presenter.barArrays,
            lowColor: presenter.lowGradientColor,
            highColor: presenter.highGradientColor,
            mode: presenter.mode
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Restore the intended transparent-mode backing during content-only animation repaints.
    ///
    /// Standard skins (including Glass) retain their configured translucent window background.
    /// Metal Cava intentionally clears its content well; keep one alpha quantum there so the
    /// WindowServer does not remove gaps between bars from the borderless window's mouse mask.
    static func drawTransparentContentBacking(
        in bounds: NSRect,
        clippedTo clipRect: NSRect,
        renderer: ModernSkinRenderer,
        adjacentEdges: AdjacentEdges = [],
        sharpCorners: CACornerMask = [],
        context: CGContext
    ) {
        context.saveGState()
        context.clip(to: clipRect)
        if renderer.skin.renderStyle == .metal {
            context.setBlendMode(.copy)
            context.setFillColor(
                NSColor(
                    calibratedWhite: 0,
                    alpha: transparentInteractionAlpha
                ).cgColor
            )
            context.fill(clipRect)
        } else {
            renderer.drawWindowBackground(
                in: bounds,
                context: context,
                adjacentEdges: adjacentEdges,
                sharpCorners: sharpCorners,
                backgroundOpacity: renderer.skin.spectrumWindowBackgroundOpacity
            )
        }
        context.restoreGState()
    }

    @objc private func windowLayoutDidChange() {
        guard let window else { return }
        let newEdges = WindowManager.shared.computeAdjacentEdges(for: window)
        let newSharp = WindowManager.shared.computeSharpCorners(for: window)
        let newSegments = WindowManager.shared.computeEdgeOcclusionSegments(for: window)
        let seamless = min(1.0, max(0.0, ModernSkinEngine.shared.currentSkin?.config.window.seamlessDocking ?? 0))
        let shouldHaveShadow = !(seamless > 0 && !newEdges.isEmpty)

        if window.hasShadow != shouldHaveShadow {
            window.hasShadow = shouldHaveShadow
            window.invalidateShadow()
        }

        if newEdges != adjacentEdges || newSharp != sharpCorners || newSegments != edgeOcclusionSegments {
            adjacentEdges = newEdges
            sharpCorners = newSharp
            edgeOcclusionSegments = newSegments
            needsDisplay = true
            needsLayout = true
        }
    }

    @objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
        let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
        let newValue = highlighted.contains { $0 === window }
        if isHighlighted != newValue {
            isHighlighted = newValue
            needsDisplay = true
        }
    }

    private func hitTestTitleBar(at point: NSPoint) -> Bool {
        if WindowManager.shared.effectiveHideTitleBars(for: window) {
            return point.y >= bounds.height - 6
        }
        let closeWidth: CGFloat = 25 * scale
        return point.y >= bounds.height - titleBarHeight && point.x < bounds.width - closeWidth
    }

    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        if WindowManager.shared.effectiveHideTitleBars(for: window) { return false }
        let closeRect = renderer.scaledRect(ModernSkinElements.spectrumBtnClose.defaultRect)
        return closeRect.insetBy(dx: -4, dy: -4).contains(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hitTestCloseButton(at: point) {
            pressedButton = "spectrum_btn_close"
            needsDisplay = true
            return
        }
        if event.clickCount == 2 {
            presenter.toggleMode()
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
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: WindowManager.shared.effectiveHideTitleBars(for: window))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingWindow, let window else { return }
        let currentPoint = event.locationInWindow
        var origin = window.frame.origin
        origin.x += currentPoint.x - windowDragStartPoint.x
        origin.y += currentPoint.y - windowDragStartPoint.y
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: origin))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isDraggingWindow, let window {
            isDraggingWindow = false
            WindowManager.shared.windowDidFinishDragging(window)
        }
        if pressedButton == "spectrum_btn_close", hitTestCloseButton(at: point) {
            window?.close()
        }
        pressedButton = nil
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        presenter.buildMenu(showTransparency: true)   // modern supports the transparency toggle
    }

    override func layout() {
        super.layout()
        updateCornerMask()
    }

    private func updateCornerMask() {
        guard let layer else { return }
        let cornerRadius = (ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault())
            .config.window.cornerRadius ?? 0
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = cornerRadius > 0
        guard cornerRadius > 0 else {
            layer.maskedCorners = []
            return
        }
        let allCorners: CACornerMask = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner
        ]
        layer.maskedCorners = allCorners.subtracting(sharpCorners)
    }
}
