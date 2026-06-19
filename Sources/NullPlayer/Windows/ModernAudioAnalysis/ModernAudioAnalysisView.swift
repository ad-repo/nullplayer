import AppKit
import SwiftUI

/// Container view for the Audio Analysis window with pane selection
class ModernAudioAnalysisView: NSView {
    weak var controller: NSWindowController?

    private var renderer: ModernSkinRenderer!
    private var hostingController: NSHostingController<AudioAnalysisContentView>?

    /// Selected-pane state shared with the SwiftUI content; driven by the right-click menu.
    private let model = AudioAnalysisModel(
        selectedPane: UserDefaults.standard.integer(forKey: "audioAnalysisSelectedPane"))

    var selectedPane: Int { model.selectedPane }

    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty

    private var isHighlighted = false
    private var pressedButton: String?
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero

    private var scale: CGFloat { ModernSkinElements.scaleFactor }

    private var titleBarHeight: CGFloat {
        let hide = WindowManager.shared.effectiveHideTitleBars(for: self.window)
        return hide ? borderWidth : ModernSkinElements.titleBarBaseHeight * scale
    }

    private var borderWidth: CGFloat { ModernSkinElements.spectrumBorderWidth }

    // MARK: - Initialization

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.isOpaque = false

        // Initialize renderer
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)

        // Create and add SwiftUI content view
        setupContentView()

        // Observe notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modernSkinDidChange),
            name: ModernSkinEngine.skinDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(doubleSizeChanged),
            name: .doubleSizeDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowLayoutDidChange),
            name: .windowLayoutDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectedWindowHighlightDidChange(_:)),
            name: .connectedWindowHighlightDidChange,
            object: nil
        )

        updateCornerMask()
    }

    private func setupContentView() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        let contentView = AudioAnalysisContentView(model: model) { [weak self] pane in
            (self?.controller as? ModernAudioAnalysisWindowController)?.setVisiblePane(pane)
        }
        let hostingController = NSHostingController(rootView: contentView)

        addSubview(hostingController.view)
        hostingController.view.autoresizingMask = []  // Manual frame updates in layout()
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        // Adapt SwiftUI controls (segmented picker) to the skin's light/dark theme
        hostingController.view.appearance = skinAppearance(for: skin)

        self.hostingController = hostingController
        layoutHostingView()
    }

    /// Content rect inside the chrome (inside the border, below the title bar).
    private func contentAreaRect() -> NSRect {
        NSRect(
            x: borderWidth,
            y: borderWidth,
            width: max(0, bounds.width - borderWidth * 2),
            height: max(0, bounds.height - titleBarHeight - borderWidth)
        )
    }

    private func layoutHostingView() {
        hostingController?.view.frame = contentAreaRect()
    }

    /// Pick an aqua/darkAqua appearance based on the skin background brightness so the
    /// SwiftUI segmented picker and system controls match the skin theme.
    private func skinAppearance(for skin: ModernSkin) -> NSAppearance? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        skin.backgroundColor.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        let brightness = 0.299 * r + 0.587 * g + 0.114 * b
        return NSAppearance(named: brightness < 0.5 ? .darkAqua : .aqua)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw window background
        renderer.drawWindowBackground(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            backgroundOpacity: renderer.skin.spectrumWindowBackgroundOpacity
        )

        // Draw window border
        renderer.drawWindowBorder(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            occlusionSegments: edgeOcclusionSegments
        )

        // Draw title bar
        if !WindowManager.shared.effectiveHideTitleBars(for: self.window) {
            renderer.drawTitleBar(
                in: ModernSkinElements.spectrumTitleBar.defaultRect,
                title: "AUDIO ANALYSIS",
                prefix: "spectrum_",
                context: context
            )

            // Draw close button
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

    // MARK: - Skin Changes

    func skinDidChange() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        hostingController?.view.appearance = skinAppearance(for: skin)
        hostingController?.rootView = AudioAnalysisContentView(model: model) { [weak self] pane in
            (self?.controller as? ModernAudioAnalysisWindowController)?.setVisiblePane(pane)
        }
        layoutHostingView()
        updateCornerMask()
        needsDisplay = true
    }

    @objc private func modernSkinDidChange() {
        skinDidChange()
    }

    @objc private func doubleSizeChanged() {
        skinDidChange()
    }

    @objc private func windowLayoutDidChange() {
        guard let window = window else { return }
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

    // MARK: - Hit Testing & Mouse Events

    private var titleBarViewRect: NSRect {
        NSRect(x: 0, y: bounds.height - titleBarHeight, width: bounds.width, height: titleBarHeight)
    }

    private func hitTestTitleBar(at point: NSPoint) -> Bool {
        if WindowManager.shared.effectiveHideTitleBars(for: self.window) {
            return point.y >= bounds.height - 6
        }
        let closeWidth: CGFloat = 25 * scale
        return point.y >= bounds.height - titleBarHeight &&
               point.x < bounds.width - closeWidth
    }

    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        if WindowManager.shared.effectiveHideTitleBars(for: self.window) { return false }
        let closeRect = renderer.scaledRect(ModernSkinElements.spectrumBtnClose.defaultRect)
        let hitRect = closeRect.insetBy(dx: -4, dy: -4)
        return hitRect.contains(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check close button
        if hitTestCloseButton(at: point) {
            pressedButton = "spectrum_btn_close"
            needsDisplay = true
            return
        }

        // Check title bar
        if hitTestTitleBar(at: point) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window = window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isDraggingWindow, let window = window {
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - windowDragStartPoint.x
            let deltaY = currentPoint.y - windowDragStartPoint.y

            var newOrigin = window.frame.origin
            newOrigin.x += deltaX
            newOrigin.y += deltaY

            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isDraggingWindow {
            isDraggingWindow = false
            if let window = window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }

        if let pressed = pressedButton {
            if pressed == "spectrum_btn_close" && hitTestCloseButton(at: point) {
                window?.close()
            }
            pressedButton = nil
            needsDisplay = true
        }
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        for (index, title) in AudioAnalysisModel.paneTitles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(selectPane(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = (model.selectedPane == index) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

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

    func setRenderingPaused(_ paused: Bool) {
        func update(in view: NSView) {
            if let spectrogram = view as? SpectrogramMetalView {
                spectrogram.setRenderingPaused(paused)
            }
            for subview in view.subviews {
                update(in: subview)
            }
        }

        update(in: self)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutHostingView()
        updateCornerMask()
    }

    private func updateCornerMask() {
        guard let layer = self.layer else { return }

        let cornerRadius = (ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault())
            .config.window.cornerRadius ?? 0
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = cornerRadius > 0

        guard cornerRadius > 0 else {
            layer.maskedCorners = []
            return
        }

        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                        .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.maskedCorners = allCorners.subtracting(sharpCorners)
    }
}
