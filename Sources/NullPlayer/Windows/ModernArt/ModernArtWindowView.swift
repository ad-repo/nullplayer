import AppKit

extension ArtWindowController {
    /// The Original-skin Art window.
    static func modern() -> ArtWindowController {
        let size = ModernSkinElements.spectrumWindowSize
        let window = BorderlessWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                      backing: .buffered, defer: false)
        window.allowedResizeEdges = [.bottom, .left, .right]
        window.titleBarHeight = ModernSkinElements.titleBarBaseHeight * ModernSkinElements.scaleFactor
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.minSize = ModernSkinElements.spectrumMinSize
        window.setAccessibilityIdentifier("ModernArtWindow")
        return ArtWindowController(window: window, chrome: ModernArtWindowView(frame: NSRect(origin: .zero, size: size)))
    }
}

/// The Original-skin Art window: modern spectrum-family chrome around an `ArtView`.
final class ModernArtWindowView: NSView, ArtWindowChrome {
    let artView = ArtView(frame: .zero)
    private var renderer: ModernSkinRenderer!
    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty
    private var isHighlighted = false
    private var pressedClose = false
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private var isFullscreen = false

    private var scale: CGFloat { ModernSkinElements.scaleFactor }
    private var borderWidth: CGFloat { ModernSkinElements.spectrumBorderWidth }
    private var titleBarHeight: CGFloat {
        WindowManager.shared.effectiveHideTitleBars(for: window)
            ? borderWidth : ModernSkinElements.titleBarBaseHeight * scale
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        renderer = ModernSkinRenderer(skin: ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault())
        addSubview(artView)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(skinDidChange),
                           name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(skinDidChange), name: .doubleSizeDidChange, object: nil)
        center.addObserver(self, selector: #selector(windowLayoutDidChange), name: .windowLayoutDidChange, object: nil)
        center.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                           name: .connectedWindowHighlightDidChange, object: nil)
        updateCornerMask()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func contentAreaRect() -> NSRect {
        if isFullscreen { return bounds }
        let rect = NSRect(x: borderWidth, y: borderWidth,
                          width: max(0, bounds.width - borderWidth * 2),
                          height: max(0, bounds.height - titleBarHeight - borderWidth))
        return rect.expandingThroughJoinedEdges(in: bounds, borderWidth: borderWidth, adjacentEdges: adjacentEdges)
            .alignedContentRectForOneXDisplay(in: self)
    }

    override func layout() {
        super.layout()
        artView.frame = contentAreaRect()
        updateCornerMask()
    }

    var chromeSize: CGSize {
        let content = contentAreaRect()
        return CGSize(width: bounds.width - content.width, height: bounds.height - content.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isFullscreen, let context = NSGraphicsContext.current?.cgContext else { return }
        renderer.drawWindowBackground(in: bounds, context: context, adjacentEdges: adjacentEdges,
                                      sharpCorners: sharpCorners,
                                      backgroundOpacity: renderer.skin.spectrumWindowBackgroundOpacity)
        renderer.drawWindowBorder(in: bounds, context: context, adjacentEdges: adjacentEdges,
                                  sharpCorners: sharpCorners, occlusionSegments: edgeOcclusionSegments)
        if !WindowManager.shared.effectiveHideTitleBars(for: window) {
            renderer.drawTitleBar(in: ModernSkinElements.spectrumTitleBar.defaultRect, title: "ART",
                                  prefix: "spectrum_", context: context)
            renderer.drawWindowControlButton("spectrum_btn_close", state: pressedClose ? "pressed" : "normal",
                                             in: ModernSkinElements.spectrumBtnClose.defaultRect, context: context)
        }
        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    @objc func skinDidChange() {
        renderer = ModernSkinRenderer(skin: ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault())
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

    // MARK: - Mouse

    private func hitTestTitleBar(at point: NSPoint) -> Bool {
        if WindowManager.shared.effectiveHideTitleBars(for: window) {
            return point.y >= bounds.height - 6
        }
        return point.y >= bounds.height - titleBarHeight && point.x < bounds.width - 25 * scale
    }

    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        if WindowManager.shared.effectiveHideTitleBars(for: window) { return false }
        return renderer.scaledRect(ModernSkinElements.spectrumBtnClose.defaultRect).insetBy(dx: -4, dy: -4).contains(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isFullscreen else { return }
        let point = convert(event.locationInWindow, from: nil)
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
        guard !isFullscreen, isDraggingWindow, let window else { return }
        var origin = window.frame.origin
        origin.x += event.locationInWindow.x - windowDragStartPoint.x
        origin.y += event.locationInWindow.y - windowDragStartPoint.y
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: origin))
    }

    override func mouseUp(with event: NSEvent) {
        guard !isFullscreen else { return }
        let point = convert(event.locationInWindow, from: nil)
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

    private func updateCornerMask() {
        guard let layer else { return }
        let cornerRadius = isFullscreen ? 0
            : (ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()).config.window.cornerRadius ?? 0
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = cornerRadius > 0
        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                        .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.maskedCorners = cornerRadius > 0 ? allCorners.subtracting(sharpCorners) : []
    }
}
