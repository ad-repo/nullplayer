import AppKit
import SwiftUI

class ModernStatsView: NSView {
    private var hostingView: NSHostingView<StatsContentView>!
    private var renderer: ModernSkinRenderer!
    let agent = PlayHistoryAgent()

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func commonInit() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)

        let contentView = StatsContentView(agent: agent)
        hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)

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
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let titleBarH = ModernSkinElements.titleBarBaseHeight * ModernSkinElements.scaleFactor
        let titleBarRect = NSRect(
            x: 0, y: bounds.height - titleBarH,
            width: bounds.width, height: titleBarH)
        if titleBarRect.contains(loc) {
            if let win = window {
                WindowManager.shared.windowWillPrimeDragging(win)
                win.performDrag(with: event)
            }
        } else {
            super.mouseDown(with: event)
        }
    }

    @objc private func modernSkinDidChange() {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        renderer = ModernSkinRenderer(skin: skin)
        needsDisplay = true
    }
}
