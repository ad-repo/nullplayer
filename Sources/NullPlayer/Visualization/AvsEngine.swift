import AppKit
import OpenGL.GL3

/// Advanced Visualization Studio as a `VisualizationEngine`: one `AvsCore` (libavs, the
/// `avs-port` skill) rendered on the host's GL thread and blitted, scaled to fill, into whatever
/// framebuffer the host has bound — the Visualizations window's, or a `.wal`/`.wmz` surface's
/// offscreen one.
///
/// AVS is stereo, so the engine takes the full-rate stereo feed itself rather than the host's
/// mono `addPCMMono`, plus two beat sources (`AvsBeatFeed`): the 576-sample waveform feed for
/// the standard detector, and aubio's beats (`.audioBeatsUpdated`) for advanced detection. Its own menu items target the engine (`addMenuItems`), so a host needs
/// no AVS-specific actions; preset state is main-thread only, and the render thread reaches
/// libavs only through `AvsCore`'s lock.
final class AvsEngine: NSObject, VisualizationEngine {
    private static let audioConsumerID = "avsEngine"
    /// AVS presets were written for a few hundred pixels across, and the renderer is software: a
    /// viewport wider than this renders at an integer fraction of it and is scaled up; one
    /// narrower than `SoftwareCanvas.minWidth` renders at that width and is shrunk.
    private static let maxRenderWidth = 800

    let displayName = "AVS"
    private(set) var isAvailable = false

    /// The editor (`AvsEditorWindowController`) edits the preset through this, on main.
    let core: AvsCore?
    private var audioObserver: NSObjectProtocol?
    private var waveformObserver: NSObjectProtocol?
    private var trackedBeatsObserver: NSObjectProtocol?

    // Render thread only.
    private var viewport = (width: 1, height: 1)
    private var pixels: [UInt32] = []
    private var texture: GLuint = 0
    private var framebuffer: GLuint = 0
    private var textureSize = (width: 0, height: 0)

    // Main thread only, once `init` returns.
    private(set) var presets: [URL] = []
    private(set) var currentIndex: Int?
    /// Set while the editor has this engine open: auto-cycle would throw the edit away.
    var isBeingEdited = false

    /// Posted on main, object the engine, after a preset load replaced the tree.
    static let presetDidLoad = Notification.Name("AvsEnginePresetDidLoad")
    /// Posted on main once the engine stops, with its `ObjectIdentifier` as `"engine"`.
    static let didStop = Notification.Name("AvsEngineDidStop")

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
        // Every 576-sample chunk, for the beat detector. Posted on the audio thread.
        waveformObserver = NotificationCenter.default.addObserver(
            forName: .audioWaveform576DataUpdated, object: nil, queue: nil
        ) { [beats = core.beats] note in
            guard let left = note.userInfo?["left"] as? [UInt8],
                  let right = note.userInfo?["right"] as? [UInt8],
                  let rate = note.userInfo?["sampleRate"] as? Double else { return }
            beats.store(left: left, right: right, sampleRate: rate)
        }
        // aubio's beats, for advanced beat detection. Posted on the audio thread.
        trackedBeatsObserver = NotificationCenter.default.addObserver(
            forName: .audioBeatsUpdated, object: nil, queue: nil
        ) { [trackedBeats = core.trackedBeats] note in
            guard let beats = note.userInfo?["beats"] as? [Bool],
                  let hopMs = note.userInfo?["hopMs"] as? Double else { return }
            trackedBeats.store(beats: beats, slotMs: hopMs)
        }
        // Not yet shared with main, so the list is written here: a host may apply a preset number
        // as soon as the engine exists. Loading the saved preset needs no notification or save.
        // ponytail: one synchronous scan on the render thread at engine start, so a huge custom
        // folder delays the first frame; main's rescans (`reloadPresets`) run in the background.
        presets = AvsPresets.all()
        if let index = Self.savedIndex(in: presets) {
            currentIndex = index
            if !core.loadPreset(at: presets[index]) {
                NSLog("AvsEngine: %@ did not load: %@", presets[index].lastPathComponent, core.lastError)
            }
        }
        // Engines are built on the render thread; the consumer table is main's.
        DispatchQueue.main.async {
            WindowManager.shared.audioEngine.addFullStereoConsumer(Self.audioConsumerID)
            WindowManager.shared.audioEngine.addWaveformConsumer(Self.audioConsumerID)
            WindowManager.shared.audioEngine.addBeatConsumer(Self.audioConsumerID)
        }
    }

    /// Hosts release an engine through `cleanup()` with their context current. The last
    /// reference can go on any thread, so this only drops the observer and never touches GL.
    deinit {
        removeObservers()
    }

    private func removeObservers() {
        for observer in [audioObserver, waveformObserver, trackedBeatsObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        audioObserver = nil
        waveformObserver = nil
        trackedBeatsObserver = nil
    }

    /// Called on the render thread with the GL context current.
    func cleanup() {
        guard isAvailable else { return }
        isAvailable = false
        removeObservers()
        let id = ObjectIdentifier(self)
        DispatchQueue.main.async {
            WindowManager.shared.audioEngine.removeFullStereoConsumer(Self.audioConsumerID)
            WindowManager.shared.audioEngine.removeWaveformConsumer(Self.audioConsumerID)
            WindowManager.shared.audioEngine.removeBeatConsumer(Self.audioConsumerID)
            NotificationCenter.default.post(name: Self.didStop, object: nil, userInfo: ["engine": id])
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
        let canvas = SoftwareCanvas.atLeastMinimum(width: viewport.width, height: viewport.height)
        let divisor = (canvas.width + Self.maxRenderWidth - 1) / Self.maxRenderWidth
        let width = (canvas.width / divisor) & ~3
        let height = (canvas.height / divisor) & ~1
        guard width > 0, height > 0 else { return }
        if pixels.count != width * height { pixels = [UInt32](repeating: 0, count: width * height) }
        guard pixels.withUnsafeMutableBufferPointer({
            core.renderFrame(into: $0.baseAddress!, width: width, height: height,
                             advancedBeats: AvsPresets.advancedBeatDetection)
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
    }

    // MARK: - Presets (main thread)

    var currentPresetName: String? {
        currentIndex.map { presets[$0].deletingPathExtension().lastPathComponent }
    }

    /// Rescans the folders off main (a custom folder can be large or on a slow volume), then
    /// publishes the list and reloads the saved preset on main.
    func reloadPresets() {
        dispatchPrecondition(condition: .onQueue(.main))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = AvsPresets.all()
            DispatchQueue.main.async {
                guard let self else { return }
                self.presets = found
                self.currentIndex = nil
                if let index = Self.savedIndex(in: found) { self.selectPreset(at: index) }
            }
        }
    }

    /// The saved preset's index, else the first preset's.
    private static func savedIndex(in presets: [URL]) -> Int? {
        let saved = AvsPresets.currentPreset
        return presets.firstIndex { $0.path == saved } ?? (presets.isEmpty ? nil : 0)
    }

    func selectPreset(at index: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard presets.indices.contains(index), let core else { return }
        currentIndex = index
        let url = presets[index]
        if core.loadPreset(at: url) {
            AvsPresets.currentPreset = url.path
            NotificationCenter.default.post(name: Self.presetDidLoad, object: self)
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
}
