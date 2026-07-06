import AppKit

final class PeppyMeterView: NSView {
    weak var controller: PeppyMeterWindowController?

    private var pressedButton: SkinRenderer.ProjectMButtonType?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private var isHighlighted = false
    private(set) var isFullscreen = false

    private var chromeLayout: SkinElements.SpectrumWindow.Layout.Type {
        SkinElements.SpectrumWindow.Layout.self
    }

    private var presenter: PeppyMeterPresenter? { controller?.presenter }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupView() {
        wantsLayer = true
        setAccessibilityIdentifier("peppyMeterView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("NullPlayer PeppyMeter")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectedWindowHighlightDidChange(_:)),
            name: .connectedWindowHighlightDidChange,
            object: nil
        )
    }

    private func contentAreaRect() -> NSRect {
        if isFullscreen { return bounds }
        let titleHeight = WindowManager.shared.hideTitleBars ? 0 : chromeLayout.titleBarHeight
        return NSRect(
            x: chromeLayout.leftBorder,
            y: chromeLayout.bottomBorder,
            width: max(0, bounds.width - chromeLayout.leftBorder - chromeLayout.rightBorder),
            height: max(0, bounds.height - titleHeight - chromeLayout.bottomBorder)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if isFullscreen {
            NSColor.black.setFill()
            bounds.fill()
        } else {
            let skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
            let renderer = SkinRenderer(skin: skin)

            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            if WindowManager.shared.hideTitleBars {
                context.translateBy(x: 0, y: -chromeLayout.titleBarHeight)
            }
            renderer.drawSpectrumAnalyzerWindow(
                in: context,
                bounds: bounds,
                isActive: window?.isKeyWindow ?? true,
                pressedButton: pressedButton,
                controlScale: WindowManager.shared.playlistChromeScale,
                title: "PEPPYMETER"
            )
            context.restoreGState()
        }

        if let presenter {
            PeppyMeterDrawing.draw(in: contentAreaRect(), presenter: presenter, context: context)
        }

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    func skinDidChange() {
        needsDisplay = true
    }

    func setFullscreen(_ enabled: Bool) {
        isFullscreen = enabled
        pressedButton = nil
        isDraggingWindow = false
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
        guard !isFullscreen else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = convertToSkinCoordinates(viewPoint)
        if hitTestCloseButton(at: point) {
            pressedButton = .close
            needsDisplay = true
        } else if hitTestTitleBar(at: point) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
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

    @objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
        let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
        let newValue = highlighted.contains { $0 === window }
        if newValue != isHighlighted {
            isHighlighted = newValue
            needsDisplay = true
        }
    }
}
