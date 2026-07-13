import AppKit

final class NetworkMonitorView: NSView {
    weak var controller: NetworkMonitorWindowController?

    var snapshot: NetworkThroughputSnapshot? { didSet { needsDisplay = true } }
    var interfaces: [NetworkInterfaceResolver.InterfaceInfo] = [] { didSet { needsDisplay = true } }

    private var pressedButton: SkinRenderer.ProjectMButtonType?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private var isHighlighted = false
    private let renderState = NetworkMonitorRenderState()
    private var animationTimer: Timer?
    private var direction = NetworkMonitorDirection.load()

    private var chromeLayout: SkinElements.SpectrumWindow.Layout.Type {
        SkinElements.SpectrumWindow.Layout.self
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
        stopAnimationTimer()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupView() {
        wantsLayer = true
        setAccessibilityIdentifier("networkMonitorView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("NullPlayer Network Monitor")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectedWindowHighlightDidChange(_:)),
            name: .connectedWindowHighlightDidChange,
            object: nil
        )
    }

    private func contentAreaRect() -> NSRect {
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
        let animationRect = contentAnimationRect(from: contentRect)

        if !isHighlighted && animationRect.contains(dirtyRect) {
            drawNetworkContent(in: contentRect, clippedTo: animationRect)
            return
        }

        let skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        let renderer = SkinRenderer(skin: skin)

        NSColor.black.setFill()
        bounds.fill()

        drawNetworkContent(in: contentRect, clippedTo: contentRect)

        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        if WindowManager.shared.hideTitleBars {
            context.translateBy(x: 0, y: -chromeLayout.titleBarHeight)
        }
        renderer.drawSpectrumAnalyzerWindowChromeOverlay(
            in: context,
            bounds: bounds,
            isActive: window?.isKeyWindow ?? true,
            pressedButton: pressedButton,
            controlScale: WindowManager.shared.playlistChromeScale,
            title: "FLOW"
        )
        context.restoreGState()

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    private func contentAnimationRect(from contentRect: NSRect) -> NSRect {
        let bottomGuard: CGFloat = 1
        return NSRect(
            x: contentRect.minX,
            y: contentRect.minY + bottomGuard,
            width: contentRect.width,
            height: max(0, contentRect.height - bottomGuard)
        )
    }

    private func drawNetworkContent(in contentRect: NSRect, clippedTo clipRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: clipRect).setClip()
        NetworkMonitorDrawing.drawContent(
            in: contentRect,
            snapshot: snapshot,
            direction: direction,
            isModern: false,
            renderState: renderState
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    func skinDidChange() {
        needsDisplay = true
    }

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
            self.setNeedsDisplay(self.contentAnimationRect(from: self.contentAreaRect()))
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
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
        if hitTestCloseButton(at: point) {
            pressedButton = .close
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
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: WindowManager.shared.hideTitleBars)
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

    @objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
        let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
        let newValue = highlighted.contains { $0 === window }
        if newValue != isHighlighted {
            isHighlighted = newValue
            needsDisplay = true
        }
    }
}
