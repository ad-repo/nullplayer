import AppKit

/// Independently rendered backdrop beneath a modern Library or Compact browser surface.
final class CompactBackdropView: NSView {
    private static let allCorners: CACornerMask = [
        .layerMinXMinYCorner,
        .layerMaxXMinYCorner,
        .layerMinXMaxYCorner,
        .layerMaxXMaxYCorner,
    ]

    private var presenterStorage: CavaPresenter?
    let scope: CavaSettings.Scope
    private let modeProvider: () -> BrowserBackdropMode
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
        modeProvider: @escaping () -> BrowserBackdropMode
    ) {
        self.scope = scope
        self.modeProvider = modeProvider
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        scope = .compactWindow
        modeProvider = { WindowManager.shared.compactBackdropMode }
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        autoresizingMask = [.width, .height]
    }

    deinit {
        presenterStorage?.stop()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func reload() {
        let mode = modeProvider()
        isHidden = !mode.showsCava

        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        applyCornerMask(for: skin)
        CavaSettings.setSkinDefaultColors(
            low: skin.primaryColor,
            high: skin.accentColor,
            scope: scope
        )

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
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        applyCornerMask(for: skin)
        needsDisplay = true
    }

    private func applyCornerMask(for skin: ModernSkin) {
        let cornerRadius = skin.config.window.cornerRadius ?? 0
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = cornerRadius > 0
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
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        skin.backgroundColor.setFill()
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
