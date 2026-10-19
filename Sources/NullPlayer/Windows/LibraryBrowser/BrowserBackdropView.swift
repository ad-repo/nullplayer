import AppKit

/// How a browser's skin dresses its Cava backdrop.
struct BrowserBackdropLook {
    /// Fills the backdrop behind the bars.
    let background: NSColor
    /// The skin's default bar colours; a user-picked Cava scheme overrides them.
    let low: NSColor
    let high: NSColor
    let cornerRadius: CGFloat
}

/// Independently rendered Cava backdrop beneath a Library or Compact browser surface.
final class BrowserBackdropView: NSView {
    private static let allCorners: CACornerMask = [
        .layerMinXMinYCorner,
        .layerMaxXMinYCorner,
        .layerMinXMaxYCorner,
        .layerMaxXMaxYCorner,
    ]

    private var presenterStorage: CavaPresenter?
    let scope: CavaSettings.Scope
    private let modeProvider: () -> BrowserBackdropMode
    private let look: () -> BrowserBackdropLook
    private var sharpCorners: CACornerMask = []

    var presenter: CavaPresenter {
        if let presenterStorage { return presenterStorage }
        let presenter = CavaPresenter(scope: scope)
        presenter.onNeedsDisplay = { [weak self] in
            self?.needsDisplay = true
        }
        presenterStorage = presenter
        return presenter
    }

    init(
        frame frameRect: NSRect,
        scope: CavaSettings.Scope,
        modeProvider: @escaping () -> BrowserBackdropMode,
        look: @escaping () -> BrowserBackdropLook
    ) {
        self.scope = scope
        self.modeProvider = modeProvider
        self.look = look
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        presenterStorage?.stop()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func reload() {
        let mode = modeProvider()
        isHidden = !mode.showsCava

        let look = look()
        applyCornerMask(radius: look.cornerRadius)
        CavaSettings.setSkinDefaultColors(low: look.low, high: look.high, scope: scope)

        if mode.showsCava, shouldAnimate {
            presenter.start()
            presenter.settingsDidChange()
        } else {
            presenterStorage?.stop()
        }
        needsDisplay = true
    }

    /// Match the browser sibling's joined-edge corner policy so a rounded backdrop never leaves
    /// a transparent wedge beneath a browser corner that becomes square while docked.
    func setSharpCorners(_ corners: CACornerMask) {
        guard sharpCorners != corners else { return }
        sharpCorners = corners
        applyCornerMask(radius: look().cornerRadius)
        needsDisplay = true
    }

    private func applyCornerMask(radius: CGFloat) {
        layer?.cornerRadius = radius
        layer?.masksToBounds = radius > 0
        layer?.maskedCorners = Self.allCorners.subtracting(sharpCorners)
    }

    func stop() {
        presenterStorage?.stop()
    }

    private var shouldAnimate: Bool {
        guard let window else { return false }
        return window.isVisible
            && window.alphaValue > 0
            && !window.isMiniaturized
            && window.occlusionState.contains(.visible)
    }

    override func draw(_ dirtyRect: NSRect) {
        look().background.setFill()
        bounds.fill()

        switch modeProvider() {
        case .off, .art:
            return
        case .cava, .cavaAndArt:
            CavaDrawing.draw(
                in: bounds,
                barArrays: presenter.barArrays,
                lowColor: presenter.lowGradientColor,
                highColor: presenter.highGradientColor,
                mode: presenter.mode,
                monoLayout: .mirrored
            )
        }
    }
}

/// Keeps a `BrowserBackdropView` beneath a browser view, as a sibling in the browser's superview,
/// while the backdrop shows Cava. A sibling rather than a child so the browser's layer clipping and
/// redraws never clip or erase it; the browser draws translucent where the bars should show.
final class BrowserBackdrop {
    private(set) var view: BrowserBackdropView?
    private let mode: () -> BrowserBackdropMode
    private let look: () -> BrowserBackdropLook
    /// Where the backdrop sits, in its container's coordinates; nil fills the container.
    private let region: (() -> NSRect)?

    var presenter: CavaPresenter? { view?.presenter }

    init(mode: @escaping () -> BrowserBackdropMode, look: @escaping () -> BrowserBackdropLook,
         region: (() -> NSRect)? = nil) {
        self.mode = mode
        self.look = look
        self.region = region
    }

    /// Show, update or remove the backdrop beneath `browser`.
    func refresh(beneath browser: NSView, showsCava: Bool, scope: CavaSettings.Scope, sharpCorners: CACornerMask) {
        let container = browser.superview
        guard showsCava, let container else {
            remove()
            redrawComposition(of: browser, in: container)
            return
        }

        let backdrop: BrowserBackdropView
        if let existing = view, existing.scope == scope, existing.superview === container {
            backdrop = existing
        } else {
            remove()
            backdrop = BrowserBackdropView(frame: container.bounds, scope: scope, modeProvider: mode, look: look)
            container.addSubview(backdrop, positioned: .below, relativeTo: browser)
            view = backdrop
        }
        updateFrame()
        backdrop.setSharpCorners(sharpCorners)
        backdrop.reload()
        redrawComposition(of: browser, in: container)
    }

    /// Size the backdrop from the container's bounds (or `region`), never the browser's frame: an
    /// offset or partially sized browser would restrict Cava to one side of the window.
    func updateFrame() {
        guard let view, let container = view.superview else { return }
        view.frame = region?() ?? container.bounds
    }

    func reload() { view?.reload() }

    func stop() { view?.stop() }

    func remove() {
        view?.stop()
        view?.removeFromSuperview()
        view = nil
    }

    /// Switching from an opaque browser to a translucent backdrop composition can leave portions
    /// of AppKit's layer cache untouched on the first selection. Repaint the complete sibling
    /// hierarchy now and once more after menu tracking/layout has returned to the main run loop.
    private func redrawComposition(of browser: NSView, in container: NSView?) {
        guard let container else {
            browser.needsDisplay = true
            return
        }

        container.markSubtreeForDisplayAndLayout()
        container.layoutSubtreeIfNeeded()
        container.window?.displayIfNeeded()

        DispatchQueue.main.async { [weak self, weak browser, weak container] in
            guard let browser, let container, browser.superview === container else { return }
            self?.updateFrame()
            container.markSubtreeForDisplayAndLayout()
            container.layoutSubtreeIfNeeded()
            container.window?.displayIfNeeded()
        }
    }
}
