import AppKit

/// Edges of a window that are adjacent (docked) to another window.
/// Used by `drawWindowBorder` to suppress borders on shared edges.
struct AdjacentEdges: OptionSet {
    let rawValue: Int
    static let top    = AdjacentEdges(rawValue: 1 << 0)
    static let bottom = AdjacentEdges(rawValue: 1 << 1)
    static let left   = AdjacentEdges(rawValue: 1 << 2)
    static let right  = AdjacentEdges(rawValue: 1 << 3)
}

/// Renders modern skin elements using images or programmatic fallback.
/// For each element, rendering priority is: skin image > programmatic fallback using palette colors.
///
/// The modern renderer uses standard macOS bottom-left origin coordinates (no flipping needed).
class ModernSkinRenderer {
    
    /// The active skin to render with
    var skin: ModernSkin
    
    /// Scale factor for rendering
    let scaleFactor: CGFloat
    
    /// Glow multiplier for element-level blur effects
    let glowMultiplier: CGFloat
    
    // MARK: - Initialization
    
    init(skin: ModernSkin, scaleFactor: CGFloat = ModernSkinElements.scaleFactor) {
        self.skin = skin
        self.scaleFactor = scaleFactor
        self.glowMultiplier = skin.elementGlowMultiplier
    }
    
    // MARK: - Generic Element Drawing
    
    /// Draw an element by ID and state into the given rect.
    /// Uses skin image if available, otherwise falls back to programmatic rendering.
    func drawElement(_ id: String, state: String = "normal", in rect: NSRect, context: CGContext) {
        // Scale the rect
        let scaledRect = scaledRect(rect)
        
        // Try image first
        if let image = skin.image(for: id, state: state) {
            drawImage(image, in: scaledRect, context: context)
            return
        }
        
        // Programmatic fallback
        drawFallback(id, state: state, in: scaledRect, context: context)
    }
    
    // MARK: - Specialized Drawing
    
    /// Draw the window background
    func drawWindowBackground(in bounds: NSRect, context: CGContext) {
        // Fill with background color
        context.setFillColor(skin.backgroundColor.cgColor)
        context.fill(bounds)
        
        // Draw background image if available
        if let bgImage = skin.backgroundImage {
            drawImage(bgImage, in: bounds, context: context)
        }
    }
    
    /// Draw the window border with optional glow.
    /// When `adjacentEdges` is non-empty and `seamlessDocking` > 0 in the skin config,
    /// borders on those edges are faded or fully hidden to make docked windows look seamless.
    func drawWindowBorder(in bounds: NSRect, context: CGContext, adjacentEdges: AdjacentEdges = []) {
        let borderWidth = skin.config.window.borderWidth ?? 1.0
        let cornerRadius = skin.config.window.cornerRadius ?? 0
        let borderColor = skin.borderColor
        let seamless = min(1.0, max(0.0, skin.config.window.seamlessDocking ?? 0))
        
        context.saveGState()
        
        // For full seamless (1.0), clip away adjacent edges entirely before drawing
        if seamless >= 1.0 && !adjacentEdges.isEmpty {
            var clipRect = bounds
            if adjacentEdges.contains(.top)    { clipRect.size.height -= borderWidth }
            if adjacentEdges.contains(.bottom) { clipRect.origin.y += borderWidth; clipRect.size.height -= borderWidth }
            if adjacentEdges.contains(.left)   { clipRect.origin.x += borderWidth; clipRect.size.width -= borderWidth }
            if adjacentEdges.contains(.right)  { clipRect.size.width -= borderWidth }
            context.clip(to: clipRect)
        }
        
        let borderRect = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let path = CGPath(roundedRect: borderRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        
        // Glow effect (draw border slightly larger and blurred behind)
        if skin.config.glow.enabled {
            context.saveGState()
            let glowRadius = skin.config.glow.radius ?? 8.0
            context.setShadow(offset: .zero, blur: glowRadius, color: borderColor.withAlphaComponent(0.5).cgColor)
            context.setStrokeColor(borderColor.cgColor)
            context.setLineWidth(borderWidth)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }
        
        // Actual border
        context.setStrokeColor(borderColor.cgColor)
        context.setLineWidth(borderWidth)
        context.addPath(path)
        context.strokePath()
        
        context.restoreGState()
        
        // For partial seamless (0 < value < 1), overdraw adjacent edges
        // with background color at seamlessDocking alpha to progressively fade them
        if seamless > 0 && seamless < 1.0 && !adjacentEdges.isEmpty {
            let bgColor = skin.backgroundColor
            context.saveGState()
            context.setFillColor(bgColor.withAlphaComponent(seamless).cgColor)
            let bw = borderWidth
            if adjacentEdges.contains(.top) {
                context.fill(CGRect(x: bounds.minX, y: bounds.maxY - bw, width: bounds.width, height: bw))
            }
            if adjacentEdges.contains(.bottom) {
                context.fill(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bw))
            }
            if adjacentEdges.contains(.left) {
                context.fill(CGRect(x: bounds.minX, y: bounds.minY, width: bw, height: bounds.height))
            }
            if adjacentEdges.contains(.right) {
                context.fill(CGRect(x: bounds.maxX - bw, y: bounds.minY, width: bw, height: bounds.height))
            }
            context.restoreGState()
        }
    }
    
