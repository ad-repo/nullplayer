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
    
    var artworkImage: NSImage? {
        get { _artworkImage }
        set { scheduleArtwork(newValue) }
    }

    // MARK: - Private State

    private var _artworkImage: NSImage?
    private var scrollOffset: CGFloat = 0
    private var artScrollOffset: CGFloat = 0
    private var textWidth: CGFloat = 0
    private var cachedLoopWidth: CGFloat = 0
    private var scrollTimer: Timer?
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
        
        let pad: CGFloat = glowEnabled ? 8.0 : 2.0

        // Art geometry
        let artSize: CGFloat = _artworkImage != nil ? bounds.height : 0
        let artGap: CGFloat = _artworkImage != nil ? 12.0 : 0
        artScrollOffset = artSize + artGap

        let needsScroll = (artScrollOffset + textWidth) > bounds.width
        let endGap = _artworkImage != nil ? artGap : scrollGap
        let loopWidth = artScrollOffset + textWidth + endGap
        cachedLoopWidth = loopWidth

        // Calculate total content width
        let contentWidth: CGFloat
        if needsScroll {
            contentWidth = loopWidth * 2 + pad * 2
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
        
        func drawArt(atX x: CGFloat) {
            guard let img = _artworkImage else { return }
            img.draw(in: NSRect(x: x, y: 0, width: artSize, height: artSize),
                     from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        if needsScroll {
            let drawText = { (x: CGFloat) in
                if self.glowEnabled {
                    self.drawWithGlow(attrStr, at: NSPoint(x: x, y: y), ctx: ctx)
                } else {
                    attrStr.draw(at: NSPoint(x: x, y: y))
                }
            }
            drawArt(atX: pad)
            drawText(pad + artScrollOffset)
            drawArt(atX: pad + loopWidth)
            drawText(pad + loopWidth + artScrollOffset)
        } else {
            drawArt(atX: pad)
            if glowEnabled {
                drawWithGlow(attrStr, at: NSPoint(x: pad + artScrollOffset, y: y), ctx: ctx)
            } else {
                attrStr.draw(at: NSPoint(x: pad + artScrollOffset, y: y))
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

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }
            let loopWidth = self.cachedLoopWidth
            guard loopWidth > 0 else { return }
            self.scrollOffset += self.scrollSpeed / 30.0
            self.scrollOffset = self.scrollOffset.truncatingRemainder(dividingBy: loopWidth)
            self.applyScrollPosition()
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }
    
    private func stopScrolling() {
        guard isScrolling else { return }
        isScrolling = false
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    private func scheduleArtwork(_ image: NSImage?) {
        if image == nil {
            // Clear immediately — never linger with stale art
            _artworkImage = nil
            needsTextRender = true
            renderAndLayout()
        } else if isScrolling {
            // Re-render now but compensate scrollOffset so visible text stays put.
            // The art lands behind the current position and scrolls in from the right naturally.
            //
            // Invariant: callers always set artworkImage = nil synchronously before starting a
            // new load (see ModernMainWindowView.updateTrackInfo), so previousArtScrollOffset
            // is 0 here. The compensation equals the full artScrollOffset of the new image,
            // shifting the text back to its current screen position after the loop widens.
            let previousArtScrollOffset = artScrollOffset
            _artworkImage = image
            needsTextRender = true
            renderAndLayout()
            scrollOffset += artScrollOffset - previousArtScrollOffset
            applyScrollPosition()
        } else {
            _artworkImage = image
            needsTextRender = true
            renderAndLayout()
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
        setNeedsDisplay()
    }
    
    // MARK: - Configuration from Skin
    
    /// Element glow multiplier from skin config
    private var glowMultiplier: CGFloat = 1.0
    
    /// Configure the marquee from a modern skin
    func configure(with skin: ModernSkin) {
        // Marquee color from skin palette (defaults to warm glowing yellow)
        textColor = skin.applyTextOpacity(to: skin.marqueeColor)
        glowEnabled = skin.config.glow.enabled
        glowColor = skin.applyTextOpacity(to: skin.marqueeColor)
        glowMultiplier = skin.elementGlowMultiplier
        
        // Marquee scroll settings from skin config
        scrollSpeed = skin.config.marquee?.scrollSpeed ?? 30.0
        scrollGap = skin.config.marquee?.scrollGap ?? 50.0
        
        // Use marquee-specific font sizing so `fonts.marqueeSize` is always honored.
        textFont = skin.marqueeFont()
    }
}
