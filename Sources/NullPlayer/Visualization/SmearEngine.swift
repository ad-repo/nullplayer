import AppKit
import OpenGL.GL3
import CSmearCore

/// Smear (mykel and xplo's Sonique visualizer) as a `VisualizationEngine`: the C core runs its
/// Stutter scripts and renders an RGBA frame on the CPU from the host's waveform and spectrum,
/// which is uploaded and blitted, scaled to fill, into the host's bound framebuffer.
///
/// Its presets are the move scripts, held: Smear's own timer only re-rolls the held script's
/// random parameters, so the host's preset cycler (`VisualizationPresetCycler`) and the user are
/// what change it. Colour, waveform and particle scripts still come and go by themselves.
final class SmearEngine: NSObject, VisualizationEngine {
    /// The drawable's own size (`SoftwareCanvas`, so never less than its minimum), at most this
    /// wide: Smear draws 1 px waveforms and builds its move map one script run per pixel.
    private static let maxRenderWidth = 1024
    /// Smear is timed in milliseconds; more frames than this only spend CPU.
    private static let updateInterval = 1.0 / 60.0
    /// Smear's clock is a 32-bit millisecond count that wraps after 24.8 days, when its timers
    /// stop firing; a core this old is replaced by a fresh one, which holds the same move.
    private static let coreLifetime: CFTimeInterval = 20 * 24 * 60 * 60

    static let moveKey = "smear.move"

    let displayName = "Smear"
    private(set) var isAvailable = false

    /// Guards what the audio thread and main hand the render thread: the audio and the held
    /// move. The core is the render thread's alone, so a menu click never waits on a frame.
    private let lock = NSLock()
    private var waveform = [Int8](repeating: 0, count: Int(SMEAR_CORE_WAVEFORM_SIZE))
    private var spectrum = [UInt8](repeating: 0, count: Int(SMEAR_CORE_SPECTRUM_SIZE))
    private var move = SmearEngine.savedMove
    /// Set by main when `move` changes; the render thread holds it and clears this.
    private var moveChanged = true

    // Render thread only.
    private var core: OpaquePointer?
    private var coreCreated: CFTimeInterval = 0
    /// Copied out of `waveform` / `spectrum` byte for byte, so the audio thread never pays for a
    /// copy-on-write of an array the render thread still holds.
    private var frameWaveform = [Int8](repeating: 0, count: Int(SMEAR_CORE_WAVEFORM_SIZE))
    private var frameSpectrum = [UInt8](repeating: 0, count: Int(SMEAR_CORE_SPECTRUM_SIZE))
    private var viewport = (width: 1, height: 1)
    private var textureSize = (width: 0, height: 0)
    private var texture: GLuint = 0
    private var framebuffer: GLuint = 0
    private var lastUpdate: CFTimeInterval = 0

    init(width: Int, height: Int) {
        super.init()
        viewport = (max(1, width), max(1, height))
        guard Self.scriptsFolder != nil else {
            NSLog("SmearEngine: bundled scripts not found")
            return
        }
        core = Self.makeCore()
        coreCreated = CACurrentMediaTime()
        guard core != nil else { return }
        glGenTextures(1, &texture)
        glGenFramebuffers(1, &framebuffer)
        isAvailable = true
    }

    /// The C core needs no GL, so an engine released without `cleanup()` still frees it.
    deinit { SmearCore_destroy(core) }

    /// Called on the render thread with the GL context current.
    func cleanup() {
        guard isAvailable else { return }
        isAvailable = false
        SmearCore_destroy(core)
        core = nil
        if framebuffer != 0 { glDeleteFramebuffers(1, &framebuffer); framebuffer = 0 }
        if texture != 0 { glDeleteTextures(1, &texture); texture = 0 }
    }

    // MARK: - VisualizationEngine

    func setViewportSize(width: Int, height: Int) {
        viewport = (max(1, width), max(1, height))
    }

    /// Sonique's 8-bit signed PCM, the one channel used for both.
    func addPCMMono(_ samples: [Float]) {
        lock.withLock {
            for i in 0..<waveform.count {
                waveform[i] = i < samples.count ? Int8(max(-1, min(1, samples[i])) * 127) : 0
            }
        }
    }

    /// The host's 256 bins, 0...255, bass first: Sonique's spectrum.
    func setSpectrum(_ mags: [Float]) {
        lock.withLock {
            for i in 0..<spectrum.count {
                spectrum[i] = i < mags.count ? UInt8(max(0, min(1, mags[i])) * 255) : 0
            }
        }
    }

