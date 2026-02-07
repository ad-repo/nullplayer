import AppKit
import Metal
import MetalKit

/// Metal-based bloom/glow post-processing for the modern skin system.
/// Renders window content to an offscreen texture, applies multi-pass Gaussian blur
/// on bright pixels, and composites the bloom back over the original.
class BloomPostProcessor {
    
    // MARK: - Properties
    
    /// Whether bloom is enabled
    var isEnabled: Bool = true
    
    /// Bloom radius (blur kernel size)
    var radius: CGFloat = 8.0
    
    /// Bloom intensity (brightness multiplier)
    var intensity: CGFloat = 0.6
    
    /// Brightness threshold (pixels above this contribute to bloom)
    var threshold: CGFloat = 0.7
    
    // MARK: - Metal State
    
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var brightnessExtractPipeline: MTLComputePipelineState?
    private var blurHorizontalPipeline: MTLComputePipelineState?
    private var blurVerticalPipeline: MTLComputePipelineState?
    private var compositePipeline: MTLComputePipelineState?
    
    // Textures
    private var sourceTexture: MTLTexture?
    private var brightnessTexture: MTLTexture?
    private var blurTempTexture: MTLTexture?
    private var bloomTexture: MTLTexture?
    private var outputTexture: MTLTexture?
    
    /// Whether Metal setup succeeded
    private(set) var isAvailable: Bool = false
    
    // MARK: - Initialization
    
