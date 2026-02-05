import AppKit
import QuartzCore

/// A CALayer subclass that renders Winamp-style bitmap font text and animates scrolling
/// using Core Animation for GPU-accelerated performance.
///
/// This replaces the timer-based marquee rendering in MainWindowView for normal mode,
/// reducing CPU usage from ~15-18% to ~3-5% when the marquee is scrolling.
class MarqueeLayer: CALayer {
    
    // MARK: - Configuration
    
    /// The text to display. Setting this triggers re-rendering.
    var text: String = "" {
        didSet {
            if text != oldValue {
                renderText()
            }
        }
    }
    
    /// The TEXT.BMP skin image containing the bitmap font
    var skinTextImage: NSImage? {
        didSet {
            if skinTextImage !== oldValue {
                // Cache CGImage immediately when skin changes (NOT during render)
                // This prevents cross-window interference from NSImage operations
                cacheSkinCGImage()
                renderText()
            }
        }
    }
    
    /// Scroll speed in pixels per second (default: 24 = 3px at 8Hz equivalent)
    var scrollSpeed: CGFloat = 24
    
    /// Separator between repeated text for seamless scrolling
    var separator: String = "  -  "
    
    // MARK: - Private Properties
    
    /// The content layer that holds the rendered text image
    private var contentLayer: CALayer?
    
    /// Cached CGImage of TEXT.BMP to avoid NSImage operations during render
    private var cachedSkinCGImage: CGImage?
    
    /// Width of one complete text cycle (text + separator)
    private var cycleWidth: CGFloat = 0
    
    /// Whether the text currently needs scrolling
    private var needsScrolling: Bool = false
    
    // MARK: - Constants (from SkinElements.TextFont)
    
    private let charWidth: CGFloat = SkinElements.TextFont.charWidth   // 5
    private let charHeight: CGFloat = SkinElements.TextFont.charHeight // 6
    
    /// No edge padding - use full marquee width
    private let edgePadding: CGFloat = 0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupLayer()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? MarqueeLayer {
            self.text = other.text
            self.skinTextImage = other.skinTextImage
            self.scrollSpeed = other.scrollSpeed
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }
    
