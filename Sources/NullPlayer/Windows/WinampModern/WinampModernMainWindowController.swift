import AppKit

final class WinampModernMainWindowController: NSWindowController, MainWindowProviding, NSWindowDelegate {
    private var loadedSkin: WinampModernLoadedSkin?
    private var skinView: WinampModernMainView?
    private var host: WinampModernAudioEngineHost?
    private var componentBridge: WinampModernComponentBridge?
    private var auxiliaryContainers: [AuxiliaryContainer] = []
    private var isApplyingSkinSize = false

    /// A separate visible container (the "separate windows" arrangement) rendered in its own native
    /// window with the shared script runtime + component host. cPro-Bento is a single-window SUI so
    /// this stays empty for it; skins that declare multiple visible containers populate it.
    private struct AuxiliaryContainer {
        let window: NSWindow
        let view: WinampModernMainView
        let kind: WinampModernComponentKind?
    }
    private(set) var loadFailure: Error?

    convenience init() {
        let defaultSize = NSSize(width: 275, height: 116)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: defaultSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        self.init(window: window)
        setupWindow()
        #if DEBUG
        if let localPath = UserDefaults.standard.string(forKey: "winampModernSkinPath"),
           !localPath.isEmpty {
            loadSkin(at: URL(fileURLWithPath: localPath))
            return
        }
        #endif
        if let selected = WinampModernSkinImporter.shared.selectedSkin() {
            loadSkin(at: selected.archiveURL)
        } else {
            showPlaceholder("Import a .wal skin from the DEBUG Winamp Modern menu")
        }
    }

    private func setupWindow() {
        guard let window else { return }
        window.title = "NullPlayer — Winamp Modern"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.styleMask.insert(.resizable)
        window.delegate = self
        window.center()
        window.setAccessibilityIdentifier("WinampModernMainWindow")
        window.setAccessibilityLabel("Winamp Modern Main Window")
    }

