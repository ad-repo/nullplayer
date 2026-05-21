import Foundation
import OpenGL.GL3
import AppKit

/// Met Museum Art Visualization Engine
///
/// Displays rotating public domain artwork from The Metropolitan Museum of Art
/// in response to audio analysis. Features include:
/// - Async slideshow with retry policy and exponential backoff
/// - Beat detection and transition triggering
/// - Audio analysis via RMS ring buffer
/// - Transition shader with 4 modes (fade, slide, zoom, dissolve)
/// - Attribution overlay rendering
/// - Configurable department, interval, transition, duration, aspect ratio, and audio-sync
final class MetMuseumEngine: VisualizationEngine {

    // MARK: - Config

    struct Config: Equatable, Codable {
        var departmentID: Int?
        var intervalSeconds: Double = 30.0
        var transitionMode: TransitionMode = .crossfade
        var transitionDurationSeconds: Double = 1.5
        var audioReactiveEffects: Bool = false
        var beatTriggeredChanges: Bool = false
        var aspectMode: AspectMode = .fit
        var showAttribution: Bool = false
    }

    enum TransitionMode: String, CaseIterable, Codable {
        case crossfade, kenBurns, beatCut, slide
    }

    enum AspectMode: String, CaseIterable, Codable {
        case fit, fill, stretch
    }

    // MARK: - VisualizationEngine

    private(set) var isAvailable: Bool = false
    let displayName: String = "Met Museum Art"

    // MARK: - State

    private let coreLock = NSRecursiveLock()
    private var config: Config = Config()

    private var width: Int = 0
    private var height: Int = 0

    private let client = MetMuseumClient()
    private let imageCache = MetMuseumImageCache()

    // Slideshow state
    private var currentObjectID: Int?
    private var currentImage: NSImage?
    private var currentAttribution: String = ""
    private var slideshowTask: Task<Void, Never>?

    // Audio analysis
    private let rmsWindowSize = 512
    private let rmsRingBufferSize = 5  // Last 5 RMS values
    private var rmsRingBuffer: [Float] = []
    private var rmsRingIndex = 0
    private var pcmBuffer: [Float] = []
    private var lastBeatTime: Date = Date()
    private var smoothedEnergy: Float = 0.0
    private let energyAlpha: Float = 0.15
    private var pendingBeatAdvance = false
    private var fetchInFlight = false

    // Transition state
    private var transitionProgress: Float = 0.0
    private var isTransitioning: Bool = false
    private var transitionStartTime: Date = Date()
    private var nextImage: NSImage?

    // GL resources
    private var program: GLuint = 0
    private var currentTexture: GLuint = 0
    private var nextTexture: GLuint = 0
    private var attributionTexture: GLuint = 0
    private var placeholderTexture: GLuint = 0
    private var vao: GLuint = 0
    private var vbo: GLuint = 0

    private var currentTexUniform: GLint = -1
    private var nextTexUniform: GLint = -1
    private var attributionTexUniform: GLint = -1
    private var progressUniform: GLint = -1
    private var modeUniform: GLint = -1
    private var imageAspectUniform: GLint = -1
    private var viewportAspectUniform: GLint = -1
    private var aspectModeUniform: GLint = -1
    private var energyUniform: GLint = -1
    private var audioReactiveUniform: GLint = -1
    private var attributionAlphaUniform: GLint = -1
    private var attributionSizeUniform: GLint = -1
    private var imageStartTimeUniform: GLint = -1

    // Actual attribution texture size, in pixels, for shader positioning
    private var attributionTextureWidth: Int = 0
    private var attributionTextureHeight: Int = 0

    // Pending upload queue
    private var pendingUploads: [(data: Data, objectID: Int)] = []
    private var pendingAttributionUpload: (cgImage: CGImage, width: Int, height: Int)?
    private var lastManualSkipTime: Date = .distantPast
    private let manualSkipMinInterval: TimeInterval = 0.5

    // Image change tracking (for attribution fade)
    private var imageChangeTime: Date = Date()

    // Image dimensions for aspect ratio handling
    private var currentImageWidth: Int = 0
    private var currentImageHeight: Int = 0
    private var imageStartTime: Date = Date()

    // Department state (loaded at init)
    enum DepartmentsState {
        case loading
        case loaded([MetDepartment])
        case failed
    }
    private var rawDepartmentsState: DepartmentsState = .loading
    // Departments that returned no public-domain artwork; removed from the
    // visible list and skipped by the slideshow.
    private var excludedDepartmentIDs: Set<Int> = []

