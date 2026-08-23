import AppKit

/// Lazily turns hosted-window route metadata into one trusted graph subtree, scene, and native
/// window. Every registered feature travels through this same path; only its existing content view
/// differs at the registry boundary.
final class WinampModernHostedWindowMaterializer: NSObject, NSWindowDelegate {
    struct MaterializedWindow {
        let id: WinampModernHostedWindowID
        let graphRoot: WasabiObject
        let window: NSWindow
        let view: WinampModernMainView
    }

    private let loadedSkin: WinampModernLoadedSkin
    private let host: WinampModernHost
    private let scripts: WinampModernScriptRuntime
    private weak var componentHost: WinampModernComponentHost?
    private let skinScale: () -> CGFloat
    private let classicFallback: (WinampModernHostedWindowID, Bool) -> Void
    private let instanceDidMaterialize: (MaterializedWindow) -> Void
    private let instanceWillTeardown: (MaterializedWindow) -> Void
    private let visibilityDidChange: (WinampModernHostedWindowID, Bool, NSRect) -> Void
    /// Synthetic tests use a no-op MAKI fixture and install the content group at the exact point a
    /// real standard-frame script would. Nil in every application construction.
    private let testContentInstaller: ((WasabiObject, WinampModernHostedWindowID) throws -> Void)?
    private var instances: [WinampModernHostedWindowID: MaterializedWindow] = [:]
    private var failedIDs: Set<WinampModernHostedWindowID> = []
    private var programmaticResizeWindows: Set<ObjectIdentifier> = []
    private var isTornDown = false

    init(loadedSkin: WinampModernLoadedSkin,
         host: WinampModernHost,
         scripts: WinampModernScriptRuntime,
         componentHost: WinampModernComponentHost,
         skinScale: @escaping () -> CGFloat,
         classicFallback: @escaping (WinampModernHostedWindowID, Bool) -> Void,
         instanceDidMaterialize: @escaping (MaterializedWindow) -> Void = { _ in },
         instanceWillTeardown: @escaping (MaterializedWindow) -> Void = { _ in },
         visibilityDidChange: @escaping (WinampModernHostedWindowID, Bool, NSRect) -> Void = { _, _, _ in },
         testContentInstaller: ((WasabiObject, WinampModernHostedWindowID) throws -> Void)? = nil) {
        self.loadedSkin = loadedSkin
        self.host = host
        self.scripts = scripts
        self.componentHost = componentHost
        self.skinScale = skinScale
        self.classicFallback = classicFallback
        self.instanceDidMaterialize = instanceDidMaterialize
        self.instanceWillTeardown = instanceWillTeardown
        self.visibilityDidChange = visibilityDidChange
        self.testContentInstaller = testContentInstaller
    }

    func route(for id: WinampModernHostedWindowID) -> WinampModernHostedWindowRoute {
        if failedIDs.contains(id) {
            return .classicFallback(reason: "request-time materialization previously failed")
        }
        return loadedSkin.surfaceSynthesis.hostedWindows[id]
    }

    func handles(_ id: WinampModernHostedWindowID) -> Bool {
        if case .skinFrame = route(for: id) { return true }
        return false
    }

    @discardableResult
    func show(_ id: WinampModernHostedWindowID, frame: NSRect? = nil) -> Bool {
        guard !isTornDown else { return false }
        switch route(for: id) {
        case .classicFallback:
            classicFallback(id, true)
            return false
        case .skinFrame:
            guard let instance = materialize(id) else {
                classicFallback(id, true)
                return false
            }
            if let frame { instance.window.setFrame(frame, display: false) }
            instance.view.needsLayout = true
            instance.view.layoutSubtreeIfNeeded()
            setVisible(true, for: instance)
            return true
        }
    }

    @discardableResult
    func toggle(_ id: WinampModernHostedWindowID) -> Bool {
        if let instance = instances[id], instance.window.isVisible {
            setVisible(false, for: instance)
            return true
        }
        return show(id)
    }

    func hide(_ id: WinampModernHostedWindowID) {
        guard let instance = instances[id] else { return }
        setVisible(false, for: instance)
    }

    func isVisible(_ id: WinampModernHostedWindowID) -> Bool {
        instances[id]?.window.isVisible == true
    }

