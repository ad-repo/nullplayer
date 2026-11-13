import AppKit
import OpenGL.GL3

/// NullPlayer-Fractal (the `fractal-vis` skill): beat-synced fractals drawn as GLSL in three passes
/// on the host's GL thread. The scene renders at `FractalScaler`'s scale into a half-float target, a
/// feedback pass lays it over the warped previous frame, and the present pass draws the result
/// into whatever framebuffer the host had bound (the window's, or a skin slot's offscreen one).
///
/// Audio: aubio's beats paced through a `BeatFeed`, the tempo from `.bpmUpdated`, and bass, mid
/// and treble from the host spectrum (`consumesHostSpectrum`). `FractalDirector` turns them into
/// the shader inputs.
final class FractalEngine: NSObject, VisualizationEngine {
    static let sceneKey = "fractal.scene"
    /// 0 for auto, else the fixed render scale (`FractalScaler`).
    static let renderScaleKey = "fractal.renderScale"
    private static let audioConsumerID = "fractalEngine"

    let displayName = "NullPlayer-Fractal"
    private(set) var isAvailable = false

    /// Guards `scene`, `hardCut`, `scaleSetting`, `bpm` and `bands`: main (presets, menu, tempo),
    /// the audio thread (spectrum) and the render thread all reach them.
    private let lock = NSLock()
    private var scene = FractalEngine.savedScene
    /// The last scene change skips the fade.
    private var hardCut = false
    private var scaleSetting = UserDefaults.standard.double(forKey: FractalEngine.renderScaleKey)
    private var bpm = 0
    private var bands = SIMD3<Float>(repeating: 0)
    private let beats = BeatFeed()
    private var observers: [NSObjectProtocol] = []

    // Render thread only.
    private var viewport = (width: 1, height: 1)
    private var renderSize = (width: 0, height: 0)
    private var director = FractalDirector(seed: UInt64.random(in: .min ... .max))
    private var directorScene = -1
    /// When the current scene began fading in over the trails.
    private var fadeStart = 0.0
    private var lastFrame: CFTimeInterval?
    private var scaler: FractalScaler
    /// A ring of `GL_TIME_ELAPSED` queries over the scene and feedback passes, each read when its
    /// slot comes round again, three frames on, so reading never waits on the GPU.
    private var timerQueries: [GLuint] = [0, 0, 0]
    private var timerFrame = 0
    private var lastGPUMs = 0.0
    /// Compiled on first use; 0 marks a scene whose shader failed.
    private var scenePrograms: [Int: GLuint] = [:]
    private var feedbackProgram: GLuint = 0
    private var presentProgram: GLuint = 0
    private var vao: GLuint = 0
    private var framebuffer: GLuint = 0
    /// The read side of a blit carrying the trails into resized targets.
    private var readFramebuffer: GLuint = 0
    private var sceneTexture: GLuint = 0
    /// Ping-pong: `feedbackTextures[newest]` holds the last frame.
    private var feedbackTextures: [GLuint] = [0, 0]
    private var newest = 0
    #if DEBUG
    private static let traces = ProcessInfo.processInfo.environment["FRACTAL_TRACE"] != nil
    private var lastTrace: CFTimeInterval = 0
    #endif

    private static var savedScene: Int {
        let saved = UserDefaults.standard.integer(forKey: sceneKey)
        return FractalScenes.all.indices.contains(saved) ? saved : 0
    }

