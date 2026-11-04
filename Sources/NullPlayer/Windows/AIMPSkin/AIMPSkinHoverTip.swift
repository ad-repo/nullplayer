import AppKit

/// The skin's tooltip: after the pointer rests on a hint for a moment, a small panel under it.
@MainActor
final class AIMPSkinHoverTip {
    private var text = ""
    private var timer: Timer?
    private lazy var label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .toolTipsFont(ofSize: 0)
        label.textColor = .labelColor
        return label
    }()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        let box = NSVisualEffectView()
        box.material = .toolTip
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 4
        box.addSubview(label)
        panel.contentView = box
        return panel
    }()

    /// The pointer is over `text` at `screenPoint` ("" for nothing): a new text restarts the wait.
    func point(at text: String, screenPoint: NSPoint) {
        guard text != self.text else { return }
        self.text = text
        timer?.invalidate()
        panel.orderOut(nil)
        guard !text.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.show(at: screenPoint) }
        }
    }

    private func show(at point: NSPoint) {
        label.stringValue = text
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 12, height: label.frame.height + 6)
        label.setFrameOrigin(NSPoint(x: 6, y: 3))
        panel.setFrame(NSRect(x: point.x + 4, y: point.y - size.height - 20, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}