    /// Inspection and restoration must not accidentally instantiate an unopened window.
    func nativeWindow(ifMaterialized id: WinampModernHostedWindowID) -> NSWindow? {
        instances[id]?.window
    }

    func nativeWindow(materializing id: WinampModernHostedWindowID) -> NSWindow? {
        materialize(id)?.window
    }

    func frame(ifMaterialized id: WinampModernHostedWindowID) -> NSRect? {
        instances[id]?.window.frame
    }

    func setFrame(_ frame: NSRect, for id: WinampModernHostedWindowID) {
        instances[id]?.window.setFrame(frame, display: false)
    }

    var materializedWindows: [MaterializedWindow] {
        WinampModernHostedWindowID.allCases.compactMap { instances[$0] }
    }

    /// Re-scales only already-materialized windows. Route metadata stays lazy, so changing UI Size
    /// never constructs a hosted window the user has not opened.
    func applySkinScale(_ scale: CGFloat) {
        let scale = max(scale, 0.01)
        for instance in materializedWindows {
            let topLeft = NSPoint(x: instance.window.frame.minX, y: instance.window.frame.maxY)
            instance.view.skinScale = scale
            let limits = instance.view.renderer.userResizeLimits
            instance.window.contentMinSize = NSSize(width: limits.minimum.width * scale,
                                                    height: limits.minimum.height * scale)
            instance.window.contentMaxSize = NSSize(
                width: limits.maximum.width.isFinite
                    ? limits.maximum.width * scale : CGFloat.greatestFiniteMagnitude,
                height: limits.maximum.height.isFinite
                    ? limits.maximum.height * scale : CGFloat.greatestFiniteMagnitude)
            let size = instance.view.scaledCanvasSize
            instance.window.setContentSize(size)
            instance.window.setFrameTopLeftPoint(topLeft)
            instance.view.setFrameSize(size)
            instance.view.needsDisplay = true
        }
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        for instance in materializedWindows {
            instanceWillTeardown(instance)
            instance.view.setHostedContentActive(false)
            instance.view.setSceneVisible(false)
            instance.view.teardown()
            instance.window.orderOut(nil)
            instance.window.contentView = nil
            instance.window.delegate = nil
        }
        instances.removeAll()
    }