    func renderFrame() {
        renewCoreIfOld()
        guard isAvailable, let core else { return }
        let canvas = SoftwareCanvas.atLeastMinimum(width: viewport.width, height: viewport.height)
        let width = min(canvas.width, Self.maxRenderWidth)
        let height = max(width * canvas.height / canvas.width, 32)

        let now = CACurrentMediaTime()
        if textureSize != (width, height) || now - lastUpdate >= Self.updateInterval {
            lastUpdate = now
            update(core, width: width, height: height)
        }
        guard textureSize == (width, height) else { return }

        // Blit into the host's framebuffer, flipped: Smear's row 0 is the top.
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

    private static func makeCore() -> OpaquePointer? {
        scriptsFolder?.withUnsafeFileSystemRepresentation { SmearCore_create($0) }
    }

    private func renewCoreIfOld() {
        guard isAvailable, CACurrentMediaTime() - coreCreated >= Self.coreLifetime,
              let fresh = Self.makeCore() else { return }
        SmearCore_destroy(core)
        core = fresh
        coreCreated = CACurrentMediaTime()
        lock.withLock { moveChanged = true }
    }

    /// Runs one Smear frame and uploads it. The core follows a new canvas size itself, as the
    /// Sonique plugin did.
    private func update(_ core: OpaquePointer, width: Int, height: Int) {
        let move: String? = lock.withLock {
            frameWaveform.withUnsafeMutableBytes { dst in waveform.withUnsafeBytes { dst.copyMemory(from: $0) } }
            frameSpectrum.withUnsafeMutableBytes { dst in spectrum.withUnsafeBytes { dst.copyMemory(from: $0) } }
            defer { moveChanged = false }
            return moveChanged ? self.move : nil
        }
        if let move { SmearCore_holdMove(core, move) }

        let frame = frameWaveform.withUnsafeBufferPointer { wave in
            frameSpectrum.withUnsafeBufferPointer { spec in
                SmearCore_render(core, Int32(width), Int32(height), wave.baseAddress, spec.baseAddress)
            }
        }
        guard let frame else { return }

        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        defer { glBindTexture(GLenum(GL_TEXTURE_2D), 0) }
        if textureSize != (width, height) {
            glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGB8, GLsizei(width), GLsizei(height), 0,
                         GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
            textureSize = (width, height)
        }
        glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, 0, GLsizei(width), GLsizei(height),
                        GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), frame)
    }

    // MARK: - Presets (the move scripts)

    static let scriptsFolder = BundleHelper.url(forResource: "Smear", withExtension: nil)

    /// The bundled move scripts' file names, sorted.
    static let moveFiles: [String] = {
        guard let moves = scriptsFolder?.appendingPathComponent("Moves"),
              let names = try? FileManager.default.contentsOfDirectory(atPath: moves.path) else { return [] }
        return names.filter { $0.lowercased().hasSuffix(".sms") }.sorted()
    }()

    var presetCount: Int { Self.moveFiles.count }

    func presetName(at index: Int) -> String {
        guard Self.moveFiles.indices.contains(index) else { return "" }
        return (Self.moveFiles[index] as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
    }

    private static var savedMove: String {
        let saved = UserDefaults.standard.string(forKey: moveKey)
        return saved.flatMap { moveFiles.contains($0) ? $0 : nil } ?? moveFiles.first ?? ""
    }

    var presetIndex: Int? { lock.withLock { Self.moveFiles.firstIndex(of: move) } }

    func selectPreset(at index: Int, hardCut: Bool) { select { _ in index } }

    func stepPreset(forward: Bool, hardCut: Bool) {
        let count = presetCount
        select { (($0 ?? 0) + (forward ? 1 : count - 1)) % count }
    }

    func randomPreset(hardCut: Bool) {
        select { current in
            var index: Int
            repeat { index = Int.random(in: 0..<self.presetCount) } while index == current
            return index
        }
    }

    /// Holds the move `pick` chooses from the held one; the render thread builds it.
    private func select(_ pick: (_ current: Int?) -> Int) {
        guard presetCount > 1 else { return }
        let chosen: String? = lock.withLock {
            let index = pick(Self.moveFiles.firstIndex(of: move))
            guard Self.moveFiles.indices.contains(index) else { return nil }
            move = Self.moveFiles[index]
            moveChanged = true
            return move
        }
        if let chosen { UserDefaults.standard.set(chosen, forKey: Self.moveKey) }
    }
}