    /// Draw the title bar with per-window prefix support and three-tier text fallback.
    ///
    /// Title bar background image lookup: `{prefix}titlebar` -> `titlebar` -> no image (transparent).
    /// Title text rendering (when `titleText.mode == .image`):
    ///   1. Full pre-rendered title image: `{prefix}titlebar_text` -> `titlebar_text`
    ///   2. Character sprite compositing (variable-width, with tinting support)
    ///   3. System font fallback (current NSFont behavior)
    ///
    /// When `titleText.mode` is nil or `.font`, skips straight to system font (step 3).
    ///
    /// - Parameters:
    ///   - rect: Title bar rect in base (unscaled) coordinates
    ///   - title: Title text string (e.g. "NULLPLAYER", "NULLPLAYER PLAYLIST")
    ///   - prefix: Per-window prefix for image lookups (e.g. "playlist_", "eq_"). Empty for main window.
    ///   - context: Core Graphics context to draw into
    func drawTitleBar(in rect: NSRect, title: String, prefix: String = "", context: CGContext) {
        let scaledR = scaledRect(rect)
        
        // --- Title bar background image ---
        // Try per-window image first, then fall back to shared titlebar image
        if let img = skin.image(for: "\(prefix)titlebar") ?? (prefix.isEmpty ? nil : skin.image(for: "titlebar")) {
            drawImage(img, in: scaledR, context: context)
        }
        // No fallback fill -- title bar is transparent, showing the window background through
        
        // --- Separator line at bottom of title bar ---
        let separatorY = scaledR.minY
        context.saveGState()
        if skin.config.glow.enabled {
            context.setShadow(offset: .zero, blur: 4 * scaleFactor * glowMultiplier,
                              color: skin.borderColor.withAlphaComponent(0.5).cgColor)
        }
        context.setStrokeColor(skin.borderColor.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5 * scaleFactor)
        context.move(to: CGPoint(x: scaledR.minX + 1, y: separatorY))
        context.addLine(to: CGPoint(x: scaledR.maxX - 1, y: separatorY))
        context.strokePath()
        context.restoreGState()
        
        // --- Title text rendering (three-tier fallback) ---
        let titleTextConfig = skin.config.titleText
        let isImageMode = titleTextConfig?.mode == .image
        if isImageMode {
            // Tier 1: Full pre-rendered title image
            let titleTextId = "\(prefix)titlebar_text"
            if let img = skin.image(for: titleTextId) ?? (prefix.isEmpty ? nil : skin.image(for: "titlebar_text")) {
                // Resolve per-window tint color: element config -> global tintColor -> nil
                let tintColor = resolveTitleTintColor(prefix: prefix)
                let finalImg = skin.tintedImage(img, key: titleTextId, color: tintColor)
                // Center the image + decorations in the title bar rect
                let imgAspect = finalImg.size.width / max(finalImg.size.height, 1)
                let drawH = scaledR.height * 0.8
                let drawW = drawH * imgAspect
                let deco = resolveDecorations(height: drawH, tintColor: tintColor)
                let totalContentW = drawW + deco.totalExtraWidth
                var drawX = scaledR.midX - totalContentW / 2
                let drawY = scaledR.midY - drawH / 2
                
                if let leftImg = deco.leftImage {
                    drawPixelArtImage(leftImg, in: NSRect(x: drawX, y: drawY, width: deco.leftWidth, height: drawH), context: context)
                    drawX += deco.leftWidth + deco.spacing
                }
                drawPixelArtImage(finalImg, in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH), context: context)
                drawX += drawW
                if let rightImg = deco.rightImage {
                    drawX += deco.spacing
                    drawPixelArtImage(rightImg, in: NSRect(x: drawX, y: drawY, width: deco.rightWidth, height: drawH), context: context)
                }
                return
            }
            
            // Tier 2: Character sprite compositing
            if drawTitleTextFromSprites(title, in: scaledR, prefix: prefix, context: context) {
                return
            }
        }
        
