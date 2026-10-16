import AppKit

/// The modern compact library window's content region for every footer tab but Library: the
/// embedded play queue, or a sub-window's own view built on selection and dropped on
/// leaving. Hidden on the library tabs so the browser drawn underneath takes the clicks.
///
/// Clips to its bounds: a panel is extended up past the top by its own title bar (and that title
/// bar's close button, which has no window to close), and the clip cuts it off. The player bar
/// above is translucent, so tucking the title bar behind it as the classic window does would show.
final class ModernCompactContentView: NSView {

    /// A sub-window's view hosted in the region. Views that lean on their window controller (a
    /// presenter, a pane coordinator, the waveform feed) come with that controller,
    /// built but never shown, whose content view is borrowed.
    private struct Panel {
        let view: NSView
        /// The height clipped off the top while the view draws its title bar.
        let titleBarHeight: CGFloat
        var owner: AnyObject?
        var waveform: WaveformWindowProviding?
        var start: () -> Void = {}
        var stop: () -> Void = {}
        /// Run again once the window takes key: a view built while it was hidden could not start.
        var resume: () -> Void = {}
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
        default: return panel?.view
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

    deinit { panel?.stop() }

    /// See `Panel.resume`: runs whenever the hosting window takes key, as it does on reveal.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        if let newWindow {
            center.addObserver(self, selector: #selector(windowDidBecomeKey),
                               name: NSWindow.didBecomeKeyNotification, object: newWindow)
        }
    }

    @objc private func windowDidBecomeKey(_ note: Notification) {
        panel?.resume()
    }

    /// The compact player bar's feed, passed on to a Waveform tab.
    func updateTime(current: TimeInterval, duration: TimeInterval) {
        panel?.waveform?.updateTime(current: current, duration: duration)
    }

    func updateTrack(_ track: Track?) {
        panel?.waveform?.updateTrack(track)
    }

    private func applyMode() {
        isHidden = mode == .library
        queue.isHidden = mode != .queue
        panel?.stop()
        panel?.view.removeFromSuperview()
        panel = Self.makePanel(for: mode)
        if let panel {
            panel.view.autoresizingMask = []
            addSubview(panel.view)
            panel.start()
        }
        layoutChildren()
    }

    private static func makePanel(for mode: CompactContentMode) -> Panel? {
        let scale = ModernSkinElements.scaleFactor
        let titleBar = ModernSkinElements.titleBarBaseHeight * scale
        switch mode {
        case .library, .queue:
            return nil
        case .equalizer:
            // The EQ rules off its title bar with a line just below it.
            return Panel(view: ModernEQView(frame: .zero),
                         titleBarHeight: ModernSkinElements.eqTitleBarHeight + scale)
        case .visualizations:
            // Starts and stops itself as it joins and leaves the window.
            let vis = ModernProjectMView(frame: .zero)
            return Panel(view: vis, titleBarHeight: ModernSkinElements.projectMTitleBarHeight,
                         resume: vis.startRendering)
        case .spectrum:
            let view = ModernSpectrumView(frame: .zero)
            return Panel(view: view, titleBarHeight: ModernSkinElements.spectrumTitleBarHeight,
                         start: view.startRendering, stop: view.stopRendering, resume: view.startRendering)
        case .waveform:
            let controller = ModernWaveformWindowController()
            let engine = WindowManager.shared.audioEngine
            return Panel(view: borrowView(of: controller), titleBarHeight: ModernSkinElements.waveformTitleBarHeight,
                         owner: controller, waveform: controller,
                         start: {
                             controller.updateTrack(engine.currentTrack)
                             controller.updateTime(current: engine.currentTime, duration: engine.duration)
                         },
                         stop: controller.stopLoadingForHide)
        case .art:
            // ArtView loads and animates itself while it is in a window.
            return Panel(view: ModernArtWindowView(frame: .zero), titleBarHeight: titleBar)
        case .peppyMeter:
            let controller = ModernPeppyMeterWindowController()
            return Panel(view: borrowView(of: controller), titleBarHeight: titleBar, owner: controller,
                         start: controller.startRenderingForShow, stop: controller.stopRenderingForHide)
        case .audioAnalysis:
            let controller = ModernAudioAnalysisWindowController()
            return Panel(view: borrowView(of: controller), titleBarHeight: titleBar, owner: controller,
                         start: controller.startRenderingForShow, stop: controller.stopRenderingForHide)
        case .sonos:
            let view = SonosWindowView(frame: .zero)
            return Panel(view: view, titleBarHeight: titleBar, start: view.resume, stop: view.suspend)
        }
    }

    /// Take a never-shown controller's content view for the region.
    private static func borrowView(of controller: NSWindowController) -> NSView {
        guard let window = controller.window, let view = window.contentView else { return NSView() }
        window.contentView = NSView()
        return view
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutChildren()
    }

    private func layoutChildren() {
        queue.frame = bounds
        if let panel {
            // Under Hide Title Bars the view already draws only a border there.
            let clip = WindowManager.shared.effectiveHideTitleBars(for: window) ? 0 : panel.titleBarHeight
            panel.view.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height + clip)
        }
        // `reloadData()` needs the final frame so it can scroll the current track into view.
        if !didLoadQueue, !bounds.isEmpty {
            didLoadQueue = true
            queue.reloadData()
            if mode == .queue { window?.makeFirstResponder(queue) }
        }
    }
}
