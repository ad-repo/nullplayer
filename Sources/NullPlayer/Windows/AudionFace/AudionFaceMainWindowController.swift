import AppKit
import UniformTypeIdentifiers

/// The Audion-mode main window. Loads the selected face off the main thread and shows it through
/// `AudionFaceMainView`, or the app-authored `AudionFaceUnskinnedView` when there is none to show.
/// The window's size is the face's, times the UI scale; a restored or reloaded frame keeps its
/// top-left corner.
final class AudionFaceMainWindowController: NSWindowController, MainWindowProviding, NSWindowDelegate {
    static let unskinnedSize = NSSize(width: 320, height: 110)

    private let importer = AudionFaceImporter()
    private let faceView = AudionFaceMainView()
    private let unskinnedView = AudionFaceUnskinnedView()
    let skinLoad = SkinLoadTask()
    /// Radio's connection state picks the face's connecting, streaming or lag animation.
    private var radioObserver: NSObjectProtocol?
    private var uiScale: CGFloat = 1
    /// The face on screen and its folder, nil while the unskinned player is up.
    private var shown: (skin: AudionFace, url: URL)? { didSet { faceView.face = shown?.skin } }
    var loadedSkinURL: URL? { shown?.url }
    /// NullPlayer's own windows, coloured from the face on screen (`AudionFacePalette`).
    private(set) var surfaceStyle = unskinnedSurfaceStyle
    static let unskinnedSurfaceStyle = AudionFacePalette.neutral

    init() {
        let window = SkinnedBorderlessWindow(contentRect: NSRect(origin: .zero, size: Self.unskinnedSize),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        // NullPlayer's shadow either way: the face's own, or the unskinned player's in `present`.
        window.hasShadow = false
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
        // `reloadSelectedSkin` presents it when there is no face to show.
        reloadSelectedSkin()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Choosing a face (`SingleCanvasMainWindow`)

    var skinSelection: SkinSelection { importer.selection }
    func selectedSkinURL() throws -> URL? { try importer.selectedFaceURL() }
    static func loadSkin(at url: URL) async throws -> AudionFace { try await AudionFaceLoader.load(folder: url) }

    /// An installed face by its folder, or anything else through the importer.
    func showFace(at url: URL) {
        let installed = url.standardizedFileURL.deletingLastPathComponent().path
            == importer.directoryURL.standardizedFileURL.path
        installed ? selectSkin(named: url.lastPathComponent) : importFace(from: url)
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
        unskinnedView.show(message: "Validating and installing \(url.lastPathComponent)…")
        skinLoad.run({ [importer] in try await importer.importFaces(from: url) },
                     done: { [weak self] _ in self?.reloadSelectedSkin() },
                     failed: { [weak self] error in self?.present(nil, error: error) })
    }

    // MARK: - Presenting

    func present(_ shown: (skin: AudionFace, url: URL)?, error: Error?) {
        guard let window else { return }
        if let shown {
            NSLog("AudionFace: loaded '%@' (%dx%d, %d findings)", shown.url.lastPathComponent,
                  shown.skin.base.width, shown.skin.base.height, shown.skin.findings.count)
        }
        self.shown = shown
        let style = shown.map { AudionFacePalette.surfaceStyle(for: $0.skin) } ?? Self.unskinnedSurfaceStyle
        if style != surfaceStyle {
            surfaceStyle = style
            NotificationCenter.default.post(name: .hostedSurfaceStyleDidChange, object: nil)
        }
        unskinnedView.show(message: error?.localizedDescription)
        let view: NSView = shown == nil ? unskinnedView : faceView
        if window.contentView !== view { window.contentView = view }
        // A face casts its own (`AudionFaceMainView.windowShadow`); the unskinned player is cast
        // from what it draws.
        window.hasSkinShadow = shown == nil
        fitWindow()
        refreshHostState()
    }

    func applyUIScale(_ scale: CGFloat) {
        uiScale = max(0.1, scale)
        faceView.uiScale = uiScale
        fitWindow()
    }

    /// The face's size times `scale`; the unskinned player keeps its own fixed size.
    func mainWindowSize(atScale scale: CGFloat) -> NSSize? {
        guard let face = shown?.skin else { return Self.unskinnedSize }
        return NSSize(width: CGFloat(face.base.width) * scale, height: CGFloat(face.base.height) * scale)
    }

    /// Sizes the window to what it shows at the current scale, holding its top-left corner. The
    /// unskinned player's shadow is pulled again after drawing at the new size: the resize's own
    /// pull ran before it.
    private func fitWindow() {
        guard let window, let size = mainWindowSize(atScale: uiScale) else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(size)
        window.setFrameTopLeftPoint(topLeft)
        window.displayIfNeeded()
        window.invalidateSkinShadowShape("fit")
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
        skinLoad.cancel()
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
