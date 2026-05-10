import Foundation
import OpenGL.GL3
import CGeissCore

/// Geiss visualization engine.
///
/// Phase 1: drives a stub C core that renders a deterministic XOR pattern
/// with a hue-cycling palette through an indexed-framebuffer + palette-LUT
/// fragment shader. The Swift side, GL textures, and ABI are the real seam;
/// the actual Geiss effect core lands in Phase 4.
final class GeissEngine: VisualizationEngine {

    // MARK: - Config
    struct Config: Equatable {
        var sensitivity: Float
        var gamma: Int
        var beatDetection: Bool
        var syncColorToSound: Bool
        var slideShift: Bool
        var modeLocked: Bool
        var paletteLocked: Bool
        var autoSwitchSeconds: Int
        var visMode: Int
    }

    // MARK: - VisualizationEngine

    private(set) var isAvailable: Bool = false
    let displayName: String = "Geiss"

    // MARK: - State

    /// Serializes access to the C core. The core is not thread-safe; audio
    /// thread (addPCMMono / setSpectrum) and render thread (renderFrame /
    /// setViewportSize) all take this lock.
    private let coreLock = NSLock()

    private var core: OpaquePointer?
    private var width: Int = 0
    private var height: Int = 0

    /// CPU-side index buffer the C core writes into each frame.
    private var indexBuf: [UInt8] = []

    /// CPU-side palette buffer (256 RGBA8 entries).
    private var palette: [UInt8] = Array(repeating: 0, count: 256 * 4)

    // GL objects
    private var program: GLuint = 0
    private var indexTex: GLuint = 0
    private var paletteTex: GLuint = 0
    private var vao: GLuint = 0
    private var vbo: GLuint = 0
    private var indicesUniform: GLint = -1
    private var paletteUniform: GLint = -1

    // MARK: - Init / cleanup

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.indexBuf = Array(repeating: 0, count: self.width * self.height)

        guard let handle = GeissCore_create(Int32(self.width), Int32(self.height)) else {
            NSLog("GeissEngine: GeissCore_create failed")
            return
        }
        self.core = handle

        if !buildGLResources() {
            NSLog("GeissEngine: failed to build GL resources")
            destroyGLResources()
            GeissCore_destroy(handle)
            self.core = nil
            return
        }

