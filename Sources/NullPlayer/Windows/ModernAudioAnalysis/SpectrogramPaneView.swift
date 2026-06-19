import AppKit
import SwiftUI
import MetalKit

/// Spectrogram pane — scrolling waterfall visualization
struct SpectrogramPaneView: NSViewRepresentable {
    func makeNSView(context: NSViewRepresentableContext<SpectrogramPaneView>) -> NSView {
        let view = SpectrogramMetalView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: NSViewRepresentableContext<SpectrogramPaneView>) {
        // Metal view handles updates internally
    }
}

/// Metal-based spectrogram renderer with scrolling history
class SpectrogramMetalView: NSView {
    private var metalView: MTKView?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var historyTexture: MTLTexture?
    private var spectrumObserver: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []

    // Scrolling history buffer (width × height, each pixel is a spectrum sample over time)
    private var historyBuffer: [Float] = []
    private var historyWidth = 1024
    private var historyHeight = 75  // Match spectrum band count

    override func awakeFromNib() {
        super.awakeFromNib()
        setupMetal()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupMetal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }

    deinit {
        if let observer = spectrumObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupMetal() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("AudioAnalysis: Metal device unavailable")
            return
        }

        self.device = device

        // Create Metal view with idiomatic paced rendering
        let mtk = MTKView(frame: bounds, device: device)
        mtk.delegate = self
        mtk.framebufferOnly = false
        mtk.preferredFramesPerSecond = 60
        mtk.isPaused = false
        mtk.enableSetNeedsDisplay = false
        addSubview(mtk)
        mtk.frame = bounds
        mtk.autoresizingMask = [.width, .height]
        metalView = mtk

        // Create command queue
        commandQueue = device.makeCommandQueue()

        // Load shader source from the resource bundle and compile at runtime.
        // makeDefaultLibrary() returns nil in SPM executables — match SpectrumAnalyzerView.
        guard let shaderURL = BundleHelper.url(forResource: "SpectrogramShaders", withExtension: "metal"),
              let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8) else {
            NSLog("AudioAnalysis: Failed to load spectrogram shader source file")
            return
        }

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            NSLog("AudioAnalysis: Failed to compile spectrogram shader library: \(error)")
            return
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "spectrogramVertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "spectrogramFragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            NSLog("AudioAnalysis: Pipeline creation failed: \(error)")
        }

        // Initialize history buffer
        historyBuffer = Array(repeating: 0, count: historyWidth * historyHeight)

        // Create history texture
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: historyWidth,
            height: historyHeight,
            mipmapped: false
        )
        textureDesc.usage = [.shaderRead, .shaderWrite]
        historyTexture = device.makeTexture(descriptor: textureDesc)

        // Subscribe to spectrum updates (on main thread)
        spectrumObserver = NotificationCenter.default.addObserver(
            forName: .audioSpectrumDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSpectrumUpdate(notification)
        }

        // Observe window minimize/deminiaturize for pause/resume
        let miniObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.metalView?.isPaused = true
        }
        observers.append(miniObserver)

        let deminiObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didDeminiaturizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.metalView?.isPaused = false
        }
        observers.append(deminiObserver)
    }

    private func handleSpectrumUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let spectrum = userInfo["spectrum"] as? [Float],
              let historyTexture = historyTexture else { return }

        // Shift history left and add new spectrum data on the right
        let bandCount = min(spectrum.count, historyHeight)
        for i in 0..<historyHeight {
            for x in 1..<historyWidth {
                historyBuffer[i * historyWidth + (x - 1)] = historyBuffer[i * historyWidth + x]
            }
            if i < bandCount {
                // `spectrum` bands are already normalized 0–1 magnitudes (see
                // AudioEngine.audioSpectrumDataUpdated) — use them directly for colormapping.
                historyBuffer[i * historyWidth + (historyWidth - 1)] = max(0, min(1, spectrum[i]))
            } else {
                historyBuffer[i * historyWidth + (historyWidth - 1)] = 0
            }
        }

        // Upload buffer to GPU
        let bytesPerRow = historyWidth * MemoryLayout<Float>.size
        let region = MTLRegionMake2D(0, 0, historyWidth, historyHeight)
        historyTexture.replace(region: region, mipmapLevel: 0, withBytes: historyBuffer, bytesPerRow: bytesPerRow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            // View removed from window, pause rendering
            metalView?.isPaused = true
        }
    }

    override func layout() {
        super.layout()
        metalView?.frame = bounds
    }
}

extension SpectrogramMetalView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes
    }

    func draw(in view: MTKView) {
        // Guard pipeline, texture, and other critical resources BEFORE creating encoder
        guard let pipelineState = pipelineState,
              let historyTexture = historyTexture,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                  descriptor: renderPassDescriptor
              ) else { return }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentTexture(historyTexture, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()
    }
}
