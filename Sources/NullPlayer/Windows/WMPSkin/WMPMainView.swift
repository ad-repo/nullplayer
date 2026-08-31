import AppKit

/// AppKit presentation of an immutable WMP scene render. Coordinates exposed to later hit testing
/// stay top-left; this view performs the single view-to-skin conversion.
final class WMPMainView: NSView {
    private var image: NSImage?
    private var isDraggingWindow = false
    private var dragStart = NSPoint.zero

    override var isFlipped: Bool { true }

    func present(_ cgImage: CGImage) {
        image = NSImage(cgImage: cgImage, size: bounds.size)
        needsDisplay = true
    }

    func prepareForUITeardown() {
        image = nil
        isDraggingWindow = false
    }

    func skinPoint(from event: NSEvent, sceneSize: WMPSize) -> WMPPoint {
        let point = convert(event.locationInWindow, from: nil)
        let x = bounds.width > 0 ? point.x * sceneSize.width / bounds.width : 0
        let y = bounds.height > 0 ? point.y * sceneSize.height / bounds.height : 0
        return WMPPoint(x: x, y: y)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        image?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.low])
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        isDraggingWindow = true
        dragStart = event.locationInWindow
        WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingWindow, let window else { return }
        let current = event.locationInWindow
        var origin = window.frame.origin
        origin.x += current.x - dragStart.x
        origin.y += current.y - dragStart.y
        origin = WindowManager.shared.windowWillMove(window, to: origin)
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDraggingWindow else { return }
        isDraggingWindow = false
        if let window { WindowManager.shared.windowDidFinishDragging(window) }
    }
}