        self.isAvailable = true
        NSLog("GeissEngine: initialized %dx%d (stub core)", self.width, self.height)
    }

    deinit {
        cleanup()
    }

    func cleanup() {
        coreLock.lock()
        defer { coreLock.unlock() }
        destroyGLResources()
        if let core {
            GeissCore_destroy(core)
            self.core = nil
        }
        isAvailable = false
    }

    // MARK: - VisualizationEngine API

    func setViewportSize(width: Int, height: Int) {
        let newW = max(1, width)
        let newH = max(1, height)
        coreLock.lock()
        defer { coreLock.unlock() }
        guard newW != self.width || newH != self.height else { return }
        self.width = newW
        self.height = newH
        self.indexBuf = Array(repeating: 0, count: newW * newH)
        if let core {
            GeissCore_resize(core, Int32(newW), Int32(newH))
        }
        // Reallocate the GL index texture storage to match.
        if indexTex != 0 {
            glBindTexture(GLenum(GL_TEXTURE_2D), indexTex)
            glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_R8,
                         GLsizei(newW), GLsizei(newH), 0,
                         GLenum(GL_RED), GLenum(GL_UNSIGNED_BYTE), nil)
            glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        }
    }

    func addPCMMono(_ samples: [Float]) {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return }
        samples.withUnsafeBufferPointer { ptr in
            GeissCore_addPCM(core, ptr.baseAddress, Int32(samples.count))
        }
    }

    /// Push a magnitude spectrum to the core. Phase 5 wires this from
    /// VisualizationGLView's audio path; Phase 1 leaves it unused.
    func setSpectrum(_ mags: [Float]) {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return }
        mags.withUnsafeBufferPointer { ptr in
            GeissCore_setSpectrum(core, ptr.baseAddress, Int32(mags.count))
        }
    }

    var effectCount: Int {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return 0 }
        return Int(GeissCore_effectCount(core))
    }

    var currentEffectName: String {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core, let cName = GeissCore_currentEffectName(core) else { return "" }
        return String(cString: cName)
    }

    func effectName(at index: Int) -> String {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core, let cName = GeissCore_effectName(core, Int32(index)) else { return "" }
        return String(cString: cName)
    }

    func nextEffect() {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return }
        GeissCore_nextEffect(core)
    }

    func previousEffect() {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return }
        GeissCore_prevEffect(core)
    }

    func randomEffect() {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return }
        GeissCore_randomEffect(core)
    }

    func selectEffect(at index: Int) {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return }
        GeissCore_selectEffect(core, Int32(index))
    }

    var config: Config {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else {
            return Config(sensitivity: 0.20, gamma: 10, beatDetection: true, syncColorToSound: false,
                         slideShift: true, modeLocked: false, paletteLocked: false, autoSwitchSeconds: 550, visMode: 0)
        }
        var cCfg = GeissCoreConfig()
        GeissCore_getConfig(core, &cCfg)
        return Config(
            sensitivity: cCfg.sensitivity,
            gamma: Int(cCfg.gamma),
            beatDetection: cCfg.beatDetection != 0,
            syncColorToSound: cCfg.syncColorToSound != 0,
            slideShift: cCfg.slideShift != 0,
            modeLocked: cCfg.modeLocked != 0,
            paletteLocked: cCfg.paletteLocked != 0,
            autoSwitchSeconds: Int(cCfg.autoSwitchSeconds),
            visMode: Int(cCfg.visMode)
        )
    }

    func setConfig(_ cfg: Config) {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return }
        var cCfg = GeissCoreConfig()
        cCfg.sensitivity = cfg.sensitivity
        cCfg.gamma = Int32(cfg.gamma)
        cCfg.beatDetection = cfg.beatDetection ? 1 : 0
        cCfg.syncColorToSound = cfg.syncColorToSound ? 1 : 0
        cCfg.slideShift = cfg.slideShift ? 1 : 0
        cCfg.modeLocked = cfg.modeLocked ? 1 : 0
        cCfg.paletteLocked = cfg.paletteLocked ? 1 : 0
        cCfg.autoSwitchSeconds = Int32(cfg.autoSwitchSeconds)
        cCfg.visMode = Int32(cfg.visMode)
        GeissCore_setConfig(core, &cCfg)
    }

    func randomizePalette() {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return }
        GeissCore_randomizePalette(core)
    }

    func renderFrame() {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard isAvailable, let core else { return }

        // C core writes width*height bytes into indexBuf, and 1024 bytes into palette.
        indexBuf.withUnsafeMutableBufferPointer { idxPtr in
            GeissCore_render(core, idxPtr.baseAddress)
        }
        palette.withUnsafeMutableBufferPointer { palPtr in
            GeissCore_palette(core, palPtr.baseAddress)
        }

        // Upload textures.
        glBindTexture(GLenum(GL_TEXTURE_2D), indexTex)
        glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
        indexBuf.withUnsafeBufferPointer { ptr in
            glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, 0,
                            GLsizei(width), GLsizei(height),
                            GLenum(GL_RED), GLenum(GL_UNSIGNED_BYTE),
                            ptr.baseAddress)
        }

        glBindTexture(GLenum(GL_TEXTURE_2D), paletteTex)
        palette.withUnsafeBufferPointer { ptr in
            glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, 0,
                            256, 1,
                            GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE),
                            ptr.baseAddress)
        }

        // Draw.
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        glUseProgram(program)

        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), indexTex)
        glUniform1i(indicesUniform, 0)

        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), paletteTex)
        glUniform1i(paletteUniform, 1)

        glBindVertexArray(vao)
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        glBindVertexArray(0)

        glUseProgram(0)
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    }

    // MARK: - GL setup

    private func buildGLResources() -> Bool {
        // Fullscreen-quad vertex/fragment program.
        let vertexSrc = """
        #version 330 core
        layout(location = 0) in vec2 a_pos;
        layout(location = 1) in vec2 a_uv;
        out vec2 v_uv;
        void main() {
            v_uv = a_uv;
            gl_Position = vec4(a_pos, 0.0, 1.0);
        }
        """
        let fragmentSrc = """
        #version 330 core
        in vec2 v_uv;
        out vec4 frag;
        uniform sampler2D u_indices;
        uniform sampler2D u_palette;
        void main() {
            float idx = texture(u_indices, v_uv).r;
            frag = texture(u_palette, vec2(idx, 0.5));
        }
        """

        guard let prog = compileProgram(vertex: vertexSrc, fragment: fragmentSrc) else {
            return false
        }
        program = prog
        indicesUniform = glGetUniformLocation(program, "u_indices")
        paletteUniform = glGetUniformLocation(program, "u_palette")

        // Index texture (R8).
        glGenTextures(1, &indexTex)
        glBindTexture(GLenum(GL_TEXTURE_2D), indexTex)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_NEAREST)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_NEAREST)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_R8,
                     GLsizei(width), GLsizei(height), 0,
                     GLenum(GL_RED), GLenum(GL_UNSIGNED_BYTE), nil)

        // Palette texture (256x1 RGBA8).
        glGenTextures(1, &paletteTex)
        glBindTexture(GLenum(GL_TEXTURE_2D), paletteTex)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8,
                     256, 1, 0,
                     GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)

        glBindTexture(GLenum(GL_TEXTURE_2D), 0)

        // Fullscreen-quad VAO/VBO. Triangle strip: BL, BR, TL, TR.
        // pos.xy in clip space, uv.xy in [0,1]. Flip V so texture y=0 is at top of screen.
        let verts: [GLfloat] = [
            -1, -1, 0, 1,
             1, -1, 1, 1,
            -1,  1, 0, 0,
             1,  1, 1, 0,
        ]
        glGenVertexArrays(1, &vao)
        glBindVertexArray(vao)
        glGenBuffers(1, &vbo)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        verts.withUnsafeBufferPointer { ptr in
            glBufferData(GLenum(GL_ARRAY_BUFFER),
                         verts.count * MemoryLayout<GLfloat>.size,
                         ptr.baseAddress,
                         GLenum(GL_STATIC_DRAW))
        }
        let stride = GLsizei(MemoryLayout<GLfloat>.size * 4)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride, nil)
        let uvOffset = UnsafePointer<GLfloat>(bitPattern: MemoryLayout<GLfloat>.size * 2)
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(1, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), stride, uvOffset)
        glBindVertexArray(0)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), 0)

        return true
    }

    private func destroyGLResources() {
        if vbo != 0 { glDeleteBuffers(1, &vbo); vbo = 0 }
        if vao != 0 { glDeleteVertexArrays(1, &vao); vao = 0 }
        if indexTex != 0 { glDeleteTextures(1, &indexTex); indexTex = 0 }
        if paletteTex != 0 { glDeleteTextures(1, &paletteTex); paletteTex = 0 }
        if program != 0 { glDeleteProgram(program); program = 0 }
    }

    private func compileShader(type: GLenum, source: String) -> GLuint? {
        let shader = glCreateShader(type)
        guard shader != 0 else { return nil }
        var cString = (source as NSString).utf8String
        var length = GLint(source.utf8.count)
        withUnsafePointer(to: &cString) { ptr in
            ptr.withMemoryRebound(to: UnsafePointer<GLchar>?.self, capacity: 1) { p in
                glShaderSource(shader, 1, p, &length)
            }
        }
        glCompileShader(shader)
        var status: GLint = 0
        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &status)
        if status == GL_FALSE {
            var logLen: GLint = 0
            glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &logLen)
            var log = [GLchar](repeating: 0, count: Int(max(logLen, 1)))
            glGetShaderInfoLog(shader, GLsizei(log.count), nil, &log)
            NSLog("GeissEngine: shader compile failed: %s", log)
            glDeleteShader(shader)
            return nil
        }
        return shader
    }

    private func compileProgram(vertex: String, fragment: String) -> GLuint? {
        guard let vs = compileShader(type: GLenum(GL_VERTEX_SHADER), source: vertex) else { return nil }
        guard let fs = compileShader(type: GLenum(GL_FRAGMENT_SHADER), source: fragment) else {
            glDeleteShader(vs)
            return nil
        }
        let prog = glCreateProgram()
        glAttachShader(prog, vs)
        glAttachShader(prog, fs)
        glLinkProgram(prog)
        glDeleteShader(vs)
        glDeleteShader(fs)
        var status: GLint = 0
        glGetProgramiv(prog, GLenum(GL_LINK_STATUS), &status)
        if status == GL_FALSE {
            var logLen: GLint = 0
            glGetProgramiv(prog, GLenum(GL_INFO_LOG_LENGTH), &logLen)
            var log = [GLchar](repeating: 0, count: Int(max(logLen, 1)))
            glGetProgramInfoLog(prog, GLsizei(log.count), nil, &log)
            NSLog("GeissEngine: program link failed: %s", log)
            glDeleteProgram(prog)
            return nil
        }
        return prog
    }
}
