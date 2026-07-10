import AppKit
import SwiftUI

/// Classic-skin shell for the shared Audio Analysis panes.
final class AudioAnalysisView: NSView {
    weak var controller: AudioAnalysisWindowController?

    private let model = AudioAnalysisModel(
        selectedPane: UserDefaults.standard.integer(
            forKey: AudioAnalysisModel.selectedPaneDefaultsKey
        )
    )
    private var hostingController: NSHostingController<AudioAnalysisContentView>?
    private var pressedButton: SkinRenderer.ProjectMButtonType?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private var isHighlighted = false

    var selectedPane: Int { model.selectedPane }

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
        NotificationCenter.default.removeObserver(self)
    }

    private func setupView() {
        wantsLayer = true
        setAccessibilityIdentifier("audioAnalysisView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("NullPlayer Audio Analyzer")

        let content = AudioAnalysisContentView(model: model) { [weak self] pane in
            self?.controller?.setVisiblePane(pane)
        }
        let hostingController = NSHostingController(rootView: content)
        hostingController.view.autoresizingMask = []
        addSubview(hostingController.view)
        self.hostingController = hostingController
        layoutContent()

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
            x: chromeLayout.leftBorder,
            y: chromeLayout.bottomBorder,
            width: max(0, bounds.width - chromeLayout.leftBorder - chromeLayout.rightBorder),
            height: max(0, bounds.height - titleHeight - chromeLayout.bottomBorder)
        )
    }

    private func layoutContent() {
        hostingController?.view.frame = contentAreaRect()
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
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
            title: "AUDIO ANALYZER"
        )
        context.restoreGState()

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    func skinDidChange() {
        needsDisplay = true
    }

    func setRenderingPaused(_ paused: Bool) {
        func update(in view: NSView) {
            if let spectrogram = view as? SpectrogramMetalView {
                spectrogram.setRenderingPaused(paused)
            }
            view.subviews.forEach { update(in: $0) }
        }
        update(in: self)
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
        let point = convertToSkinCoordinates(convert(event.locationInWindow, from: nil))
        if hitTestCloseButton(at: point) {
            pressedButton = .close
            needsDisplay = true
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
        let menu = NSMenu()
        for (index, title) in AudioAnalysisModel.paneTitles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(selectPane(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = model.selectedPane == index ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close", action: #selector(closeWindow(_:)), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        return menu
    }

    @objc private func selectPane(_ sender: NSMenuItem) {
        model.selectedPane = sender.tag
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
