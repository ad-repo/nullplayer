import AppKit

/// Classic waveform window content view with shared waveform rendering.
class WaveformView: BaseWaveformView {
    private var pressedClose = false
    private var isDraggingWindow = false
    private var windowDragStartPoint: NSPoint = .zero

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
        let transparent = WindowManager.shared.isWaveformTransparentBackgroundEnabled()
        return WaveformRenderColors(
            background: NSColor.black,
            backgroundMode: transparent ? .clear : .opaque,
            backgroundOpacity: transparent ? 0 : 1,
            contentOpacity: 1.0,
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
        startAppearanceObservation()
        setAccessibilityIdentifier("waveformView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("NullPlayer Waveform")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        startAppearanceObservation()
        setAccessibilityIdentifier("waveformView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("NullPlayer Waveform")
    }

    deinit {
        stopAppearanceObservation()
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
            isDraggingWindow = true
            windowDragStartPoint = event.locationInWindow
            if let window {
                WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isDraggingWindow, let window {
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
        endWaveformDrag(at: point)
    }

    private func titleBarRect() -> NSRect {
        let titleHeight = SkinElements.Playlist.titleHeight
        return NSRect(x: 0, y: bounds.height - titleHeight, width: bounds.width, height: titleHeight)
    }

    private func closeButtonRect() -> NSRect {
        let titleHeight = SkinElements.Playlist.titleHeight
        return NSRect(
            x: bounds.width - SkinElements.SpectrumWindow.TitleBarButtons.closeOffset,
            y: bounds.height - titleHeight + 3,
            width: 9,
            height: 9
        )
    }
}