    init(width: Int, height: Int) {
        scaler = FractalScaler(setting: UserDefaults.standard.double(forKey: Self.renderScaleKey), viewportWidth: width)
        super.init()
        viewport = (max(1, width), max(1, height))
        guard let feedback = GLProgram.make(vertex: FractalShaders.vertex, fragment: FractalShaders.feedback, label: "FractalEngine") else { return }
        guard let present = GLProgram.make(vertex: FractalShaders.vertex, fragment: FractalShaders.present, label: "FractalEngine") else {
            glDeleteProgram(feedback)
            return
        }
        feedbackProgram = feedback
        presentProgram = present
        glGenVertexArrays(1, &vao)
        glGenFramebuffers(1, &framebuffer)
        glGenFramebuffers(1, &readFramebuffer)
        glGenQueries(3, &timerQueries)
        isAvailable = true

        // Posted on the audio thread: store and return.
        observers.append(NotificationCenter.default.addObserver(
            forName: .audioBeatsUpdated, object: nil, queue: nil
        ) { [beats] note in
            guard let tracked = note.userInfo?["beats"] as? [Bool],
                  let hopMs = note.userInfo?["hopMs"] as? Double else { return }
            beats.store(beats: tracked, slotMs: hopMs)
        })
        // Posted on main; 0 when the detector resets.
        observers.append(NotificationCenter.default.addObserver(
            forName: .bpmUpdated, object: nil, queue: nil
        ) { [weak self] note in
            guard let self, let bpm = note.userInfo?["bpm"] as? Int else { return }
            self.lock.withLock { self.bpm = bpm }
        })
        // Engines are built on the render thread; the consumer table is main's.
        DispatchQueue.main.async {
            WindowManager.shared.audioEngine.addBeatConsumer(Self.audioConsumerID)
        }
    }

    /// Hosts release an engine through `cleanup()` with their context current; the last
    /// reference can go on any thread, so this never touches GL.
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Called on the render thread with the GL context current.
    func cleanup() {
        guard isAvailable else { return }
        isAvailable = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        DispatchQueue.main.async {
            WindowManager.shared.audioEngine.removeBeatConsumer(Self.audioConsumerID)
        }
        for program in [feedbackProgram, presentProgram] + scenePrograms.values where program != 0 {
            glDeleteProgram(program)
        }
        scenePrograms = [:]
        glDeleteTextures(1, &sceneTexture)
        glDeleteTextures(2, &feedbackTextures)
        glDeleteFramebuffers(1, &framebuffer)
        glDeleteFramebuffers(1, &readFramebuffer)
        glDeleteQueries(3, &timerQueries)
        glDeleteVertexArrays(1, &vao)
    }

    // MARK: - VisualizationEngine

    func setViewportSize(width: Int, height: Int) {
        viewport = (max(1, width), max(1, height))
    }

    /// The engine reads bands from the host spectrum and beats from aubio.
    func addPCMMono(_ samples: [Float]) {}

    /// The host's 256 linear bins (about 86 Hz each at 44.1 kHz), on the audio thread.
    func setSpectrum(_ mags: [Float]) {
        guard mags.count >= 128 else { return }
        func mean(_ range: Range<Int>) -> Float { mags[range].reduce(0, +) / Float(range.count) }
        let levels = SIMD3(mean(1..<4), mean(4..<24), mean(24..<128))
        lock.withLock { bands = levels }
    }

    func renderFrame() {
        guard isAvailable else { return }
        var hostDraw: GLint = 0, hostRead: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &hostDraw)
        glGetIntegerv(GLenum(GL_READ_FRAMEBUFFER_BINDING), &hostRead)

        let now = CACurrentMediaTime()
        let dt = lastFrame.map { now - $0 } ?? 0
        lastFrame = now
        let (sceneIndex, cut, setting, tempo, levels) = lock.withLock { (scene, hardCut, scaleSetting, self.bpm, self.bands) }

        scaler.setting = setting
        let scale = scaler.update(gpuMs: readTimerQuery(), frameMs: dt * 1000, now: now)
        let size = (width: max(1, Int((Double(viewport.width) * scale).rounded())),
                    height: max(1, Int((Double(viewport.height) * scale).rounded())))
        if size != renderSize { allocateTargets(size) }

