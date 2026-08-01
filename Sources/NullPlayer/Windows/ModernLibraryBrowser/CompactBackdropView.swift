import AppKit

/// Independently rendered backdrop beneath a modern Library or Compact browser surface.
final class CompactBackdropView: NSView {
    private var artwork: NSImage?
    private var presenterStorage: CavaPresenter?
    let scope: CavaSettings.Scope
    private let modeProvider: () -> BrowserBackdropMode

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

    func updateArtwork(_ artwork: NSImage?) {
        self.artwork = artwork
        if modeProvider() == .albumArt {
            needsDisplay = true
        }
    }

    func reload() {
        let mode = modeProvider()
        isHidden = mode == .off

        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        layer?.cornerRadius = skin.config.window.cornerRadius ?? 0
        layer?.masksToBounds = (skin.config.window.cornerRadius ?? 0) > 0
        CavaSettings.setSkinDefaultColors(
            low: skin.primaryColor,
            high: skin.accentColor,
            scope: scope
        )

        if mode == .cava, shouldAnimate {
            presenter.start()
            presenter.settingsDidChange()
        } else {
            presenterStorage?.stop()
        }
        needsDisplay = true
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
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        skin.backgroundColor.setFill()
        bounds.fill()

        switch modeProvider() {
        case .off:
            return
        case .albumArt:
            guard let artwork,
                  let image = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return
            }
            context.saveGState()
            context.clip(to: bounds)
            context.interpolationQuality = .high
            context.draw(image, in: Self.aspectFillRect(
                imageSize: NSSize(width: image.width, height: image.height),
                targetRect: bounds
            ))
            context.restoreGState()
        case .cava:
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

    static func aspectFillRect(imageSize: NSSize, targetRect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0,
              targetRect.width > 0, targetRect.height > 0 else { return targetRect }
        let scale = max(targetRect.width / imageSize.width, targetRect.height / imageSize.height)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(
            x: targetRect.midX - size.width / 2,
            y: targetRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
