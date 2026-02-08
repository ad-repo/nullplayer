import AppKit
import QuartzCore

/// Independent marquee layer for the modern skin system.
/// Uses NSFont (not bitmap sprites) for text rendering. Handles scrolling track titles,
/// cast indicators, error messages, and radio ICY metadata.
///
/// Completely independent of the classic `MarqueeLayer` in `Skin/`.
class ModernMarqueeLayer: CALayer {
    
    // MARK: - Properties
    
    /// The text to display/scroll
    var text: String = "" {
        didSet {
            if text != oldValue {
                scrollOffset = 0
                needsTextRender = true
                renderAndLayout()
            }
        }
    }
    
    /// Text color
    var textColor: NSColor = .cyan {
        didSet { needsTextRender = true; renderAndLayout() }
    }
    
    /// Text font
    var textFont: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) {
        didSet { scrollOffset = 0; needsTextRender = true; renderAndLayout() }
    }
    
    /// Whether glow is enabled
    var glowEnabled: Bool = false
    
    /// Glow color (defaults to textColor)
    var glowColor: NSColor?
    
    /// Scroll speed in points per second
    var scrollSpeed: CGFloat = 30.0
    
    /// Gap between end of text and start of repeat (for seamless looping)
    var scrollGap: CGFloat = 50.0
    
    /// Whether scrolling is active
    private(set) var isScrolling = false
    
    // MARK: - Private State
    
    private var scrollOffset: CGFloat = 0
    private var textWidth: CGFloat = 0
    private var displayLink: CVDisplayLink?
    private var lastTimestamp: TimeInterval = 0
    private var isPaused = false
    private var needsTextRender = true
    private var cachedTextImage: CGImage?
    private var cachedContentWidth: CGFloat = 0
    private var lastBoundsSize: NSSize = .zero
    
    /// Content sublayer that holds the rendered text bitmap
    private let contentLayer = CALayer()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        commonInit()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
        if let marquee = layer as? ModernMarqueeLayer {
            self.text = marquee.text
            self.textColor = marquee.textColor
            self.textFont = marquee.textFont
            self.glowEnabled = marquee.glowEnabled
            self.glowColor = marquee.glowColor
            self.scrollSpeed = marquee.scrollSpeed
            self.scrollGap = marquee.scrollGap
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        masksToBounds = true
        isOpaque = false
        contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        contentLayer.contentsScale = contentsScale
        contentLayer.isOpaque = false
        contentLayer.anchorPoint = .zero
        // Disable implicit animations on the content layer
        contentLayer.actions = ["position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "contents": NSNull()]
        addSublayer(contentLayer)
    }
    
    deinit {
        stopScrolling()
    }
    
    // MARK: - Layout
    
    override func layoutSublayers() {
        super.layoutSublayers()
        // Only re-render if bounds actually changed
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            needsTextRender = true
            renderAndLayout()
        }
    }
    
    // MARK: - Rendering (separate from scrolling)
    
    /// Render the text bitmap and configure scrolling. Called when text/font/bounds change.
    private func renderAndLayout() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard needsTextRender else { return }
        needsTextRender = false
        
        // Calculate text size
        let attrs = textAttributes()
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        textWidth = attrStr.size().width
        
        let needsScroll = textWidth > bounds.width
        let pad: CGFloat = glowEnabled ? 8.0 : 2.0
        
        // Calculate total content width
        let contentWidth: CGFloat
        if needsScroll {
            // Two copies of text + gap + padding on both sides
            contentWidth = (textWidth + scrollGap) * 2 + pad * 2
        } else {
            contentWidth = bounds.width + pad * 2
        }
        cachedContentWidth = contentWidth
        
        // Render the text to a bitmap
        let scale = contentsScale
        let pixelWidth = Int(contentWidth * scale)
        let pixelHeight = Int(bounds.height * scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: pixelWidth,
                                  height: pixelHeight,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
        
        ctx.scaleBy(x: scale, y: scale)
        ctx.clear(NSRect(origin: .zero, size: NSSize(width: contentWidth, height: bounds.height)))
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        
        let textSize = attrStr.size()
        let y = (bounds.height - textSize.height) / 2
        
        if needsScroll {
            // Draw text twice for seamless looping
            let drawText = { (x: CGFloat) in
                if self.glowEnabled {
                    self.drawWithGlow(attrStr, at: NSPoint(x: x, y: y), ctx: ctx)
                } else {
                    attrStr.draw(at: NSPoint(x: x, y: y))
                }
            }
            drawText(pad)
            drawText(pad + textWidth + scrollGap)
        } else {
            // Static text
            if glowEnabled {
                drawWithGlow(attrStr, at: NSPoint(x: pad, y: y), ctx: ctx)
            } else {
                attrStr.draw(at: NSPoint(x: pad, y: y))
            }
        }
        
        NSGraphicsContext.restoreGraphicsState()
        
        cachedTextImage = ctx.makeImage()
        
        // Apply to content layer without animation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contents = cachedTextImage
        contentLayer.frame = NSRect(x: -pad, y: 0, width: contentWidth, height: bounds.height)
        CATransaction.commit()
        
        // Start/stop scrolling as needed
        if needsScroll && !isScrolling {
            scrollOffset = 0
            startScrolling()
        } else if !needsScroll && isScrolling {
            stopScrolling()
            scrollOffset = 0
        }
    }
    
    // MARK: - Scrolling
    
    private func startScrolling() {
        guard !isScrolling else { return }
        isScrolling = true
        lastTimestamp = CACurrentMediaTime()
        
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let displayLink = link else { return }
        
        self.displayLink = displayLink
        
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context -> CVReturn in
            guard let context = context else { return kCVReturnError }
            let layer = Unmanaged<ModernMarqueeLayer>.fromOpaque(context).takeUnretainedValue()
            
            let now = CACurrentMediaTime()
            let dt = now - layer.lastTimestamp
            layer.lastTimestamp = now
            
            guard !layer.isPaused else { return kCVReturnSuccess }
            
            // Update scroll offset on the display link thread, apply position on main
            let newOffset = layer.scrollOffset + layer.scrollSpeed * CGFloat(dt)
            let loopWidth = layer.textWidth + layer.scrollGap
            layer.scrollOffset = loopWidth > 0 ? newOffset.truncatingRemainder(dividingBy: loopWidth) : 0
            
            DispatchQueue.main.async {
                layer.applyScrollPosition()
            }
            
            return kCVReturnSuccess
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(displayLink, callback, selfPtr)
        CVDisplayLinkStart(displayLink)
    }
    
    private func stopScrolling() {
        guard isScrolling else { return }
        isScrolling = false
        
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }
    
    /// Apply the current scroll offset to the content layer position (main thread only)
    private func applyScrollPosition() {
        let pad: CGFloat = glowEnabled ? 8.0 : 2.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.frame = NSRect(x: -scrollOffset - pad, y: 0,
                                    width: cachedContentWidth, height: bounds.height)
        CATransaction.commit()
    }
    
    // MARK: - Text Drawing Helpers
    
    private func drawWithGlow(_ str: NSAttributedString, at point: NSPoint, ctx: CGContext) {
        let color = glowColor ?? textColor
        let gm = glowMultiplier
        // Wide outer bloom (EQ style multi-pass glow)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 8 * gm, color: color.withAlphaComponent(0.5).cgColor)
        str.draw(at: point)
        ctx.restoreGState()
        // Inner glow pass
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 4 * gm, color: color.withAlphaComponent(0.7).cgColor)
        str.draw(at: point)
        ctx.restoreGState()
        // Crisp text on top
        str.draw(at: point)
    }
    
    private func textAttributes() -> [NSAttributedString.Key: Any] {
        return [
            .font: textFont,
            .foregroundColor: textColor
        ]
    }
    
    // MARK: - Pause/Resume
    
    func pauseScrolling() {
        isPaused = true
    }
    
    func resumeScrolling() {
        isPaused = false
        lastTimestamp = CACurrentMediaTime()
    }
    
    // MARK: - Configuration from Skin
    
    /// Element glow multiplier from skin config
    private var glowMultiplier: CGFloat = 1.0
    
    /// Configure the marquee from a modern skin
    func configure(with skin: ModernSkin) {
        // Marquee color from skin palette (defaults to warm glowing yellow)
        textColor = skin.marqueeColor
        glowEnabled = skin.config.glow.enabled
        glowColor = skin.marqueeColor
        glowMultiplier = skin.elementGlowMultiplier
        
        // Marquee scroll settings from skin config
        scrollSpeed = skin.config.marquee?.scrollSpeed ?? 30.0
        scrollGap = skin.config.marquee?.scrollGap ?? 50.0
        
        if let font = skin.primaryFont {
            let bodySize = skin.config.fonts.bodySize ?? 9
            textFont = font.withSize(bodySize * ModernSkinElements.scaleFactor)
        }
    }
}