    /// Departments with empty (no public-domain) entries filtered out.
    var departmentsState: DepartmentsState {
        coreLock.lock()
        defer { coreLock.unlock() }
        switch rawDepartmentsState {
        case .loading, .failed:
            return rawDepartmentsState
        case .loaded(let depts):
            let filtered = depts.filter { !excludedDepartmentIDs.contains($0.id) }
            return .loaded(filtered)
        }
    }

    // Network retry state
    private var retryTaskActive = false

    // MARK: - Init / cleanup

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.rmsRingBuffer = Array(repeating: 0, count: rmsRingBufferSize)
        self.pcmBuffer = []

        if !buildGLResources() {
            NSLog("MetMuseumEngine: failed to build GL resources")
            destroyGLResources()
            return
        }

        self.isAvailable = true
        NSLog("MetMuseumEngine: initialized %dx%d", self.width, self.height)

        // Load departments on background task
        Task {
            do {
                let depts = try await client.fetchDepartments()
                coreLock.lock()
                self.rawDepartmentsState = .loaded(depts)
                coreLock.unlock()
            } catch {
                coreLock.lock()
                self.rawDepartmentsState = .failed
                coreLock.unlock()
                NSLog("MetMuseumEngine: Failed to fetch departments: %@", error.localizedDescription)
            }
        }

