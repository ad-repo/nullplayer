import AppKit

final class WMPMainWindowController: NSWindowController, MainWindowProviding, NSWindowDelegate {
    static let unskinnedSize = NSSize(width: 440, height: 170)

    private let importer: WMPSkinImporter
    private var loadTask: Task<Void, Never>?
    private var loadedSkin: WMPLoadedSkin?
    private var imageStore: WMPImageStore?
    private var activeViewID: String?
    private var activeLimits: WMPResizeLimits?
    private var mainView: WMPMainView?
    private var unskinnedView: WMPUnskinnedMainView?
    private var isApplyingSceneSize = false
    private var pendingRestoredFrame: NSRect?
    private var pendingRestoredViewID: String?
    private(set) var lastLoadDiagnostic: String?

    convenience init() {
        self.init(importer: WMPSkinImporter())
    }

    init(importer: WMPSkinImporter) {
        self.importer = importer
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.unskinnedSize),
                              styleMask: [.borderless, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        configureWindow()
        presentUnskinned(message: nil)
        reloadSelectedSkin()
    }

    required init?(coder: NSCoder) { nil }

    private func configureWindow() {
        guard let window else { return }
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.title = "NullPlayer — Windows Media Player"
        window.minSize = Self.unskinnedSize
        window.delegate = self
        window.center()
        window.setAccessibilityIdentifier("WMPMainWindow")
        window.setAccessibilityLabel("Windows Media Player Main Window")
    }

