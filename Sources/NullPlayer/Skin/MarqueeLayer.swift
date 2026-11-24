import AppKit
import QuartzCore

/// A CALayer subclass that renders skin-style bitmap font text and animates scrolling
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
                scheduleRenderText()
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
                scheduleRenderText()
            }
        }
    }

    /// When true, always render with system font instead of skin bitmap font
    var useSystemFont: Bool = false {
        didSet { if useSystemFont != oldValue { scheduleRenderText() } }
    }

    /// Font size for text drawn in the system font
    var systemFontSize: CGFloat = SkinElements.TextFont.charHeight {
        didSet { if systemFontSize != oldValue { scheduleRenderText() } }
    }

    /// Text color for text drawn in the system font
    var systemFontColor: NSColor = .green {
        didSet { if systemFontColor != oldValue { scheduleRenderText() } }
    }

    /// Scroll speed in pixels per second (default: 24 = 3px at 8Hz equivalent)
    var scrollSpeed: CGFloat = 24
    
    /// Separator between repeated text for seamless scrolling
    var separator: String = "  -  "
    
    // MARK: - Private Properties
    
    /// The content layer that holds the rendered text image
    private var contentLayer: CALayer?
    
    /// TEXT.BMP and its lettering colour, cached together outside the render cycle so no render
    /// touches the NSImage
    private var cachedSkinText: (sheet: CGImage, glyphColor: CGColor)?

    /// Width of one complete text cycle (text + separator)
    private var cycleWidth: CGFloat = 0
    
    /// Whether the text currently needs scrolling
    private var needsScrolling: Bool = false

    /// Coalesces multiple property changes into one render on the main queue.
    private var renderScheduled = false
    private var needsRender = false
    
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
            self.useSystemFont = other.useSystemFont
            self.systemFontSize = other.systemFontSize
            self.systemFontColor = other.systemFontColor
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
        actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull(), "hidden": NSNull()]
        
        // Create content sublayer for the scrolling text
        contentLayer = CALayer()
        contentLayer?.anchorPoint = CGPoint(x: 0, y: 0)
        contentLayer?.position = .zero
        contentLayer?.contentsScale = contentsScale
        // Use resize gravity so content fills the frame properly
        contentLayer?.contentsGravity = .resize
        // Bitmap-font text is pixel art: the scroll animation lands it on fractional points, so
        // sample it nearest rather than smoothing it between device pixels
        contentLayer?.magnificationFilter = .nearest
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
    static let sharedRenderQueue = DispatchQueue(label: "com.nullplayer.marquee.render")
    
    /// Cache the CGImage from skinTextImage - MUST be called outside of render cycle
    /// This prevents cross-window interference from NSImage.cgImage() calls
    private func cacheSkinCGImage() {
        cachedSkinText = nil
        // Get CGImage from NSImage - safe to call here (not during render)
        guard let sheet = skinTextImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        cachedSkinText = (sheet, SkinElements.TextFont.glyphColor(in: sheet))
    }
    
    /// Render the text to a CGImage and update the content layer
    func renderText() {
        guard !text.isEmpty else {
            contentLayer?.contents = nil
            stopScrollAnimation()
            return
        }

        // Capture values for async rendering
        let (face, currentText) = face(for: text)
        let currentSeparator = separator
        let currentScale = contentsScale
        let currentBoundsHeight = bounds.height
        let currentEdgePadding = edgePadding

        // Text dimensions in base coordinates (matching the bounds)
        let textWidth = face.width(of: currentText)
        // Available scroll width = full marquee width minus small edge padding
        let availableWidth = bounds.width - (edgePadding * 2)

        if textWidth <= availableWidth {
            // Text fits - render once, no scrolling, left-aligned
            needsScrolling = false
            cycleWidth = textWidth

            // Render on background queue to avoid NSGraphicsContext interference
            Self.sharedRenderQueue.async { [weak self] in
                // Render at full bounds height so text is centered and not stretched
                let image = face.image(of: currentText, width: textWidth, scale: currentScale,
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
            let separatorWidth = face.width(of: currentSeparator)
            cycleWidth = textWidth + separatorWidth

            // Render two copies for seamless scrolling
            let fullText = currentText + currentSeparator + currentText + currentSeparator
            let totalWidth = cycleWidth * 2
            let finalCycleWidth = cycleWidth

            // Render on background queue to avoid NSGraphicsContext interference
            Self.sharedRenderQueue.async { [weak self] in
                // Render at full bounds height so text is centered and not stretched
                let image = face.image(of: fullText, width: totalWidth, scale: currentScale,
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

    // MARK: - Title Font

    /// The font a title draws in, carrying what that font needs to measure and draw it.
    private enum Face {
        case skin(CGImage)
        case pixel(CGColor)
        case system(size: CGFloat, color: NSColor)

        func width(of text: String) -> CGFloat {
            switch self {
            case .skin: return CGFloat(text.count) * SkinElements.TextFont.charWidth
            case .pixel: return SkinElements.TextFont.pixelFontWidth(text)
            case .system(let size, _): return text.size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width
            }
        }

        /// Thread-safe: reads only what the case carries.
        func image(of text: String, width: CGFloat, scale: CGFloat, boundsHeight: CGFloat) -> CGImage? {
            switch self {
            case .skin(let sheet):
                return MarqueeLayer.renderBitmapFontToImageSync(text, width: width, skinCGImage: sheet, scale: scale,
                                                                boundsHeight: boundsHeight)
            case .pixel(let color):
                return SkinElements.TextFont.pixelFontImage(text, width: width, height: boundsHeight, color: color)
            case .system(let size, let color):
                return MarqueeLayer.renderSystemFontToImageSync(text, width: width, scale: scale, fontSize: size,
                                                                color: color, boundsHeight: boundsHeight)
            }
        }
    }

    /// `text`'s face — skin glyphs, then the pixel font, then the system font — and `text` spelled
    /// for it. A layer set to `useSystemFont`, or a skin with no TEXT.BMP, always uses the system font.
    private func face(for text: String) -> (Face, String) {
        let system = Face.system(size: systemFontSize, color: systemFontColor)
        guard !useSystemFont, let skinText = cachedSkinText else { return (system, text) }
        let choice = SkinElements.TextFont.titleFont(for: text)
        switch choice.font {
        case .skin: return (.skin(skinText.sheet), choice.text)
        case .pixel: return (.pixel(skinText.glyphColor), choice.text)
        case .system: return (system, choice.text)
        }
    }
    
    /// Render using skin bitmap font (TEXT.BMP) - thread-safe version
    /// Uses NSBitmapImageRep for reliable rendering with proper coordinate handling
    /// The skinCGImage is converted to NSImage for drawing to ensure correct orientation
    private static func renderBitmapFontToImageSync(_ string: String, width: CGFloat, skinCGImage: CGImage,
                                                    scale: CGFloat, boundsHeight: CGFloat) -> CGImage? {
        let charWidth = SkinElements.TextFont.charWidth, charHeight = SkinElements.TextFont.charHeight
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
            // Get source rect in skin coordinates (Y=0 at top)
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
    
    /// Render using system font (for Unicode characters or when useSystemFont is set) - thread-safe version
    private static func renderSystemFontToImageSync(_ string: String, width: CGFloat, scale: CGFloat,
                                             fontSize: CGFloat, color: NSColor, boundsHeight: CGFloat) -> CGImage? {
        let height = boundsHeight
        let pixelWidth = Int(ceil(width * scale))
        let pixelHeight = Int(ceil(height * scale))

        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

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
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular)
        ]

        let yOffset = (boundsHeight - fontSize) / 2
        string.draw(at: NSPoint(x: 0, y: yOffset), withAttributes: attrs)

        NSGraphicsContext.restoreGraphicsState()

        return bitmapRep.cgImage
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
        // Only a paused layer: on a running one this rewinds the clock behind the scroll
        // animation's start, freezing it until a new title adds a fresh one. A window shown for
        // the first time reports visible with no pause before it.
        guard let layer = contentLayer, layer.speed == 0 else { return }
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
        scheduleRenderText()
    }
    
    /// Update the contents scale (call when moving between displays)
    func updateContentsScale(_ scale: CGFloat) {
        guard contentsScale != scale else { return }
        contentsScale = scale
        scheduleRenderText()
    }

    /// Scales the layer up from base skin size with a transform and renders its text at device
    /// pixels for that size; at backing scale alone it is stretched on the GPU and blurs (#611).
    /// `scale` is clamped to 1 only for the zero-bounds pass before the first layout — the window's
    /// minimum size is never below base size.
    func applyDisplayScale(_ scale: CGFloat, backingScale: CGFloat) {
        transform = CATransform3DMakeScale(scale, scale, 1)
        updateContentsScale(backingScale * max(scale, 1))
    }

    private func scheduleRenderText() {
        if Thread.isMainThread {
            scheduleRenderTextOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleRenderTextOnMain()
            }
        }
    }

    private func scheduleRenderTextOnMain() {
        needsRender = true
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.renderScheduled = false
            guard self.needsRender else { return }
            self.needsRender = false
            self.renderText()
        }
    }
}