    private func materialize(_ id: WinampModernHostedWindowID) -> MaterializedWindow? {
        if let instance = instances[id] { return instance }
        guard !failedIDs.contains(id),
              let definition = WinampModernHostedWindowRegistry.entry(id: id),
              case .skinFrame(let frame) = loadedSkin.surfaceSynthesis.hostedWindows[id],
              let instantiate = loadedSkin.runtime.instantiateHostedWindow,
              let componentHost else { return nil }

        var root: WasabiObject?
        var view: WinampModernMainView?
        var nativeWindow: NSWindow?
        do {
            let createdRoot = try instantiate(.init(definition: definition, frame: frame))
            root = createdRoot
            let renderer = try WasabiSceneRenderer(loadedSkin: loadedSkin, host: host,
                                                   containerID: id.containerIdentifier)
            renderer.componentHost = componentHost
            renderer.configStateProvider = { [weak scripts] in scripts?.configValue(of: $0) ?? false }
            renderer.configValueProvider = { [weak scripts] in scripts?.configInteger(of: $0) }
            renderer.layerFXProvider = { [weak scripts] in scripts?.layerFXMesh(for: $0) }
            let createdView = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                                   componentHost: componentHost,
                                                   drivesScripts: false)
            view = createdView
            createdView.skinScale = skinScale()

            let window = WinampModernSkinWindow(
                contentRect: NSRect(origin: .zero, size: createdView.scaledCanvasSize),
                styleMask: [.borderless, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false)
            nativeWindow = window
            window.title = definition.title
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.contentView = createdView
            window.delegate = self
            let limits = renderer.userResizeLimits
            let scale = max(skinScale(), 0.01)
            window.contentMinSize = NSSize(width: limits.minimum.width * scale,
                                           height: limits.minimum.height * scale)
            window.contentMaxSize = NSSize(width: limits.maximum.width.isFinite
                                                ? limits.maximum.width * scale
                                                : CGFloat.greatestFiniteMagnitude,
                                           height: limits.maximum.height.isFinite
                                                ? limits.maximum.height * scale
                                                : CGFloat.greatestFiniteMagnitude)
            window.setAccessibilityIdentifier("WinampModernHostedWindow_\(id.rawValue)")
            window.setAccessibilityLabel(definition.title)
            window.orderOut(nil)
            createdView.closeRequested = { [weak self] in self?.hide(id) }
            createdView.minimizeRequested = { [weak window] in window?.miniaturize(nil) }
            createdView.canvasSizeDidChange = { [weak window, weak createdView] size in
                guard let window, let createdView else { return }
                window.setContentSize(size)
                if createdView.frame.size != size { createdView.setFrameSize(size) }
            }

            try scripts.startTrustedHostedWindowScripts(beneath: createdRoot)
            try testContentInstaller?(createdRoot, id)
            createdView.scriptsDidStart()
            createdView.needsLayout = true
            createdView.layoutSubtreeIfNeeded()
            guard createdView.hasHostedWindowSurface(id) else {
                throw WalFailure(WalDiagnostic(
                    .unsupportedElement,
                    "Hosted window '\(id.rawValue)' produced no host surface.",
                    severity: .warning,
                    location: WalSourceLocation(path: WasabiSurfaceSynthesizer.sourcePath)))
            }

            let instance = MaterializedWindow(id: id, graphRoot: createdRoot,
                                              window: window, view: createdView)
            instances[id] = instance
            instanceDidMaterialize(instance)
            return instance
        } catch {
            view?.teardown()
            nativeWindow?.orderOut(nil)
            nativeWindow?.contentView = nil
            nativeWindow?.delegate = nil
            if let root { loadedSkin.runtime.discardHostedWindow(root) }
            failedIDs.insert(id)
            loadedSkin.runtime.record(WalDiagnostic(
                .malformedXML,
                "Hosted window '\(id.rawValue)' could not be materialized and will use the "
                    + "fallback: \(error.localizedDescription)",
                severity: .warning,
                location: WalSourceLocation(path: WasabiSurfaceSynthesizer.sourcePath)))
            return nil
        }
    }

    private func setVisible(_ visible: Bool, for instance: MaterializedWindow) {
        guard instance.window.isVisible != visible else { return }
        let transitionFrame = instance.window.frame
        if visible {
            instance.window.orderFront(nil)
        } else {
            instance.view.setHostedContentActive(false)
            instance.view.setSceneVisible(false)
            instance.window.orderOut(nil)
        }
        if visible {
            instance.view.setSceneVisible(true)
            updateConsumerState(for: instance)
        }
        visibilityDidChange(instance.id, visible, transitionFrame)
    }

    private func updateConsumerState(for instance: MaterializedWindow) {
        let active = instance.window.isVisible && !instance.window.isMiniaturized
            && instance.window.occlusionState.contains(.visible)
        instance.view.setHostedContentActive(active)
    }

    private func instance(for window: NSWindow) -> MaterializedWindow? {
        instances.values.first { $0.window === window }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let instance = instance(for: sender) else { return true }
        setVisible(false, for: instance)
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) { update(from: notification) }
    func windowDidDeminiaturize(_ notification: Notification) { update(from: notification) }
    func windowDidChangeOcclusionState(_ notification: Notification) { update(from: notification) }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let instance = instance(for: window) else { return }
        let key = ObjectIdentifier(window)
        guard !programmaticResizeWindows.contains(key) else { return }
        let scale = max(skinScale(), 0.01)
        let proposed = CGSize(width: window.contentLayoutRect.width / scale,
                              height: window.contentLayoutRect.height / scale)
        let accepted = instance.view.renderer.resize(to: proposed)
        let target = CGSize(width: accepted.width * scale, height: accepted.height * scale)
        if target != window.contentLayoutRect.size {
            programmaticResizeWindows.insert(key)
            window.setContentSize(target)
            programmaticResizeWindows.remove(key)
        }
        instance.view.setFrameSize(target)
        instance.view.needsDisplay = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let instance = instance(for: window) else { return }
        instance.view.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let instance = instance(for: window) else { return }
        instance.view.needsDisplay = true
    }

    private func update(from notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let instance = instance(for: window) else { return }
        updateConsumerState(for: instance)
    }

    deinit { teardown() }
}
