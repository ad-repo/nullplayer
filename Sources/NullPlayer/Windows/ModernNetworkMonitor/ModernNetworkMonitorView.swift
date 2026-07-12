import AppKit

final class ModernNetworkMonitorView: NSView {
    weak var controller: ModernNetworkMonitorWindowController?

    var snapshot: NetworkThroughputSnapshot? { didSet { needsDisplay = true } }
    var interfaces: [NetworkInterfaceResolver.InterfaceInfo] = [] { didSet { needsDisplay = true } }

    private var renderer: ModernSkinRenderer!
    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty
    private var isHighlighted = false
    private var pressedButton: String?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private let renderState = NetworkMonitorRenderState()
    private var animationTimer: Timer?
    private var direction = NetworkMonitorDirection.load()

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
        stopAnimationTimer()
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

        renderer.drawWindowBackground(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            backgroundOpacity: renderer.skin.spectrumWindowBackgroundOpacity
        )
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
                title: "FLOW",
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

        NetworkMonitorDrawing.drawContent(
            in: contentAreaRect(),
            snapshot: snapshot,
            direction: direction,
            isModern: true,
            renderState: renderState
        )

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
        return rect.expandingThroughJoinedEdges(
            in: bounds,
            borderWidth: borderWidth,
            adjacentEdges: adjacentEdges
        )
    }

    func skinDidChange() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        updateCornerMask()
        needsDisplay = true
    }

    @objc private func modernSkinDidChange() { skinDidChange() }
    @objc private func doubleSizeChanged() { skinDidChange() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimationTimer()
        } else {
            startAnimationTimer()
        }
    }

    private func startAnimationTimer() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            // Only repaint while values are still animating; when the network is idle
            // or steady the next data snapshot will invalidate us instead. This avoids
            // repainting the full window chrome 30 fps for a static picture.
            guard self.renderState.hasActiveAnimation else { return }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
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
            toggleDirection()
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
        controller?.refreshInterfaces()
        let menu = NSMenu()
        if !interfaces.isEmpty {
            let selectedName = snapshot?.interface?.name
            for interface in interfaces {
                let item = NSMenuItem(title: interface.displayName, action: #selector(selectInterface(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = interface.name
                item.state = interface.name == selectedName ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        let cycleItem = NSMenuItem(title: "Next Interface", action: #selector(cycleInterface(_:)), keyEquivalent: "")
        cycleItem.target = self
        cycleItem.isEnabled = interfaces.count > 1
        menu.addItem(cycleItem)
        menu.addItem(.separator())
        let toggleItem = NSMenuItem(title: direction.toggleMenuTitle, action: #selector(toggleDirection(_:)), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close", action: #selector(closeWindow(_:)), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        return menu
    }

    private func toggleDirection() {
        direction = direction.toggled
        direction.save()
        needsDisplay = true
    }

    @objc private func toggleDirection(_ sender: Any?) {
        toggleDirection()
    }

    @objc private func cycleInterface(_ sender: Any?) {
        controller?.cycleInterface()
    }

    @objc private func selectInterface(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        controller?.selectInterface(named: name)
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
