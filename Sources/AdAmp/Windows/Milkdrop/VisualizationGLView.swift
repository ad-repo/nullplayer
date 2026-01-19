import AppKit
import OpenGL.GL3
import CoreVideo
import Accelerate

// Silence OpenGL deprecation warnings (macOS still supports OpenGL 4.1)
// We use OpenGL for visualization as Metal doesn't have the same ecosystem of presets

/// Protocol for receiving audio data for visualization
protocol VisualizationDataSource: AnyObject {
    /// Get current spectrum data (75 bands, normalized 0-1)
    var spectrumData: [Float] { get }
    
    /// Get current PCM audio samples (mono, -1 to 1)
    var pcmData: [Float] { get }
    
    /// Sample rate of PCM data
    var sampleRate: Double { get }
}

/// OpenGL view for real-time audio visualization
/// Uses CVDisplayLink for 60fps updates
/// Designed to support projectM integration in the future
class VisualizationGLView: NSOpenGLView {
    
    // MARK: - Properties
    
    weak var dataSource: VisualizationDataSource?
    
    /// CVDisplayLink for vsync'd rendering
    private var displayLink: CVDisplayLink?
    
    /// Whether rendering is currently active
    private(set) var isRendering = false
    
    /// Current visualization mode
    enum VisualizationMode {
        case spectrum      // Bar spectrum analyzer
        case oscilloscope  // Waveform display
        case milkdrop      // ProjectM presets (future)
    }
    
    var mode: VisualizationMode = .spectrum
    
    /// Local copy of spectrum data for thread-safe access
    private var localSpectrum: [Float] = Array(repeating: 0, count: 75)
    private var localPCM: [Float] = Array(repeating: 0, count: 1024)
    private let dataLock = NSLock()
    
    /// OpenGL shader program
    private var shaderProgram: GLuint = 0
    private var vao: GLuint = 0
    private var vbo: GLuint = 0
    
    /// Colors for spectrum bars (gradient from green to red)
    private let barColors: [(r: Float, g: Float, b: Float)] = {
        var colors: [(Float, Float, Float)] = []
        for i in 0..<75 {
            let ratio = Float(i) / 74.0
            // Green -> Yellow -> Orange -> Red
            let r: Float
            let g: Float
            if ratio < 0.5 {
                r = ratio * 2.0
                g = 1.0
            } else {
                r = 1.0
                g = 1.0 - (ratio - 0.5) * 2.0
            }
            colors.append((r, g, 0.0))
        }
        return colors
    }()
    
    // MARK: - Initialization
    
    override init?(frame frameRect: NSRect, pixelFormat format: NSOpenGLPixelFormat?) {
        // Create pixel format for OpenGL 4.1 Core Profile
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 24,
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            0
        ]
        
        guard let pixelFormat = NSOpenGLPixelFormat(attributes: attrs) else {
            NSLog("VisualizationGLView: Failed to create OpenGL pixel format")
            super.init(frame: frameRect, pixelFormat: nil)
            return nil
        }
        
        super.init(frame: frameRect, pixelFormat: pixelFormat)
        
        wantsBestResolutionOpenGLSurface = true
        
