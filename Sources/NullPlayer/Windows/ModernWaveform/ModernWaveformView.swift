import AppKit
import QuartzCore

/// Modern waveform window view with modern skin chrome and shared waveform rendering.
class ModernWaveformView: BaseWaveformView {
    private var renderer: ModernSkinRenderer!
    private var pressedClose = false

    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty

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
        return WaveformRenderColors(
            background: NSColor(calibratedWhite: 0.04, alpha: 1.0),
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
        stopLoadingForHide()
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
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeButtonRect().contains(point) {
            pressedClose = true
            needsDisplay = true
            return
        }
        if waveformRect.contains(point) {
            beginWaveformDrag(at: point)
            return
        }
        if titleBarRect().contains(point) {
            window?.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        continueWaveformDrag(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if pressedClose {
            pressedClose = false
            needsDisplay = true
            if closeButtonRect().contains(point) {
                WindowManager.shared.toggleWaveform()
            }
            return
        }
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