    init() {
        setupMetal()
    }
    
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("BloomPostProcessor: No Metal device available")
            return
        }
        
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        
        // Load shader library
        guard let library = loadShaderLibrary(device: device) else {
            NSLog("BloomPostProcessor: Failed to load shader library")
            return
        }
        
        // Create compute pipelines
        do {
            if let fn = library.makeFunction(name: "bloom_extract_brightness") {
                brightnessExtractPipeline = try device.makeComputePipelineState(function: fn)
            }
            if let fn = library.makeFunction(name: "bloom_blur_horizontal") {
                blurHorizontalPipeline = try device.makeComputePipelineState(function: fn)
            }
            if let fn = library.makeFunction(name: "bloom_blur_vertical") {
                blurVerticalPipeline = try device.makeComputePipelineState(function: fn)
            }
            if let fn = library.makeFunction(name: "bloom_composite") {
                compositePipeline = try device.makeComputePipelineState(function: fn)
            }
            
            isAvailable = brightnessExtractPipeline != nil &&
                          blurHorizontalPipeline != nil &&
                          blurVerticalPipeline != nil &&
                          compositePipeline != nil
            
            if isAvailable {
                NSLog("BloomPostProcessor: Metal setup complete")
            }
        } catch {
            NSLog("BloomPostProcessor: Pipeline creation failed: %@", error.localizedDescription)
        }
    }
    
    private func loadShaderLibrary(device: MTLDevice) -> MTLLibrary? {
        // Try loading from the default library first
        if let library = device.makeDefaultLibrary() {
            // Check if our bloom functions exist
            if library.makeFunction(name: "bloom_extract_brightness") != nil {
                return library
            }
        }
        
        // Try loading from a compiled metallib in the bundle
        let bundle = Bundle.main
        let searchPaths = [
            bundle.resourceURL?.appendingPathComponent("BloomShader.metallib"),
            bundle.resourceURL?.appendingPathComponent("Resources/BloomShader.metallib"),
            bundle.resourceURL?.appendingPathComponent("NullPlayer_NullPlayer.bundle/BloomShader.metallib"),
        ].compactMap { $0 }
        
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path.path) {
                if let library = try? device.makeLibrary(URL: path) {
                    return library
                }
            }
        }
        
        // Try compiling from source at runtime
        let sourceSearchPaths = [
            bundle.resourceURL?.appendingPathComponent("BloomShader.metal"),
            bundle.resourceURL?.appendingPathComponent("Resources/BloomShader.metal"),
            bundle.resourceURL?.appendingPathComponent("NullPlayer_NullPlayer.bundle/BloomShader.metal"),
            bundle.resourceURL?.appendingPathComponent("ModernSkin/BloomShader.metal"),
        ].compactMap { $0 }
        
        for path in sourceSearchPaths {
            if let source = try? String(contentsOf: path, encoding: .utf8) {
                if let library = try? device.makeLibrary(source: source, options: nil) {
                    return library
                }
            }
        }
        
        NSLog("BloomPostProcessor: Could not find or compile BloomShader")
        return nil
    }
    
    // MARK: - Texture Management
    
    private func ensureTextures(width: Int, height: Int) {
        guard let device = device else { return }
        
        // Check if existing textures match
        if let existing = sourceTexture,
           existing.width == width, existing.height == height {
            return
        }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        
        sourceTexture = device.makeTexture(descriptor: descriptor)
        brightnessTexture = device.makeTexture(descriptor: descriptor)
        blurTempTexture = device.makeTexture(descriptor: descriptor)
        bloomTexture = device.makeTexture(descriptor: descriptor)
        outputTexture = device.makeTexture(descriptor: descriptor)
    }
    
    // MARK: - Processing
    
    /// Apply bloom to a CGImage and return the result
    func apply(to image: CGImage) -> CGImage? {
        guard isEnabled, isAvailable else { return image }
        guard let device = device, let commandQueue = commandQueue else { return image }
        
        let width = image.width
        let height = image.height
        
        ensureTextures(width: width, height: height)
        
        guard let source = sourceTexture,
              let brightness = brightnessTexture,
              let blurTemp = blurTempTexture,
              let bloom = bloomTexture,
              let output = outputTexture else { return image }
        
        // Upload source image to texture
        let loader = MTKTextureLoader(device: device)
        guard let uploadedTexture = try? loader.newTexture(cgImage: image, options: [
            .textureUsage: MTLTextureUsage([.shaderRead, .shaderWrite]).rawValue as NSNumber,
            .textureStorageMode: MTLStorageMode.managed.rawValue as NSNumber
        ]) else { return image }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return image }
        
        // Copy uploaded texture to our source texture
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(from: uploadedTexture, to: source)
            blitEncoder.endEncoding()
        }
        
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        // Pass 1: Extract bright pixels
        if let encoder = commandBuffer.makeComputeCommandEncoder(),
           let pipeline = brightnessExtractPipeline {
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(brightness, index: 1)
            var thresh = Float(threshold)
            encoder.setBytes(&thresh, length: MemoryLayout<Float>.size, index: 0)
            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
        }
        
        // Pass 2: Horizontal blur
        if let encoder = commandBuffer.makeComputeCommandEncoder(),
           let pipeline = blurHorizontalPipeline {
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(brightness, index: 0)
            encoder.setTexture(blurTemp, index: 1)
            var rad = Int32(radius)
            encoder.setBytes(&rad, length: MemoryLayout<Int32>.size, index: 0)
            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
        }
        
        // Pass 3: Vertical blur
        if let encoder = commandBuffer.makeComputeCommandEncoder(),
           let pipeline = blurVerticalPipeline {
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(blurTemp, index: 0)
            encoder.setTexture(bloom, index: 1)
            var rad = Int32(radius)
            encoder.setBytes(&rad, length: MemoryLayout<Int32>.size, index: 0)
            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
        }
        
        // Pass 4: Composite bloom over original
        if let encoder = commandBuffer.makeComputeCommandEncoder(),
           let pipeline = compositePipeline {
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(bloom, index: 1)
            encoder.setTexture(output, index: 2)
            var inten = Float(intensity)
            encoder.setBytes(&inten, length: MemoryLayout<Float>.size, index: 0)
            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read back result
        return textureToImage(output, width: width, height: height)
    }
    
    private func textureToImage(_ texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        let dataSize = bytesPerRow * height
        var data = [UInt8](repeating: 0, count: dataSize)
        
        texture.getBytes(&data,
                         bytesPerRow: bytesPerRow,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: width, height: height, depth: 1)),
                         mipmapLevel: 0)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &data,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        
        return context.makeImage()
    }
    
    // MARK: - Configuration
    
    /// Configure from skin glow settings
    func configure(with glowConfig: GlowConfig) {
        isEnabled = glowConfig.enabled
        radius = glowConfig.radius ?? 8.0
        intensity = glowConfig.intensity ?? 0.6
        threshold = glowConfig.threshold ?? 0.7
    }
}
