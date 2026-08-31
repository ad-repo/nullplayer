import AppKit

struct ReeltonePanelMenuEntry: Equatable {
    let name: String
    let title: String
    let isVisible: Bool
}

final class ReeltoneSurfaceCoordinator: NSObject, ReeltoneSurfaceViewDelegate {
    let inventory: ReeltoneSurfaceInventory
    let diagnostics: [ReeltoneDiagnostic]

    private weak var mainWindow: NSWindow?
    private let skin: ReeltoneLoadedSkin
    private let bridge: ReeltoneComponentBridging
    private let identity: String
    private let defaults: UserDefaults
    private(set) var mainView: ReeltoneSurfaceView
    private var panels: [String: ReeltoneSurfaceWindowController] = [:]
    private var attachedPanels = Set<String>()
    private var suppressPanelMove = false
    private var suppressVisibilityPersistence = false
    private var panelsVisibleBeforeMainHide = Set<String>()
    private var panelsVisibleBeforeMiniaturize = Set<String>()
    private var lastMainFrame: NSRect
    private var lastMainVisibility: Bool?

    var allWindows: [NSWindow] {
        [mainWindow].compactMap { $0 } + panels.keys.sorted().compactMap { panels[$0]?.window }
    }

    var panelMenuEntries: [ReeltonePanelMenuEntry] {
        panels.keys.sorted().compactMap { name in
            guard let controller = panels[name] else { return nil }
            return .init(name: name, title: controller.surface.displayName, isVisible: controller.window?.isVisible == true)
        }
    }

    // Internal topology seams used by focused coordinator tests. Keeping these keyed by the
    // normalized panel name also avoids tests depending on controller-array ordering.
    var panelCount: Int { panels.count }
    var runningAnimationTimerCount: Int { surfaceViews.filter(\.isAnimationTimerRunning).count }
    func panelFrame(named name: String) -> NSRect? { panels[name]?.window?.frame }
    func panelIsAttached(named name: String) -> Bool { attachedPanels.contains(name) }
    func panelIsVisible(named name: String) -> Bool { panels[name]?.window?.isVisible == true }

    init(
        mainWindow: NSWindow,
        skin: ReeltoneLoadedSkin,
        inventory: ReeltoneSurfaceInventory,
        scale: CGFloat,
        identity: String,
        defaults: UserDefaults = ReeltoneDefaults.shared,
        bridge: ReeltoneComponentBridging = ReeltoneComponentBridge(),
        hostFactory: ReeltoneComponentHostFactory = .live
    ) {
        self.mainWindow = mainWindow
        self.skin = skin
        self.inventory = inventory
        self.identity = identity
        self.defaults = defaults
        self.bridge = bridge
        mainView = ReeltoneSurfaceView(surface: inventory.main, skin: skin, bridge: bridge, hostFactory: hostFactory)
        lastMainFrame = mainWindow.frame
        diagnostics = skin.diagnostics + inventory.diagnostics
        super.init()
        mainView.delegate = self
        mainView.frame = NSRect(origin: .zero, size: mainWindow.frame.size)
        mainView.autoresizingMask = [.width, .height]
        mainWindow.contentView = mainView
        mainView.visibilityDidChange(mainWindow.isVisible)
        createPanels(scale: scale, hostFactory: hostFactory)
    }

    func showInitialPanels() {
        guard let mainWindow else { return }
        lastMainFrame = mainWindow.frame
        for surface in inventory.panels {
            guard let name = surface.id.panelName, let controller = panels[name], let window = controller.window else { continue }
            if ReeltoneSkinState.panelIsDetached(identity: identity, surfaceID: surface.id, in: defaults),
               let restored = ReeltoneSkinState.panelFrame(identity: identity, surfaceID: surface.id, in: defaults),
               restored != .zero {
                window.setFrame(restored, display: false)
                attachedPanels.remove(name)
            } else {
                setAttachedFrame(for: name, display: false)
                attachedPanels.insert(name)
            }
            let visible = ReeltoneSkinState.panelVisibility(identity: identity, surfaceID: surface.id, in: defaults)
                ?? surface.initiallyVisible
            if visible {
                window.orderFront(nil)
                window.level = mainWindow.level
                controller.surfaceView.visibilityDidChange(true)
            } else {
                controller.surfaceView.visibilityDidChange(false)
            }
        }
    }

    func mainWindowDidMove() {
        guard let mainWindow else { return }
        suppressPanelMove = true
        for name in attachedPanels {
            // Generic docking may already have moved the panel with main. Re-derive the authored
            // attachment instead of adding a delta, which would move it twice.
            setAttachedFrame(for: name, display: true)
        }
        suppressPanelMove = false
        lastMainFrame = mainWindow.frame
    }