        // Set up OpenGL context
        openGLContext?.makeCurrentContext()
        setupOpenGL()
        setupDisplayLink()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupOpenGL()
        setupDisplayLink()
    }
    
    deinit {
        stopRendering()
        cleanupOpenGL()
    }
    
    // MARK: - OpenGL Setup
    
    private func setupOpenGL() {
        guard let context = openGLContext else { return }
        context.makeCurrentContext()
        
        // Enable vsync
        var swapInterval: GLint = 1
        context.setValues(&swapInterval, for: .swapInterval)
        
        // Set up basic OpenGL state
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glEnable(GLenum(GL_BLEND))
        glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA))
        
        // Create VAO and VBO for spectrum bars
        glGenVertexArrays(1, &vao)
        glGenBuffers(1, &vbo)
        
        glBindVertexArray(vao)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        
        // Allocate buffer for max vertices (75 bars * 6 vertices * 6 floats per vertex)
        let maxVertices = 75 * 6 * 6
        glBufferData(GLenum(GL_ARRAY_BUFFER), maxVertices * MemoryLayout<Float>.size, nil, GLenum(GL_DYNAMIC_DRAW))
        
        // Position attribute (2 floats)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 
                             GLsizei(6 * MemoryLayout<Float>.size), nil)
        
        // Color attribute (4 floats)
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(1, 4, GLenum(GL_FLOAT), GLboolean(GL_FALSE),
                             GLsizei(6 * MemoryLayout<Float>.size),
                             UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.size))
        
        glBindVertexArray(0)
        
        // Create simple shader program
        createShaders()
    }
    
    private func createShaders() {
        let vertexShaderSource = """
        #version 330 core
        layout (location = 0) in vec2 aPos;
        layout (location = 1) in vec4 aColor;
        out vec4 vertexColor;
        void main() {
            gl_Position = vec4(aPos, 0.0, 1.0);
            vertexColor = aColor;
        }
        """
        
        let fragmentShaderSource = """
        #version 330 core
        in vec4 vertexColor;
        out vec4 FragColor;
        void main() {
            FragColor = vertexColor;
        }
        """
        
        // Compile vertex shader
        let vertexShader = glCreateShader(GLenum(GL_VERTEX_SHADER))
        vertexShaderSource.withCString { ptr in
            var source: UnsafePointer<GLchar>? = ptr
            glShaderSource(vertexShader, 1, &source, nil)
        }
        glCompileShader(vertexShader)
        checkShaderCompilation(vertexShader, "vertex")
        
        // Compile fragment shader
        let fragmentShader = glCreateShader(GLenum(GL_FRAGMENT_SHADER))
        fragmentShaderSource.withCString { ptr in
            var source: UnsafePointer<GLchar>? = ptr
            glShaderSource(fragmentShader, 1, &source, nil)
        }
        glCompileShader(fragmentShader)
        checkShaderCompilation(fragmentShader, "fragment")
        
        // Link program
        shaderProgram = glCreateProgram()
        glAttachShader(shaderProgram, vertexShader)
        glAttachShader(shaderProgram, fragmentShader)
        glLinkProgram(shaderProgram)
        checkProgramLinking(shaderProgram)
        
        // Clean up shaders (they're linked now)
        glDeleteShader(vertexShader)
        glDeleteShader(fragmentShader)
    }
    
    private func checkShaderCompilation(_ shader: GLuint, _ type: String) {
        var success: GLint = 0
        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &success)
        if success == GL_FALSE {
            var logLength: GLint = 0
            glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &logLength)
            var log = [GLchar](repeating: 0, count: Int(logLength))
            glGetShaderInfoLog(shader, logLength, nil, &log)
            NSLog("VisualizationGLView: \(type) shader compilation failed: \(String(cString: log))")
        }
    }
    
    private func checkProgramLinking(_ program: GLuint) {
        var success: GLint = 0
        glGetProgramiv(program, GLenum(GL_LINK_STATUS), &success)
        if success == GL_FALSE {
            var logLength: GLint = 0
            glGetProgramiv(program, GLenum(GL_INFO_LOG_LENGTH), &logLength)
            var log = [GLchar](repeating: 0, count: Int(logLength))
            glGetProgramInfoLog(program, logLength, nil, &log)
            NSLog("VisualizationGLView: Shader program linking failed: \(String(cString: log))")
        }
    }
    
    private func cleanupOpenGL() {
        openGLContext?.makeCurrentContext()
        
        if vao != 0 {
            glDeleteVertexArrays(1, &vao)
            vao = 0
        }
        if vbo != 0 {
            glDeleteBuffers(1, &vbo)
            vbo = 0
        }
        if shaderProgram != 0 {
            glDeleteProgram(shaderProgram)
            shaderProgram = 0
        }
    }
    
    // MARK: - Display Link
    
    private func setupDisplayLink() {
        // Create display link
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        
        guard let displayLink = displayLink else {
            NSLog("VisualizationGLView: Failed to create CVDisplayLink")
            return
        }
        
        // Set the callback
        let callback: CVDisplayLinkOutputCallback = { displayLink, inNow, inOutputTime, flagsIn, flagsOut, context in
            let view = Unmanaged<VisualizationGLView>.fromOpaque(context!).takeUnretainedValue()
            view.renderFrame()
            return kCVReturnSuccess
        }
        
        CVDisplayLinkSetOutputCallback(displayLink, callback, Unmanaged.passUnretained(self).toOpaque())
        
        // Set the display link to the display of the OpenGL context
        if let cglContext = openGLContext?.cglContextObj,
           let cglPixelFormat = pixelFormat?.cglPixelFormatObj {
            CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(displayLink, cglContext, cglPixelFormat)
        }
    }
    
    // MARK: - Rendering Control
    
    func startRendering() {
        guard let displayLink = displayLink, !isRendering else { return }
        
        CVDisplayLinkStart(displayLink)
        isRendering = true
        NSLog("VisualizationGLView: Started rendering")
    }
    
    func stopRendering() {
        guard let displayLink = displayLink, isRendering else { return }
        
        CVDisplayLinkStop(displayLink)
        isRendering = false
        NSLog("VisualizationGLView: Stopped rendering")
    }
    
    // MARK: - Data Update
    
    /// Update spectrum data (called from main thread)
    func updateSpectrum(_ data: [Float]) {
        dataLock.lock()
        for i in 0..<min(data.count, localSpectrum.count) {
            localSpectrum[i] = data[i]
        }
        dataLock.unlock()
    }
    
    /// Update PCM data (called from main thread)
    func updatePCM(_ data: [Float]) {
        dataLock.lock()
        for i in 0..<min(data.count, localPCM.count) {
            localPCM[i] = data[i]
        }
        dataLock.unlock()
    }
    
    // MARK: - Frame Rendering
    
    private func renderFrame() {
        guard let context = openGLContext else { return }
        
        // Make context current on this thread
        context.makeCurrentContext()
        
        // Lock focus
        CGLLockContext(context.cglContextObj!)
        defer { CGLUnlockContext(context.cglContextObj!) }
        
        // Get data snapshot
        dataLock.lock()
        let spectrum = localSpectrum
        let pcm = localPCM
        dataLock.unlock()
        
        // Get viewport dimensions
        let backingBounds = convertToBacking(bounds)
        glViewport(0, 0, GLsizei(backingBounds.width), GLsizei(backingBounds.height))
        
        // Clear
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        // Draw based on mode
        switch mode {
        case .spectrum:
            drawSpectrumBars(spectrum)
        case .oscilloscope:
            drawOscilloscope(pcm)
        case .milkdrop:
            // Future: projectM rendering
            drawSpectrumBars(spectrum) // Fallback for now
        }
        
        // Swap buffers
        context.flushBuffer()
    }
    
    private func drawSpectrumBars(_ spectrum: [Float]) {
        guard shaderProgram != 0 else { return }
        
        glUseProgram(shaderProgram)
        glBindVertexArray(vao)
        
        // Build vertex data for bars
        var vertices: [Float] = []
        let barCount = 75
        let barWidth = 2.0 / Float(barCount) * 0.9 // Leave small gap
        let gap = 2.0 / Float(barCount) * 0.1
        
        for i in 0..<barCount {
            let height = max(0.02, spectrum[i]) // Minimum height so bars are visible
            let x = -1.0 + Float(i) * (barWidth + gap)
            let y: Float = -1.0
            
            // Get color for this bar
            let (r, g, b) = barColors[i]
            
            // Create two triangles for the bar (6 vertices)
            // Bottom left
            vertices.append(contentsOf: [x, y, r, g, b, 1.0])
            // Bottom right
            vertices.append(contentsOf: [x + barWidth, y, r, g, b, 1.0])
            // Top right
            vertices.append(contentsOf: [x + barWidth, y + height * 2.0, r, g, b, 1.0])
            
            // Bottom left
            vertices.append(contentsOf: [x, y, r, g, b, 1.0])
            // Top right
            vertices.append(contentsOf: [x + barWidth, y + height * 2.0, r, g, b, 1.0])
            // Top left
            vertices.append(contentsOf: [x, y + height * 2.0, r, g, b, 1.0])
        }
        
        // Upload vertex data
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        vertices.withUnsafeBytes { ptr in
            glBufferSubData(GLenum(GL_ARRAY_BUFFER), 0, ptr.count, ptr.baseAddress)
        }
        
        // Draw
        glDrawArrays(GLenum(GL_TRIANGLES), 0, GLsizei(barCount * 6))
        
        glBindVertexArray(0)
        glUseProgram(0)
    }
    
    private func drawOscilloscope(_ pcm: [Float]) {
        guard shaderProgram != 0 else { return }
        
        glUseProgram(shaderProgram)
        glBindVertexArray(vao)
        
        // Build vertex data for waveform
        var vertices: [Float] = []
        let sampleCount = min(pcm.count, 512)
        
        for i in 0..<sampleCount {
            let x = -1.0 + Float(i) / Float(sampleCount) * 2.0
            let y = pcm[i] * 0.8 // Scale to fit
            
            // Green color for waveform
            vertices.append(contentsOf: [x, y, 0.0, 1.0, 0.0, 1.0])
        }
        
        // Upload vertex data
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        vertices.withUnsafeBytes { ptr in
            glBufferSubData(GLenum(GL_ARRAY_BUFFER), 0, ptr.count, ptr.baseAddress)
        }
        
        // Draw as line strip
        glDrawArrays(GLenum(GL_LINE_STRIP), 0, GLsizei(sampleCount))
        
        glBindVertexArray(0)
        glUseProgram(0)
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if window != nil {
            // Start rendering when added to a window
            startRendering()
        } else {
            // Stop rendering when removed from window
            stopRendering()
        }
    }
    
    override func viewDidHide() {
        super.viewDidHide()
        stopRendering()
    }
    
    override func viewDidUnhide() {
        super.viewDidUnhide()
        if window != nil {
            startRendering()
        }
    }
    
    override func reshape() {
        super.reshape()
        
        // Update viewport on resize
        openGLContext?.makeCurrentContext()
        openGLContext?.update()
        
        let backingBounds = convertToBacking(bounds)
        glViewport(0, 0, GLsizei(backingBounds.width), GLsizei(backingBounds.height))
    }
    
    // MARK: - Hit Testing
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass through clicks to parent view for window dragging
        return nil
    }
}
