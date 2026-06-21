import AppKit

/// Content view used while the classic library browser is in Compact Mode.
///
/// Lays out two children deterministically on every resize (rather than relying on
/// autoresizing masks, which proved fragile and let the browser occasionally cover the
/// player bar's SOURCE row):
///   • `playerBar` — pinned across the top, fixed `barHeight`.
///   • `browser`   — fills the rest, but is extended *up behind* the player bar by
///                   `titleBarHeight` so the browser's own "LIBRARY" title bar is tucked
///                   out of sight under the (opaque) player bar.
final class ClassicCompactContainerView: NSView {

    weak var playerBar: NSView?
    weak var browser: NSView?
    var barHeight: CGFloat = 0
    var titleBarHeight: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        autoresizesSubviews = false
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutChildren()
    }

    override func layout() {
        super.layout()
        layoutChildren()
    }

    func layoutChildren() {
        let w = bounds.width
        let h = bounds.height
        browser?.frame = NSRect(x: 0, y: 0, width: w, height: max(0, h - barHeight + titleBarHeight))
        playerBar?.frame = NSRect(x: 0, y: h - barHeight, width: w, height: barHeight)
    }
}
