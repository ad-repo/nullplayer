import AppKit
import OpenGL.GL3
import CCoronaCore

/// Corona (libvisual's port of the Sonique visualizer) as a `VisualizationEngine`: the C core
/// renders an RGBA frame on the CPU from the host spectrum, which is uploaded and blitted, scaled
/// to fill, into the host's bound framebuffer.
///
/// Its presets are the palettes, held: Corona never picks its own, so the host's preset cycler
/// (`VisualizationPresetCycler`) and the user are the only things that change it. Blaze is its
/// own menu item.
final class CoronaEngine: NSObject, VisualizationEngine {
    /// The drawable's own size (`SoftwareCanvas`, so never less than its minimum), at most this
    /// wide. Not half of it as Goom does: Corona draws in fixed pixel sizes (1 px particles, at
    /// least 2,000 of them, a 1 px blur), so a half-size canvas scaled up reads as a close-up.
    private static let maxRenderWidth = 1024
    /// Corona advances its particles one step per update, with no time scaling.
    private static let updateInterval = 1.0 / 60.0

    static let paletteKey = "corona.palette"
    static let blazeKey = "corona.blaze"

    let displayName = "Corona"
    private(set) var isAvailable = false

    /// Guards what the audio thread and main hand the render thread: the spectrum and the
    /// settings. The core is the render thread's alone, so a menu click never waits on a frame.
    private let lock = NSLock()
    /// Sonique's 512-bin host spectrum, 0...255.
    private var spectrum = [UInt8](repeating: 0, count: 512)
    /// Applied again to every new core (a resize makes one).
    private var palette = CoronaEngine.savedPalette
    private var blaze = UserDefaults.standard.bool(forKey: CoronaEngine.blazeKey)
    /// Set by main when `palette` or `blaze` changes; the render thread applies them and clears it.
    private var settingsChanged = false

    // Render thread only.
    private var core: OpaquePointer?
    /// The spectrum copied out of `spectrum` byte for byte, so the audio thread never pays for a
    /// copy-on-write of an array the render thread still holds.
    private var frameSpectrum = [UInt8](repeating: 0, count: 512)
    private var viewport = (width: 1, height: 1)
    private var coreSize = (width: 0, height: 0)
    private var texture: GLuint = 0
    private var framebuffer: GLuint = 0
    private var lastUpdate: CFTimeInterval = 0

    init(width: Int, height: Int) {
        super.init()
        viewport = (max(1, width), max(1, height))
        glGenTextures(1, &texture)
        glGenFramebuffers(1, &framebuffer)
        isAvailable = true
    }

    /// The C core needs no GL, so an engine released without `cleanup()` still frees it.
    deinit { CoronaCore_destroy(core) }

    /// Called on the render thread with the GL context current.
    func cleanup() {
        guard isAvailable else { return }
        isAvailable = false
        CoronaCore_destroy(core)
        core = nil
        if framebuffer != 0 { glDeleteFramebuffers(1, &framebuffer); framebuffer = 0 }
        if texture != 0 { glDeleteTextures(1, &texture); texture = 0 }
    }

    // MARK: - VisualizationEngine

    func setViewportSize(width: Int, height: Int) {
        viewport = (max(1, width), max(1, height))
    }

    func addPCMMono(_ samples: [Float]) {}

    /// The host's 256 bins, each doubled into Sonique's 512 as libvisual's wrapper did.
    func setSpectrum(_ mags: [Float]) {
        lock.withLock {
            for i in 0..<256 {
                let value = i < mags.count ? UInt8(max(0, min(1, mags[i])) * 255) : 0
                spectrum[2 * i] = value
                spectrum[2 * i + 1] = value
            }
        }
    }