        // Tier 3: System font fallback (default behavior)
        drawTitleTextWithFont(title, in: scaledR, prefix: prefix, context: context)
    }
    
    /// Composite a title string from individual character sprite images.
    ///
    /// Uses variable-width layout: each glyph image's actual pixel width is measured.
    /// Applies `charSpacing`, `alignment`, `padLeft`, `padRight`, `verticalOffset`, and `tintColor`
    /// from `TitleTextConfig`. Per-window color override via `elements["{prefix}titlebar_text"]["color"]`.
    ///
    /// If a character has no sprite, that character alone falls back to font rendering (mixed mode).
    ///
    /// - Returns: `true` if at least one character sprite was found and rendered, `false` if no sprites exist at all.
    func drawTitleTextFromSprites(_ text: String, in rect: NSRect, prefix: String = "", context: CGContext) -> Bool {
        guard skin.hasTitleCharSprites else { return false }
        
        let titleTextConfig = skin.config.titleText
        let charSpacing = (titleTextConfig?.charSpacing ?? 1) * scaleFactor
        let charHeight = (titleTextConfig?.charHeight ?? 10) * scaleFactor
        let padLeft = (titleTextConfig?.padLeft ?? 0) * scaleFactor
        let padRight = (titleTextConfig?.padRight ?? 0) * scaleFactor
        let verticalOffset = (titleTextConfig?.verticalOffset ?? 0) * scaleFactor
        let alignment = titleTextConfig?.alignment ?? .center
        let tintColor = resolveTitleTintColor(prefix: prefix)
        
        // First pass: measure total width and collect glyph data
        struct GlyphInfo {
            let char: Character
            let image: NSImage?     // nil = font fallback for this character
            let width: CGFloat
        }
        
        var glyphs: [GlyphInfo] = []
        var totalWidth: CGFloat = 0
        let fallbackFont = skin.titleBarFont()
        
        for char in text {
            if let img = skin.titleCharImage(for: char) {
                let tinted = skin.tintedImage(img, key: "title_char_\(char)", color: tintColor)
                // Variable width: measure actual image aspect ratio
                let aspect = tinted.size.width / max(tinted.size.height, 1)
                let glyphWidth = charHeight * aspect
                glyphs.append(GlyphInfo(char: char, image: tinted, width: glyphWidth))
                totalWidth += glyphWidth
            } else {
                // Font fallback for this character
                let charStr = NSAttributedString(string: String(char), attributes: [.font: fallbackFont])
                let charWidth = charStr.size().width
                glyphs.append(GlyphInfo(char: char, image: nil, width: charWidth))
                totalWidth += charWidth
            }
        }
        
        // Add spacing between characters
        if glyphs.count > 1 {
            totalWidth += charSpacing * CGFloat(glyphs.count - 1)
        }
        
        // If no image glyphs were found at all, return false to fall back entirely
        guard glyphs.contains(where: { $0.image != nil }) else { return false }
        
        // Resolve decorations (drawn at charHeight, same tint as title text)
        let deco = resolveDecorations(height: charHeight, tintColor: tintColor)
        let totalContentWidth = totalWidth + deco.totalExtraWidth
        
        // Calculate starting X based on alignment (using total content width including decorations)
        let availableWidth = rect.width - padLeft - padRight
        let contentStartX: CGFloat
        switch alignment {
        case .left:
            contentStartX = rect.minX + padLeft
        case .right:
            contentStartX = rect.maxX - padRight - totalContentWidth
        case .center:
            contentStartX = rect.minX + padLeft + (availableWidth - totalContentWidth) / 2
        }
        
        // Calculate Y: center vertically in rect, then apply offset
        let baseY = rect.midY - charHeight / 2 + verticalOffset
        
        // Second pass: draw left decoration, glyphs, right decoration
        var x = contentStartX
        
        // Left decoration
        if let leftImg = deco.leftImage {
            drawPixelArtImage(leftImg, in: NSRect(x: x, y: baseY, width: deco.leftWidth, height: charHeight), context: context)
            x += deco.leftWidth + deco.spacing
        }
        
        // Draw each glyph
        for glyph in glyphs {
            if let img = glyph.image {
                let glyphRect = NSRect(x: x, y: baseY, width: glyph.width, height: charHeight)
                drawPixelArtImage(img, in: glyphRect, context: context)
            } else {
                // Font fallback for this single character
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: fallbackFont,
                    .foregroundColor: tintColor ?? skin.textColor
                ]
                let charStr = NSAttributedString(string: String(glyph.char), attributes: attrs)
                let charSize = charStr.size()
                let charY = rect.midY - charSize.height / 2 + verticalOffset
                charStr.draw(at: NSPoint(x: x, y: charY))
            }
            x += glyph.width + charSpacing
        }
        
        // Right decoration
        if let rightImg = deco.rightImage {
            // x already has the last charSpacing added; subtract it and add decoration spacing instead
            x = x - charSpacing + deco.spacing
            drawPixelArtImage(rightImg, in: NSRect(x: x, y: baseY, width: deco.rightWidth, height: charHeight), context: context)
        }
        
        return true
    }
    
    /// Draw title text using the system font (tier 3 fallback).
    private func drawTitleTextWithFont(_ title: String, in scaledR: NSRect, prefix: String = "", context: CGContext) {
        let titleFont = skin.titleBarFont()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: skin.textColor
        ]
        let titleStr = NSAttributedString(string: title, attributes: attrs)
        let titleSize = titleStr.size()
        
        // Resolve decorations at font text height
        let tintColor = resolveTitleTintColor(prefix: prefix)
        let deco = resolveDecorations(height: titleSize.height, tintColor: tintColor)
        let totalContentW = titleSize.width + deco.totalExtraWidth
        var drawX = scaledR.midX - totalContentW / 2
        let textY = scaledR.midY - titleSize.height / 2
        
        // Left decoration
        if let leftImg = deco.leftImage {
            drawPixelArtImage(leftImg, in: NSRect(x: drawX, y: textY, width: deco.leftWidth, height: titleSize.height), context: context)
            drawX += deco.leftWidth + deco.spacing
        }
        
        // Draw title text
        let titleOrigin = NSPoint(x: drawX, y: textY)
        if skin.config.glow.enabled {
            drawTextWithGlow(titleStr, at: titleOrigin, glowColor: skin.textColor, context: context)
        } else {
            titleStr.draw(at: titleOrigin)
        }
        drawX += titleSize.width
        
        // Right decoration
        if let rightImg = deco.rightImage {
            drawX += deco.spacing
            drawPixelArtImage(rightImg, in: NSRect(x: drawX, y: textY, width: deco.rightWidth, height: titleSize.height), context: context)
        }
    }
    
    /// Resolve the tint color for title text, checking per-window element override first,
    /// then global titleText.tintColor, then nil (no tinting).
    private func resolveTitleTintColor(prefix: String) -> NSColor? {
        // Per-window override: elements["{prefix}titlebar_text"]["color"]
        let elementId = "\(prefix)titlebar_text"
        if let colorHex = skin.elementConfig(for: elementId)?.color {
            return NSColor.from(hex: colorHex)
        }
        // Also check unprefixed for main window
        if !prefix.isEmpty, let colorHex = skin.elementConfig(for: "titlebar_text")?.color {
            return NSColor.from(hex: colorHex)
        }
        // Global tint from titleText config
        if let tintHex = skin.config.titleText?.tintColor {
            return NSColor.from(hex: tintHex)
        }
        return nil
    }
    
    /// Resolved decoration images and their scaled dimensions for drawing alongside title text.
    private struct DecorationInfo {
        let leftImage: NSImage?
        let leftWidth: CGFloat
        let rightImage: NSImage?
        let rightWidth: CGFloat
        let spacing: CGFloat
        
        /// Total extra width consumed by decorations (including spacing on each side).
        var totalExtraWidth: CGFloat {
            var w: CGFloat = 0
            if leftImage != nil { w += leftWidth + spacing }
            if rightImage != nil { w += rightWidth + spacing }
            return w
        }
        
        static let empty = DecorationInfo(leftImage: nil, leftWidth: 0, rightImage: nil, rightWidth: 0, spacing: 0)
    }
    
    /// Resolve title decoration images and calculate their scaled dimensions.
    /// Decorations are rendered at the given height, preserving the source image aspect ratio.
    /// Supports the same tinting mechanism as character sprites.
    private func resolveDecorations(height: CGFloat, tintColor: NSColor?) -> DecorationInfo {
        let titleTextConfig = skin.config.titleText
        let spacing = (titleTextConfig?.decorationSpacing ?? 3) * scaleFactor
        
        var leftImg: NSImage? = nil
        var leftW: CGFloat = 0
        if let leftKey = titleTextConfig?.decorationLeft, let img = skin.image(for: leftKey) {
            let tinted = skin.tintedImage(img, key: leftKey, color: tintColor)
            let aspect = tinted.size.width / max(tinted.size.height, 1)
            leftW = height * aspect
            leftImg = tinted
        }
        
        var rightImg: NSImage? = nil
        var rightW: CGFloat = 0
        if let rightKey = titleTextConfig?.decorationRight, let img = skin.image(for: rightKey) {
            let tinted = skin.tintedImage(img, key: rightKey, color: tintColor)
            let aspect = tinted.size.width / max(tinted.size.height, 1)
            rightW = height * aspect
            rightImg = tinted
        }
        
        return DecorationInfo(leftImage: leftImg, leftWidth: leftW, rightImage: rightImg, rightWidth: rightW, spacing: spacing)
    }
    
    /// Draw a time digit (0-9, minus, colon) as 7-segment LED display
    func drawTimeDigit(_ character: String, in rect: NSRect, context: CGContext) {
        let scaledR = scaledRect(rect)
        
        // Map character to image name
        let imageName: String
        switch character {
        case "0"..."9":
            imageName = "time_digit_\(character)"
        case "-":
            imageName = "time_minus"
        case ":":
            imageName = "time_colon"
        default:
            return
        }
        
        if let img = skin.image(for: imageName) {
            // Use pixel art rendering for crisp scaling of small digit sprites
            drawPixelArtImage(img, in: scaledR, context: context)
        } else {
            // Programmatic 7-segment LED rendering
            draw7SegmentChar(character, in: scaledR, context: context)
        }
    }
    
    /// Draw a character as a 7-segment LED display
    ///
    /// Segment layout:
    /// ```
    ///  _a_
    /// |   |
    /// f   b
    /// |_g_|
    /// |   |
    /// e   c
    /// |_d_|
    /// ```
    private func draw7SegmentChar(_ char: String, in rect: NSRect, context: CGContext) {
        // Time digit color from skin palette (defaults to warm glowing yellow)
        let color = skin.timeColor
        
        // Segment thickness relative to digit size
        let segT = rect.width * 0.15       // segment thickness
        let gap = segT * 0.3              // tiny gap between segments
        
        context.saveGState()
        
        // Multi-pass glow for warm neon effect (EQ style)
        if skin.config.glow.enabled {
            // Wide outer bloom
            context.setShadow(offset: .zero, blur: 8 * scaleFactor * glowMultiplier,
                              color: color.withAlphaComponent(0.5).cgColor)
        }
        
        context.setFillColor(color.cgColor)
        
        // Colon: two small rounded squares
        if char == ":" {
            let dotSize = rect.width * 0.35
            let dotX = rect.midX - dotSize / 2
            let radius = dotSize * 0.2
            fillRoundedSegment(NSRect(x: dotX, y: rect.minY + rect.height * 0.27 - dotSize / 2,
                                       width: dotSize, height: dotSize), radius: radius, context: context)
            fillRoundedSegment(NSRect(x: dotX, y: rect.minY + rect.height * 0.73 - dotSize / 2,
                                       width: dotSize, height: dotSize), radius: radius, context: context)
            context.restoreGState()
            return
        }
        
        // Minus: just the middle segment
        if char == "-" {
            fillRoundedSegment(NSRect(x: rect.minX + gap,
                                       y: rect.midY - segT / 2,
                                       width: rect.width - gap * 2,
                                       height: segT), context: context)
            context.restoreGState()
            return
        }
        
        // 7-segment patterns: which segments are on for each digit
        // Segments: a(top), b(top-right), c(bottom-right), d(bottom), e(bottom-left), f(top-left), g(middle)
        let segments: [Character: [Bool]] = [
            "0": [true,  true,  true,  true,  true,  true,  false],
            "1": [false, true,  true,  false, false, false, false],
            "2": [true,  true,  false, true,  true,  false, true],
            "3": [true,  true,  true,  true,  false, false, true],
            "4": [false, true,  true,  false, false, true,  true],
            "5": [true,  false, true,  true,  false, true,  true],
            "6": [true,  false, true,  true,  true,  true,  true],
            "7": [true,  true,  true,  false, false, false, false],
            "8": [true,  true,  true,  true,  true,  true,  true],
            "9": [true,  true,  true,  true,  false, true,  true],
        ]
        
        guard let digit = char.first, let segs = segments[digit] else {
            context.restoreGState()
            return
        }
        
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        
        // The middle line is at exact center
        let midY = y + h / 2
        // Top and bottom halves are equal: from segT to midY-gap, and midY+gap to h-segT
        let topVStart = midY + gap
        let topVEnd = y + h - segT
        let botVStart = y + segT
        let botVEnd = midY - gap
        let hInset = segT * 0.5  // horizontal segments inset from vertical edges
        
        // Segment a (top horizontal)
        if segs[0] {
            fillRoundedSegment(NSRect(x: x + hInset, y: topVEnd,
                                       width: w - hInset * 2, height: segT), context: context)
        }
        // Segment b (top-right vertical)
        if segs[1] {
            fillRoundedSegment(NSRect(x: x + w - segT, y: topVStart,
                                       width: segT, height: topVEnd - topVStart), context: context)
        }
        // Segment c (bottom-right vertical)
        if segs[2] {
            fillRoundedSegment(NSRect(x: x + w - segT, y: botVStart,
                                       width: segT, height: botVEnd - botVStart), context: context)
        }
        // Segment d (bottom horizontal)
        if segs[3] {
            fillRoundedSegment(NSRect(x: x + hInset, y: y,
                                       width: w - hInset * 2, height: segT), context: context)
        }
        // Segment e (bottom-left vertical)
        if segs[4] {
            fillRoundedSegment(NSRect(x: x, y: botVStart,
                                       width: segT, height: botVEnd - botVStart), context: context)
        }
        // Segment f (top-left vertical)
        if segs[5] {
            fillRoundedSegment(NSRect(x: x, y: topVStart,
                                       width: segT, height: topVEnd - topVStart), context: context)
        }
        // Segment g (middle horizontal)
        if segs[6] {
            fillRoundedSegment(NSRect(x: x + hInset, y: midY - segT / 2,
                                       width: w - hInset * 2, height: segT), context: context)
        }
        
        context.restoreGState()
    }
    
    /// Fill a rounded segment rectangle
    private func fillRoundedSegment(_ rect: NSRect, radius: CGFloat? = nil, context: CGContext) {
        let r = radius ?? min(rect.width, rect.height) * 0.2
        let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        context.addPath(path)
        context.fillPath()
    }
    
    /// Draw a transport button
    func drawTransportButton(_ id: String, state: String, in rect: NSRect, context: CGContext) {
        let scaledR = scaledRect(rect)
        
        if let img = skin.image(for: id, state: state) {
            drawImage(img, in: scaledR, context: context)
            return
        }
        
        // Programmatic fallback: thin outlined icon (finer lines like reference)
        let isPressed = state == "pressed"
        let color = isPressed ? skin.primaryColor.withAlphaComponent(0.7) : skin.primaryColor
        
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.0 * scaleFactor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        let inset = scaledR.insetBy(dx: 5 * scaleFactor, dy: 4 * scaleFactor)
        
        switch id {
        case "btn_prev":
            drawPrevIcon(in: inset, context: context)
        case "btn_play":
            drawPlayIcon(in: inset, context: context)
        case "btn_pause":
            drawPauseIcon(in: inset, context: context)
        case "btn_stop":
            drawStopIcon(in: inset, context: context)
        case "btn_next":
            drawNextIcon(in: inset, context: context)
        case "btn_eject":
            drawEjectIcon(in: inset, context: context)
        default:
            break
        }
        
        context.restoreGState()
    }
    
    /// Draw a slider (seek or volume)
    func drawSlider(trackId: String, fillId: String, thumbId: String,
                    trackRect: NSRect, fillFraction: CGFloat, thumbState: String,
                    context: CGContext, gradient: (NSColor, NSColor)? = nil) {
        let scaledTrack = scaledRect(trackRect)
        
        // Track background
        if let img = skin.image(for: trackId) {
            drawImage(img, in: scaledTrack, context: context)
        } else {
            context.setFillColor(skin.surfaceColor.cgColor)
            context.fill(scaledTrack)
        }
        
        // Fill
        let fillWidth = scaledTrack.width * min(max(fillFraction, 0), 1)
        let fillRect = NSRect(x: scaledTrack.minX, y: scaledTrack.minY,
                              width: fillWidth, height: scaledTrack.height)
        
        if let img = skin.image(for: fillId) {
            drawImage(img, in: fillRect, context: context)
        } else if let (startColor, endColor) = gradient {
            // Gradient fill
            context.saveGState()
            context.clip(to: fillRect)
            let colors = [startColor.cgColor, endColor.cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                context.drawLinearGradient(grad,
                                          start: CGPoint(x: fillRect.minX, y: fillRect.midY),
                                          end: CGPoint(x: scaledTrack.maxX, y: fillRect.midY),
                                          options: [])
            }
            context.restoreGState()
        } else {
            // Solid fill with glow
            context.saveGState()
            if skin.config.glow.enabled {
                context.setShadow(offset: .zero, blur: 4 * scaleFactor * glowMultiplier,
                                  color: skin.primaryColor.withAlphaComponent(0.6).cgColor)
            }
            context.setFillColor(skin.primaryColor.cgColor)
            context.fill(fillRect)
            context.restoreGState()
        }
        
        // Thumb -- small dot at the current position, uses gradient end color if provided
        let thumbColor = gradient?.1 ?? skin.primaryColor
        let thumbDiameter: CGFloat = 5 * scaleFactor
        let thumbX = scaledTrack.minX + fillWidth - thumbDiameter / 2
        let thumbY = scaledTrack.midY - thumbDiameter / 2
        let thumbRect = NSRect(x: thumbX, y: thumbY, width: thumbDiameter, height: thumbDiameter)
        
        if let img = skin.image(for: thumbId, state: thumbState) {
            drawImage(img, in: thumbRect, context: context)
        } else {
            // Fallback: tiny glowing circle
            context.saveGState()
            if skin.config.glow.enabled {
                context.setShadow(offset: .zero, blur: 3 * scaleFactor * glowMultiplier,
                                  color: thumbColor.withAlphaComponent(0.8).cgColor)
            }
            context.setFillColor(thumbColor.cgColor)
            context.fillEllipse(in: thumbRect)
            context.restoreGState()
        }
    }
    
    /// Draw a toggle button (shuffle, repeat, EQ, playlist)
    func drawToggleButton(_ id: String, isOn: Bool, isPressed: Bool, label: String?,
                          in rect: NSRect, context: CGContext) {
        let scaledR = scaledRect(rect)
        
        // Determine state string
        let state: String
        if isPressed {
            state = isOn ? "on_pressed" : "off_pressed"
        } else {
            state = isOn ? "on" : "off"
        }
        
        if let img = skin.image(for: id, state: state) {
            drawImage(img, in: scaledR, context: context)
            return
        }
        
        // Fallback: text label with accent (magenta) for ON state, dim for OFF
        let onColor = skin.accentColor
        let offColor = skin.textDimColor
        let textColor = isOn ? onColor : offColor
        let font = skin.smallLabelFont()
        let labelText = label ?? id.replacingOccurrences(of: "btn_", with: "").uppercased()
        
        // Toggle buttons with outlined boxes
        let isBoxedButton = (id == "btn_eq" || id == "btn_playlist" || id == "btn_library" || id == "btn_projectm" || id == "btn_spectrum")
        if isBoxedButton {
            let boxColor = isOn ? onColor : offColor
            context.saveGState()
            context.setStrokeColor(boxColor.withAlphaComponent(isOn ? 0.8 : 0.4).cgColor)
            context.setLineWidth(0.8 * scaleFactor)
            let boxPath = CGPath(roundedRect: scaledR.insetBy(dx: 1, dy: 1),
                                 cornerWidth: 2 * scaleFactor, cornerHeight: 2 * scaleFactor, transform: nil)
            context.addPath(boxPath)
            context.strokePath()
            context.restoreGState()
        }
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let str = NSAttributedString(string: labelText, attributes: attrs)
        let size = str.size()
        let origin = NSPoint(
            x: scaledR.midX - size.width / 2,
            y: scaledR.midY - size.height / 2
        )
        
        if isOn && skin.config.glow.enabled {
            drawTextWithGlow(str, at: origin, glowColor: onColor, context: context)
        } else {
            str.draw(at: origin)
        }
    }
    
    /// Draw a text label
    func drawLabel(_ text: String, in rect: NSRect, font: NSFont? = nil,
                   color: NSColor? = nil, alignment: NSTextAlignment = .left,
                   context: CGContext) {
        let scaledR = scaledRect(rect)
        let drawFont = font ?? skin.smallLabelFont()
        let drawColor = color ?? skin.textDimColor
        
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: drawFont,
            .foregroundColor: drawColor,
            .paragraphStyle: style
        ]
        
        let str = NSAttributedString(string: text, attributes: attrs)
        str.draw(in: scaledR)
    }
    
    /// Draw a text label with glow effect
    func drawLabelWithGlow(_ text: String, in rect: NSRect, font: NSFont? = nil,
                           color: NSColor? = nil, alignment: NSTextAlignment = .left,
                           context: CGContext) {
        let scaledR = scaledRect(rect)
        let drawFont = font ?? skin.smallLabelFont()
        let drawColor = color ?? skin.textColor
        
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: drawFont,
            .foregroundColor: drawColor,
            .paragraphStyle: style
        ]
        
        let str = NSAttributedString(string: text, attributes: attrs)
        
        // Draw with glow
        context.saveGState()
        context.setShadow(offset: .zero, blur: 3 * scaleFactor * glowMultiplier,
                          color: drawColor.withAlphaComponent(0.7).cgColor)
        str.draw(in: scaledR)
        context.restoreGState()
        str.draw(in: scaledR)
    }
    
    /// Draw a window control button (close, minimize, shade)
    func drawWindowControlButton(_ id: String, state: String, in rect: NSRect, context: CGContext) {
        let scaledR = scaledRect(rect)
        
        if let img = skin.image(for: id, state: state) {
            drawImage(img, in: scaledR, context: context)
            return
        }
        
        // Fallback: small outlined icons
        let isPressed = state == "pressed"
        let color = isPressed ? skin.textColor : skin.textDimColor
        
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.0 * scaleFactor)
        
        let inset = scaledR.insetBy(dx: 2 * scaleFactor, dy: 2 * scaleFactor)
        
        switch id {
        case "btn_close", "spectrum_btn_close", "playlist_btn_close", "eq_btn_close", "library_btn_close", "projectm_btn_close":
            // X shape
            context.move(to: CGPoint(x: inset.minX, y: inset.minY))
            context.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            context.move(to: CGPoint(x: inset.maxX, y: inset.minY))
            context.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
            context.strokePath()
            
        case "btn_minimize":
            // Dash
            context.move(to: CGPoint(x: inset.minX, y: inset.midY))
            context.addLine(to: CGPoint(x: inset.maxX, y: inset.midY))
            context.strokePath()
            
        case "btn_shade", "playlist_btn_shade", "eq_btn_shade", "library_btn_shade":
            // Small square
            context.stroke(inset)
            
        default:
            break
        }
        
        context.restoreGState()
    }
    
    /// Draw the mini spectrum bars
    func drawMiniSpectrum(_ levels: [Float], in rect: NSRect, context: CGContext) {
        let scaledR = scaledRect(rect)
        let barCount = min(levels.count, 8)
        guard barCount > 0 else { return }
        
        // Recessed panel background behind the bars
        drawInsetPanelScaled(scaledR, context: context)
        
        let barWidth = scaledR.width / CGFloat(barCount) - 1 * scaleFactor
        let gap = 1 * scaleFactor
        
        context.saveGState()
        
        for i in 0..<barCount {
            let level = CGFloat(min(max(levels[i], 0), 1))
            let barHeight = scaledR.height * level
            let x = scaledR.minX + CGFloat(i) * (barWidth + gap)
            let barRect = NSRect(x: x, y: scaledR.minY, width: barWidth, height: barHeight)
            
            // Gradient from accent (bottom) to primary (top)
            context.saveGState()
            context.clip(to: barRect)
            let colors = [skin.accentColor.cgColor, skin.primaryColor.cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                context.drawLinearGradient(grad,
                                          start: CGPoint(x: barRect.midX, y: barRect.minY),
                                          end: CGPoint(x: barRect.midX, y: scaledR.maxY),
                                          options: [])
            }
            context.restoreGState()
        }
        
        context.restoreGState()
    }
    
    /// Draw a status indicator (play/pause/stop triangle/icon)
    func drawStatusIndicator(_ state: PlaybackState, in rect: NSRect, context: CGContext) {
        let scaledR = scaledRect(rect)
        
        let imageId: String
        switch state {
        case .playing: imageId = "status_play"
        case .paused: imageId = "status_pause"
        case .stopped: imageId = "status_stop"
        }
        
        if let img = skin.image(for: imageId) {
            drawImage(img, in: scaledR, context: context)
            return
        }
        
        // Fallback: small icon
        context.saveGState()
        context.setFillColor(skin.primaryColor.cgColor)
        
        if skin.config.glow.enabled {
            context.setShadow(offset: .zero, blur: 3 * scaleFactor * glowMultiplier,
                              color: skin.primaryColor.withAlphaComponent(0.6).cgColor)
        }
        
        let inset = scaledR.insetBy(dx: 2 * scaleFactor, dy: 2 * scaleFactor)
        
        switch state {
        case .playing:
            // Triangle pointing right
            context.move(to: CGPoint(x: inset.minX, y: inset.minY))
            context.addLine(to: CGPoint(x: inset.maxX, y: inset.midY))
            context.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
            context.closePath()
            context.fillPath()
            
        case .paused:
            // Two vertical bars
            let barW = inset.width * 0.3
            context.fill(NSRect(x: inset.minX, y: inset.minY, width: barW, height: inset.height))
            context.fill(NSRect(x: inset.maxX - barW, y: inset.minY, width: barW, height: inset.height))
            
        case .stopped:
            // Square
            context.fill(inset)
        }
        
        context.restoreGState()
    }
    
    /// Draw playlist bottom bar with ADD/REM/SEL/MISC/LIST buttons
    func drawPlaylistBottomBar(in rect: NSRect, pressedButton: String?, context: CGContext) {
        let barHeight = rect.height
        let barY = rect.minY
        
        // Background fill
        context.saveGState()
        context.setFillColor(skin.surfaceColor.withAlphaComponent(0.6).cgColor)
        context.fill(rect)
        
        // Separator line at top
        if skin.config.glow.enabled {
            context.setShadow(offset: .zero, blur: 4 * scaleFactor * glowMultiplier,
                              color: skin.borderColor.withAlphaComponent(0.4).cgColor)
        }
        context.setStrokeColor(skin.borderColor.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(0.5 * scaleFactor)
        context.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY))
        context.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY))
        context.strokePath()
        context.restoreGState()
        
        // Button layout: ADD REM SEL on left, MISC LIST on right
        let font = skin.smallLabelFont()
        let buttons: [(String, CGFloat, CGFloat)] = [
            ("ADD", rect.minX + 4 * scaleFactor, 30 * scaleFactor),
            ("REM", rect.minX + 36 * scaleFactor, 30 * scaleFactor),
            ("SEL", rect.minX + 68 * scaleFactor, 30 * scaleFactor),
            ("MISC", rect.maxX - 64 * scaleFactor, 30 * scaleFactor),
            ("LIST", rect.maxX - 32 * scaleFactor, 30 * scaleFactor),
        ]
        
        for (label, x, width) in buttons {
            let buttonId = "playlist_btn_\(label.lowercased())"
            let isPressed = pressedButton == buttonId
            let color = isPressed ? skin.primaryColor : skin.textDimColor
            
            let buttonRect = NSRect(x: x, y: barY + 2 * scaleFactor,
                                    width: width, height: barHeight - 4 * scaleFactor)
            
            // Outlined box
            context.saveGState()
            context.setStrokeColor(color.withAlphaComponent(isPressed ? 0.8 : 0.4).cgColor)
            context.setLineWidth(0.8 * scaleFactor)
            let boxPath = CGPath(roundedRect: buttonRect,
                                 cornerWidth: 2 * scaleFactor, cornerHeight: 2 * scaleFactor, transform: nil)
            context.addPath(boxPath)
            context.strokePath()
            context.restoreGState()
            
            // Text label
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let size = str.size()
            let textOrigin = NSPoint(
                x: buttonRect.midX - size.width / 2,
                y: buttonRect.midY - size.height / 2
            )
            str.draw(at: textOrigin)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Scale a rect by the scale factor
    func scaledRect(_ rect: NSRect) -> NSRect {
        NSRect(x: rect.origin.x * scaleFactor,
               y: rect.origin.y * scaleFactor,
               width: rect.size.width * scaleFactor,
               height: rect.size.height * scaleFactor)
    }
    
    /// Draw an NSImage into a CGContext
    private func drawImage(_ image: NSImage, in rect: NSRect, context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }
    
    /// Draw a pixel-art NSImage with nearest-neighbor interpolation (no smoothing).
    /// Used for character sprites and other small pixel-art assets that should stay crisp when scaled.
    private func drawPixelArtImage(_ image: NSImage, in rect: NSRect, context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }
    
    /// Draw text with a glow/shadow effect
    private func drawTextWithGlow(_ attributedString: NSAttributedString, at point: NSPoint,
                                   glowColor: NSColor, context: CGContext) {
        // Draw glow layer
        context.saveGState()
        context.setShadow(offset: .zero, blur: 4 * scaleFactor * glowMultiplier,
                          color: glowColor.withAlphaComponent(0.6).cgColor)
        attributedString.draw(at: point)
        context.restoreGState()
        
        // Draw crisp text on top
        attributedString.draw(at: point)
    }
    
    // MARK: - Shared Panel Drawing
    
    /// Draw a subtle recessed inset panel — dark fill with faint border.
    /// Accepts base (unscaled) coordinates. Used for the time display and spectrum area.
    func drawInsetPanel(in rect: NSRect, context: CGContext) {
        drawInsetPanelScaled(scaledRect(rect), context: context)
    }
    
    /// Same as drawInsetPanel but accepts an already-scaled rect (used from drawFallback).
    private func drawInsetPanelScaled(_ scaledR: NSRect, context: CGContext) {
        context.saveGState()
        let corner = 2 * scaleFactor
        let path = CGPath(roundedRect: scaledR, cornerWidth: corner, cornerHeight: corner, transform: nil)
        context.setFillColor(skin.surfaceColor.withAlphaComponent(0.8).cgColor)
        context.addPath(path)
        context.fillPath()
        context.setStrokeColor(skin.borderColor.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(0.5 * scaleFactor)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }
    
    // MARK: - Programmatic Fallback Drawing
    
    private func drawFallback(_ id: String, state: String, in rect: NSRect, context: CGContext) {
        // Default fallback: filled rect with surface color and optional border
        switch id {
        case "marquee_bg":
            drawInsetPanelScaled(rect, context: context)
            
        case _ where id.hasPrefix("btn_"):
            // Already handled by specific draw methods
            break
            
        default:
            // Generic element fallback
            break
        }
    }
    
    // MARK: - Transport Icon Drawing (Fallback)
    
    private func drawPrevIcon(in rect: NSRect, context: CGContext) {
        // |<< icon
        let barX = rect.minX
        let barW: CGFloat = 1.2 * scaleFactor
        context.setFillColor(skin.primaryColor.cgColor)
        context.fill(NSRect(x: barX, y: rect.minY, width: barW, height: rect.height))
        
        let triW = (rect.width - barW) / 2
        let triStart = rect.minX + barW + 1
        context.move(to: CGPoint(x: triStart + triW, y: rect.minY))
        context.addLine(to: CGPoint(x: triStart, y: rect.midY))
        context.addLine(to: CGPoint(x: triStart + triW, y: rect.maxY))
        context.strokePath()
        
        context.move(to: CGPoint(x: triStart + triW * 2, y: rect.minY))
        context.addLine(to: CGPoint(x: triStart + triW, y: rect.midY))
        context.addLine(to: CGPoint(x: triStart + triW * 2, y: rect.maxY))
        context.strokePath()
    }
    
    private func drawPlayIcon(in rect: NSRect, context: CGContext) {
        context.move(to: CGPoint(x: rect.minX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        context.closePath()
        context.strokePath()
    }
    
    private func drawPauseIcon(in rect: NSRect, context: CGContext) {
        let barW = rect.width * 0.3
        let gap = rect.width * 0.15
        let leftX = rect.midX - gap - barW
        let rightX = rect.midX + gap
        context.stroke(NSRect(x: leftX, y: rect.minY, width: barW, height: rect.height))
        context.stroke(NSRect(x: rightX, y: rect.minY, width: barW, height: rect.height))
    }
    
    private func drawStopIcon(in rect: NSRect, context: CGContext) {
        let inset = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)
        context.stroke(inset)
    }
    
    private func drawNextIcon(in rect: NSRect, context: CGContext) {
        // >>| icon
        let barX = rect.maxX - 1.2 * scaleFactor
        let barW: CGFloat = 1.2 * scaleFactor
        context.setFillColor(skin.primaryColor.cgColor)
        context.fill(NSRect(x: barX, y: rect.minY, width: barW, height: rect.height))
        
        let triW = (rect.width - barW - 1) / 2
        context.move(to: CGPoint(x: rect.minX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.minX + triW, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        context.strokePath()
        
        context.move(to: CGPoint(x: rect.minX + triW, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.minX + triW * 2, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.minX + triW, y: rect.maxY))
        context.strokePath()
    }
    
    private func drawEjectIcon(in rect: NSRect, context: CGContext) {
        // Triangle above a line
        let lineY = rect.minY
        let lineH: CGFloat = 1.2 * scaleFactor
        context.setFillColor(skin.primaryColor.cgColor)
        context.fill(NSRect(x: rect.minX, y: lineY, width: rect.width, height: lineH))
        
        let triBottom = lineY + lineH + 2 * scaleFactor
        context.move(to: CGPoint(x: rect.minX, y: triBottom))
        context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        context.addLine(to: CGPoint(x: rect.maxX, y: triBottom))
        context.closePath()
        context.strokePath()
    }
}
