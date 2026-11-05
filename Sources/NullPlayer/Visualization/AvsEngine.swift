import AppKit
import OpenGL.GL3

/// Advanced Visualization Studio as a `VisualizationEngine`: one `AvsCore` (libavs, the
/// `avs-port` skill) rendered on the host's GL thread and blitted, scaled to fill, into whatever
/// framebuffer the host has bound — the Visualizations window's, or a `.wal`/`.wmz` surface's
/// offscreen one.
///
/// AVS is stereo, so the engine takes the full-rate stereo feed itself rather than the host's
/// mono `addPCMMono`. Its preset menu items target the engine (`addMenuItems`), so a host needs
/// no AVS-specific actions; preset state is main-thread only, and the render thread reaches
/// libavs only through `AvsCore`'s lock.
final class AvsEngine: NSObject, VisualizationEngine {
    private static let audioConsumerID = "avsEngine"
    /// AVS presets were written for a few hundred pixels across, and the renderer is software: a
    /// viewport wider than this renders at an integer fraction of it and is scaled up.
    private static let maxRenderWidth = 800

    let displayName = "AVS"
    private(set) var isAvailable = false

    private let core: AvsCore?
    private var audioObserver: NSObjectProtocol?

    // Render thread only.
    private var viewport = (width: 1, height: 1)
    private var pixels: [UInt32] = []
    private var texture: GLuint = 0
    private var framebuffer: GLuint = 0
    private var textureSize = (width: 0, height: 0)
    private var lastCycleCheck = Date()

    // Main thread only, once `init` returns.
    private(set) var presets: [URL] = []
    private(set) var currentIndex: Int?
    private var lastPresetChange = Date()

    init(width: Int, height: Int) {
        // AVSTrans writes eeltrans.ini into the base path when it is torn down, so it is a
        // writable folder of ours rather than the app bundle.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NullPlayer/AVS", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        core = AvsCore(resourcePath: support.path)
        super.init()
        guard let core else { return }
        viewport = (max(1, width), max(1, height))
        glGenTextures(1, &texture)
        glGenFramebuffers(1, &framebuffer)
        isAvailable = true

        // Posted on the audio tap thread: store and return.
        audioObserver = NotificationCenter.default.addObserver(
            forName: .audioStereoPCMFullDataUpdated, object: nil, queue: nil
        ) { [audio = core.audio] note in
            guard let left = note.userInfo?["left"] as? [Float],
                  let right = note.userInfo?["right"] as? [Float],
                  let rate = note.userInfo?["sampleRate"] as? Double, rate > 0 else { return }
            audio.store(AvsAudioSlot.Buffer(left: left, right: right, sampleRate: rate))
        }
        // Not yet shared with main, so the preset list can be read here; a host may apply a
        // preset number as soon as the engine exists.
        reloadPresets()
        // Engines are built on the render thread; the consumer table is main's.
        DispatchQueue.main.async {
            WindowManager.shared.audioEngine.addFullStereoConsumer(Self.audioConsumerID)
        }
    }

    deinit { cleanup() }

    /// Called on the render thread with the GL context current.
    func cleanup() {
        guard isAvailable else { return }
        isAvailable = false
        if let audioObserver { NotificationCenter.default.removeObserver(audioObserver) }
        audioObserver = nil
        DispatchQueue.main.async {
            WindowManager.shared.audioEngine.removeFullStereoConsumer(Self.audioConsumerID)
        }
        if framebuffer != 0 { glDeleteFramebuffers(1, &framebuffer); framebuffer = 0 }
        if texture != 0 { glDeleteTextures(1, &texture); texture = 0 }
    }

    // MARK: - VisualizationEngine

    func setViewportSize(width: Int, height: Int) {
        viewport = (max(1, width), max(1, height))
    }

    /// AVS reads the stereo feed directly (see the type comment).
    func addPCMMono(_ samples: [Float]) {}

