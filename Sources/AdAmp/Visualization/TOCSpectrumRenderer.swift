import Foundation
import OpenGL.GL3
import Accelerate

/// TOC Spectrum visualization renderer
///
/// Renders a classic spectrum analyzer visualization with vertical bars
/// that respond to audio frequency data. Inspired by early 2000s analyzers
/// and the iZotope Ozone aesthetic.
class TOCSpectrumRenderer: VisualizationEngine {

    // MARK: - VisualizationEngine Protocol

    private(set) var isAvailable: Bool = false

    var displayName: String {
        return "TOC Spectrum"
    }

    // MARK: - Types

    /// Color scheme for the visualization
    enum ColorScheme: String, CaseIterable {
        case classic = "Classic"
        case modern = "Modern"
        case ozone = "Ozone"

        var glValue: Int32 {
            switch self {
            case .classic: return 0
            case .modern: return 1
            case .ozone: return 2
            }
        }
    }

    /// Scale mode for frequency mapping
    enum ScaleMode: String {
        case linear = "Linear"
        case logarithmic = "Logarithmic"
    }

    /// Visualization mode - different 3D rendering styles
    enum VisualizationMode: String, CaseIterable {
        case circularLayers = "Circular Layers"
        case gridCube = "3D Grid Cube"
        case sphere = "Sphere"
        case waveSurface = "Wave Surface"
        case tunnel = "Tunnel"
        case dnaHelix = "DNA Helix"
    }

    // MARK: - Properties

    private var viewportWidth: Int = 0
    private var viewportHeight: Int = 0

    // Spectrum data
    private var spectrumBands: [Float] = []
    private var smoothedSpectrum: [Float] = []
    private let dataLock = NSLock()

    // OpenGL resources
    private var shaderProgram: GLuint = 0
    private var reflectionShaderProgram: GLuint = 0
    private var vao: GLuint = 0
    private var vbo: GLuint = 0
    private var ebo: GLuint = 0

    // Shader uniforms
    private var projectionUniform: GLint = -1
    private var viewUniform: GLint = -1
    private var modelUniform: GLint = -1
    private var maxHeightUniform: GLint = -1
    private var colorSchemeUniform: GLint = -1
    private var barCountUniform: GLint = -1
    private var lightDirUniform: GLint = -1
    private var cameraPosUniform: GLint = -1

    // Reflection shader uniforms
    private var reflectionProjectionUniform: GLint = -1
    private var reflectionMaxHeightUniform: GLint = -1
    private var reflectionColorSchemeUniform: GLint = -1
    private var reflectionBarCountUniform: GLint = -1

    // Settings (loaded from UserDefaults)
    private var colorScheme: ColorScheme = .classic
    private var barCount: Int = 128
    private var scaleMode: ScaleMode = .logarithmic
    private var smoothingFactor: Float = 0.75
    private var reflectionEnabled: Bool = false
    private var wireframeMode: Bool = false
    private var visualizationMode: VisualizationMode = .circularLayers

    // Settings change observer
    private var settingsObserver: NSObjectProtocol?

    // 3D Camera and animation
    private var cameraAngle: Float = 0.0
    private var cameraDistance: Float = 5.5  // Pull back to see full 3D structure
    private var cameraHeight: Float = 2.0   // Higher viewpoint
    private var animationTime: Float = 0.0  // Global time for effects

    // MARK: - Initialization

