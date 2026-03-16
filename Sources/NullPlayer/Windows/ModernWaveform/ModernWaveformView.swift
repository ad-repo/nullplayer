import AppKit
import QuartzCore

/// Modern waveform window view with modern skin chrome and shared waveform rendering.
class ModernWaveformView: BaseWaveformView {
    private var renderer: ModernSkinRenderer!
    private var pressedClose = false
    private var isDraggingWindow = false
    private var hasDraggedWindow = false
    private var windowDragStartPoint: NSPoint = .zero
    private var pendingWaveformSeekPoint: NSPoint?

    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty

    /// Highlight state for drag-mode visual feedback
    private var isHighlighted = false

    private var titleBarHeight: CGFloat {
        WindowManager.shared.effectiveHideTitleBars(for: window) ? borderWidth : ModernSkinElements.waveformTitleBarHeight
    }

    private var borderWidth: CGFloat { ModernSkinElements.waveformBorderWidth }

    override var waveformRect: NSRect {
        NSRect(
            x: borderWidth,
            y: borderWidth,
            width: max(0, bounds.width - borderWidth * 2),
            height: max(0, bounds.height - titleBarHeight - borderWidth)
        )
    }

    override var waveformColors: WaveformRenderColors {
        let skin = renderer.skin
        let accent = skin.elementColor(for: "seek_fill")
        let cue = skin.elementColor(for: "info_cast").withAlphaComponent(0.65)
        let transparent = WindowManager.shared.isWaveformTransparentBackgroundEnabled()
        let waveformOpacity = skin.resolvedOpacity(for: .waveformArea)
        let backgroundMode: WaveformBackgroundMode
        let background: NSColor
        let backgroundOpacity: CGFloat
        let contentOpacity: CGFloat

        if transparent {
            background = skin.surfaceColor
            contentOpacity = waveformOpacity.content
            switch skin.waveformTransparentBackgroundStyle {
            case .glass:
                backgroundMode = .glass
                backgroundOpacity = waveformOpacity.background
            case .clear:
                backgroundMode = .clear
                backgroundOpacity = 0
            }
        } else {
            backgroundMode = .opaque
            background = NSColor(calibratedWhite: 0.04, alpha: 1.0)
            backgroundOpacity = 1.0
            contentOpacity = 1.0
        }

        return WaveformRenderColors(
            background: background,
            backgroundMode: backgroundMode,
            backgroundOpacity: backgroundOpacity,
            contentOpacity: contentOpacity,
            waveform: accent.withAlphaComponent(0.95),
            playedWaveform: accent.withAlphaComponent(0.45),
            cuePoint: cue,
            playhead: skin.textColor,
            text: skin.textColor,
            selection: skin.textColor
        )
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
        stopAppearanceObservation()
        stopLoadingForHide()
        NotificationCenter.default.removeObserver(self)
    }

    private func commonInit() {
        wantsLayer = true
        layer?.isOpaque = false
        startAppearanceObservation()
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

        setAccessibilityIdentifier("modernWaveformView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("NullPlayer Waveform")
        updateCornerMask()
    }

    func skinDidChange() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeButtonRect().contains(point) {
            NSCursor.pointingHand.set()
        } else if waveformRect.contains(point), snapshot.isInteractive {
            NSCursor.pointingHand.set()
        } else if titleBarRect().contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        renderer.drawWindowBackground(in: bounds, context: context, adjacentEdges: adjacentEdges, sharpCorners: sharpCorners)
        renderer.drawWindowBorder(in: bounds, context: context, adjacentEdges: adjacentEdges, sharpCorners: sharpCorners, occlusionSegments: edgeOcclusionSegments)

        if !WindowManager.shared.effectiveHideTitleBars(for: window) {
            renderer.drawTitleBar(in: ModernSkinElements.waveformTitleBar.defaultRect, title: "NULLPLAYER WAVEFORM", prefix: "waveform_", context: context)
            renderer.drawWindowControlButton(
                "waveform_btn_close",
                state: pressedClose ? "pressed" : "normal",
                in: ModernSkinElements.waveformBtnClose.defaultRect,
                context: context
            )
        }

        drawWaveform(in: context)

        if isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeButtonRect().contains(point) {
            pressedClose = true
            needsDisplay = true
            return
        }
        if waveformRect.contains(point) {
            if WindowManager.shared.effectiveHideTitleBars(for: window) {
                pendingWaveformSeekPoint = point
                hasDraggedWindow = false
                isDraggingWindow = true
                windowDragStartPoint = event.locationInWindow
                if let window {
                    WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
                }
                return
            }
            beginWaveformDrag(at: point)
            return
        }
        if titleBarRect().contains(point) {
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
            return
        }
        if WindowManager.shared.effectiveHideTitleBars(for: window) {
            hasDraggedWindow = false
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isDraggingWindow, let window {
            hasDraggedWindow = true
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - windowDragStartPoint.x
            let deltaY = currentPoint.y - windowDragStartPoint.y

            var newOrigin = window.frame.origin
            newOrigin.x += deltaX
            newOrigin.y += deltaY

            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
            return
        }
        continueWaveformDrag(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isDraggingWindow {
            isDraggingWindow = false
            if let window {
                WindowManager.shared.windowDidFinishDragging(window)
            }
        }
        if pressedClose {
            pressedClose = false
            needsDisplay = true
            if closeButtonRect().contains(point) {
                window?.close()
            }
            return
        }
        if let seekPoint = pendingWaveformSeekPoint, !hasDraggedWindow {
            beginWaveformDrag(at: seekPoint)
            endWaveformDrag(at: point)
            pendingWaveformSeekPoint = nil
            hasDraggedWindow = false
            return
        }
        pendingWaveformSeekPoint = nil
        hasDraggedWindow = false
        endWaveformDrag(at: point)
    }

    private func titleBarRect() -> NSRect {
        guard !WindowManager.shared.effectiveHideTitleBars(for: window) else { return .zero }
        return NSRect(
            x: 0,
            y: bounds.height - ModernSkinElements.waveformTitleBarHeight,
            width: bounds.width,
            height: ModernSkinElements.waveformTitleBarHeight
        )
    }

    private func closeButtonRect() -> NSRect {
        guard !WindowManager.shared.effectiveHideTitleBars(for: window) else { return .zero }
        let rect = ModernSkinElements.waveformBtnClose.defaultRect
        return NSRect(
            x: rect.minX * ModernSkinElements.scaleFactor,
            y: rect.minY * ModernSkinElements.scaleFactor,
            width: rect.width * ModernSkinElements.scaleFactor,
            height: rect.height * ModernSkinElements.scaleFactor
        )
    }

    private func updateCornerMask() {
        guard let layer else { return }
        let cornerRadius = (ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()).config.window.cornerRadius ?? 0
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = cornerRadius > 0
        guard cornerRadius > 0 else { return }
        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                        .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.maskedCorners = allCorners.subtracting(sharpCorners)
    }
}
