import AppKit
import OpenGL.GL3
import CGoomCore

/// Goom (the `goom-port` skill) as a `VisualizationEngine`: the C core renders an RGBA frame on
/// the CPU, which is uploaded and blitted, scaled to fill, into the host's bound framebuffer.
///
/// Goom picks its own effects from the music; the menu's choices force one, and Goom moves on
/// from it at its next change, as upstream's forced switch does.
final class GoomEngine: NSObject, VisualizationEngine {
    /// Upstream's desktop canvas: half the drawable, at most this wide (`GoomWidget.cpp`).
    private static let maxRenderWidth = 1024
    /// Goom advances one cycle per update and its motion is tuned to upstream's 30 per second.
    private static let updateInterval = 1.0 / 30.0

    /// The held effect's index; absent while Goom picks its own.
    static let heldEffectKey = "goom.heldEffect"

    let displayName = "Goom"
    private(set) var isAvailable = false

    /// Guards `core`, `pcm` and `heldEffect`: audio thread, render thread and main's menu all
    /// reach them.
    private let lock = NSLock()
    private var core: OpaquePointer?
    /// The effect Goom is held on, applied again to every new core (a resize makes one).
    private var heldEffect: Int? = UserDefaults.standard.object(forKey: GoomEngine.heldEffectKey) as? Int
    /// 512 left then 512 right frames, as `GoomCore_update` reads them.
    private var pcm = [Int16](repeating: 0, count: 1024)

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
            GoomCore_destroy(core)
            core = nil
        }
        if framebuffer != 0 { glDeleteFramebuffers(1, &framebuffer); framebuffer = 0 }
        if texture != 0 { glDeleteTextures(1, &texture); texture = 0 }
    }

    // MARK: - VisualizationEngine

    func setViewportSize(width: Int, height: Int) {
        viewport = (max(1, width), max(1, height))
    }

    func addPCMMono(_ samples: [Float]) {
        lock.withLock {
            for i in 0..<512 {
                let s = i < samples.count ? Int16(max(-1, min(1, samples[i])) * 32767) : 0
                pcm[i] = s
                pcm[512 + i] = s
            }
        }
    }

    func renderFrame() {
        guard isAvailable else { return }
        let width = min(max(viewport.width / 2, 1), Self.maxRenderWidth)
        let height = max(width * viewport.height / viewport.width, 1)

        let now = CACurrentMediaTime()
        if coreSize != (width, height) || now - lastUpdate >= Self.updateInterval {
            lastUpdate = now
            update(width: width, height: height)
        }

        // Blit into the host's framebuffer, flipped: Goom row 0 is the top.
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

    /// Runs one Goom cycle and uploads it. A new canvas size starts a new core: upstream's
    /// `goom_set_resolution` does not resize the zoom filter's own buffers.
    private func update(width: Int, height: Int) {
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        lock.withLock {
            if coreSize != (width, height) {
                GoomCore_destroy(core)
                core = GoomCore_create(Int32(width), Int32(height))
                coreSize = (width, height)
                if let core, let heldEffect {
                    GoomCore_forceEffect(core, Int32(heldEffect))
                    GoomCore_setHold(core, 1)
                }
                // RGB8 storage drops Goom's alpha byte, which it leaves unset.
                glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGB8, GLsizei(width), GLsizei(height), 0,
                             GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
            }
            guard let core, let frame = pcm.withUnsafeBufferPointer({ GoomCore_update(core, $0.baseAddress) }) else { return }
            glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, 0, GLsizei(width), GLsizei(height),
                            GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), frame)
        }
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    }

    // MARK: - Effects

    static let effectCount = Int(GOOM_CORE_EFFECT_COUNT)

    static func effectName(at index: Int) -> String { String(cString: GoomCore_effectName(Int32(index))) }

    var currentEffect: Int {
        lock.withLock { core.map { Int(GoomCore_currentEffect($0)) } ?? 0 }
    }

    /// While held, the chosen effect becomes the held one.
    func selectEffect(at index: Int) {
        lock.withLock {
            if let core { GoomCore_forceEffect(core, Int32(index)) }
            if heldEffect != nil { hold(index) }
        }
    }

    var isHolding: Bool { lock.withLock { heldEffect != nil } }

    /// Holds the running effect, or lets Goom pick its own again.
    func setHolding(_ on: Bool) {
        let current = currentEffect
        lock.withLock { hold(on ? current : nil) }
    }

    /// Called with `lock` held.
    private func hold(_ index: Int?) {
        heldEffect = index
        if let core { GoomCore_setHold(core, index == nil ? 0 : 1) }
        UserDefaults.standard.set(index, forKey: Self.heldEffectKey)
    }

    func step(by offset: Int) {
        selectEffect(at: (currentEffect + offset + Self.effectCount) % Self.effectCount)
    }

    func selectRandomEffect() {
        let current = currentEffect
        var index = current
        while index == current { index = Int.random(in: 0..<Self.effectCount) }
        selectEffect(at: index)
    }

    // MARK: - Menu

    /// The engine's section of the shared visualization menu (`VisualizationContextMenu`). The
    /// items target the engine, so a host needs no Goom-specific actions.
    func addMenuItems(to menu: NSMenu) {
        let current = NSMenuItem(title: "Effect: \(Self.effectName(at: currentEffect))", action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)
        menu.addItem(.separator())
        menu.addItem(item("Next Effect", #selector(nextEffectAction)))
        menu.addItem(item("Previous Effect", #selector(previousEffectAction)))
        menu.addItem(item("Random Effect", #selector(randomEffectAction)))

        let list = NSMenu()
        for index in 0..<Self.effectCount {
            let entry = item(Self.effectName(at: index), #selector(chooseEffectAction(_:)))
            entry.tag = index
            entry.state = index == currentEffect ? .on : .off
            list.addItem(entry)
        }
        let listItem = NSMenuItem(title: "Effects", action: nil, keyEquivalent: "")
        listItem.submenu = list
        menu.addItem(listItem)
        let holdItem = item("Hold Effect", #selector(toggleHoldAction))
        holdItem.state = isHolding ? .on : .off
        menu.addItem(holdItem)
        menu.addItem(.separator())
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func nextEffectAction() { step(by: 1) }
    @objc private func previousEffectAction() { step(by: -1) }
    @objc private func randomEffectAction() { selectRandomEffect() }
    @objc private func chooseEffectAction(_ sender: NSMenuItem) { selectEffect(at: sender.tag) }
    @objc private func toggleHoldAction() { setHolding(!isHolding) }
}