    required init(width: Int, height: Int) {
        viewportWidth = width
        viewportHeight = height

        // Load settings from UserDefaults
        loadSettings()

        // Initialize spectrum arrays
        spectrumBands = Array(repeating: 0, count: barCount)
        smoothedSpectrum = Array(repeating: 0, count: barCount)

        // Set up OpenGL resources
        setupOpenGL()

        // Subscribe to settings changes
        settingsObserver = NotificationCenter.default.addObserver(
            forName: TOCSpectrumSettings.settingsChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSettingsChanged()
        }

        NSLog("TOCSpectrumRenderer: Initialized with %dx%d viewport, %d bars", width, height, barCount)
    }

    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        cleanup()
    }

    // MARK: - Settings

    private func loadSettings() {
        let settings = TOCSpectrumSettings.shared
        colorScheme = settings.colorScheme
        barCount = settings.barCount
        scaleMode = settings.scaleMode
        smoothingFactor = settings.smoothing
        reflectionEnabled = settings.reflectionEnabled
        wireframeMode = settings.wireframeMode
        visualizationMode = settings.visualizationMode

        NSLog("TOCSpectrumRenderer: Loaded settings - scheme: %@, bars: %d, mode: %@, reflection: %d, wireframe: %d",
              colorScheme.rawValue, barCount, visualizationMode.rawValue, reflectionEnabled ? 1 : 0, wireframeMode ? 1 : 0)
    }

    /// Handle settings changed notification
    private func handleSettingsChanged() {
        NSLog("TOCSpectrumRenderer: Settings changed, reloading...")
        let settings = TOCSpectrumSettings.shared

        // Update settings that can change without recreation
        colorScheme = settings.colorScheme
        scaleMode = settings.scaleMode
        smoothingFactor = settings.smoothing
        reflectionEnabled = settings.reflectionEnabled
        wireframeMode = settings.wireframeMode
        visualizationMode = settings.visualizationMode

        // Bar count change requires array reallocation
        let newBarCount = settings.barCount
        if newBarCount != barCount {
            barCount = newBarCount
            spectrumBands = Array(repeating: 0, count: barCount)
            smoothedSpectrum = Array(repeating: 0, count: barCount)
            NSLog("TOCSpectrumRenderer: Bar count changed to %d", barCount)
        }

        NSLog("TOCSpectrumRenderer: Settings updated - scheme: %@, mode: %@, reflection: %d, wireframe: %d",
              colorScheme.rawValue, visualizationMode.rawValue, reflectionEnabled ? 1 : 0, wireframeMode ? 1 : 0)
    }

    // MARK: - OpenGL Setup

    private func setupOpenGL() {
        // Compile shaders
        guard compileShaders() else {
            NSLog("TOCSpectrumRenderer: Shader compilation failed")
            isAvailable = false
            return
        }

        // Create vertex array object
        glGenVertexArrays(1, &vao)
        glBindVertexArray(vao)

        // Create vertex buffer
        glGenBuffers(1, &vbo)
        glGenBuffers(1, &ebo)

        // Set up vertex attributes
        setupVertexAttributes()

        glBindVertexArray(0)

        isAvailable = true
        NSLog("TOCSpectrumRenderer: OpenGL setup complete")
    }

    private func compileShaders() -> Bool {
        // Compile main shader program
        shaderProgram = createShaderProgram(
            vertexSource: TOCSpectrumShaders.vertexShader,
            fragmentSource: TOCSpectrumShaders.fragmentShader
        )

        guard shaderProgram != 0 else {
            NSLog("TOCSpectrumRenderer: Failed to create main shader program")
            return false
        }

        // Get uniform locations for main shader
        glUseProgram(shaderProgram)
        projectionUniform = glGetUniformLocation(shaderProgram, "projection")
        viewUniform = glGetUniformLocation(shaderProgram, "view")
        modelUniform = glGetUniformLocation(shaderProgram, "model")
        maxHeightUniform = glGetUniformLocation(shaderProgram, "maxHeight")
        colorSchemeUniform = glGetUniformLocation(shaderProgram, "colorScheme")
        barCountUniform = glGetUniformLocation(shaderProgram, "barCount")
        lightDirUniform = glGetUniformLocation(shaderProgram, "lightDir")
        cameraPosUniform = glGetUniformLocation(shaderProgram, "cameraPos")

        // Compile reflection shader program
        reflectionShaderProgram = createShaderProgram(
            vertexSource: TOCSpectrumShaders.reflectionVertexShader,
            fragmentSource: TOCSpectrumShaders.reflectionFragmentShader
        )

        if reflectionShaderProgram == 0 {
            NSLog("TOCSpectrumRenderer: Failed to create reflection shader program")
            // Non-fatal - reflection is optional
        }

        // Get uniform locations for reflection shader
        if reflectionShaderProgram != 0 {
            glUseProgram(reflectionShaderProgram)
            reflectionProjectionUniform = glGetUniformLocation(reflectionShaderProgram, "projection")
            reflectionMaxHeightUniform = glGetUniformLocation(reflectionShaderProgram, "maxHeight")
            reflectionColorSchemeUniform = glGetUniformLocation(reflectionShaderProgram, "colorScheme")
            reflectionBarCountUniform = glGetUniformLocation(reflectionShaderProgram, "barCount")
        }

        glUseProgram(0)
        return true
    }

    private func createShaderProgram(vertexSource: String, fragmentSource: String) -> GLuint {
        // Compile vertex shader
        let vertexShader = compileShader(source: vertexSource, type: GLenum(GL_VERTEX_SHADER))
        guard vertexShader != 0 else { return 0 }

        // Compile fragment shader
        let fragmentShader = compileShader(source: fragmentSource, type: GLenum(GL_FRAGMENT_SHADER))
        guard fragmentShader != 0 else {
            glDeleteShader(vertexShader)
            return 0
        }

        // Link program
        let program = glCreateProgram()
        glAttachShader(program, vertexShader)
        glAttachShader(program, fragmentShader)
        glLinkProgram(program)

        // Check link status
        var linkStatus: GLint = 0
        glGetProgramiv(program, GLenum(GL_LINK_STATUS), &linkStatus)
        if linkStatus == GL_FALSE {
            var logLength: GLint = 0
            glGetProgramiv(program, GLenum(GL_INFO_LOG_LENGTH), &logLength)
            if logLength > 0 {
                var log = [GLchar](repeating: 0, count: Int(logLength))
                glGetProgramInfoLog(program, logLength, nil, &log)
                NSLog("TOCSpectrumRenderer: Shader link error: %s", String(cString: log))
            }
            glDeleteProgram(program)
            glDeleteShader(vertexShader)
            glDeleteShader(fragmentShader)
            return 0
        }

        // Clean up shaders (no longer needed after linking)
        glDeleteShader(vertexShader)
        glDeleteShader(fragmentShader)

        return program
    }

    private func compileShader(source: String, type: GLenum) -> GLuint {
        let shader = glCreateShader(type)
        var sourcePtr: UnsafePointer<GLchar>? = (source as NSString).utf8String
        glShaderSource(shader, 1, &sourcePtr, nil)
        glCompileShader(shader)

        // Check compile status
        var compileStatus: GLint = 0
        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &compileStatus)
        if compileStatus == GL_FALSE {
            var logLength: GLint = 0
            glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &logLength)
            if logLength > 0 {
                var log = [GLchar](repeating: 0, count: Int(logLength))
                glGetShaderInfoLog(shader, logLength, nil, &log)
                let typeName = type == GLenum(GL_VERTEX_SHADER) ? "vertex" : "fragment"
                NSLog("TOCSpectrumRenderer: %s shader compile error: %s", typeName, String(cString: log))
            }
            glDeleteShader(shader)
            return 0
        }

        return shader
    }

    private func setupVertexAttributes() {
        // Vertex layout: position(3) + normal(3) + barIndex(1) + heightMult(1) = 8 floats per vertex
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), ebo)

        let stride = GLsizei(8 * MemoryLayout<GLfloat>.size)

        // Position attribute (vec3)
        let positionAttrib = GLuint(glGetAttribLocation(shaderProgram, "position"))
        glEnableVertexAttribArray(positionAttrib)
        glVertexAttribPointer(positionAttrib, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE),
                             stride, nil)

        // Normal attribute (vec3)
        let normalAttrib = GLuint(glGetAttribLocation(shaderProgram, "normal"))
        glEnableVertexAttribArray(normalAttrib)
        glVertexAttribPointer(normalAttrib, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE),
                             stride, UnsafeRawPointer(bitPattern: 3 * MemoryLayout<GLfloat>.size))

        // Bar index attribute (float)
        let barIndexAttrib = GLuint(glGetAttribLocation(shaderProgram, "barIndex"))
        glEnableVertexAttribArray(barIndexAttrib)
        glVertexAttribPointer(barIndexAttrib, 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE),
                             stride, UnsafeRawPointer(bitPattern: 6 * MemoryLayout<GLfloat>.size))

        // Height multiplier attribute (float)
        let heightMultAttrib = GLuint(glGetAttribLocation(shaderProgram, "heightMult"))
        glEnableVertexAttribArray(heightMultAttrib)
        glVertexAttribPointer(heightMultAttrib, 1, GLenum(GL_FLOAT), GLboolean(GL_FALSE),
                             stride, UnsafeRawPointer(bitPattern: 7 * MemoryLayout<GLfloat>.size))
    }

    // MARK: - VisualizationEngine Protocol Methods

    func setViewportSize(width: Int, height: Int) {
        guard width != viewportWidth || height != viewportHeight else { return }
        viewportWidth = width
        viewportHeight = height
    }

    func addPCMMono(_ samples: [Float]) {
        // We don't use PCM directly - we'll get spectrum data from the data source
        // But we need to implement this for protocol conformance
    }

    func renderFrame() {
        guard isAvailable else { return }

        // Set viewport
        glViewport(0, 0, GLsizei(viewportWidth), GLsizei(viewportHeight))

        // Clear background and depth buffer
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))

        // Enable depth testing for 3D
        glEnable(GLenum(GL_DEPTH_TEST))
        glDepthFunc(GLenum(GL_LESS))

        // Get spectrum data snapshot
        dataLock.lock()
        let spectrum = smoothedSpectrum
        dataLock.unlock()

        // Skip rendering if no data
        guard !spectrum.isEmpty else { return }

        // Update animation time
        animationTime += 1.0 / 60.0  // Assume 60fps

        // Calculate average spectrum energy for dynamic effects
        let avgEnergy = spectrum.reduce(0, +) / Float(spectrum.count)

        // Animate camera with dynamic movement
        cameraAngle += 0.3 + avgEnergy * 0.5  // Faster rotation with more audio
        if cameraAngle >= 360.0 {
            cameraAngle -= 360.0
        }

        // Calculate camera position with subtle vertical bob
        let angleRad = cameraAngle * Float.pi / 180.0
        let heightBob = sin(animationTime * 0.5) * 0.15 * (1.0 + avgEnergy)  // Bob up/down based on energy
        let distancePulse = cameraDistance + cos(animationTime * 0.8) * 0.2 * avgEnergy  // Zoom in/out with energy

        let camX = sin(angleRad) * distancePulse
        let camZ = cos(angleRad) * distancePulse
        let camY = cameraHeight + heightBob

        // Create perspective projection matrix
        let aspect = Float(viewportWidth) / Float(max(viewportHeight, 1))
        let projection = createPerspectiveMatrix(fov: 45.0, aspect: aspect, near: 0.1, far: 100.0)

        // Create view matrix (look at center from rotating camera)
        let view = createViewMatrix(eye: [camX, camY, camZ], center: [0, 0, 0], up: [0, 1, 0])

        // Create model matrix (identity for now, bars positioned in world space)
        let model = createIdentityMatrix()

        // Light direction (from above and front-right)
        let lightDir: [Float] = [0.5, 1.0, 0.5]

        // Render main spectrum
        renderSpectrum(spectrum: spectrum, projection: projection, view: view, model: model,
                       lightDir: lightDir, cameraPos: [camX, camY, camZ],
                       avgEnergy: avgEnergy, isReflection: false)

        // Render reflection if enabled
        if reflectionEnabled && reflectionShaderProgram != 0 {
            // Enable blending for semi-transparent reflection
            glEnable(GLenum(GL_BLEND))
            glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA))

            // Flip model matrix for reflection
            var reflectionModel = model
            reflectionModel[5] = -1.0  // Flip Y scale

            renderSpectrum(spectrum: spectrum, projection: projection, view: view, model: reflectionModel,
                          lightDir: lightDir, cameraPos: [camX, camY, camZ],
                          avgEnergy: avgEnergy, isReflection: true)

            glDisable(GLenum(GL_BLEND))
        }

        glDisable(GLenum(GL_DEPTH_TEST))
    }

    private func renderSpectrum(spectrum: [Float], projection: [GLfloat], view: [GLfloat], model: [GLfloat],
                                lightDir: [Float], cameraPos: [Float], avgEnergy: Float, isReflection: Bool) {
        let program = isReflection ? reflectionShaderProgram : shaderProgram
        guard program != 0 else { return }

        glUseProgram(program)

        // Set matrix uniforms
        glUniformMatrix4fv(projectionUniform, 1, GLboolean(GL_FALSE), projection)
        glUniformMatrix4fv(viewUniform, 1, GLboolean(GL_FALSE), view)
        glUniformMatrix4fv(modelUniform, 1, GLboolean(GL_FALSE), model)

        // Set other uniforms
        glUniform1f(maxHeightUniform, 1.5)  // Max bar height in world space
        glUniform1i(colorSchemeUniform, colorScheme.glValue)
        glUniform1i(barCountUniform, GLint(barCount))
        glUniform3f(lightDirUniform, lightDir[0], lightDir[1], lightDir[2])
        glUniform3f(cameraPosUniform, cameraPos[0], cameraPos[1], cameraPos[2])

        // Generate geometry based on visualization mode
        var vertices: [GLfloat] = []
        var indices: [GLuint] = []

        switch visualizationMode {
        case .circularLayers:
            generateCircularLayersGeometry(spectrum: spectrum, avgEnergy: avgEnergy, vertices: &vertices, indices: &indices)
        case .gridCube:
            generate3DGridCubeGeometry(spectrum: spectrum, avgEnergy: avgEnergy, vertices: &vertices, indices: &indices)
        case .sphere:
            generateSphereGeometry(spectrum: spectrum, avgEnergy: avgEnergy, vertices: &vertices, indices: &indices)
        case .waveSurface:
            generateWaveSurfaceGeometry(spectrum: spectrum, avgEnergy: avgEnergy, vertices: &vertices, indices: &indices)
        case .tunnel:
            generateTunnelGeometry(spectrum: spectrum, avgEnergy: avgEnergy, vertices: &vertices, indices: &indices)
        case .dnaHelix:
            generateDNAHelixGeometry(spectrum: spectrum, avgEnergy: avgEnergy, vertices: &vertices, indices: &indices)
        }

        // Upload geometry
        glBindVertexArray(vao)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        glBufferData(GLenum(GL_ARRAY_BUFFER),
                    vertices.count * MemoryLayout<GLfloat>.size,
                    vertices, GLenum(GL_DYNAMIC_DRAW))

        glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), ebo)
        glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER),
                    indices.count * MemoryLayout<GLuint>.size,
                    indices, GLenum(GL_DYNAMIC_DRAW))

        // Draw
        if wireframeMode {
            glPolygonMode(GLenum(GL_FRONT_AND_BACK), GLenum(GL_LINE))
        }

        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(indices.count), GLenum(GL_UNSIGNED_INT), nil)

        if wireframeMode {
            glPolygonMode(GLenum(GL_FRONT_AND_BACK), GLenum(GL_FILL))
        }

        glBindVertexArray(0)
        glUseProgram(0)
    }

    // MARK: - Geometry Generation Functions

    /// Generate circular layers geometry (original mode)
    private func generateCircularLayersGeometry(spectrum: [Float], avgEnergy: Float,
                                                vertices: inout [GLfloat], indices: inout [GLuint]) {
        let layers = 3
        let barsPerLayer = barCount / layers
        let barBaseSize: Float = 0.04

        for layer in 0..<layers {
            let layerRadius: Float = 1.8 + Float(layer) * 0.6
            let layerYOffset: Float = Float(layer) * 0.3 - 0.3

            for i in 0..<barsPerLayer {
                let spectrumIndex = layer * barsPerLayer + i
                guard spectrumIndex < spectrum.count else { continue }

                let height = spectrum[spectrumIndex] * 1.5
                let angle = Float(i) / Float(barsPerLayer) * Float.pi * 2.0
                let rotatedAngle = angle + animationTime * 0.3 * (1.0 + Float(layer) * 0.5)
                let wave = sin(animationTime * 2.0 + angle * 3.0 + Float(layer) * Float.pi) * 0.15 * avgEnergy

                let x = cos(rotatedAngle) * (layerRadius + wave)
                let z = sin(rotatedAngle) * (layerRadius + wave)
                let y = layerYOffset + sin(animationTime * 1.5 + Float(layer)) * 0.1

                let baseVertex = GLuint(vertices.count / 8)
                addRotatedCubeVertices(to: &vertices, x: x, y: y, z: z,
                                     width: barBaseSize, height: height, depth: barBaseSize * 1.5,
                                     rotationAngle: rotatedAngle, barIndex: Float(spectrumIndex))
                addCubeIndices(to: &indices, baseVertex: baseVertex)
            }
        }

        // Central column
        let centralBars = min(20, barCount / 4)
        for i in 0..<centralBars {
            let spectrumIndex = i * (barCount / centralBars)
            guard spectrumIndex < spectrum.count else { continue }

            let height = spectrum[spectrumIndex] * 2.0
            let angle = Float(i) / Float(centralBars) * Float.pi * 2.0
            let radius: Float = 0.5

            let x = cos(angle + animationTime * 0.5) * radius
            let z = sin(angle + animationTime * 0.5) * radius

            let baseVertex = GLuint(vertices.count / 8)
            addCubeVertices(to: &vertices, x: x, y: 0, z: z,
                          width: barBaseSize * 1.2, height: height, depth: barBaseSize * 1.2,
                          barIndex: Float(spectrumIndex))
            addCubeIndices(to: &indices, baseVertex: baseVertex)
        }
    }

    /// Generate 3D grid cube geometry - bars arranged in a volumetric cube
    private func generate3DGridCubeGeometry(spectrum: [Float], avgEnergy: Float,
                                           vertices: inout [GLfloat], indices: inout [GLuint]) {
        // Create a 3D grid of bars filling a cube volume
        let gridSize = Int(ceil(pow(Double(barCount), 1.0/3.0)))  // Cube root for 3D grid
        let spacing: Float = 0.3
        let cubeSize: Float = Float(gridSize) * spacing
        let barBaseSize: Float = 0.08

        var spectrumIndex = 0
        for x in 0..<gridSize {
            for y in 0..<gridSize {
                for z in 0..<gridSize {
                    guard spectrumIndex < spectrum.count else { return }

                    let height = spectrum[spectrumIndex] * 1.5

                    // Position in grid (centered at origin)
                    let px = Float(x) * spacing - cubeSize / 2
                    let py = Float(y) * spacing - cubeSize / 2
                    let pz = Float(z) * spacing - cubeSize / 2

                    // Wave deformation propagating through the cube
                    let wave = sin(animationTime * 2.0 + Float(x) * 0.5 + Float(y) * 0.3 + Float(z) * 0.4) * 0.2 * avgEnergy

                    let baseVertex = GLuint(vertices.count / 8)
                    addCubeVertices(to: &vertices, x: px + wave, y: py + wave, z: pz + wave,
                                  width: barBaseSize, height: height * 0.5, depth: barBaseSize,
                                  barIndex: Float(spectrumIndex))
                    addCubeIndices(to: &indices, baseVertex: baseVertex)

                    spectrumIndex += 1
                }
            }
        }
    }

    /// Generate sphere geometry - bars radiating outward from center
    private func generateSphereGeometry(spectrum: [Float], avgEnergy: Float,
                                       vertices: inout [GLfloat], indices: inout [GLuint]) {
        // Distribute bars on a sphere using Fibonacci sphere algorithm
        let phi: Float = (1.0 + sqrt(5.0)) / 2.0  // Golden ratio
        let barBaseSize: Float = 0.06

        for i in 0..<barCount {
            guard i < spectrum.count else { break }

            let height = spectrum[i] * 2.0

            // Fibonacci sphere distribution
            let y = 1.0 - (Float(i) / Float(barCount - 1)) * 2.0  // -1 to 1
            let radius = sqrt(1.0 - y * y)
            let theta = Float(i) * 2.0 * Float.pi / phi

            let baseRadius: Float = 2.0
            let radiusPulse = baseRadius + sin(animationTime * 1.5 + Float(i) * 0.1) * 0.3 * avgEnergy

            let x = cos(theta) * radius * radiusPulse
            let z = sin(theta) * radius * radiusPulse
            let py = y * radiusPulse

            // Calculate rotation to face outward from center
            let angle = atan2(z, x)

            let baseVertex = GLuint(vertices.count / 8)
            addRotatedCubeVertices(to: &vertices, x: x, y: py, z: z,
                                 width: barBaseSize, height: height, depth: barBaseSize,
                                 rotationAngle: angle, barIndex: Float(i))
            addCubeIndices(to: &indices, baseVertex: baseVertex)
        }
    }

    /// Generate wave surface geometry - deforming mesh like water waves
    private func generateWaveSurfaceGeometry(spectrum: [Float], avgEnergy: Float,
                                            vertices: inout [GLfloat], indices: inout [GLuint]) {
        // Create a grid surface that deforms based on spectrum
        let gridX = Int(sqrt(Double(barCount)))
        let gridZ = gridX
        let spacing: Float = 0.15
        let surfaceSize: Float = Float(gridX) * spacing
        let barBaseSize: Float = 0.05

        for x in 0..<gridX {
            for z in 0..<gridZ {
                let spectrumIndex = x * gridZ + z
                guard spectrumIndex < spectrum.count else { continue }

                let height = spectrum[spectrumIndex] * 2.0

                // Position on surface grid
                let px = Float(x) * spacing - surfaceSize / 2
                let pz = Float(z) * spacing - surfaceSize / 2

                // Multiple overlapping sine waves for complex surface deformation
                let wave1 = sin(animationTime * 1.5 + Float(x) * 0.4) * 0.3
                let wave2 = cos(animationTime * 2.0 + Float(z) * 0.3) * 0.25
                let wave3 = sin(animationTime * 1.0 + Float(x + z) * 0.2) * 0.2
                let py = (wave1 + wave2 + wave3) * avgEnergy

                let baseVertex = GLuint(vertices.count / 8)
                addCubeVertices(to: &vertices, x: px, y: py, z: pz,
                              width: barBaseSize, height: height, depth: barBaseSize,
                              barIndex: Float(spectrumIndex))
                addCubeIndices(to: &indices, baseVertex: baseVertex)
            }
        }
    }

    /// Generate tunnel geometry - bars spiraling into a tunnel effect
    private func generateTunnelGeometry(spectrum: [Float], avgEnergy: Float,
                                       vertices: inout [GLfloat], indices: inout [GLuint]) {
        // Create rings of bars extending into depth (tunnel effect)
        let rings = 15
        let barsPerRing = barCount / rings
        let barBaseSize: Float = 0.06

        for ring in 0..<rings {
            let depth = Float(ring) * 0.4 - 3.0  // Tunnel extends from -3 to 3
            let radiusBase: Float = 1.5 + Float(ring) * 0.1  // Tunnel gets wider

            for i in 0..<barsPerRing {
                let spectrumIndex = ring * barsPerRing + i
                guard spectrumIndex < spectrum.count else { continue }

                let height = spectrum[spectrumIndex] * 1.5
                let angle = Float(i) / Float(barsPerRing) * Float.pi * 2.0

                // Spiral rotation along the tunnel
                let spiralRotation = Float(ring) * 0.3 + animationTime * 0.5
                let rotatedAngle = angle + spiralRotation

                // Pulsing tunnel walls
                let pulse = sin(animationTime * 2.0 + Float(ring) * 0.5) * 0.2 * avgEnergy
                let radius = radiusBase + pulse

                let x = cos(rotatedAngle) * radius
                let y = sin(rotatedAngle) * radius

                let baseVertex = GLuint(vertices.count / 8)
                addRotatedCubeVertices(to: &vertices, x: x, y: y, z: depth,
                                     width: barBaseSize, height: height, depth: barBaseSize,
                                     rotationAngle: rotatedAngle, barIndex: Float(spectrumIndex))
                addCubeIndices(to: &indices, baseVertex: baseVertex)
            }
        }
    }

    /// Generate DNA helix geometry - double helix structure
    private func generateDNAHelixGeometry(spectrum: [Float], avgEnergy: Float,
                                         vertices: inout [GLfloat], indices: inout [GLuint]) {
        // Create two intertwined helixes
        let barsPerHelix = barCount / 2
        let helixHeight: Float = 4.0
        let helixRadius: Float = 1.2
        let barBaseSize: Float = 0.06

        for i in 0..<barsPerHelix {
            let t = Float(i) / Float(barsPerHelix - 1)  // 0 to 1
            let py = t * helixHeight - helixHeight / 2  // -2 to 2

            // First helix
            let spectrumIndex1 = i
            if spectrumIndex1 < spectrum.count {
                let angle1 = t * Float.pi * 4.0 + animationTime * 0.5  // 2 full rotations
                let radius1 = helixRadius + sin(animationTime * 2.0 + t * Float.pi * 2.0) * 0.2 * avgEnergy
                let height1 = spectrum[spectrumIndex1] * 1.5

                let x1 = cos(angle1) * radius1
                let z1 = sin(angle1) * radius1

                let baseVertex1 = GLuint(vertices.count / 8)
                addRotatedCubeVertices(to: &vertices, x: x1, y: py, z: z1,
                                     width: barBaseSize, height: height1 * 0.3, depth: barBaseSize,
                                     rotationAngle: angle1, barIndex: Float(spectrumIndex1))
                addCubeIndices(to: &indices, baseVertex: baseVertex1)
            }

            // Second helix (180 degrees offset)
            let spectrumIndex2 = i + barsPerHelix
            if spectrumIndex2 < spectrum.count {
                let angle2 = t * Float.pi * 4.0 + Float.pi + animationTime * 0.5  // Offset by pi
                let radius2 = helixRadius + cos(animationTime * 2.0 + t * Float.pi * 2.0) * 0.2 * avgEnergy
                let height2 = spectrum[spectrumIndex2] * 1.5

                let x2 = cos(angle2) * radius2
                let z2 = sin(angle2) * radius2

                let baseVertex2 = GLuint(vertices.count / 8)
                addRotatedCubeVertices(to: &vertices, x: x2, y: py, z: z2,
                                     width: barBaseSize, height: height2 * 0.3, depth: barBaseSize,
                                     rotationAngle: angle2, barIndex: Float(spectrumIndex2))
                addCubeIndices(to: &indices, baseVertex: baseVertex2)
            }
        }
    }

    // Add vertices for a 3D cube rotated around Y axis (for radial arrangement)
    private func addRotatedCubeVertices(to vertices: inout [GLfloat], x: Float, y: Float, z: Float,
                                       width: Float, height: Float, depth: Float,
                                       rotationAngle: Float, barIndex: Float) {
        // Create rotation matrix for Y axis
        let cosA = cos(rotationAngle)
        let sinA = sin(rotationAngle)

        // Helper to rotate a point around Y axis
        func rotateY(_ px: Float, _ pz: Float) -> (Float, Float) {
            return (px * cosA - pz * sinA, px * sinA + pz * cosA)
        }

        // Define cube corners (before rotation)
        let x0 = -width / 2, x1 = width / 2
        let y0: Float = 0, y1 = height
        let z0 = -depth / 2, z1 = depth / 2

        // Vertex format: position(3) + normal(3) + barIndex(1) + heightMult(1)

        // Front face (+Z local)
        var corners = [
            (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)
        ]
        for (px, py, pz) in corners {
            let (rx, rz) = rotateY(px, pz)
            let (nx, nz) = rotateY(0, 1)  // Rotated normal
            vertices += [x + rx, y + py, z + rz,  nx, 0, nz,  barIndex, height]
        }

        // Back face (-Z local)
        corners = [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)]
        for (px, py, pz) in corners {
            let (rx, rz) = rotateY(px, pz)
            let (nx, nz) = rotateY(0, -1)
            vertices += [x + rx, y + py, z + rz,  nx, 0, nz,  barIndex, height]
        }

        // Right face (+X local)
        corners = [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)]
        for (px, py, pz) in corners {
            let (rx, rz) = rotateY(px, pz)
            let (nx, nz) = rotateY(1, 0)
            vertices += [x + rx, y + py, z + rz,  nx, 0, nz,  barIndex, height]
        }

        // Left face (-X local)
        corners = [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)]
        for (px, py, pz) in corners {
            let (rx, rz) = rotateY(px, pz)
            let (nx, nz) = rotateY(-1, 0)
            vertices += [x + rx, y + py, z + rz,  nx, 0, nz,  barIndex, height]
        }

        // Top face (+Y)
        corners = [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)]
        for (px, py, pz) in corners {
            let (rx, rz) = rotateY(px, pz)
            vertices += [x + rx, y + py, z + rz,  0, 1, 0,  barIndex, height]
        }

        // Bottom face (-Y)
        corners = [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)]
        for (px, py, pz) in corners {
            let (rx, rz) = rotateY(px, pz)
            vertices += [x + rx, y + py, z + rz,  0, -1, 0,  barIndex, height]
        }
    }

    // Add vertices for a 3D cube (24 vertices, 4 per face with proper normals)
    private func addCubeVertices(to vertices: inout [GLfloat], x: Float, y: Float, z: Float,
                                  width: Float, height: Float, depth: Float, barIndex: Float) {
        let x0 = x, x1 = x + width
        let y0 = y, y1 = y + height
        let z0 = z - depth / 2, z1 = z + depth / 2

        // Vertex format: position(3) + normal(3) + barIndex(1) + heightMult(1)

        // Front face (+Z)
        vertices += [x0, y0, z1,  0, 0, 1,  barIndex, height,
                     x1, y0, z1,  0, 0, 1,  barIndex, height,
                     x1, y1, z1,  0, 0, 1,  barIndex, height,
                     x0, y1, z1,  0, 0, 1,  barIndex, height]

        // Back face (-Z)
        vertices += [x1, y0, z0,  0, 0, -1,  barIndex, height,
                     x0, y0, z0,  0, 0, -1,  barIndex, height,
                     x0, y1, z0,  0, 0, -1,  barIndex, height,
                     x1, y1, z0,  0, 0, -1,  barIndex, height]

        // Right face (+X)
        vertices += [x1, y0, z1,  1, 0, 0,  barIndex, height,
                     x1, y0, z0,  1, 0, 0,  barIndex, height,
                     x1, y1, z0,  1, 0, 0,  barIndex, height,
                     x1, y1, z1,  1, 0, 0,  barIndex, height]

        // Left face (-X)
        vertices += [x0, y0, z0,  -1, 0, 0,  barIndex, height,
                     x0, y0, z1,  -1, 0, 0,  barIndex, height,
                     x0, y1, z1,  -1, 0, 0,  barIndex, height,
                     x0, y1, z0,  -1, 0, 0,  barIndex, height]

        // Top face (+Y)
        vertices += [x0, y1, z1,  0, 1, 0,  barIndex, height,
                     x1, y1, z1,  0, 1, 0,  barIndex, height,
                     x1, y1, z0,  0, 1, 0,  barIndex, height,
                     x0, y1, z0,  0, 1, 0,  barIndex, height]

        // Bottom face (-Y)
        vertices += [x0, y0, z0,  0, -1, 0,  barIndex, height,
                     x1, y0, z0,  0, -1, 0,  barIndex, height,
                     x1, y0, z1,  0, -1, 0,  barIndex, height,
                     x0, y0, z1,  0, -1, 0,  barIndex, height]
    }

    // Add indices for a cube (6 faces * 2 triangles * 3 vertices = 36 indices)
    private func addCubeIndices(to indices: inout [GLuint], baseVertex: GLuint) {
        for face in 0..<6 {
            let base = baseVertex + GLuint(face * 4)
            indices += [base, base + 1, base + 2,  base, base + 2, base + 3]
        }
    }

    // MARK: - Matrix Math

    private func createPerspectiveMatrix(fov: Float, aspect: Float, near: Float, far: Float) -> [GLfloat] {
        var matrix = [GLfloat](repeating: 0, count: 16)

        let f = 1.0 / tan(fov * Float.pi / 360.0)  // fov is in degrees, convert to half-angle radians

        matrix[0] = f / aspect
        matrix[5] = f
        matrix[10] = (far + near) / (near - far)
        matrix[11] = -1.0
        matrix[14] = (2.0 * far * near) / (near - far)

        return matrix
    }

    private func createViewMatrix(eye: [Float], center: [Float], up: [Float]) -> [GLfloat] {
        // Calculate forward, right, and up vectors
        let f = normalize([center[0] - eye[0], center[1] - eye[1], center[2] - eye[2]])
        let r = normalize(cross(f, up))
        let u = cross(r, f)

        var matrix = [GLfloat](repeating: 0, count: 16)

        matrix[0] = r[0]
        matrix[4] = r[1]
        matrix[8] = r[2]
        matrix[12] = -dot(r, eye)

        matrix[1] = u[0]
        matrix[5] = u[1]
        matrix[9] = u[2]
        matrix[13] = -dot(u, eye)

        matrix[2] = -f[0]
        matrix[6] = -f[1]
        matrix[10] = -f[2]
        matrix[14] = dot(f, eye)

        matrix[15] = 1.0

        return matrix
    }

    private func createIdentityMatrix() -> [GLfloat] {
        var matrix = [GLfloat](repeating: 0, count: 16)
        matrix[0] = 1.0
        matrix[5] = 1.0
        matrix[10] = 1.0
        matrix[15] = 1.0
        return matrix
    }

    // Vector math helpers
    private func normalize(_ v: [Float]) -> [Float] {
        let len = sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
        return [v[0]/len, v[1]/len, v[2]/len]
    }

    private func cross(_ a: [Float], _ b: [Float]) -> [Float] {
        return [
            a[1]*b[2] - a[2]*b[1],
            a[2]*b[0] - a[0]*b[2],
            a[0]*b[1] - a[1]*b[0]
        ]
    }

    private func dot(_ a: [Float], _ b: [Float]) -> Float {
        return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
    }

    // MARK: - Spectrum Processing

    /// Update spectrum data from external source (e.g., AudioEngine)
    /// - Parameter input: Array of spectrum values (typically 75 bands from AudioEngine)
    func updateSpectrum(_ input: [Float]) {
        guard !input.isEmpty else { return }

        dataLock.lock()
        defer { dataLock.unlock() }

        // Resample to target bar count
        let resampled = resampleSpectrum(input, toCount: barCount)

        // Smooth with previous frame (fast attack, slow decay)
        for i in 0..<barCount {
            let newValue = resampled[i]
            let oldValue = smoothedSpectrum[i]

            if newValue > oldValue {
                // Fast attack
                smoothedSpectrum[i] = newValue
            } else {
                // Slow decay
                smoothedSpectrum[i] = oldValue * smoothingFactor + newValue * (1.0 - smoothingFactor)
            }
        }
    }

    private func resampleSpectrum(_ input: [Float], toCount: Int) -> [Float] {
        var output = [Float](repeating: 0, count: toCount)

        for i in 0..<toCount {
            // Map to input range with interpolation
            let position = Float(i) * Float(input.count - 1) / Float(toCount - 1)
            let index = Int(position)
            let fraction = position - Float(index)

            if index < input.count - 1 {
                // Linear interpolation
                output[i] = input[index] * (1.0 - fraction) + input[index + 1] * fraction
            } else {
                output[i] = input[index]
            }

            // Apply power curve for visual dynamics (adjusted for more response)
            output[i] = pow(output[i], 0.6)

            // Scale up for better visual range
            output[i] = min(output[i] * 1.3, 1.0)

            // Ensure minimum height for visual appeal (reduced for less clutter)
            output[i] = max(output[i], 0.005)
        }

        return output
    }

    // MARK: - Cleanup

    func cleanup() {
        if vao != 0 {
            glDeleteVertexArrays(1, &vao)
            vao = 0
        }
        if vbo != 0 {
            glDeleteBuffers(1, &vbo)
            vbo = 0
        }
        if ebo != 0 {
            glDeleteBuffers(1, &ebo)
            ebo = 0
        }
        if shaderProgram != 0 {
            glDeleteProgram(shaderProgram)
            shaderProgram = 0
        }
        if reflectionShaderProgram != 0 {
            glDeleteProgram(reflectionShaderProgram)
            reflectionShaderProgram = 0
        }

        isAvailable = false
        NSLog("TOCSpectrumRenderer: Cleaned up OpenGL resources")
    }
}