    func renderFrame() {
        guard isAvailable, let core else { return }
        let divisor = (viewport.width + Self.maxRenderWidth - 1) / Self.maxRenderWidth
        let width = (viewport.width / divisor) & ~3
        let height = (viewport.height / divisor) & ~1
        guard width > 0, height > 0 else { return }
        if pixels.count != width * height { pixels = [UInt32](repeating: 0, count: width * height) }
        guard pixels.withUnsafeMutableBufferPointer({
            core.renderFrame(into: $0.baseAddress!, width: width, height: height)
        }) else { return }

        // RGB0 (0x00RRGGBB little-endian) is BGRA in memory; RGB8 storage ignores the zero alpha.
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        if textureSize != (width, height) {
            glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGB8, GLsizei(width), GLsizei(height), 0,
                         GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), nil)
            textureSize = (width, height)
        }
        pixels.withUnsafeBufferPointer {
            glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, 0, GLsizei(width), GLsizei(height),
                            GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), $0.baseAddress)
        }
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)

        // Blit into the host's framebuffer, flipped: AVS row 0 is the top.
        var previousRead: GLint = 0
        glGetIntegerv(GLenum(GL_READ_FRAMEBUFFER_BINDING), &previousRead)
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), framebuffer)
        glFramebufferTexture2D(GLenum(GL_READ_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_2D), texture, 0)
        glBlitFramebuffer(0, 0, GLint(width), GLint(height),
                          0, GLint(viewport.height), GLint(viewport.width), 0,
                          GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_LINEAR))
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(previousRead))

        if Date().timeIntervalSince(lastCycleCheck) >= 1 {
            lastCycleCheck = Date()
            DispatchQueue.main.async { [weak self] in self?.cycleIfDue() }
        }
    }

    // MARK: - Presets (main thread)

    var currentPresetName: String? {
        currentIndex.map { presets[$0].deletingPathExtension().lastPathComponent }
    }

    func reloadPresets() {
        presets = AvsPresets.all()
        let saved = AvsPresets.currentPreset
        if let index = presets.firstIndex(where: { $0.path == saved }) ?? (presets.isEmpty ? nil : 0) {
            selectPreset(at: index)
        }
    }

    func selectPreset(at index: Int) {
        guard presets.indices.contains(index), let core else { return }
        currentIndex = index
        lastPresetChange = Date()
        let url = presets[index]
        if core.loadPreset(at: url) {
            AvsPresets.currentPreset = url.path
        } else {
            NSLog("AvsEngine: %@ did not load: %@", url.lastPathComponent, core.lastError)
        }
    }

    func step(by offset: Int) {
        guard !presets.isEmpty else { return }
        selectPreset(at: ((currentIndex ?? -1) + offset + presets.count) % presets.count)
    }

    func selectRandomPreset() {
        guard presets.count > 1 else { return }
        var index = currentIndex ?? 0
        while index == currentIndex { index = Int.random(in: presets.indices) }
        selectPreset(at: index)
    }

    private func cycleIfDue() {
        let mode = AvsPresets.cycleMode
        guard mode != .off, Date().timeIntervalSince(lastPresetChange) >= AvsPresets.cycleInterval else { return }
        mode == .random ? selectRandomPreset() : step(by: 1)
    }

    // MARK: - Menu

    /// The engine's own section of the shared visualization menu (`VisualizationContextMenu`).
    func addMenuItems(to menu: NSMenu) {
        let current = NSMenuItem(title: "Preset: \(currentPresetName ?? "(none)")", action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)
        menu.addItem(.separator())
        menu.addItem(item("Next Preset", #selector(nextPresetAction)))
        menu.addItem(item("Previous Preset", #selector(previousPresetAction)))
        menu.addItem(item("Random Preset", #selector(randomPresetAction)))

        let list = NSMenu()
        for (index, url) in presets.enumerated() {
            let entry = item(url.deletingPathExtension().lastPathComponent, #selector(choosePresetAction(_:)))
            entry.tag = index
            entry.state = index == currentIndex ? .on : .off
            list.addItem(entry)
        }
        let listItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        listItem.submenu = list
        menu.addItem(listItem)
        menu.addItem(.separator())

        for (title, mode) in [("Hold Preset", VisualizationCycleMode.off), ("Auto-Cycle", .cycle), ("Auto-Random", .random)] {
            let entry = item(title, #selector(setCycleModeAction(_:)))
            entry.representedObject = mode.rawValue
            entry.state = AvsPresets.cycleMode == mode ? .on : .off
            menu.addItem(entry)
        }
        let intervals = NSMenu()
        for seconds in AvsPresets.cycleIntervals {
            let title = seconds < 60 ? "\(Int(seconds)) seconds" : "\(Int(seconds / 60)) minute\(seconds > 60 ? "s" : "")"
            let entry = item(title, #selector(setCycleIntervalAction(_:)))
            entry.tag = Int(seconds)
            entry.state = AvsPresets.cycleInterval == seconds ? .on : .off
            intervals.addItem(entry)
        }
        let intervalItem = NSMenuItem(title: "Cycle Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervals
        menu.addItem(intervalItem)
        menu.addItem(.separator())

        menu.addItem(item("Choose AVS Preset Folder…", #selector(choosePresetFolderAction)))
        if AvsPresets.customFolder != nil {
            menu.addItem(item("Use Bundled AVS Presets Only", #selector(clearPresetFolderAction)))
        }
        menu.addItem(.separator())
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func nextPresetAction() { step(by: 1) }
    @objc private func previousPresetAction() { step(by: -1) }
    @objc private func randomPresetAction() { selectRandomPreset() }
    @objc private func choosePresetAction(_ sender: NSMenuItem) { selectPreset(at: sender.tag) }

    @objc private func setCycleModeAction(_ sender: NSMenuItem) {
        guard let mode = (sender.representedObject as? String).flatMap(VisualizationCycleMode.init) else { return }
        AvsPresets.cycleMode = mode
        lastPresetChange = Date()
    }

    @objc private func setCycleIntervalAction(_ sender: NSMenuItem) {
        AvsPresets.cycleInterval = TimeInterval(sender.tag)
    }

    @objc private func choosePresetFolderAction() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of AVS presets (.avs)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AvsPresets.customFolder = url.path
        reloadPresets()
    }

    @objc private func clearPresetFolderAction() {
        AvsPresets.customFolder = nil
        reloadPresets()
    }
}