    func reloadSelectedSkin() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let url = try importer.selectedSkinURL() else {
                    presentUnskinned(message: nil)
                    return
                }
                let skin = try await importer.loader.load(from: url)
                try Task.checkCancellation()
                let preferred = importer.selectedViewID
                let registration = preferred.flatMap { wanted in
                    skin.views.first { $0.id.caseInsensitiveCompare(wanted) == .orderedSame }
                } ?? skin.views.first { $0.id.caseInsensitiveCompare("vPlayer") == .orderedSame }
                    ?? skin.views.first
                guard let registration else {
                    throw WMPFailure(WMPDiagnostic(.invalidGeometry, "The skin contains no renderable WMP view."))
                }
                let store = WMPImageStore(provider: skin.archive)
                let restoredViewMatches = pendingRestoredViewID?.caseInsensitiveCompare(registration.id) == .orderedSame
                let requested = restoredViewMatches ? pendingRestoredFrame.map {
                    WMPSize(width: $0.width, height: $0.height)
                } : nil
                if pendingRestoredFrame != nil, !restoredViewMatches {
                    pendingRestoredFrame = nil
                    pendingRestoredViewID = nil
                }
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: registration.id, requestedSize: requested)
                let rendered = try await WMPRenderer(imageStore: store).render(scene: scene, backingScale: 1)
                try Task.checkCancellation()
                apply(skin: skin, store: store, scene: scene, image: rendered.image)
            } catch is CancellationError {
                return
            } catch {
                presentUnskinned(message: error.localizedDescription)
            }
        }
    }

    func importSkinFromPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "wmz")!]
        panel.message = "Select a Windows Media Player .wmz skin"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importSkin(from: url)
    }

    func importSkin(from url: URL) {
        loadTask?.cancel()
        presentUnskinned(message: "Validating and importing \(url.lastPathComponent)…")
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await importer.importSkin(from: url)
                try Task.checkCancellation()
                reloadSelectedSkin()
            } catch is CancellationError {
                return
            } catch {
                presentUnskinned(message: error.localizedDescription)
            }
        }
    }

    func selectInstalledSkin(named name: String) {
        guard let skin = importer.installedSkins().first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            presentUnskinned(message: WMPSkinImportError.selectionMissing(name).localizedDescription)
            return
        }
        importer.select(skin)
        reloadSelectedSkin()
    }

    func resetToUnskinned() {
        loadTask?.cancel()
        importer.resetSelection()
        presentUnskinned(message: nil)
    }

    func restoreFrame(_ frame: NSRect, skinName: String?, viewID: String?) {
        guard frame != .zero else { return }
        let selectedName = importer.selectedSkinName
        let nameMatches = selectedName?.caseInsensitiveCompare(skinName ?? "") == .orderedSame
            || (selectedName == nil && skinName == nil)
        let selectedView = importer.selectedViewID
        let viewMatches = selectedView?.caseInsensitiveCompare(viewID ?? "") == .orderedSame
            || (selectedView == nil && viewID == nil)
        guard nameMatches, viewMatches else { return }
        pendingRestoredFrame = WMPWindowRestorePolicy.safeFrame(frame, screens: NSScreen.screens.map(\.visibleFrame))
        pendingRestoredViewID = viewID
        if loadedSkin != nil { reloadSelectedSkin() }
        else if skinName == nil, let safe = pendingRestoredFrame {
            // The unskinned player owns a fixed safe size; restore position only.
            var positioned = safe
            positioned.size = Self.unskinnedSize
            positioned.origin.y = safe.maxY - Self.unskinnedSize.height
            window?.setFrame(positioned, display: true)
        }
    }

    private func apply(skin: WMPLoadedSkin, store: WMPImageStore, scene: WMPScene, image: CGImage) {
        loadedSkin = skin
        imageStore = store
        activeViewID = scene.viewID
        activeLimits = scene.resizeLimits
        lastLoadDiagnostic = nil
        importer.defaults.set(scene.viewID, forKey: WMPSkinImporter.selectedViewIDKey)

        let view = mainView ?? WMPMainView(frame: .zero)
        mainView = view
        unskinnedView = nil
        window?.contentView = view
        if let restored = pendingRestoredFrame {
            var frame = restored
            frame.size = NSSize(width: scene.canvasSize.width, height: scene.canvasSize.height)
            frame.origin.y = restored.maxY - frame.height
            isApplyingSceneSize = true
            window?.setFrame(frame, display: true)
            isApplyingSceneSize = false
            pendingRestoredFrame = nil
            pendingRestoredViewID = nil
        } else {
            setWindowSize(NSSize(width: scene.canvasSize.width, height: scene.canvasSize.height))
        }
        view.present(image)
    }

    private func presentUnskinned(message: String?) {
        loadedSkin = nil
        imageStore = nil
        activeViewID = nil
        activeLimits = nil
        lastLoadDiagnostic = message
        mainView?.prepareForUITeardown()
        mainView = nil

        let view = unskinnedView ?? WMPUnskinnedMainView(frame: NSRect(origin: .zero, size: Self.unskinnedSize))
        unskinnedView = view
        view.onImport = { [weak self] in self?.importSkinFromPanel() }
        view.onMinimize = { [weak self] in self?.window?.miniaturize(nil) }
        view.onClose = { [weak self] in self?.window?.orderOut(nil) }
        view.show(message: message)
        window?.contentView = view
        setWindowSize(Self.unskinnedSize)
    }

    private func setWindowSize(_ size: NSSize) {
        guard let window else { return }
        let old = window.frame
        var frame = old
        frame.size = size
        frame.origin.y = old.maxY - size.height
        isApplyingSceneSize = true
        window.setFrame(frame, display: true)
        isApplyingSceneSize = false
    }

    private func renderCurrentSize() {
        guard !isApplyingSceneSize, let skin = loadedSkin, let store = imageStore,
              let viewID = activeViewID, let window else { return }
        loadTask?.cancel()
        let requested = WMPSize(width: window.contentLayoutRect.width, height: window.contentLayoutRect.height)
        loadTask = Task { [weak self] in
            do {
                let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                    .build(viewID: viewID, requestedSize: requested)
                let result = try await WMPRenderer(imageStore: store).render(scene: scene, backingScale: 1)
                try Task.checkCancellation()
                self?.mainView?.present(result.image)
            } catch is CancellationError {} catch {
                self?.lastLoadDiagnostic = error.localizedDescription
            }
        }
    }

    func prepareForUITeardown() {
        loadTask?.cancel()
        loadTask = nil
        mainView?.prepareForUITeardown()
        mainView = nil
        unskinnedView?.onImport = nil
        unskinnedView?.onMinimize = nil
        unskinnedView?.onClose = nil
        unskinnedView = nil
        loadedSkin = nil
        imageStore = nil
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let limits = activeLimits else { return Self.unskinnedSize }
        let clamped = limits.clamp(WMPSize(width: frameSize.width, height: frameSize.height))
        return NSSize(width: clamped.width, height: clamped.height)
    }

    func windowDidResize(_ notification: Notification) { renderCurrentSize() }
    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
    }
    func windowWillMiniaturize(_ notification: Notification) {
        if let window { WindowManager.shared.attachDockedWindowsForMiniaturize(mainWindow: window) }
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        if let window { WindowManager.shared.detachDockedWindowsAfterDeminiaturize(mainWindow: window) }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func updateTrackInfo(_ track: Track?) {}
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) {}
    func clearVideoTrackInfo() {}
    func updateTime(current: TimeInterval, duration: TimeInterval) {}
    func updatePlaybackState() {}
    func updateSpectrum(_ levels: [Float]) {}
    func skinDidChange() {}
    func windowVisibilityDidChange() {}
    func setNeedsDisplay() { window?.contentView?.needsDisplay = true }
}

enum WMPWindowRestorePolicy {
    static func safeFrame(_ frame: NSRect, screens: [NSRect]) -> NSRect {
        guard let screen = screens.first(where: { $0.intersects(frame) }) ?? screens.first else { return frame }
        var result = frame
        // Preserve the saved top-left anchor where possible while keeping a usable strip visible.
        let visibleStrip: CGFloat = min(80, max(24, frame.width))
        result.origin.x = min(screen.maxX - visibleStrip, max(screen.minX - frame.width + visibleStrip, result.origin.x))
        result.origin.y = min(screen.maxY - frame.height, max(screen.minY - frame.height + 24, result.origin.y))
        return result
    }
}
