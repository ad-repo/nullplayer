import AppKit

/// Content view used while the classic library browser is in Compact Mode.
///
/// Lays out its children deterministically on every resize (rather than relying on
/// autoresizing masks, which proved fragile and let the browser occasionally cover the
/// player bar's SOURCE row):
///   • `playerBar` — pinned across the top, fixed `barHeight`.
///   • `footer`    — pinned across the bottom, fixed `footerHeight`: the content-mode tabs.
///   • `browser` / `playlist` / `panel` — fill the region between footer and player bar. Exactly
///                   one is visible at a time (chosen by the footer tabs). The browser is extended
///                   *up behind* the player bar by `titleBarHeight` so its own "LIBRARY" title
///                   bar is tucked out of sight under the (opaque) player bar; the embedded
///                   playlist tucks its own title bar internally, so it uses the plain region.
///                   `panel` (EQ or visualizer) tucks its title bar the same way; the EQ keeps
///                   its fixed aspect, fitted to the top of the region over the skin background.
final class ClassicCompactContainerView: NSView {

    /// The EQ or visualizer the footer's other tabs show; built on selection, dropped on leaving.
    enum Panel {
        case equalizer(EQView)
        case visualizer(ProjectMView)

        var view: NSView {
            switch self {
            case .equalizer(let eq): return eq
            case .visualizer(let vis): return vis
            }
        }
    }

    weak var playerBar: NSView?
    weak var footer: NSView?
    weak var browser: NSView?
    weak var playlist: NSView?
    /// Owned here: setting it swaps the subview in under the player bar and lays it out.
    var panel: Panel? {
        didSet {
            oldValue?.view.removeFromSuperview()
            if let view = panel?.view {
                view.autoresizingMask = []
                addSubview(view, positioned: .below, relativeTo: playerBar)
            }
            layoutChildren()
            needsDisplay = true
        }
    }
    var barHeight: CGFloat = 0
    var footerHeight: CGFloat = 0
    /// How far the browser's frame extends up behind the player bar to hide its title bar.
    var titleBarHeight: CGFloat = 0
    /// Same, for the embedded playlist — sized to the playlist's own (scaled) title bar.
    var playlistTitleInset: CGFloat = 0

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
        // Visible content region between the footer (bottom) and the player bar (top).
        let contentBottom = footerHeight
        let contentHeight = max(0, h - barHeight - footerHeight)
        // Browser and embedded playlist are each extended up behind the player bar by their own
        // title-bar height so the title bar is hidden and the visible content fills to the footer.
        browser?.frame = NSRect(x: 0, y: contentBottom, width: w, height: contentHeight + titleBarHeight)
        playlist?.frame = NSRect(x: 0, y: contentBottom, width: w, height: contentHeight + playlistTitleInset)
        switch panel {
        case .equalizer(let eq):
            // Native units: scale so everything below the title bar fits the region.
            let native = Skin.baseEQSize
            let title = SkinElements.titleBarHeight
            let scale = min(w / native.width, contentHeight / (native.height - title))
            let size = NSSize(width: native.width * scale, height: native.height * scale)
            eq.frame = NSRect(x: ((w - size.width) / 2).rounded(),
                              y: contentBottom + contentHeight + title * scale - size.height,
                              width: size.width, height: size.height)
        case .visualizer(let vis):
            vis.frame = NSRect(x: 0, y: contentBottom, width: w,
                               height: contentHeight + SkinElements.ProjectM.Layout.titleBarHeight)
        case nil:
            break
        }
        footer?.frame = NSRect(x: 0, y: 0, width: w, height: footerHeight)
        playerBar?.frame = NSRect(x: 0, y: h - barHeight, width: w, height: barHeight)
    }

    /// The skin background behind an aspect-fitted panel.
    override func draw(_ dirtyRect: NSRect) {
        guard panel != nil else { return }
        let skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        skin.playlistColors.normalBackground.setFill()
        dirtyRect.fill()
    }
}