        // Slideshow is gated on audio state — VisualizationGLView's engine
        // factory calls setAudioActive() after creating us, which starts the
        // slideshow if audio is playing. Auto-starting here would race that
        // call and leave the slideshow running even when audio is stopped.
    }

    deinit {
        cleanup()
    }

    func cleanup() {
        coreLock.lock()
        defer { coreLock.unlock() }

        slideshowTask?.cancel()
        slideshowTask = nil
        destroyGLResources()
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
    }

    func addPCMMono(_ samples: [Float]) {
        coreLock.lock()
        defer { coreLock.unlock() }

        // Accumulate PCM samples
        pcmBuffer.append(contentsOf: samples)

        // When we have enough samples, compute RMS and update ring buffer
        while pcmBuffer.count >= rmsWindowSize {
            let window = Array(pcmBuffer.prefix(rmsWindowSize))
            pcmBuffer.removeFirst(rmsWindowSize)

            // Compute RMS of this window
            let meanSquare = window.reduce(0) { $0 + $1 * $1 } / Float(window.count)
            let rms = sqrt(meanSquare)

            // Update RMS ring buffer
            rmsRingBuffer[rmsRingIndex] = rms
            rmsRingIndex = (rmsRingIndex + 1) % rmsRingBufferSize

            // Update smoothed energy (one-pole low-pass)
            smoothedEnergy = smoothedEnergy * (1.0 - energyAlpha) + rms * energyAlpha

            // Beat detection: RMS > 1.5 × mean of ring buffer AND 250ms gate
            let ringMean = rmsRingBuffer.reduce(0, +) / Float(rmsRingBufferSize)
            let now = Date()
            if rms > 1.5 * ringMean && now.timeIntervalSince(lastBeatTime) > 0.25 {
                lastBeatTime = now
                // Set flag; drain in renderFrame to avoid reentrancy on coreLock
                if config.beatTriggeredChanges {
                    pendingBeatAdvance = true
                }
            }
        }
    }

    func renderFrame() {
        coreLock.lock()
        defer { coreLock.unlock() }

        guard isAvailable else { return }

        // Drain pending beat advance flag
        let shouldAdvanceOnBeat = pendingBeatAdvance
        pendingBeatAdvance = false

        // Process pending uploads (target appropriate texture)
        for (data, objectID) in pendingUploads {
            uploadImage(data: data, to: isTransitioning ? nextTexture : currentTexture)
        }
        pendingUploads.removeAll()

        // Process pending attribution texture upload on the GL thread
        if let pending = pendingAttributionUpload {
            pendingAttributionUpload = nil
            if attributionTexture == 0 {
                glGenTextures(1, &attributionTexture)
                glBindTexture(GLenum(GL_TEXTURE_2D), attributionTexture)
                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
                glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
                glBindTexture(GLenum(GL_TEXTURE_2D), 0)
            }
            uploadCGImage(pending.cgImage, to: attributionTexture, width: pending.width, height: pending.height)
            attributionTextureWidth = pending.cgImage.width
            attributionTextureHeight = pending.cgImage.height
        }

        // Advance on beat if flagged
        if shouldAdvanceOnBeat && !isTransitioning && !fetchInFlight {
            advanceSlideshowImmediate()
        }

        // Update transition progress
        if isTransitioning {
            let elapsed = Float(Date().timeIntervalSince(transitionStartTime))
            let duration = Float(config.transitionDurationSeconds)
            transitionProgress = min(1.0, elapsed / duration)

            if transitionProgress >= 1.0 {
                isTransitioning = false
                currentImage = nextImage
                nextImage = nil
                transitionProgress = 0.0
                imageChangeTime = Date()
                // Swap textures
                if currentTexture != 0 && nextTexture != 0 {
                    let temp = currentTexture
                    currentTexture = nextTexture
                    nextTexture = temp
                }
            }
        }

        // Render
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        glClearColor(0.1, 0.1, 0.1, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        guard currentImage != nil || placeholderTexture != 0 else { return }

        glUseProgram(program)

        let texToRender = currentImage != nil ? currentTexture : placeholderTexture

        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), texToRender)
        glUniform1i(currentTexUniform, 0)

        if isTransitioning && nextTexture != 0 {
            glActiveTexture(GLenum(GL_TEXTURE1))
            glBindTexture(GLenum(GL_TEXTURE_2D), nextTexture)
            glUniform1i(nextTexUniform, 1)
        }

        if attributionTexture != 0 {
            glActiveTexture(GLenum(GL_TEXTURE2))
            glBindTexture(GLenum(GL_TEXTURE_2D), attributionTexture)
            glUniform1i(attributionTexUniform, 2)
        }

        glUniform1f(progressUniform, transitionProgress)
        glUniform1i(modeUniform, GLint(config.transitionMode.modeValue))
        glUniform1f(energyUniform, smoothedEnergy)
        glUniform1i(audioReactiveUniform, config.audioReactiveEffects ? 1 : 0)

        // Set aspect ratio uniforms per-frame
        glUniform2f(imageAspectUniform, Float(currentImageWidth), Float(currentImageHeight))
        glUniform2f(viewportAspectUniform, Float(width), Float(height))
        glUniform1i(aspectModeUniform, GLint(config.aspectMode.shaderValue))

        // Set image elapsed time for Ken Burns
        let imageElapsed = Float(Date().timeIntervalSince(imageStartTime))
        glUniform1f(imageStartTimeUniform, imageElapsed)

        // Attribution fade timing
        let timeSinceImageChange = Float(Date().timeIntervalSince(imageChangeTime))
        let attributionAlpha: Float
        if timeSinceImageChange < 4.0 {
            // Fade in over first 4s
            attributionAlpha = min(1.0, timeSinceImageChange / 4.0)
        } else if timeSinceImageChange < 5.0 {
            // Fade out over 1s (from 4s to 5s)
            attributionAlpha = max(0.0, 1.0 - (timeSinceImageChange - 4.0))
        } else {
            attributionAlpha = 0.0
        }
        // Only show the overlay when a real attribution texture is bound. Without
        // this guard the shader samples an unbound texture (garbage) or smears
        // the dark background of the previous overlay across a hard-coded rect.
        let overlayActive = config.showAttribution && attributionTexture != 0 && attributionTextureWidth > 0 && attributionTextureHeight > 0
        glUniform1f(attributionAlphaUniform, overlayActive ? attributionAlpha : 0.0)
        if overlayActive {
            glUniform2f(attributionSizeUniform, Float(attributionTextureWidth), Float(attributionTextureHeight))
        } else {
            glUniform2f(attributionSizeUniform, 0.0, 0.0)
        }

        glBindVertexArray(vao)
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        glBindVertexArray(0)

        glUseProgram(0)
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    }

    // MARK: - Configuration

    func setConfig(_ newConfig: Config) {
        coreLock.lock()
        defer { coreLock.unlock() }

        let oldDepartment = config.departmentID
        config = newConfig

        // If department changed, restart slideshow
        if oldDepartment != newConfig.departmentID {
            slideshowTask?.cancel()
            slideshowTask = nil
            startSlideshow()
        }
    }

    func getConfig() -> Config {
        coreLock.lock()
        defer { coreLock.unlock() }
        return config
    }

    func clearCache() {
        imageCache.clearCache()
        NSLog("MetMuseumEngine: Image cache cleared")
    }

    /// Immediately advance to a new random artwork. Safe to call from any thread.
    /// Rate-limited so rapid key-mashing doesn't flood the Met API (which throttles).
    func skipToNextArtwork() {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard isAvailable else { return }
        // Drop the request if a fetch is already underway — prevents key-mashing
        // from cancelling and re-issuing requests in a tight loop.
        if fetchInFlight { return }
        let now = Date()
        if now.timeIntervalSince(lastManualSkipTime) < manualSkipMinInterval {
            return
        }
        lastManualSkipTime = now
        advanceSlideshowImmediate()
    }

    func setAudioActive(_ active: Bool) {
        coreLock.lock()
        defer { coreLock.unlock() }

        if !active {
            slideshowTask?.cancel()
            slideshowTask = nil
        } else if slideshowTask == nil {
            startSlideshow()
        }
    }

    // MARK: - Slideshow Management

    private func startSlideshow() {
        slideshowTask?.cancel()
        // Task.detached so the slideshow loop is not born cancelled when
        // started from inside another task (e.g. advanceSlideshowImmediate).
        slideshowTask = Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await self.fetchAndDisplayRandomArtwork()
                    try await Task.sleep(nanoseconds: UInt64(self.getConfig().intervalSeconds * 1_000_000_000))
                } catch is CancellationError {
                    return
                } catch {
                    NSLog("MetMuseumEngine slideshow error: %@", error.localizedDescription)
                    // For throttle errors honour Retry-After (or use a long
                    // default) instead of hammering the API on the 1/2/4s ladder.
                    let throttle = (error as? MetMuseumClient.NetworkError)?.isThrottle == true
                    let retryAfter = (error as? MetMuseumClient.NetworkError)?.retryAfter
                    let retryDelays: [Double]
                    if throttle {
                        let base = max(10.0, retryAfter ?? 30.0)
                        retryDelays = [base, base * 2, base * 4]
                    } else {
                        retryDelays = [1.0, 2.0, 4.0]
                    }
                    var success = false
                    for retryDelay in retryDelays {
                        if Task.isCancelled { break }
                        try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                        do {
                            try await self.fetchAndDisplayRandomArtwork()
                            success = true
                            break
                        } catch {
                            // Continue to next retry
                        }
                    }
                    if !success && !Task.isCancelled {
                        NSLog("MetMuseumEngine: 3 retries exhausted, will retry every 30s")
                        // Pause slideshow, retry every 30s
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 30_000_000_000)
                            if Task.isCancelled { break }
                            do {
                                try await self.fetchAndDisplayRandomArtwork()
                                // Success, resume normal loop
                                break
                            } catch {
                                // Continue retrying every 30s
                            }
                        }
                    }
                }
            }
        }
    }

    /// Mark the currently-selected department as having no public-domain
    /// artwork (we just exhausted the random-attempt loop). Switch the active
    /// department to any remaining one, or to "all departments" if there's
    /// nothing else to fall back to.
    private func excludeCurrentDepartmentAndPickAnother() {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let currentID = config.departmentID else {
            // Already searching across all departments — nothing to exclude.
            return
        }
        excludedDepartmentIDs.insert(currentID)
        NSLog("MetMuseumEngine: department %d has no public-domain artwork; removing from list", currentID)

        let remaining: [MetDepartment]
        if case .loaded(let depts) = rawDepartmentsState {
            remaining = depts.filter { !excludedDepartmentIDs.contains($0.id) }
        } else {
            remaining = []
        }
        let nextID = remaining.randomElement()?.id
        // nil here means "all departments" — a safe fallback.
        config.departmentID = nextID
        let key = MetMuseumEngine.DefaultsKey.departmentID
        if let nextID = nextID {
            UserDefaults.standard.set(nextID, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func advanceSlideshowImmediate() {
        // Called from renderFrame under coreLock; trigger next fetch
        // without waiting for the interval timer.
        // Task.detached so the child task does not inherit cancellation
        // from the parent context (see CLAUDE.md: regular Task { } inherits
        // cancellation and would self-cancel when startSlideshow() runs below).
        slideshowTask?.cancel()
        slideshowTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                try await self.fetchAndDisplayRandomArtwork()
            } catch is CancellationError {
                return
            } catch {
                NSLog("MetMuseumEngine beat-triggered advance error: %@", error.localizedDescription)
            }
            self.startSlideshow()
        }
    }

    private func fetchAndDisplayRandomArtwork() async throws {
        coreLock.lock()
        if fetchInFlight {
            coreLock.unlock()
            return
        }
        fetchInFlight = true
        coreLock.unlock()
        defer {
            coreLock.lock()
            fetchInFlight = false
            coreLock.unlock()
        }

        // Fetch list of object IDs for the department
        let objectIDs = try await client.fetchObjectIDs(departmentID: config.departmentID)
        guard !objectIDs.isEmpty else {
            throw MetMuseumError.noArtworkFound
        }

        // Try random objects until we find a public-domain one with an image.
        // Per-object errors (404, transient 403 throttle) don't kill the loop —
        // they just count as a miss so we can keep looking. Throttle errors
        // are re-thrown so the slideshow's outer backoff can wait properly.
        let maxAttempts = min(40, objectIDs.count)
        var attempts = 0
        var selectedObject: MetObject?
        var lastThrottleError: Error?

        while attempts < maxAttempts {
            let randomID = objectIDs.randomElement() ?? objectIDs.first!
            attempts += 1

            do {
                if let obj = try await client.fetchObject(id: randomID) {
                    selectedObject = obj
                    break
                }
            } catch let error as MetMuseumClient.NetworkError where error.isThrottle {
                // Remember and bail out so the outer loop can back off.
                lastThrottleError = error
                break
            } catch {
                // Per-object miss (404, decode error, transient). Skip and try another.
                continue
            }
        }

        if let throttleError = lastThrottleError, selectedObject == nil {
            throw throttleError
        }

        guard let objectInfo = selectedObject else {
            // Exhausted attempts without finding a public-domain piece. Mark
            // this department as empty so the menu hides it and the slideshow
            // doesn't keep retrying it. Pick a different department for the
            // next attempt.
            excludeCurrentDepartmentAndPickAnother()
            throw MetMuseumError.noArtworkFound
        }

        // Download image (check cache first)
        let imageData: Data
        if let cachedData = imageCache.cachedImageData(for: objectInfo.objectID) {
            imageData = cachedData
        } else {
            imageData = try await client.downloadImage(url: URL(string: objectInfo.primaryImage)!)
            imageCache.store(imageData, for: objectInfo.objectID)
        }

        let image = NSImage(data: imageData)
        guard let image = image else { throw MetMuseumError.noImageURL }

        // If the slideshow was cancelled while we were fetching (e.g. audio
        // stopped), drop the image instead of pushing it to the GPU.
        try Task.checkCancellation()

        coreLock.lock()
        let attribution = "\(objectInfo.title) - \(objectInfo.artistDisplayName ?? "Unknown") (\(objectInfo.objectDate ?? ""))"
        currentObjectID = objectInfo.objectID
        currentAttribution = attribution

        // Skip the transition effect when the new image's aspect ratio differs
        // from the current image's — the shader samples both textures with a
        // single aspect uniform, so a mid-transition mismatch visibly stretches
        // one of the two images. Hard-cutting looks cleaner than a stretched
        // crossfade. Threshold is relative (>5%) so near-matches still animate.
        let newW = Double(image.size.width)
        let newH = Double(image.size.height)
        let newAspect = newH > 0 ? newW / newH : 1.0
        let curAspect = (currentImageWidth > 0 && currentImageHeight > 0)
            ? Double(currentImageWidth) / Double(currentImageHeight)
            : newAspect
        let aspectMismatch = currentImage != nil &&
            abs(newAspect - curAspect) / max(newAspect, curAspect) > 0.05

        if aspectMismatch {
            // Hard cut: route the upload straight to currentTexture and skip
            // the animation. uploadImage targets currentTexture when
            // !isTransitioning (see renderFrame), so clear the flag first.
            isTransitioning = false
            nextImage = nil
            transitionProgress = 0.0
            currentImage = image
        } else {
            nextImage = image
            isTransitioning = true
            transitionStartTime = Date()
            transitionProgress = 0.0
        }
        imageChangeTime = Date()
        pendingUploads.append((imageData, objectInfo.objectID))
        coreLock.unlock()

        // Queue attribution texture upload (runs on GL thread in renderFrame).
        // GL calls must happen on the render thread with the active context;
        // calling glBindTexture from this async Task crashes (KERN_INVALID_ADDRESS).
        if config.showAttribution {
            queueAttributionTexture(from: attribution)
        }
    }

    // MARK: - GL Setup

    private func buildGLResources() -> Bool {
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
        uniform sampler2D u_current;
        uniform sampler2D u_next;
        uniform float u_progress;
        uniform int u_mode;
        uniform vec2 u_imageAspect;
        uniform vec2 u_viewportAspect;
        uniform int u_aspectMode;
        uniform float u_energy;
        uniform int u_audioReactive;
        uniform float u_imageElapsed;
        uniform sampler2D u_attribution;
        uniform float u_attributionAlpha;
        uniform vec2 u_attributionSize;  // attribution texture size in px, (0,0) => disabled

        vec3 rgb2hsv(vec3 rgb) {
            vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
            vec4 p = rgb.g < rgb.b ? vec4(rgb.bg, K.wz) : vec4(rgb.gb, K.xy);
            vec4 q = rgb.r < p.x ? vec4(p.xyw, rgb.r) : vec4(rgb.r, p.yzx);
            float d = q.x - min(q.w, q.y);
            float e = 1.0e-10;
            return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
        }

        vec3 hsv2rgb(vec3 hsv) {
            vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
            vec3 p = abs(fract(hsv.xxx + K.xyz) * 6.0 - K.www);
            return hsv.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), hsv.y);
        }

        vec2 computeAspectAdjustedUV(vec2 uv) {
            vec2 adjustedUV = uv;
            if (u_aspectMode == 0) {
                // Fit: letterbox/pillarbox. Map viewport UV into image space so the
                // image fully fits and the leftover bands fall outside [0,1].
                float imageAspect = u_imageAspect.x / u_imageAspect.y;
                float viewAspect = u_viewportAspect.x / u_viewportAspect.y;
                if (imageAspect > viewAspect) {
                    // Image wider than viewport: full image width, letterbox top/bottom
                    float scale = imageAspect / viewAspect;
                    adjustedUV.y = (adjustedUV.y - 0.5) * scale + 0.5;
                } else {
                    // Image taller than viewport: full image height, pillarbox sides
                    float scale = viewAspect / imageAspect;
                    adjustedUV.x = (adjustedUV.x - 0.5) * scale + 0.5;
                }
            } else if (u_aspectMode == 1) {
                // Fill: crop to fill viewport
                float imageAspect = u_imageAspect.x / u_imageAspect.y;
                float viewAspect = u_viewportAspect.x / u_viewportAspect.y;
                if (imageAspect < viewAspect) {
                    // Image is taller, crop top/bottom
                    float scale = viewAspect / imageAspect;
                    adjustedUV.y = (adjustedUV.y - 0.5) / scale + 0.5;
                } else {
                    // Image is wider, crop left/right
                    float scale = imageAspect / viewAspect;
                    adjustedUV.x = (adjustedUV.x - 0.5) / scale + 0.5;
                }
            }
            // u_aspectMode == 2: stretch (no adjustment needed)
            return adjustedUV;
        }

        // Sample a texture, returning black for UVs outside [0,1] so letterbox
        // bars don't smear the edge pixel via CLAMP_TO_EDGE.
        vec4 sampleBounded(sampler2D tex, vec2 uv) {
            if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
                return vec4(0.0, 0.0, 0.0, 1.0);
            }
            return texture(tex, uv);
        }

        void main() {
            vec2 imgUV = computeAspectAdjustedUV(v_uv);

            // For Ken Burns, zoom inside image space; the zoom is clamped so it
            // never escapes the image bounds, so the letterbox bars stay intact.
            vec2 curUV = imgUV;
            if (u_mode == 1) {
                float zoomAmount = clamp(u_imageElapsed / 30.0, 0.0, 0.1);
                float scale = 1.0 + zoomAmount;
                curUV = (imgUV - 0.5) / scale + 0.5;
            }

            vec4 current = sampleBounded(u_current, curUV);
            vec4 next = sampleBounded(u_next, imgUV);

            vec4 result;
            if (u_mode == 0 || u_mode == 1) {
                // Crossfade (mode 0) and Ken Burns crossfade (mode 1)
                result = mix(current, next, u_progress);
            } else if (u_mode == 2) {
                // Beat-cut (hard cut at progress >= 1.0)
                result = u_progress >= 1.0 ? next : current;
            } else if (u_mode == 3) {
                // Slide: current scrolls left, next scrolls in from right
                vec2 curSlideUV = vec2(imgUV.x + u_progress, imgUV.y);
                vec2 nxtSlideUV = vec2(imgUV.x + u_progress - 1.0, imgUV.y);
                vec4 curSlide = sampleBounded(u_current, curSlideUV);
                vec4 nxtSlide = sampleBounded(u_next, nxtSlideUV);
                result = (imgUV.x < (1.0 - u_progress)) ? curSlide : nxtSlide;
            } else {
                result = current;
            }

            // Apply audio reactive effects if enabled
            if (u_audioReactive == 1) {
                result.rgb *= mix(1.0, 1.03, u_energy);
                vec3 hsv = rgb2hsv(result.rgb);
                hsv.y = mix(hsv.y, hsv.y + 0.15, u_energy);
                result.rgb = hsv2rgb(hsv);
            }

            // Composite attribution overlay anchored at bottom-left of the viewport,
            // sampling only inside the overlay's actual pixel rect so we don't
            // smear the edge texel across the screen via CLAMP_TO_EDGE.
            if (u_attributionAlpha > 0.0 && u_attributionSize.x > 0.0 && u_attributionSize.y > 0.0) {
                // gl_FragCoord origin is bottom-left in GL; place the overlay
                // with an 8px margin from the bottom-left corner.
                vec2 margin = vec2(8.0, 8.0);
                vec2 pxFromCorner = gl_FragCoord.xy - margin;
                if (pxFromCorner.x >= 0.0 && pxFromCorner.x < u_attributionSize.x &&
                    pxFromCorner.y >= 0.0 && pxFromCorner.y < u_attributionSize.y) {
                    // Texture was uploaded with top-left origin; flip Y for sampling.
                    vec2 attrUV = vec2(pxFromCorner.x / u_attributionSize.x,
                                       1.0 - pxFromCorner.y / u_attributionSize.y);
                    vec4 attrSample = texture(u_attribution, attrUV);
                    result.rgb = mix(result.rgb, attrSample.rgb, attrSample.a * u_attributionAlpha);
                }
            }

            frag = result;
        }
        """

        guard let prog = compileProgram(vertex: vertexSrc, fragment: fragmentSrc) else {
            return false
        }
        program = prog
        currentTexUniform = glGetUniformLocation(program, "u_current")
        nextTexUniform = glGetUniformLocation(program, "u_next")
        progressUniform = glGetUniformLocation(program, "u_progress")
        modeUniform = glGetUniformLocation(program, "u_mode")
        imageAspectUniform = glGetUniformLocation(program, "u_imageAspect")
        viewportAspectUniform = glGetUniformLocation(program, "u_viewportAspect")
        aspectModeUniform = glGetUniformLocation(program, "u_aspectMode")
        energyUniform = glGetUniformLocation(program, "u_energy")
        audioReactiveUniform = glGetUniformLocation(program, "u_audioReactive")
        attributionTexUniform = glGetUniformLocation(program, "u_attribution")
        attributionAlphaUniform = glGetUniformLocation(program, "u_attributionAlpha")
        attributionSizeUniform = glGetUniformLocation(program, "u_attributionSize")
        imageStartTimeUniform = glGetUniformLocation(program, "u_imageElapsed")

        // Setup VAO/VBO (fullscreen quad)
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

        // Create textures (allocate on first upload, not here)
        glGenTextures(1, &currentTexture)
        glGenTextures(1, &nextTexture)
        glGenTextures(1, &placeholderTexture)

        for tex in [currentTexture, nextTexture, placeholderTexture] {
            glBindTexture(GLenum(GL_TEXTURE_2D), tex)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        }
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)

        // Create placeholder texture
        createPlaceholderTexture()

        return true
    }

    private func destroyGLResources() {
        if vbo != 0 { glDeleteBuffers(1, &vbo); vbo = 0 }
        if vao != 0 { glDeleteVertexArrays(1, &vao); vao = 0 }
        if currentTexture != 0 { glDeleteTextures(1, &currentTexture); currentTexture = 0 }
        if nextTexture != 0 { glDeleteTextures(1, &nextTexture); nextTexture = 0 }
        if attributionTexture != 0 { glDeleteTextures(1, &attributionTexture); attributionTexture = 0 }
        if placeholderTexture != 0 { glDeleteTextures(1, &placeholderTexture); placeholderTexture = 0 }
        if program != 0 { glDeleteProgram(program); program = 0 }
    }

    private func createPlaceholderTexture() {
        let placeholder = NSImage(size: NSMakeSize(256, 256))
        placeholder.lockFocus()
        NSColor.darkGray.setFill()
        NSBezierPath(rect: NSMakeRect(0, 0, 256, 256)).fill()
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.lightGray
        ]
        let str = NSAttributedString(string: "Met Museum\nunavailable", attributes: attr)
        str.draw(at: NSMakePoint(30, 110))
        placeholder.unlockFocus()

        if let tiffData = placeholder.tiffRepresentation,
           let cgImage = NSBitmapImageRep(data: tiffData)?.cgImage {
            uploadCGImage(cgImage, to: placeholderTexture, width: 256, height: 256)
        }
    }

    private func queueAttributionTexture(from attribution: String) {
        // Render attribution text to a CGImage; the actual GL upload is deferred
        // to renderFrame so it runs on the GL thread with the active context.
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: attribution, attributes: attr)
        let size = attrString.size()
        let padding: CGFloat = 8
        let imgSize = NSMakeSize(size.width + padding * 2, size.height + padding * 2)

        let image = NSImage(size: imgSize)
        image.lockFocus()
        NSColor(red: 0, green: 0, blue: 0, alpha: 0.6).setFill()
        NSBezierPath(rect: NSMakeRect(0, 0, imgSize.width, imgSize.height)).fill()
        NSColor(red: 0, green: 0, blue: 0, alpha: 0.3).set()
        attrString.draw(at: NSMakePoint(padding + 1, padding - 1))
        attrString.draw(at: NSMakePoint(padding, padding))
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let cgImage = NSBitmapImageRep(data: tiffData)?.cgImage else {
            return
        }

        coreLock.lock()
        pendingAttributionUpload = (cgImage, Int(imgSize.width), Int(imgSize.height))
        coreLock.unlock()
    }

    private func uploadImage(data: Data, to textureID: GLuint) {
        guard textureID != 0, let image = NSImage(data: data) else { return }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            NSLog("MetMuseumEngine: Failed to get CGImage from NSImage")
            return
        }

        uploadCGImage(cgImage, to: textureID, width: Int(image.size.width), height: Int(image.size.height), updateImageDims: true)
    }

    private func uploadCGImage(_ cgImage: CGImage, to textureID: GLuint, width: Int, height: Int, updateImageDims: Bool = false) {
        let w = cgImage.width
        let h = cgImage.height

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            NSLog("MetMuseumEngine: Failed to create CGContext for image upload")
            return
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let pixelData = ctx.data else {
            NSLog("MetMuseumEngine: Failed to get pixel data from context")
            return
        }

        glBindTexture(GLenum(GL_TEXTURE_2D), textureID)
        glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
        // Allocate texture with actual image dimensions (not viewport)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8,
                     GLsizei(w), GLsizei(h), 0,
                     GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), pixelData)
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)

        // Only update artwork aspect ratio for the artwork texture upload.
        // Attribution and placeholder uploads must not clobber these or the
        // shader stretches the artwork to the overlay's dimensions.
        if updateImageDims {
            coreLock.lock()
            currentImageWidth = w
            currentImageHeight = h
            imageStartTime = Date()
            coreLock.unlock()
        }
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
            let msg = String(cString: log)
            NSLog("MetMuseumEngine: shader compile failed: %@", msg)
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
            let msg = String(cString: log)
            NSLog("MetMuseumEngine: program link failed: %@", msg)
            glDeleteProgram(prog)
            return nil
        }
        return prog
    }
}

// MARK: - Error Types

enum MetMuseumError: LocalizedError {
    case noArtworkFound
    case noImageURL

    var errorDescription: String? {
        switch self {
        case .noArtworkFound:
            return "No public domain artwork found in department"
        case .noImageURL:
            return "Artwork has no primary image URL"
        }
    }
}

// MARK: - Persistence (UserDefaults keys)

extension MetMuseumEngine {
    enum DefaultsKey {
        static let departmentID = "metMuseumDepartmentID"
        static let intervalSeconds = "metMuseumIntervalSeconds"
        static let transitionMode = "metMuseumTransitionMode"
        static let transitionDuration = "metMuseumTransitionDuration"
        static let audioReactive = "metMuseumAudioReactive"
        static let beatTriggered = "metMuseumBeatTriggered"
        static let aspectMode = "metMuseumAspectMode"
        static let showAttribution = "metMuseumShowAttribution"
    }
}

// MARK: - Transition Mode Extension

extension MetMuseumEngine.TransitionMode {
    var modeValue: Int {
        switch self {
        case .crossfade: return 0
        case .kenBurns: return 1
        case .beatCut: return 2
        case .slide: return 3
        }
    }
}

// MARK: - Aspect Mode Extension

extension MetMuseumEngine.AspectMode {
    var shaderValue: Int {
        switch self {
        case .fit: return 0
        case .fill: return 1
        case .stretch: return 2
        }
    }
}
