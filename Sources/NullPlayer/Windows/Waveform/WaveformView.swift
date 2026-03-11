import AppKit

/// Classic waveform window content view with shared waveform rendering.
class WaveformView: BaseWaveformView {
    private var pressedClose = false

    private var windowScale: CGFloat {
        bounds.width / max(SkinElements.WaveformWindow.windowSize.width, 1)
    }

    override var waveformRect: NSRect {
        let titleHeight = SkinElements.WaveformWindow.Layout.titleBarHeight * windowScale
        let leftBorder = SkinElements.WaveformWindow.Layout.leftBorder * windowScale
        let rightBorder = SkinElements.WaveformWindow.Layout.rightBorder * windowScale
        let bottomBorder = SkinElements.WaveformWindow.Layout.bottomBorder * windowScale

        return NSRect(
            x: leftBorder,
            y: bottomBorder,
            width: max(0, bounds.width - leftBorder - rightBorder),
            height: max(0, bounds.height - titleHeight - bottomBorder)
        )
    }

    override var waveformColors: WaveformRenderColors {
        WaveformRenderColors(
            background: NSColor.black,
            waveform: NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
            playedWaveform: NSColor(calibratedRed: 0.0, green: 0.55, blue: 0.0, alpha: 1.0),
            cuePoint: NSColor(calibratedRed: 0.46, green: 0.45, blue: 0.54, alpha: 1.0),
            playhead: NSColor.white,
            text: NSColor(calibratedRed: 0.0, green: 0.8, blue: 0.0, alpha: 1.0),
            selection: NSColor.white
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityIdentifier("waveformView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("NullPlayer Waveform")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setAccessibilityIdentifier("waveformView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("NullPlayer Waveform")
    }

    deinit {
        stopLoadingForHide()
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

        let skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        let renderer = SkinRenderer(skin: skin)
        let isActive = window?.isKeyWindow ?? true

        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        renderer.drawSpectrumAnalyzerWindow(
            in: context,
            bounds: bounds,
            isActive: isActive,
            pressedButton: pressedClose ? .close : nil,
            isShadeMode: false
        )
        context.restoreGState()

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
        let titleHeight = SkinElements.WaveformWindow.Layout.titleBarHeight * windowScale
        return NSRect(x: 0, y: bounds.height - titleHeight, width: bounds.width, height: titleHeight)
    }

    private func closeButtonRect() -> NSRect {
        let scale = windowScale
        return NSRect(
            x: bounds.width - (11 * scale),
            y: bounds.height - (SkinElements.WaveformWindow.Layout.titleBarHeight * windowScale) + (3 * scale),
            width: 9 * scale,
            height: 9 * scale
        )
    }
}