    func mainVisibilityDidChange(_ visible: Bool) {
        mainView.visibilityDidChange(visible)
        guard lastMainVisibility != visible else { return }
        lastMainVisibility = visible
        suppressVisibilityPersistence = true
        if visible {
            for name in panelsVisibleBeforeMainHide {
                panels[name]?.window?.orderFront(nil)
                panels[name]?.surfaceView.visibilityDidChange(true)
            }
            panelsVisibleBeforeMainHide.removeAll()
        } else {
            panelsVisibleBeforeMainHide = Set(panels.compactMap { $0.value.window?.isVisible == true ? $0.key : nil })
            for name in panelsVisibleBeforeMainHide {
                panels[name]?.surfaceView.visibilityDidChange(false)
                panels[name]?.window?.orderOut(nil)
            }
        }
        suppressVisibilityPersistence = false
    }

    func applyScale(_ scale: CGFloat) {
        guard let mainWindow else { return }
        suppressPanelMove = true
        let mainTop = mainWindow.frame.maxY
        var mainFrame = mainWindow.frame
        mainFrame.size = NSSize(width: inventory.main.authoredSize.width * scale, height: inventory.main.authoredSize.height * scale)
        mainFrame.origin.y = mainTop - mainFrame.height
        mainWindow.minSize = mainFrame.size
        mainWindow.maxSize = mainFrame.size
        mainWindow.setFrame(mainFrame, display: true)
        mainView.needsLayout = true
        mainView.needsDisplay = true
        panels.values.forEach { $0.applyScale(scale) }
        attachedPanels.forEach { setAttachedFrame(for: $0, display: true) }
        suppressPanelMove = false
        lastMainFrame = mainFrame
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        let level: NSWindow.Level = enabled ? .floating : .normal
        allWindows.forEach { $0.level = level }
    }

    func miniaturizeVisiblePanels() {
        panelsVisibleBeforeMiniaturize = Set(panels.compactMap { $0.value.window?.isVisible == true ? $0.key : nil })
        suppressVisibilityPersistence = true
        for name in panelsVisibleBeforeMiniaturize {
            panels[name]?.surfaceView.visibilityDidChange(false)
            panels[name]?.window?.miniaturize(nil)
        }
        suppressVisibilityPersistence = false
    }

    func restoreVisiblePanelsAfterMiniaturize() {
        suppressVisibilityPersistence = true
        for name in panelsVisibleBeforeMiniaturize {
            panels[name]?.window?.deminiaturize(nil)
            panels[name]?.surfaceView.visibilityDidChange(true)
        }
        suppressVisibilityPersistence = false
        panelsVisibleBeforeMiniaturize.removeAll()
    }

    func updatePlaybackState() { surfaceViews.forEach { $0.updatePlaybackState() } }
    func updateTime(current: TimeInterval, duration: TimeInterval) { surfaceViews.forEach { $0.updateTime(current: current, duration: duration) } }
    func updateTrack(_ track: Track?) { surfaceViews.forEach { $0.updateTrack(track) } }
    func updateSpectrum(_ levels: [Float]) { surfaceViews.forEach { $0.updateSpectrum(levels) } }
    func updateTheme() { surfaceViews.forEach { $0.updateTheme() } }

