import AppKit

final class ReeltoneSurfaceWindowController: NSWindowController, NSWindowDelegate {
    let surface: ReeltoneSurface
    let surfaceView: ReeltoneSurfaceView
    var moveHandler: ((ReeltoneSurfaceWindowController) -> Void)?
    var visibilityHandler: ((ReeltoneSurfaceWindowController, Bool) -> Void)?

    init(
        surface: ReeltoneSurface,
        skin: ReeltoneLoadedSkin,
        scale: CGFloat,
        bridge: ReeltoneComponentBridging,
        hostFactory: ReeltoneComponentHostFactory = .live
    ) {
        self.surface = surface
        surfaceView = ReeltoneSurfaceView(surface: surface, skin: skin, bridge: bridge, hostFactory: hostFactory)
        let size = NSSize(width: surface.authoredSize.width * scale, height: surface.authoredSize.height * scale)
        let window = BorderlessWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.title = surface.displayName
        window.minSize = size
        window.maxSize = size
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        window.contentView = surfaceView
        window.delegate = self
        window.setAccessibilityIdentifier("ReeltoneWindow.\(surface.id.rawValue)")
        window.setAccessibilityLabel(surface.displayName)
        surfaceView.frame = NSRect(origin: .zero, size: size)
        surfaceView.autoresizingMask = [.width, .height]
        surfaceView.visibilityDidChange(window.isVisible)
    }

    required init?(coder: NSCoder) { nil }

    func applyScale(_ scale: CGFloat, preservingTopLeft: Bool = true) {
        guard let window else { return }
        let newSize = NSSize(width: surface.authoredSize.width * scale, height: surface.authoredSize.height * scale)
        var frame = window.frame
        let top = frame.maxY
        frame.size = newSize
        if preservingTopLeft { frame.origin.y = top - newSize.height }
        window.minSize = newSize
        window.maxSize = newSize
        window.setFrame(frame, display: true)
        surfaceView.needsLayout = true
        surfaceView.needsDisplay = true
    }

    func prepareForTeardown() {
        surfaceView.prepareForTeardown()
    }

    func windowDidMove(_ notification: Notification) { moveHandler?(self) }
    func windowWillMiniaturize(_ notification: Notification) {
        surfaceView.visibilityDidChange(false)
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        refreshEffectiveVisibility()
    }
    func windowDidChangeOcclusionState(_ notification: Notification) { refreshEffectiveVisibility() }
    func windowWillClose(_ notification: Notification) {
        surfaceView.visibilityDidChange(false)
        visibilityHandler?(self, false)
    }

    private func refreshEffectiveVisibility() {
        guard let window else { surfaceView.visibilityDidChange(false); return }
        surfaceView.visibilityDidChange(
            window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        )
    }
}