    func renderFrame() {
        guard isAvailable else { return }
        let canvas = SoftwareCanvas.atLeastMinimum(width: viewport.width, height: viewport.height)
        let width = min(canvas.width, Self.maxRenderWidth)
        let height = max(width * canvas.height / canvas.width, 32)

        let now = CACurrentMediaTime()
        if coreSize != (width, height) || now - lastUpdate >= Self.updateInterval {
            let elapsed = lastUpdate == 0 ? 0 : now - lastUpdate
            lastUpdate = now
            update(width: width, height: height, elapsedMs: UInt32(min(elapsed, 1) * 1000))
        }
        // No core (it failed to start): the texture may have no storage to blit.
        guard coreSize == (width, height) else { return }

        // Corona's row 0 is the bottom, as GL's is: no flip.
        var previousRead: GLint = 0
        glGetIntegerv(GLenum(GL_READ_FRAMEBUFFER_BINDING), &previousRead)
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), framebuffer)
        glFramebufferTexture2D(GLenum(GL_READ_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_2D), texture, 0)
        glBlitFramebuffer(0, 0, GLint(width), GLint(height),
                          0, 0, GLint(viewport.width), GLint(viewport.height),
                          GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_LINEAR))
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(previousRead))
    }

    /// Runs one Corona step and uploads it. A new canvas size starts a new core, as libvisual's
    /// `lv_corona_dimension` does; a core that fails to start is tried again next frame.
    private func update(width: Int, height: Int, elapsedMs: UInt32) {
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        defer { glBindTexture(GLenum(GL_TEXTURE_2D), 0) }
        var isNewCore = false
        if coreSize != (width, height) {
            CoronaCore_destroy(core)
            core = CoronaCore_create(Int32(width), Int32(height))
            guard core != nil else { coreSize = (0, 0); return }
            coreSize = (width, height)
            isNewCore = true
            glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGB8, GLsizei(width), GLsizei(height), 0,
                         GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
        }
        guard let core else { return }

        let (palette, blaze, changed) = lock.withLock {
            frameSpectrum.withUnsafeMutableBytes { dst in spectrum.withUnsafeBytes { dst.copyMemory(from: $0) } }
            defer { settingsChanged = false }
            return (self.palette, self.blaze, settingsChanged)
        }
        if isNewCore || changed {
            // A new core starts on the held palette; a change fades to it.
            CoronaCore_setPalette(core, Int32(palette), isNewCore ? 0 : 1)
            CoronaCore_setBlaze(core, blaze ? 1 : 0)
        }

        guard let frame = frameSpectrum.withUnsafeBufferPointer({ CoronaCore_update(core, $0.baseAddress, elapsedMs) })
        else { return }
        glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, 0, GLsizei(width), GLsizei(height),
                        GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), frame)
    }

    // MARK: - Presets (the palettes)

    static let presetCount = Int(CORONA_CORE_PALETTE_COUNT)

    private static var savedPalette: Int {
        let saved = UserDefaults.standard.integer(forKey: paletteKey)
        return (0..<presetCount).contains(saved) ? saved : 0
    }

    var presetCount: Int { Self.presetCount }
    var presetIndex: Int? { lock.withLock { palette } }

    func presetName(at index: Int) -> String { String(cString: CoronaCore_paletteName(Int32(index))) }

    func selectPreset(at index: Int, hardCut: Bool) { select { _ in index } }
    func stepPreset(by offset: Int, hardCut: Bool) { select { ($0 + offset + Self.presetCount) % Self.presetCount } }

    func randomPreset(hardCut: Bool) {
        select { current in
            var index = current
            while index == current { index = Int.random(in: 0..<Self.presetCount) }
            return index
        }
    }

    /// Holds the palette `pick` chooses from the held one; the render thread fades to it.
    private func select(_ pick: (_ current: Int) -> Int) {
        let chosen: Int? = lock.withLock {
            let index = pick(palette)
            guard (0..<Self.presetCount).contains(index) else { return nil }
            palette = index
            settingsChanged = true
            return index
        }
        if let chosen { UserDefaults.standard.set(chosen, forKey: Self.paletteKey) }
    }

    // MARK: - Menu

    func addMenuItems(to menu: NSMenu, target: VisualizationMenuTarget) {
        let item = NSMenuItem(title: "Blaze", action: #selector(toggleBlazeAction), keyEquivalent: "")
        item.target = self
        item.state = lock.withLock { blaze } ? .on : .off
        menu.addItem(item)
    }

    @objc private func toggleBlazeAction() {
        let blaze: Bool = lock.withLock {
            self.blaze.toggle()
            settingsChanged = true
            return self.blaze
        }
        UserDefaults.standard.set(blaze, forKey: Self.blazeKey)
    }
}
