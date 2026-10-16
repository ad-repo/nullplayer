import AppKit

/// The modern compact library window's content region for every footer tab but Library: the
/// embedded play queue, or an EQ / visualizer built on selection and dropped on leaving. Hidden on
/// the Library tab so the browser drawn underneath takes the clicks.
///
/// Clips to its bounds: a panel is extended up past the top by its own title bar (and that title
/// bar's close button, which has no window to close), and the clip cuts it off. The player bar
/// above is translucent, so tucking the title bar behind it as the classic window does would show.
final class ModernCompactContentView: NSView {

    private enum Panel {
        case equalizer(ModernEQView)
        case visualizer(ModernProjectMView)

        var view: NSView {
            switch self {
            case .equalizer(let eq): return eq
            case .visualizer(let vis): return vis
            }
        }

        /// The height clipped off the top. The EQ rules off its title bar with a line just below it.
        var titleBarHeight: CGFloat {
            switch self {
            case .equalizer: return ModernSkinElements.eqTitleBarHeight + ModernSkinElements.scaleFactor
            case .visualizer: return ModernSkinElements.projectMTitleBarHeight
            }
        }
    }

    /// Kept across tab switches so its scroll position and selection survive.
    let queue = ModernPlaylistView(frame: .zero)
    private var panel: Panel?
    private var didLoadQueue = false

    var mode: CompactContentMode {
        didSet { if mode != oldValue { applyMode() } }
    }

    /// The view that should take keyboard focus for the current tab; nil on Library.
    var focusTarget: NSView? {
        switch mode {
        case .library: return nil
        case .queue: return queue
        case .equalizer, .visualizations: return panel?.view
        }
    }

    init(mode: CompactContentMode) {
        self.mode = mode
        super.init(frame: .zero)
        clipsToBounds = true
        queue.isEmbedded = true
        addSubview(queue)
        applyMode()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The visualizer starts itself on joining the window, but cannot while the window is still
    /// hidden; the controller retries once the window takes key on reveal.
    func resumeVisualizer() {
        if case .visualizer(let vis) = panel { vis.startRendering() }
    }

    private func applyMode() {
        isHidden = mode == .library
        queue.isHidden = mode != .queue
        // The visualizer stops itself on leaving the window.
        panel?.view.removeFromSuperview()
        panel = switch mode {
        case .equalizer: .equalizer(ModernEQView(frame: .zero))
        case .visualizations: .visualizer(ModernProjectMView(frame: .zero))
        case .library, .queue: nil
        }
        if let view = panel?.view { addSubview(view) }
        layoutChildren()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutChildren()
    }

    private func layoutChildren() {
        queue.frame = bounds
        if let panel {
            panel.view.frame = NSRect(x: 0, y: 0, width: bounds.width,
                                      height: bounds.height + panel.titleBarHeight)
        }
        // `reloadData()` needs the final frame so it can scroll the current track into view.
        if !didLoadQueue, !bounds.isEmpty {
            didLoadQueue = true
            queue.reloadData()
            if mode == .queue { window?.makeFirstResponder(queue) }
        }
    }
}