        let sceneDef = FractalScenes.all[sceneIndex]
        let isBeat = beats.take(nowMs: BeatFeed.milliseconds())
        director.advance(dt: dt, beat: isBeat, bpm: tempo, bands: levels)
        if sceneIndex != directorScene {
            director.setScene(ranges: sceneDef.params)
            directorScene = sceneIndex
            // The new scene fades in over the old one's trails for a bar; a hard cut is at once.
            fadeStart = cut ? -.infinity : director.time
        }
        let barSeconds = director.beatInterval(bpm: tempo) * Double(FractalDirector.beatsPerBar)
        let fade = Float(min(1, (director.time - fadeStart) / barSeconds))
        trace(now: now, bpm: tempo, scale: scale)

        // The host resets shared state only when an engine is created; set ours every frame.
        glDisable(GLenum(GL_BLEND))
        glDisable(GLenum(GL_DEPTH_TEST))
        glDisable(GLenum(GL_SCISSOR_TEST))
        glDisable(GLenum(GL_CULL_FACE))
        glColorMask(GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE))
        glBindVertexArray(vao)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glViewport(0, 0, GLsizei(renderSize.width), GLsizei(renderSize.height))
        glBeginQuery(GLenum(GL_TIME_ELAPSED), timerQueries[timerFrame % timerQueries.count])

        // Scene.
        attach(sceneTexture)
        if let program = program(for: sceneIndex) {
            glUseProgram(program)
            setSceneUniforms(program, scene: sceneDef)
            glDrawArrays(GLenum(GL_TRIANGLES), 0, 3)
        } else {
            glClearColor(0, 0, 0, 0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }

        // Feedback.
        let next = 1 - newest
        attach(feedbackTextures[next])
        glUseProgram(feedbackProgram)
        bind(feedbackTextures[newest], unit: 0, to: "u_prev", in: feedbackProgram)
        bind(sceneTexture, unit: 1, to: "u_scene", in: feedbackProgram)
        let pulse = director.beatPulse
        glUniform2f(location(feedbackProgram, "u_res"), GLfloat(renderSize.width), GLfloat(renderSize.height))
        glUniform1f(location(feedbackProgram, "u_decay"), sceneDef.trail)
        glUniform1f(location(feedbackProgram, "u_zoom"), 1 / (1.003 + sceneDef.push + 0.01 * pulse))
        glUniform1f(location(feedbackProgram, "u_rot"), 0.001 + 0.005 * pulse * (director.barCount % 2 == 0 ? 1 : -1))
        glUniform1f(location(feedbackProgram, "u_swirl"), sceneDef.swirl * (0.3 + director.bands.y))
        glUniform1f(location(feedbackProgram, "u_hue"), 0.01 + 0.05 * director.fastBands.z)
        glUniform1f(location(feedbackProgram, "u_fade"), fade * fade * (3 - 2 * fade))
        glDrawArrays(GLenum(GL_TRIANGLES), 0, 3)
        glEndQuery(GLenum(GL_TIME_ELAPSED))
        timerFrame += 1
        glBindTexture(GLenum(GL_TEXTURE_2D), feedbackTextures[next])
        glGenerateMipmap(GLenum(GL_TEXTURE_2D))
        newest = next

        // Present into the host's framebuffer.
        glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), GLuint(hostDraw))
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(hostRead))
        glViewport(0, 0, GLsizei(viewport.width), GLsizei(viewport.height))
        glUseProgram(presentProgram)
        bind(feedbackTextures[newest], unit: 0, to: "u_image", in: presentProgram)
        glUniform2f(location(presentProgram, "u_res"), GLfloat(viewport.width), GLfloat(viewport.height))
        glUniform1f(location(presentProgram, "u_beat"), pulse)
        glDrawArrays(GLenum(GL_TRIANGLES), 0, 3)

        glUseProgram(0)
        glBindVertexArray(0)
        for unit in [1, 0] {
            glActiveTexture(GLenum(GL_TEXTURE0 + Int32(unit)))
            glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        }
    }

    // MARK: - GL helpers (render thread)

    // ponytail: compiled on first show, so the first switch to each scene stalls about a frame;
    // precompile on a shared background context if that hitch is ever noticed.
    private func program(for index: Int) -> GLuint? {
        if let program = scenePrograms[index] { return program == 0 ? nil : program }
        let scene = FractalScenes.all[index]
        let program = GLProgram.make(vertex: FractalShaders.vertex, fragment: FractalShaders.fragment(for: scene),
                                     label: "FractalEngine \(scene.name)") ?? 0
        scenePrograms[index] = program
        return program == 0 ? nil : program
    }

    private func setSceneUniforms(_ program: GLuint, scene: FractalScene) {
        let d = director
        let palette = d.palette
        glUniform2f(location(program, "u_res"), GLfloat(renderSize.width), GLfloat(renderSize.height))
        // ponytail: wrapped so float precision holds over a long session; the wrap is a visible
        // jump every 10 min (`u_time`) or 4096 beats (`u_beatTime`, whose periods all divide it).
        glUniform1f(location(program, "u_time"), GLfloat(d.time.truncatingRemainder(dividingBy: 600)))
        glUniform1f(location(program, "u_beatTime"), GLfloat(d.beatTime.truncatingRemainder(dividingBy: 4096)))
        glUniform1f(location(program, "u_beat"), d.beatPulse)
        glUniform1f(location(program, "u_bar"), GLfloat(d.barCount % 256))
        glUniform3f(location(program, "u_bands"), d.bands.x, d.bands.y, d.bands.z)
        glUniform3f(location(program, "u_fast"), d.fastBands.x, d.fastBands.y, d.fastBands.z)
        glUniform4f(location(program, "u_p"), d.params.x, d.params.y, d.params.z, d.params.w)
        glUniform3f(location(program, "u_pa"), palette.a.x, palette.a.y, palette.a.z)
        glUniform3f(location(program, "u_pb"), palette.b.x, palette.b.y, palette.b.z)
        glUniform3f(location(program, "u_pc"), palette.c.x, palette.c.y, palette.c.z)
        glUniform3f(location(program, "u_pd"), palette.d.x, palette.d.y, palette.d.z)
        glUniform1i(location(program, "u_steps"), scene.steps)
    }

    private func location(_ program: GLuint, _ name: String) -> GLint {
        glGetUniformLocation(program, name)
    }

    private func bind(_ texture: GLuint, unit: Int32, to name: String, in program: GLuint) {
        glActiveTexture(GLenum(GL_TEXTURE0 + unit))
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glUniform1i(location(program, name), unit)
    }

    private func attach(_ texture: GLuint) {
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_2D), texture, 0)
    }

    /// Half-float scene and feedback targets at `size`, the feedback ones with mips for the present
    /// pass's bloom. The trails are scaled across, so a resize (or a render-scale step) keeps them.
    private func allocateTargets(_ size: (width: Int, height: Int)) {
        var textures = [GLuint](repeating: 0, count: 3)
        glGenTextures(3, &textures)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glClearColor(0, 0, 0, 0)
        for (i, texture) in textures.enumerated() {
            let mipmapped = i > 0
            glBindTexture(GLenum(GL_TEXTURE_2D), texture)
            glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA16F, GLsizei(size.width), GLsizei(size.height), 0,
                         GLenum(GL_RGBA), GLenum(GL_HALF_FLOAT), nil)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER),
                            mipmapped ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
            attach(texture)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }
        let newFeedback = [textures[1], textures[2]]
        if feedbackTextures[newest] != 0 {
            glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), readFramebuffer)
            glFramebufferTexture2D(GLenum(GL_READ_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                                   GLenum(GL_TEXTURE_2D), feedbackTextures[newest], 0)
            glFramebufferTexture2D(GLenum(GL_DRAW_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                                   GLenum(GL_TEXTURE_2D), newFeedback[newest], 0)
            glBlitFramebuffer(0, 0, GLint(renderSize.width), GLint(renderSize.height),
                              0, 0, GLint(size.width), GLint(size.height),
                              GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_LINEAR))
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        }
        for texture in newFeedback {
            glBindTexture(GLenum(GL_TEXTURE_2D), texture)
            glGenerateMipmap(GLenum(GL_TEXTURE_2D))
        }
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
        glDeleteTextures(1, &sceneTexture)
        glDeleteTextures(2, &feedbackTextures)
        sceneTexture = textures[0]
        feedbackTextures = newFeedback
        renderSize = size
    }

    /// The GPU time of the frame three back, if its query has finished; nil leaves the scale be.
    private func readTimerQuery() -> Double? {
        guard timerFrame >= timerQueries.count else { return nil }
        let query = timerQueries[timerFrame % timerQueries.count]
        var available: GLint = 0
        glGetQueryObjectiv(query, GLenum(GL_QUERY_RESULT_AVAILABLE), &available)
        guard available != 0 else { return nil }
        var nanoseconds: GLuint64 = 0
        glGetQueryObjectui64v(query, GLenum(GL_QUERY_RESULT), &nanoseconds)
        lastGPUMs = Double(nanoseconds) / 1_000_000
        return lastGPUMs
    }

    private func trace(now: CFTimeInterval, bpm: Int, scale: Double) {
        #if DEBUG
        guard Self.traces, now - lastTrace >= 1 else { return }
        lastTrace = now
        NSLog("FRACTAL scene=%@ render=%dx%d scale=%.2f gpu=%.1fms bpm=%d beats=%d bar=%d phase=%.2f bands=%.2f/%.2f/%.2f",
              FractalScenes.all[directorScene].name, renderSize.width, renderSize.height, scale, lastGPUMs, bpm,
              director.beatCount, director.barCount, director.tempoPhase,
              director.bands.x, director.bands.y, director.bands.z)
        #endif
    }

    // MARK: - Scenes (presets)

    var presetCount: Int { FractalScenes.all.count }
    var presetIndex: Int? { lock.withLock { scene } }

    func presetName(at index: Int) -> String {
        FractalScenes.all.indices.contains(index) ? FractalScenes.all[index].name : ""
    }

    func selectPreset(at index: Int, hardCut: Bool) {
        guard FractalScenes.all.indices.contains(index) else { return }
        select(hardCut: hardCut) { _ in index }
    }

    func stepPreset(forward: Bool, hardCut: Bool) {
        select(hardCut: hardCut) { ($0 + (forward ? 1 : presetCount - 1)) % presetCount }
    }

    func randomPreset(hardCut: Bool) {
        select(hardCut: hardCut) { current in
            var index = current
            while index == current { index = Int.random(in: 0..<presetCount) }
            return index
        }
    }

    /// Picks the scene from the current one under one lock.
    /// The audio and render threads take this lock, so the preference is written after it.
    private func select(hardCut: Bool, _ pick: (_ current: Int) -> Int) {
        let picked = lock.withLock {
            scene = pick(scene)
            self.hardCut = hardCut
            return scene
        }
        UserDefaults.standard.set(picked, forKey: Self.sceneKey)
    }

    // MARK: - Menu (main thread)

    private static let scaleChoices: [(title: String, scale: Double)] = [("Auto", 0), ("50%", 0.5), ("75%", 0.75), ("100%", 1)]

    func addMenuItems(to menu: NSMenu) {
        let current = lock.withLock { scaleSetting }
        let submenu = NSMenu()
        for (i, choice) in Self.scaleChoices.enumerated() {
            let item = NSMenuItem(title: choice.title, action: #selector(renderScaleAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = choice.scale == current ? .on : .off
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Render Scale", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    @objc private func renderScaleAction(_ sender: NSMenuItem) {
        let scale = Self.scaleChoices[sender.tag].scale
        lock.withLock { scaleSetting = scale }
        UserDefaults.standard.set(scale, forKey: Self.renderScaleKey)
    }
}
