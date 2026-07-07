import AppKit

final class ModernPeppyMeterView: NSView {
    weak var controller: ModernPeppyMeterWindowController?

    private var renderer: ModernSkinRenderer!
    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty
    private var isHighlighted = false
    private var pressedButton: String?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private(set) var isFullscreen = false

    private var presenter: PeppyMeterPresenter? { controller?.presenter }
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
        NotificationCenter.default.removeObserver(self)
    }

    private func commonInit() {
        wantsLayer = true
        layer?.isOpaque = false
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)

        NotificationCenter.default.addObserver(self, selector: #selector(modernSkinDidChange),
                                               name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(doubleSizeChanged),
                                               name: .doubleSizeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowLayoutDidChange),
                                               name: .windowLayoutDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                               name: .connectedWindowHighlightDidChange, object: nil)
        updateCornerMask()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let contentRect = contentAreaRect()
        // Fast path: a content-only redraw (driven by requestMeterRedraw) repaints just the
        // meter and returns before the isHighlighted tint below. Skip it while highlighted so
        // the connected-window tint isn't wiped out of the content area on every VU tick.
        if !isFullscreen && !isHighlighted && contentRect.insetBy(dx: -1, dy: -1).contains(dirtyRect) {
            if let presenter {
                drawMeterContent(in: contentRect, presenter: presenter, context: context)
            }
            return
        }

        if isFullscreen {
            NSColor.black.setFill()
            bounds.fill()
            if let presenter {
                drawMeterContent(in: bounds, presenter: presenter, context: context)
            }
        } else {
            renderer.drawWindowBackground(
                in: bounds,
                context: context,
                adjacentEdges: adjacentEdges,
                sharpCorners: sharpCorners,
                backgroundOpacity: renderer.skin.spectrumWindowBackgroundOpacity
            )
            if let presenter {
                drawMeterContent(in: contentRect, presenter: presenter, context: context)
            }
            renderer.drawWindowBorder(
                in: bounds,
                context: context,
                adjacentEdges: adjacentEdges,
                sharpCorners: sharpCorners,
                occlusionSegments: edgeOcclusionSegments
            )
        }

        if !isFullscreen && !WindowManager.shared.effectiveHideTitleBars(for: window) {
            renderer.drawTitleBar(
                in: ModernSkinElements.spectrumTitleBar.defaultRect,
                title: "PEPPYMETER",
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
        if isFullscreen { return bounds }
        let rect = NSRect(
            x: borderWidth,
            y: borderWidth,
            width: max(0, bounds.width - borderWidth * 2),
            height: max(0, bounds.height - titleBarHeight - borderWidth)
        )
        return rect
            .insetBy(dx: ModernSkinElements.peppyMeterContentPadding, dy: ModernSkinElements.peppyMeterContentPadding)
            .expandingThroughMetalJoinedEdges(
                in: bounds,
                borderWidth: borderWidth,
                adjacentEdges: adjacentEdges
            )
    }

    private func drawMeterContent(in rect: NSRect, presenter: PeppyMeterPresenter, context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        NSColor.black.setFill()
        context.fill(rect)
        PeppyMeterDrawing.draw(in: rect, presenter: presenter, context: context)
        context.restoreGState()
    }

    func requestMeterRedraw() {
        if isFullscreen {
            needsDisplay = true
        } else {
            setNeedsDisplay(contentAreaRect())
        }
    }

    func skinDidChange() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        updateCornerMask()
        needsDisplay = true
    }

    func setFullscreen(_ enabled: Bool) {
        isFullscreen = enabled
        pressedButton = nil
        isDraggingWindow = false
        updateCornerMask()
        needsDisplay = true
    }

    @objc private func modernSkinDidChange() { skinDidChange() }
    @objc private func doubleSizeChanged() { skinDidChange() }

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
        guard !isFullscreen else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hitTestCloseButton(at: point) {
            pressedButton = "spectrum_btn_close"
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
        guard isDraggingWindow, let window else { return }
        let currentPoint = event.locationInWindow
        var origin = window.frame.origin
        origin.x += currentPoint.x - windowDragStartPoint.x
        origin.y += currentPoint.y - windowDragStartPoint.y
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: origin))
    }

    override func mouseUp(with event: NSEvent) {
        guard !isFullscreen else { return }
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
        presenter?.buildMenu(
            target: self,
            selectMeter: #selector(selectMeter(_:)),
            toggleRandom: #selector(toggleRandom(_:)),
            toggleFullscreen: #selector(toggleFullscreen(_:)),
            close: #selector(closeWindow(_:)),
            isFullscreen: controller?.isFullscreen ?? false
        )
    }

    @objc private func selectMeter(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        presenter?.selectMeter(named: name)
    }

    @objc private func toggleRandom(_ sender: Any?) {
        presenter?.toggleRandom()
    }

    @objc private func toggleFullscreen(_ sender: Any?) {
        controller?.toggleFullscreen()
    }

    @objc private func closeWindow(_ sender: Any?) {
        window?.close()
    }

    override func layout() {
        super.layout()
        updateCornerMask()
    }

    private func updateCornerMask() {
        guard let layer else { return }
        if isFullscreen {
            layer.cornerRadius = 0
            layer.masksToBounds = false
            layer.maskedCorners = []
            return
        }
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