    func loadSkin(at url: URL) {
        tearDownSkin()
        do {
            let loaded = try WinampModernSkinLoader().load(from: url)
            let host = WinampModernAudioEngineHost(engine: WindowManager.shared.audioEngine)
            let componentBridge = WinampModernComponentBridge(engine: WindowManager.shared.audioEngine)
            let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
            renderer.componentHost = componentBridge
            let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
            let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                            componentHost: componentBridge)

            loadedSkin = loaded
            self.host = host
            self.componentBridge = componentBridge
            skinView = view
            view.canvasSizeDidChange = { [weak self] size in self?.resizeWindow(to: size) }
            loadFailure = nil
            window?.contentView = view
            resizeWindow(to: renderer.canvasSize)
            setupAuxiliaryContainers(loaded: loaded, host: host, scripts: scripts,
                                     componentBridge: componentBridge)
            view.componentWindowToggleRequested = { [weak self] kind in
                self?.toggleAuxiliaryWindow(for: kind) ?? false
            }
            try scripts.start()
            view.updatePlaybackState()
            view.updateTime(current: host.currentTime, duration: host.duration)
            view.needsDisplay = true
        } catch {
            loadFailure = error
            NSLog("WinampModern: Failed to load '%@': %@", url.lastPathComponent, error.localizedDescription)
            tearDownSkin()
            showPlaceholder(error.localizedDescription)
        }
    }

    /// Create one native window per visible non-main container. The main window owns the scripted
    /// scene; auxiliary containers render + take input against the shared runtime but do not drive
    /// the single-owner script callbacks (`drivesScripts: false`). Full per-container MAKI layout
    /// switching in auxiliary windows is deferred to Phase 7.
    private func setupAuxiliaryContainers(loaded: WinampModernLoadedSkin,
                                          host: WinampModernAudioEngineHost,
                                          scripts: WinampModernScriptRuntime,
                                          componentBridge: WinampModernComponentBridge) {
        let containers = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
            .filter { !$0.isMainPlayer }
        for info in containers {
            guard let renderer = try? WasabiSceneRenderer(loadedSkin: loaded, host: host,
                                                          containerID: info.id) else { continue }
            renderer.componentHost = componentBridge
            let view = WinampModernMainView(renderer: renderer, scripts: scripts, host: host,
                                            componentHost: componentBridge, drivesScripts: false)
            let auxWindow = NSWindow(contentRect: NSRect(origin: .zero, size: renderer.canvasSize),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
            auxWindow.isReleasedWhenClosed = false
            auxWindow.isOpaque = false
            auxWindow.backgroundColor = .clear
            auxWindow.hasShadow = false
            auxWindow.contentView = view
            auxWindow.setAccessibilityIdentifier("WinampModernContainer_\(info.id)")
            auxWindow.orderOut(nil)
            let kind = WinampModernComponentRegistry.kind(for: info.id)
            auxiliaryContainers.append(AuxiliaryContainer(window: auxWindow, view: view, kind: kind))
        }
    }

    @discardableResult
    private func toggleAuxiliaryWindow(for kind: WinampModernComponentKind) -> Bool {
        guard let container = auxiliaryContainers.first(where: { $0.kind == kind }) else { return false }
        if container.window.isVisible {
            container.window.orderOut(nil)
        } else {
            container.view.needsDisplay = true
            container.window.orderFront(nil)
        }
        return true
    }

    /// Number of separate-container windows the current skin declares (0 for a single-window SUI).
    var auxiliaryContainerCount: Int { auxiliaryContainers.count }

    private func resizeWindow(to size: NSSize) {
        guard let window else { return }
        guard !isApplyingSkinSize else { return }
        isApplyingSkinSize = true
        defer { isApplyingSkinSize = false }
        let oldTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        window.setFrame(NSRect(x: oldTopLeft.x, y: oldTopLeft.y - frame.height,
                               width: frame.width, height: frame.height), display: true)
    }

    private func showPlaceholder(_ message: String) {
        let size = NSSize(width: 275, height: 116)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        let label = NSTextField(wrappingLabelWithString: "Winamp Modern (.wal)\n\(message)")
        label.font = .systemFont(ofSize: 10)
        label.textColor = NSColor(white: 0.7, alpha: 1)
        label.alignment = .center
        label.frame = NSRect(x: 12, y: 28, width: size.width - 24, height: 60)
        content.addSubview(label)
        window?.contentView = content
        resizeWindow(to: size)
    }

    func updateTrackInfo(_ track: Track?) { skinView?.updateTrackInfo() }
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) { skinView?.updateTrackInfo() }
    func clearVideoTrackInfo() { skinView?.updateTrackInfo() }
    func updateTime(current: TimeInterval, duration: TimeInterval) {
        skinView?.updateTime(current: current, duration: duration)
    }
    func updatePlaybackState() { skinView?.updatePlaybackState() }
    func updateSpectrum(_ levels: [Float]) { skinView?.updateSpectrum(levels) }
    func skinDidChange() { skinView?.needsDisplay = true }
    func windowVisibilityDidChange() { skinView?.needsDisplay = true }

    func windowDidResize(_ notification: Notification) {
        guard !isApplyingSkinSize, let view = skinView, let window, window.contentView === view else { return }
        let size = view.renderer.resize(to: window.contentLayoutRect.size)
        if size != window.contentLayoutRect.size { resizeWindow(to: size) }
        if size != view.frame.size { view.setFrameSize(size) }
        view.needsDisplay = true
    }

    func prepareForUITeardown() { tearDownSkin() }

    private func tearDownSkin() {
        // Auxiliary views share the main view's script runtime + host, so tear them down first
        // (they only release their own renderer); the main view then tears down the shared runtime.
        for container in auxiliaryContainers {
            container.view.teardown()
            container.window.orderOut(nil)
            container.window.contentView = nil
        }
        auxiliaryContainers.removeAll()
        skinView?.teardown()
        skinView = nil
        host?.endVisualizationConsumption()
        host = nil
        componentBridge = nil
        loadedSkin?.teardown()
        loadedSkin = nil
    }

    deinit { tearDownSkin() }
}
