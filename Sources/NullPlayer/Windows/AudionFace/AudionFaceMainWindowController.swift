import AppKit
import UniformTypeIdentifiers

/// A face's window: borderless and clear, so the face's alpha is the window's shape. AppKit refuses
/// a borderless window key status by default, which would also cut off the mouse-moved stream.
final class AudionFaceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The Audion-mode main window. Loads the selected face off the main thread and shows it through
/// `AudionFaceMainView`, or the app-authored `AudionFaceUnskinnedView` when there is none to show.
/// The window's size is the face's, times the UI scale; a restored or reloaded frame keeps its
/// top-left corner.
final class AudionFaceMainWindowController: NSWindowController, MainWindowProviding, NSWindowDelegate {
    static let unskinnedSize = NSSize(width: 320, height: 110)

    private let importer = AudionFaceImporter()
    private let faceView = AudionFaceMainView()
    private let unskinnedView = AudionFaceUnskinnedView()
    private var loadTask: Task<Void, Never>?
    /// Radio's connection state picks the face's connecting, streaming or lag animation.
    private var radioObserver: NSObjectProtocol?
    private var uiScale: CGFloat = 1
    /// The face on screen and its folder, nil while the unskinned player is up.
    private var shown: (face: AudionFace, url: URL)? { didSet { faceView.face = shown?.face } }
    var loadedFaceURL: URL? { shown?.url }
    /// NullPlayer's own windows, coloured from the face on screen (`AudionFacePalette`).
    private(set) var surfaceStyle = AudionFacePalette.neutral

    init() {
        let window = AudionFaceWindow(contentRect: NSRect(origin: .zero, size: Self.unskinnedSize),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.title = "NullPlayer — Audion Faces"
        window.setAccessibilityIdentifier("AudionFaceMainWindow")
        window.center()
        super.init(window: window)
        window.delegate = self
        let perform: (AudionFaceCommand) -> Void = { [weak self] command in
            MainActor.assumeIsolated {
                AudionFaceAudioEngineHost.perform(command, engine: WindowManager.shared.audioEngine)
                self?.refreshHostState()
            }
        }
        faceView.onCommand = perform
        unskinnedView.onCommand = perform
        radioObserver = NotificationCenter.default.addObserver(
            forName: RadioManager.connectionStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshHostState() } }
        unskinnedView.onLoadFace = { [weak self] in self?.importFaceFromPanel() }
        // No placeholder while the selected face loads: it would flash at its own size first.
        // `reloadSelectedFace` presents it when there is no face to show.
        reloadSelectedFace()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Choosing a face

    func reloadSelectedFace() {
        loadTask?.cancel()
        let url: URL?
        do {
            url = try importer.selectedFaceURL()
        } catch {
            present(nil, message: error.localizedDescription)
            return
        }
        guard let url else { return present(nil, message: nil) }
        loadTask = Task { @MainActor [weak self] in
            do {
                let face = try await AudionFaceLoader.load(folder: url)
                try Task.checkCancellation()
                self?.present((face, url), message: nil)
                NSLog("AudionFace: loaded '%@' (%dx%d, %d findings)", url.lastPathComponent,
                      face.base.width, face.base.height, face.findings.count)
            } catch is CancellationError {
                return
            } catch {
                self?.present(nil, message: error.localizedDescription)
            }
        }
    }

    func selectFace(named name: String) {
        importer.select(name)
        reloadSelectedFace()
    }

    /// An installed face by its folder, or anything else through the importer.
    func showFace(at url: URL) {
        let installed = url.standardizedFileURL.deletingLastPathComponent().path
            == importer.directoryURL.standardizedFileURL.path
        installed ? selectFace(named: url.lastPathComponent) : importFace(from: url)
    }

    func importFaceFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .folder]
        panel.message = "Select an Audion face folder, or a .zip of faces"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFace(from: url)
    }

    func importFace(from url: URL) {
        loadTask?.cancel()
        unskinnedView.show(message: "Validating and installing \(url.lastPathComponent)…")
        loadTask = Task { @MainActor [weak self] in
            do {
                _ = try await self?.importer.importFaces(from: url)
                try Task.checkCancellation()
                self?.reloadSelectedFace()
            } catch is CancellationError {
                return
            } catch {
                self?.present(nil, message: error.localizedDescription)
            }
        }
    }

    func resetToUnskinned() {
        loadTask?.cancel()
        importer.resetSelection()
        present(nil, message: nil)
    }

    /// Only the top-left is restored: the size is the face's.
    func restoreFrame(_ frame: NSRect) {
        guard frame != .zero, let window else { return }
        window.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: frame.maxY))
    }

    // MARK: - Presenting

    private func present(_ shown: (face: AudionFace, url: URL)?, message: String?) {
        guard let window else { return }
        self.shown = shown
        let style = shown.map { AudionFacePalette.surfaceStyle(for: $0.face) } ?? AudionFacePalette.neutral
        if style != surfaceStyle {
            surfaceStyle = style
            NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
        }
        unskinnedView.show(message: message)
        let view: NSView = shown == nil ? unskinnedView : faceView
        if window.contentView !== view { window.contentView = view }
        fitWindow()
        refreshHostState()
        // The shape comes from the pixels, so draw at the new size first: a face that loads after
        // the window is on screen otherwise keeps the placeholder's outline until focus changes.
        window.displayIfNeeded()
        window.invalidateShadow()
    }

    func applyUIScale(_ scale: CGFloat) {
        uiScale = max(0.1, scale)
        faceView.uiScale = uiScale
        fitWindow()
    }

    /// The face's size times `scale`; the unskinned player keeps its own fixed size.
    func mainWindowSize(atScale scale: CGFloat) -> NSSize? {
        guard let face = shown?.face else { return Self.unskinnedSize }
        return NSSize(width: CGFloat(face.base.width) * scale, height: CGFloat(face.base.height) * scale)
    }

    /// Sizes the window to what it shows at the current scale, holding its top-left corner.
    private func fitWindow() {
        guard let window, let size = mainWindowSize(atScale: uiScale) else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(size)
        window.setFrameTopLeftPoint(topLeft)
    }

    // MARK: - Host state

    private func refreshHostState() {
        faceView.host = MainActor.assumeIsolated {
            AudionFaceAudioEngineHost.snapshot(WindowManager.shared.audioEngine,
                                               isWindowActive: window?.isKeyWindow ?? true)
        }
    }

    func updateTrackInfo(_ track: Track?) { refreshHostState() }
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) {}
    func clearVideoTrackInfo() {}
    func updateTime(current: TimeInterval, duration: TimeInterval) { refreshHostState() }
    func updatePlaybackState() { refreshHostState() }
    func updateSpectrum(_ levels: [Float]) {}
    func skinDidChange() {}
    func windowVisibilityDidChange() {}

    func prepareForUITeardown() {
        loadTask?.cancel()
        loadTask = nil
        radioObserver.map(NotificationCenter.default.removeObserver)
        radioObserver = nil
    }

    // MARK: - Window delegate

    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        WindowManager.shared.applySnappedPosition(window, to: WindowManager.shared.windowWillMove(window, to: window.frame.origin))
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshHostState() }
    func windowDidResignKey(_ notification: Notification) { refreshHostState() }
    func windowDidChangeOcclusionState(_ notification: Notification) { faceView.updateClock() }
}