    func route(component: ReeltoneComponent) -> Bool {
        guard let owner = inventory.owner(of: component) else { return false }
        if case .panel(let name) = owner {
            showPanel(name)
            panels[name]?.window?.makeKeyAndOrderFront(nil)
            _ = panels[name]?.surfaceView.focusHostedComponent(component)
            return true
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        _ = mainView.focusHostedComponent(component)
        return true
    }

    func togglePanel(_ name: String) {
        guard let controller = panels[name], let window = controller.window else { return }
        if window.isVisible {
            persist(controller, visible: false)
            controller.surfaceView.visibilityDidChange(false)
            window.orderOut(nil)
        } else {
            showPanel(name)
        }
    }

    func captureLayout() -> ReeltoneSurfaceLayoutSnapshot {
        let panelSnapshots = inventory.panels.compactMap { surface -> ReeltonePanelLayoutSnapshot? in
            guard let name = surface.id.panelName, let window = panels[name]?.window else { return nil }
            return .init(
                surfaceID: surface.id,
                frame: window.frame,
                wasVisible: window.isVisible,
                wasAttached: attachedPanels.contains(name)
            )
        }
        return .init(skinIdentity: identity, panels: panelSnapshots)
    }

    func restoreLayout(_ snapshot: ReeltoneSurfaceLayoutSnapshot) {
        guard snapshot.skinIdentity == identity else { return }
        suppressPanelMove = true
        suppressVisibilityPersistence = true
        defer {
            suppressVisibilityPersistence = false
            suppressPanelMove = false
        }

        for state in snapshot.panels {
            guard let name = state.surfaceID.panelName,
                  let controller = panels[name],
                  let window = controller.window else { continue }
            if state.wasAttached {
                attachedPanels.insert(name)
                setAttachedFrame(for: name, display: false)
            } else {
                attachedPanels.remove(name)
                let frame = ReeltonePanelGeometry.frameForPresentation(
                    state.frame,
                    visibleFrames: NSScreen.screens.map(\.visibleFrame)
                )
                window.setFrame(frame, display: false)
            }
            if state.wasVisible {
                window.orderFront(nil)
                controller.surfaceView.visibilityDidChange(true)
            } else {
                controller.surfaceView.visibilityDidChange(false)
                window.orderOut(nil)
            }
        }
    }

    func prepareForTeardown() {
        mainView.prepareForTeardown()
        suppressVisibilityPersistence = true
        for controller in panels.values {
            controller.surfaceView.visibilityDidChange(false)
            controller.prepareForTeardown()
            controller.window?.orderOut(nil)
            controller.close()
        }
        suppressVisibilityPersistence = false
        panels.removeAll()
        attachedPanels.removeAll()
    }

    func reeltoneSurfaceViewDidRequestClose(_ view: ReeltoneSurfaceView) {
        if view === mainView { mainWindow?.close(); return }
        guard let entry = panels.first(where: { $0.value.surfaceView === view }) else { return }
        togglePanel(entry.key)
    }

    func reeltoneSurfaceViewDidRequestMinimise(_ view: ReeltoneSurfaceView) {
        guard let mainWindow else { return }
        if view === mainView {
            mainWindow.miniaturize(nil)
        } else {
            view.visibilityDidChange(false)
            view.window?.miniaturize(nil)
        }
    }

    func reeltoneSurfaceView(_ view: ReeltoneSurfaceView, togglePanel name: String) { togglePanel(name) }

    func reeltoneSurfaceViewDidRequestLibraryBack(_ view: ReeltoneSurfaceView) {
        for surfaceView in surfaceViews {
            for subview in surfaceView.subviews {
                if let library = subview as? ModernLibraryBrowserView { library.navigateBackFromEmbeddedHost(); return }
            }
        }
    }

    private var surfaceViews: [ReeltoneSurfaceView] {
        [mainView] + panels.keys.sorted().compactMap { panels[$0]?.surfaceView }
    }

    private func createPanels(scale: CGFloat, hostFactory: ReeltoneComponentHostFactory) {
        for surface in inventory.panels {
            guard let name = surface.id.panelName else { continue }
            let controller = ReeltoneSurfaceWindowController(
                surface: surface,
                skin: skin,
                scale: scale,
                bridge: bridge,
                hostFactory: hostFactory
            )
            controller.surfaceView.delegate = self
            controller.moveHandler = { [weak self] controller in self?.panelDidMove(name: name, controller: controller) }
            controller.visibilityHandler = { [weak self] controller, visible in self?.persist(controller, visible: visible) }
            panels[name] = controller
        }
    }

    private func showPanel(_ name: String) {
        guard let controller = panels[name], let window = controller.window else { return }
        if window.frame == .zero { setAttachedFrame(for: name, display: false) }
        window.level = mainWindow?.level ?? .normal
        window.makeKeyAndOrderFront(nil)
        controller.surfaceView.visibilityDidChange(true)
        persist(controller, visible: true)
    }

    private func panelDidMove(name: String, controller: ReeltoneSurfaceWindowController) {
        guard !suppressPanelMove, let frame = controller.window?.frame else { return }
        let expected = attachedFrame(for: controller.surface)
        let detached = abs(frame.minX - expected.minX) > 2 || abs(frame.minY - expected.minY) > 2
        if detached {
            attachedPanels.remove(name)
        } else {
            attachedPanels.insert(name)
        }
        ReeltoneSkinState.setPanelDetached(detached, identity: identity, surfaceID: controller.surface.id, in: defaults)
        ReeltoneSkinState.setPanelFrame(frame, identity: identity, surfaceID: controller.surface.id, in: defaults)
    }

    private func persist(_ controller: ReeltoneSurfaceWindowController, visible: Bool) {
        guard !suppressVisibilityPersistence else { return }
        ReeltoneSkinState.setPanelVisibility(visible, identity: identity, surfaceID: controller.surface.id, in: defaults)
        if let frame = controller.window?.frame, frame != .zero {
            ReeltoneSkinState.setPanelFrame(frame, identity: identity, surfaceID: controller.surface.id, in: defaults)
        }
    }

    private func setAttachedFrame(for name: String, display: Bool) {
        guard let controller = panels[name], let window = controller.window else { return }
        window.setFrame(attachedFrame(for: controller.surface), display: display)
    }

    private func attachedFrame(for surface: ReeltoneSurface) -> NSRect {
        guard let main = mainWindow?.frame else { return .zero }
        let size = panels[surface.id.panelName ?? ""]?.window?.frame.size ?? .zero
        return ReeltonePanelGeometry.attachedFrame(mainFrame: main, panelSize: size, attachment: surface.attachment ?? .right)
    }
}
