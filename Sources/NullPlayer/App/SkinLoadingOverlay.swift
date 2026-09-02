import AppKit
import QuartzCore

/// A small borderless loader shown across a skin or UI-mode switch.
///
/// Skin loading is one long synchronous block on the main thread — a `.wal` archive can take
/// several seconds to decompress, parse and build — so an `NSProgressIndicator` (whose animation
/// is driven by a main-thread timer) would freeze the instant the work started. The bars here are
/// `CABasicAnimation`s instead: once the layer tree is committed to the render server they keep
/// bouncing in that process, with no main-thread involvement at all. `show()` therefore ends with
/// an explicit `CATransaction.flush()` to force that commit *before* the caller blocks.
final class SkinLoadingOverlay {
    static let shared = SkinLoadingOverlay()

    private var panel: NSPanel?
    private var depth = 0

    private init() {}

    /// Show the loader, run `work`, then hide it. Re-entrant: nested calls share one loader.
    @discardableResult
    func run<T>(_ work: () throws -> T) rethrows -> T {
        show()
        defer { hide() }
        return try work()
    }

    func show() {
        depth += 1
        guard depth == 1 else { return }

        let size = NSSize(width: 88, height: 88)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        panel.contentView = makeContentView(size: size)
        panel.setFrameOrigin(originCenteringPanel(ofSize: size))
        panel.orderFrontRegardless()
        self.panel = panel

        // Draw and hand the layer tree (with its animations) to the render server now — the caller
        // is about to block the main thread, and nothing would be presented otherwise.
        panel.displayIfNeeded()
        CATransaction.flush()
    }

    func hide() {
        guard depth > 0 else { return }
        depth -= 1
        guard depth == 0 else { return }
        // One runloop turn later, so the rebuilt windows are on screen before the loader goes away.
        let closing = panel
        panel = nil
        DispatchQueue.main.async {
            closing?.orderOut(nil)
        }
    }

    // MARK: - Content

    private func makeContentView(size: NSSize) -> NSView {
        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true

        let bars = NSView(frame: NSRect(origin: .zero, size: size))
        bars.wantsLayer = true
        bars.layer.map { addBars(to: $0, in: CGRect(origin: .zero, size: size)) }
        container.addSubview(bars)
        return container
    }

    /// A row of spectrum-analyzer bars bouncing out of phase. Pure Core Animation: no timer, no
    /// drawing callback, so it keeps running while the main thread is busy loading the skin.
    private func addBars(to layer: CALayer, in rect: CGRect) {
        let barCount = 5
        let barWidth: CGFloat = 6
        let gap: CGFloat = 5
        let minHeight: CGFloat = 8
        let maxHeight: CGFloat = 40
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        let left = rect.midX - totalWidth / 2
        let baseline = rect.midY - maxHeight / 2

        // Out-of-phase offsets, deliberately not a straight ramp — a bounce that reads as levels
        // rather than as a wave sweeping one way.
        let phases: [Double] = [0.0, 0.45, 0.15, 0.6, 0.3]
        let period = 0.85
        let now = CACurrentMediaTime()

        for index in 0..<barCount {
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.frame = CGRect(x: left + CGFloat(index) * (barWidth + gap),
                               y: baseline,
                               width: barWidth,
                               height: minHeight)
            bar.cornerRadius = barWidth / 2
            bar.backgroundColor = NSColor.labelColor.withAlphaComponent(0.9).cgColor

            let grow = CABasicAnimation(keyPath: "bounds.size.height")
            grow.fromValue = minHeight
            grow.toValue = maxHeight
            grow.duration = period / 2
            grow.autoreverses = true
            grow.repeatCount = .greatestFiniteMagnitude
            grow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            grow.isRemovedOnCompletion = false
            // Negative offset so the row is already staggered on its very first frame.
            grow.beginTime = now - phases[index] * period

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.45
            fade.toValue = 1.0
            fade.duration = period / 2
            fade.autoreverses = true
            fade.repeatCount = .greatestFiniteMagnitude
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fade.isRemovedOnCompletion = false
            fade.beginTime = grow.beginTime

            bar.add(grow, forKey: "grow")
            bar.add(fade, forKey: "fade")
            layer.addSublayer(bar)
        }
    }

    private func originCenteringPanel(ofSize size: NSSize) -> NSPoint {
        let anchor = WindowManager.shared.mainWindowController?.window
            ?? NSApp.keyWindow
        let bounds = anchor?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: bounds.midX - size.width / 2,
                       y: bounds.midY - size.height / 2)
    }
}
