import AppKit
import SwiftUI

class ModernStatsView: NSView {
    private var hostingView: NSHostingView<StatsContentView>!
    private var renderer: ModernSkinRenderer!
    let agent = PlayHistoryAgent()
    private var panDragStartWindowOrigin: NSPoint = .zero
    private var panDragStartMouseLocation: NSPoint = .zero
    private var pressedClose = false
    private var pressedMinimize = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func commonInit() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)

        let contentView = StatsContentView(agent: agent, skinTextColor: Color(skin.textColor))
        hostingView = NSHostingView(rootView: contentView)
        hostingView.appearance = skinAppearance(for: skin)
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handleHeaderPan(_:)))
        pan.delaysPrimaryMouseButtonEvents = false
        pan.delegate = self
        hostingView.addGestureRecognizer(pan)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modernSkinDidChange),
            name: ModernSkinEngine.skinDidChangeNotification,
            object: nil)
    }

    override func layout() {
        super.layout()
        let titleBarH = ModernSkinElements.titleBarBaseHeight * ModernSkinElements.scaleFactor
        let inset: CGFloat = 1
        hostingView.frame = NSRect(
            x: inset,
            y: inset,
            width: bounds.width - inset * 2,
            height: bounds.height - titleBarH - inset)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        renderer.drawWindowBackground(in: bounds, context: context)
        renderer.drawWindowBorder(in: bounds, context: context)
        let titleBarH = ModernSkinElements.titleBarBaseHeight * ModernSkinElements.scaleFactor
        let titleBarRect = NSRect(
            x: 0, y: bounds.height - titleBarH,
            width: bounds.width, height: titleBarH)
        renderer.drawTitleBar(in: titleBarRect, title: "PLAY HISTORY", prefix: "stats_", context: context)
        drawTitleBarButtons(in: titleBarRect, context: context)
    }

    private func drawTitleBarButtons(in titleBarRect: NSRect, context: CGContext) {
        let scale = ModernSkinElements.scaleFactor
        let r: CGFloat = 5 * scale
        let cy = titleBarRect.midY

        let closeColor = pressedClose ? NSColor.systemRed.blended(withFraction: 0.4, of: .black)! : NSColor.systemRed
        context.setFillColor(closeColor.cgColor)
        context.fillEllipse(in: CGRect(x: 10 * scale - r, y: cy - r, width: r * 2, height: r * 2))

        let minColor = pressedMinimize ? NSColor.systemYellow.blended(withFraction: 0.4, of: .black)! : NSColor.systemYellow
        context.setFillColor(minColor.cgColor)
        context.fillEllipse(in: CGRect(x: 24 * scale - r, y: cy - r, width: r * 2, height: r * 2))
    }

    private func closeButtonRect() -> NSRect {
        let scale = ModernSkinElements.scaleFactor
        let titleBarH = ModernSkinElements.titleBarBaseHeight * scale
        let r: CGFloat = 7 * scale
        return NSRect(x: 10 * scale - r, y: bounds.height - titleBarH / 2 - r, width: r * 2, height: r * 2)
    }

    private func minimizeButtonRect() -> NSRect {
        let scale = ModernSkinElements.scaleFactor
        let titleBarH = ModernSkinElements.titleBarBaseHeight * scale
        let r: CGFloat = 7 * scale
        return NSRect(x: 24 * scale - r, y: bounds.height - titleBarH / 2 - r, width: r * 2, height: r * 2)
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let titleBarH = ModernSkinElements.titleBarBaseHeight * ModernSkinElements.scaleFactor
        let titleBarRect = NSRect(
            x: 0, y: bounds.height - titleBarH,
            width: bounds.width, height: titleBarH)
        guard titleBarRect.contains(loc) else { super.mouseDown(with: event); return }

        if closeButtonRect().contains(loc) {
            pressedClose = true; needsDisplay = true; return
        }
        if minimizeButtonRect().contains(loc) {
            pressedMinimize = true; needsDisplay = true; return
        }
        if let win = window {
            WindowManager.shared.windowWillPrimeDragging(win)
            win.performDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if pressedClose {
            pressedClose = false; needsDisplay = true
            if closeButtonRect().contains(loc) { window?.close() }
        }
        if pressedMinimize {
            pressedMinimize = false; needsDisplay = true
            if minimizeButtonRect().contains(loc) { window?.miniaturize(nil) }
        }
        super.mouseUp(with: event)
    }

    private func skinAppearance(for skin: ModernSkin) -> NSAppearance? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        skin.backgroundColor.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        let brightness = 0.299 * r + 0.587 * g + 0.114 * b
        return NSAppearance(named: brightness < 0.5 ? .darkAqua : .aqua)
    }

    @objc private func modernSkinDidChange() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        hostingView.rootView = StatsContentView(agent: agent, skinTextColor: Color(skin.textColor))
        hostingView.appearance = skinAppearance(for: skin)
        needsDisplay = true
    }

    @objc private func handleHeaderPan(_ recognizer: NSPanGestureRecognizer) {
        guard let win = window else { return }

        switch recognizer.state {
        case .began:
            WindowManager.shared.windowWillStartDragging(win, fromTitleBar: true)
            panDragStartWindowOrigin = win.frame.origin
            panDragStartMouseLocation = NSEvent.mouseLocation
        case .changed:
            let current = NSEvent.mouseLocation
            let dx = current.x - panDragStartMouseLocation.x
            let dy = current.y - panDragStartMouseLocation.y
            var newOrigin = NSPoint(x: panDragStartWindowOrigin.x + dx,
                                   y: panDragStartWindowOrigin.y + dy)
            newOrigin = WindowManager.shared.windowWillMove(win, to: newOrigin)
            win.setFrameOrigin(newOrigin)
        case .ended, .cancelled:
            WindowManager.shared.windowDidFinishDragging(win)
        default:
            break
        }
    }
}

// MARK: - NSGestureRecognizerDelegate

extension ModernStatsView: NSGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        let loc = gestureRecognizer.location(in: hostingView)
        let headerHeight: CGFloat = 36
        return loc.y >= hostingView.bounds.height - headerHeight
    }
}
