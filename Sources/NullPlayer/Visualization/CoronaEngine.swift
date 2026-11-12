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
    /// Half the drawable, at most this wide, as Goom renders.
    private static let maxRenderWidth = 1024
    /// Corona advances its particles one step per update, with no time scaling.
    private static let updateInterval = 1.0 / 60.0

    static let paletteKey = "corona.palette"
    static let blazeKey = "corona.blaze"

    let displayName = "Corona"
    private(set) var isAvailable = false

    /// Guards `core`, `spectrum`, `palette` and `blaze`: audio thread, render thread and main's
    /// menu all reach them.
    private let lock = NSLock()
    private var core: OpaquePointer?
    /// Applied again to every new core (a resize makes one).
    private var palette = (UserDefaults.standard.object(forKey: CoronaEngine.paletteKey) as? Int)
        .flatMap { (0..<CoronaEngine.presetCount).contains($0) ? $0 : nil } ?? 0
    private var blaze = UserDefaults.standard.bool(forKey: CoronaEngine.blazeKey)
    /// Sonique's 512-bin host spectrum, 0...255.
    private var spectrum = [UInt8](repeating: 0, count: 512)

    // Render thread only.
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

    /// Called on the render thread with the GL context current.
    func cleanup() {
        guard isAvailable else { return }
        isAvailable = false
        lock.withLock {
            CoronaCore_destroy(core)
            core = nil
        }
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
        let width = min(max(viewport.width / 2, 32), Self.maxRenderWidth)
        let height = max(width * viewport.height / viewport.width, 32)

        let now = CACurrentMediaTime()
        if coreSize != (width, height) || now - lastUpdate >= Self.updateInterval {
            let elapsed = lastUpdate == 0 ? 0 : now - lastUpdate
            lastUpdate = now
            update(width: width, height: height, elapsedMs: UInt32(min(elapsed, 1) * 1000))
        }

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
    /// `lv_corona_dimension` does.
    private func update(width: Int, height: Int, elapsedMs: UInt32) {
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        lock.withLock {
            if coreSize != (width, height) {
                CoronaCore_destroy(core)
                core = CoronaCore_create(Int32(width), Int32(height))
                coreSize = (width, height)
                if let core {
                    CoronaCore_setPalette(core, Int32(palette), 0)
                    CoronaCore_setBlaze(core, blaze ? 1 : 0)
                }
                glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGB8, GLsizei(width), GLsizei(height), 0,
                             GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
            }
            guard let core,
                  let frame = spectrum.withUnsafeBufferPointer({ CoronaCore_update(core, $0.baseAddress, elapsedMs) })
            else { return }
            glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, 0, GLsizei(width), GLsizei(height),
                            GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), frame)
        }
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    }

    // MARK: - Presets (the palettes)

    static let presetCount = Int(CORONA_CORE_PALETTE_COUNT)

    static func presetName(at index: Int) -> String { String(cString: CoronaCore_paletteName(Int32(index))) }

    var currentPreset: Int { lock.withLock { palette } }

    func selectPreset(at index: Int) { select { _ in index } }
    func step(by offset: Int) { select { ($0 + offset + Self.presetCount) % Self.presetCount } }

    func selectRandomPreset() {
        select { current in
            var index = current
            while index == current { index = Int.random(in: 0..<Self.presetCount) }
            return index
        }
    }

    /// Holds the palette `pick` chooses from the held one, read and applied under one lock so the
    /// render thread cannot change it in between. Corona fades to it.
    private func select(_ pick: (_ current: Int) -> Int) {
        lock.withLock {
            let index = pick(palette)
            guard (0..<Self.presetCount).contains(index) else { return }
            palette = index
            if let core { CoronaCore_setPalette(core, Int32(palette), 1) }
            UserDefaults.standard.set(palette, forKey: Self.paletteKey)
        }
    }

    // MARK: - Menu

    func addMenuItems(to menu: NSMenu) {
        let item = NSMenuItem(title: "Blaze", action: #selector(toggleBlazeAction), keyEquivalent: "")
        item.target = self
        item.state = lock.withLock { blaze } ? .on : .off
        menu.addItem(item)
    }

    @objc private func toggleBlazeAction() {
        lock.withLock {
            blaze.toggle()
            if let core { CoronaCore_setBlaze(core, blaze ? 1 : 0) }
            UserDefaults.standard.set(blaze, forKey: Self.blazeKey)
        }
    }
}