    private func setupLayer() {
        masksToBounds = true
        backgroundColor = CGColor.clear
        
        // Disable implicit animations on this layer to prevent unexpected changes
        actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
        
        // Create content sublayer for the scrolling text
        contentLayer = CALayer()
        contentLayer?.anchorPoint = CGPoint(x: 0, y: 0)
        contentLayer?.position = .zero
        contentLayer?.contentsScale = contentsScale
        // Use resize gravity so content fills the frame properly
        contentLayer?.contentsGravity = .resize
        // Disable implicit animations on content layer to prevent unexpected changes
        contentLayer?.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull(), "contents": NSNull()]
        addSublayer(contentLayer!)
    }
    
    // Override contentsScale to propagate to contentLayer
    override var contentsScale: CGFloat {
        didSet {
            contentLayer?.contentsScale = contentsScale
        }
    }
    
    // MARK: - Text Rendering
    
    /// Shared serial queue for marquee text rendering
    static let sharedRenderQueue = DispatchQueue(label: "com.adamp.marquee.render")
    
    /// Cache the CGImage from skinTextImage - MUST be called outside of render cycle
    /// This prevents cross-window interference from NSImage.cgImage() calls
    private func cacheSkinCGImage() {
        cachedSkinCGImage = nil
        guard let nsImage = skinTextImage else { return }
        // Get CGImage from NSImage - safe to call here (not during render)
        cachedSkinCGImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    /// Render the text to a CGImage and update the content layer
    func renderText() {
        guard !text.isEmpty else {
            contentLayer?.contents = nil
            stopScrollAnimation()
            return
        }
        
        // Text dimensions in base coordinates (matching the bounds)
        let textWidth = CGFloat(text.count) * charWidth
        // Available scroll width = full marquee width minus small edge padding
        let availableWidth = bounds.width - (edgePadding * 2)
        
        
        // Capture values for async rendering
        let currentText = text
        let currentSeparator = separator
        let currentSkinCGImage = cachedSkinCGImage  // Use cached CGImage, not NSImage
        let currentScale = contentsScale
        let currentBoundsHeight = bounds.height
        let currentCharWidth = charWidth
        let currentCharHeight = charHeight
        let currentEdgePadding = edgePadding
        
        if textWidth <= availableWidth {
            // Text fits - render once, no scrolling, left-aligned
            needsScrolling = false
            cycleWidth = textWidth
            
            // Render on background queue to avoid NSGraphicsContext interference
            Self.sharedRenderQueue.async { [weak self] in
                // Render at full bounds height so text is centered and not stretched
                let image = self?.renderTextToImageSync(currentText, width: textWidth, 
                                                        skinCGImage: currentSkinCGImage, scale: currentScale,
                                                        charWidth: currentCharWidth, charHeight: currentCharHeight,
                                                        boundsHeight: currentBoundsHeight)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // Use explicit CATransaction to prevent interference from other view updates
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.contentLayer?.contents = image
                    // Frame fills full bounds height - text is centered within the rendered image
                    let contentFrame = CGRect(x: currentEdgePadding, y: 0,
                                              width: textWidth, height: currentBoundsHeight)
                    self.contentLayer?.frame = contentFrame
                    CATransaction.commit()
                    self.stopScrollAnimation()
                }
            }
        } else {
            // Text overflows - render text + separator twice for seamless loop
            needsScrolling = true
            let separatorWidth = CGFloat(currentSeparator.count) * currentCharWidth
            cycleWidth = textWidth + separatorWidth
            
            // Render two copies for seamless scrolling
            let fullText = currentText + currentSeparator + currentText + currentSeparator
            let totalWidth = cycleWidth * 2
            let finalCycleWidth = cycleWidth
            
            // Render on background queue to avoid NSGraphicsContext interference
            Self.sharedRenderQueue.async { [weak self] in
                // Render at full bounds height so text is centered and not stretched
                let image = self?.renderTextToImageSync(fullText, width: totalWidth,
                                                        skinCGImage: currentSkinCGImage, scale: currentScale,
                                                        charWidth: currentCharWidth, charHeight: currentCharHeight,
                                                        boundsHeight: currentBoundsHeight)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // Use explicit CATransaction to prevent interference from other view updates
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.contentLayer?.contents = image
                    // Frame fills full bounds height - text is centered within the rendered image
                    let contentFrame = CGRect(x: currentEdgePadding, y: 0,
                                              width: totalWidth, height: currentBoundsHeight)
                    self.contentLayer?.frame = contentFrame
                    CATransaction.commit()
                    // Start scroll animation
                    self.startScrollAnimationWithCycleWidth(finalCycleWidth)
                }
            }
        }
    }
    
    /// Render text string to a CGImage using bitmap font sprites (thread-safe version)
    /// Uses pre-cached CGImage to avoid NSImage operations that can cause cross-window interference
    private func renderTextToImageSync(_ string: String, width: CGFloat, skinCGImage: CGImage?, 
                                       scale: CGFloat, charWidth: CGFloat, charHeight: CGFloat,
                                       boundsHeight: CGFloat) -> CGImage? {
        // Check for system font fallback (non-Latin characters or no skin image)
        if skinCGImage == nil || containsNonLatinCharacters(string) {
            return renderSystemFontToImageSync(string, width: width, scale: scale, charHeight: charHeight, boundsHeight: boundsHeight)
        }
        
        return renderBitmapFontToImageSync(string, width: width, skinCGImage: skinCGImage!, 
                                           scale: scale, charWidth: charWidth, charHeight: charHeight, boundsHeight: boundsHeight)
    }
    
    /// Render using Winamp bitmap font (TEXT.BMP) - thread-safe version
    /// Uses NSBitmapImageRep for reliable rendering with proper coordinate handling
    /// The skinCGImage is converted to NSImage for drawing to ensure correct orientation
    private func renderBitmapFontToImageSync(_ string: String, width: CGFloat, skinCGImage: CGImage,
                                             scale: CGFloat, charWidth: CGFloat, charHeight: CGFloat,
                                             boundsHeight: CGFloat) -> CGImage? {
        // Render at full bounds height so text is vertically centered without stretching
        let height = boundsHeight
        let pixelWidth = Int(ceil(width * scale))
        let pixelHeight = Int(ceil(height * scale))
        
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        
        // Convert cached CGImage to NSImage for proper coordinate handling
        let skinImage = NSImage(cgImage: skinCGImage, size: NSSize(width: skinCGImage.width, height: skinCGImage.height))
        let skinImageHeight = skinImage.size.height
        
        // Create bitmap image rep at exact pixel dimensions
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else { return nil }
        
        // Set the size in points (for proper Retina handling)
        bitmapRep.size = NSSize(width: width, height: height)
        
        // Create graphics context from bitmap rep
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return nil }
        
        // Use thread-local graphics state
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .none
        
        // Center text vertically within the bounds height
        let yOffset = (boundsHeight - charHeight) / 2
        
        var xPos: CGFloat = 0
        for char in string.uppercased() {
            // Get source rect in Winamp coordinates (Y=0 at top)
            let charRect = SkinElements.TextFont.character(char)
            
            // Convert to NSImage coordinates (Y=0 at bottom)
            let sourceRect = NSRect(
                x: charRect.origin.x,
                y: skinImageHeight - charRect.origin.y - charRect.height,
                width: charRect.width,
                height: charRect.height
            )
            
            let destRect = NSRect(x: xPos, y: yOffset, width: charWidth, height: charHeight)
            
            skinImage.draw(in: destRect,
                          from: sourceRect,
                          operation: .sourceOver,
                          fraction: 1.0,
                          respectFlipped: false,
                          hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
            
            xPos += charWidth
        }
        
        NSGraphicsContext.restoreGraphicsState()
        
        return bitmapRep.cgImage
    }
    
    /// Render using system font (for Unicode characters) - thread-safe version
    private func renderSystemFontToImageSync(_ string: String, width: CGFloat, scale: CGFloat, charHeight: CGFloat, boundsHeight: CGFloat) -> CGImage? {
        // Render at full bounds height
        let height = boundsHeight
        let pixelWidth = Int(ceil(width * scale))
        let pixelHeight = Int(ceil(height * scale))
        
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        
        // Create bitmap image rep at exact pixel dimensions
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else { return nil }
        
        bitmapRep.size = NSSize(width: width, height: height)
        
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return nil }
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.green,
            .font: NSFont.systemFont(ofSize: 8, weight: .regular)
        ]
        
        // Center vertically
        let yOffset = (boundsHeight - charHeight) / 2
        string.draw(at: NSPoint(x: 0, y: yOffset), withAttributes: attrs)
        
        NSGraphicsContext.restoreGraphicsState()
        
        return bitmapRep.cgImage
    }
    
    /// Check if string contains non-Latin characters that need system font
    private func containsNonLatinCharacters(_ string: String) -> Bool {
        let supportedChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \"@:()-'!_+\\/[]^&%.=$#?,*")
        let uppercased = string.uppercased()
        for scalar in uppercased.unicodeScalars {
            if !supportedChars.contains(scalar) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Animation
    
    /// Start the continuous scroll animation
    func startScrollAnimation() {
        startScrollAnimationWithCycleWidth(cycleWidth)
    }
    
    /// Start scroll animation with specific cycle width
    private func startScrollAnimationWithCycleWidth(_ animationCycleWidth: CGFloat) {
        guard needsScrolling, animationCycleWidth > 0 else { return }
        
        // Use explicit transaction to prevent interference
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer?.removeAnimation(forKey: "scroll")
        CATransaction.commit()
        
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = 0
        animation.toValue = -animationCycleWidth
        animation.duration = CFTimeInterval(animationCycleWidth / scrollSpeed)
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        
        contentLayer?.add(animation, forKey: "scroll")
    }
    
    /// Stop the scroll animation
    func stopScrollAnimation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer?.removeAnimation(forKey: "scroll")
        contentLayer?.position = CGPoint(x: 0, y: contentLayer?.position.y ?? 0)
        CATransaction.commit()
    }
    
    /// Pause animation (for when window is hidden)
    func pauseAnimation() {
        guard let layer = contentLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = pausedTime
        CATransaction.commit()
    }
    
    /// Resume animation (for when window becomes visible)
    func resumeAnimation() {
        guard let layer = contentLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        let timeSincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        layer.beginTime = timeSincePause
        CATransaction.commit()
    }
    
    // MARK: - Layout
    
    /// Track previous bounds to detect actual changes
    private var lastLayoutBounds: CGRect = .zero
    
    override func layoutSublayers() {
        super.layoutSublayers()
        // Only re-render when bounds actually change (e.g., window scaling)
        // Skip if bounds is zero (not yet configured)
        guard bounds.width > 0, bounds.height > 0, bounds != lastLayoutBounds else { return }
        lastLayoutBounds = bounds
        renderText()
    }
    
    /// Update the contents scale (call when moving between displays)
    func updateContentsScale(_ scale: CGFloat) {
        guard contentsScale != scale else { return }
        contentsScale = scale
        contentLayer?.contentsScale = scale
        renderText()
    }
}
