import AppKit
import CoreImage

// =============================================================================
// SKIN RENDERER - Drawing code for all skin elements
// =============================================================================
// For comprehensive documentation on Winamp skin format, sprite coordinates,
// and implementation notes, see: AGENT_DOCS/SKIN_FORMAT_RESEARCH.md
//
// Primary external reference for coordinates:
// https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts
// =============================================================================

/// Handles pixel-perfect rendering of Winamp skin sprites
/// Renders to an offscreen 1x buffer and scales for Retina displays
class SkinRenderer {
    
    // MARK: - Properties
    
    /// The skin to render
    let skin: Skin
    
    /// Scale factor for Retina displays (renders at 1x then scales)
    var scaleFactor: CGFloat = 2.0

    private let plexTitleText = "WINAMP LIBRARY"
    
    /// Cached white-tinted version of the text font image
    private var _whiteTextImage: NSImage?
    
    /// Lazily creates and caches a white-tinted version of the skin's text image
    private var whiteTextImage: NSImage? {
        if _whiteTextImage == nil {
            _whiteTextImage = createWhiteTextImage()
        }
        return _whiteTextImage
    }
    
    // MARK: - Initialization
    
    init(skin: Skin) {
        self.skin = skin
    }
    
    // MARK: - Pixel Alignment Helpers
    
    // MARK: - Main Window Rendering
    
    /// Draw the complete main window background
    func drawMainWindowBackground(in context: CGContext, bounds: NSRect, isActive: Bool) {
        if let mainImage = skin.main {
            // Draw main background from skin
            drawImage(mainImage, in: bounds, context: context)
        } else {
            // Draw fallback background
            drawFallbackMainBackground(in: context, bounds: bounds, isActive: isActive)
        }
        
        // Draw title bar
        drawTitleBar(in: context, bounds: bounds, isActive: isActive)
    }
    
    /// Draw title bar (from titlebar.bmp)
    func drawTitleBar(in context: CGContext, bounds: NSRect, isActive: Bool) {
        guard let titlebarImage = skin.titlebar else {
            // Fallback title bar handled by drawFallbackMainBackground
            return
        }
        
        let sourceRect = isActive ? SkinElements.TitleBar.active : SkinElements.TitleBar.inactive
        let destRect = NSRect(x: 0, y: 0,
                              width: bounds.width, height: SkinElements.titleBarHeight)
        
        drawSprite(from: titlebarImage, sourceRect: sourceRect, to: destRect, in: context)
    }
    
    // MARK: - Button Rendering
    
    /// Draw a transport button
    func drawButton(_ button: ButtonType, state: ButtonState, at position: NSRect, in context: CGContext) {
        // Get the appropriate sprite sheet
        let spriteSheet: NSImage?
        switch button {
        case .previous, .play, .pause, .stop, .next, .eject:
            spriteSheet = skin.cbuttons
        case .close, .minimize, .shade, .unshade:
            spriteSheet = skin.titlebar
        case .shuffle, .repeatTrack, .eqToggle, .playlistToggle:
            spriteSheet = skin.shufrep
        case .eqOnOff, .eqAuto, .eqPresets:
            spriteSheet = skin.eqmain
        default:
            spriteSheet = nil
        }
        
        guard let image = spriteSheet else {
            // Draw fallback button
            drawFallbackButton(button, state: state, at: position, in: context)
            return
        }
        
        let sourceRect = SkinElements.spriteRect(for: button, state: state)
        drawSprite(from: image, sourceRect: sourceRect, to: position, in: context)
    }
    
    /// Draw all transport buttons
    func drawTransportButtons(in context: CGContext, pressedButton: ButtonType?, playbackState: PlaybackState) {
        let buttons: [(ButtonType, NSRect)] = [
            (.previous, SkinElements.Transport.Positions.previous),
            (.play, SkinElements.Transport.Positions.play),
            (.pause, SkinElements.Transport.Positions.pause),
            (.stop, SkinElements.Transport.Positions.stop),
            (.next, SkinElements.Transport.Positions.next),
            (.eject, SkinElements.Transport.Positions.eject)
        ]
        
        for (button, position) in buttons {
            let state: ButtonState = (pressedButton == button) ? .pressed : .normal
            drawButton(button, state: state, at: position, in: context)
        }
    }
    
    /// Draw window control buttons (minimize, shade, close)
    func drawWindowControls(in context: CGContext, bounds: NSRect, pressedButton: ButtonType?) {
        let controls: [(ButtonType, NSRect)] = [
            (.minimize, SkinElements.TitleBar.Positions.minimizeButton),
            (.shade, SkinElements.TitleBar.Positions.shadeButton),
            (.close, SkinElements.TitleBar.Positions.closeButton)
        ]
        
        for (button, position) in controls {
            let state: ButtonState = (pressedButton == button) ? .pressed : .normal
            drawButton(button, state: state, at: position, in: context)
        }
    }
    
    /// Draw shuffle/repeat and EQ/PL toggle buttons
    func drawToggleButtons(in context: CGContext, shuffleOn: Bool, repeatOn: Bool, 
                           eqVisible: Bool, playlistVisible: Bool, pressedButton: ButtonType?) {
        // Shuffle button
        let shuffleState: ButtonState
        if pressedButton == .shuffle {
            shuffleState = shuffleOn ? .activePressed : .pressed
        } else {
            shuffleState = shuffleOn ? .active : .normal
        }
        drawButton(.shuffle, state: shuffleState, at: SkinElements.ShuffleRepeat.Positions.shuffle, in: context)
        
        // Repeat button
        let repeatState: ButtonState
        if pressedButton == .repeatTrack {
            repeatState = repeatOn ? .activePressed : .pressed
        } else {
            repeatState = repeatOn ? .active : .normal
        }
        drawButton(.repeatTrack, state: repeatState, at: SkinElements.ShuffleRepeat.Positions.repeatBtn, in: context)
        
        // EQ toggle button
        let eqState: ButtonState
        if pressedButton == .eqToggle {
            eqState = eqVisible ? .activePressed : .pressed
        } else {
            eqState = eqVisible ? .active : .normal
        }
        drawButton(.eqToggle, state: eqState, at: SkinElements.ShuffleRepeat.Positions.eqToggle, in: context)
        
        // Playlist toggle button
        let plState: ButtonState
        if pressedButton == .playlistToggle {
            plState = playlistVisible ? .activePressed : .pressed
        } else {
            plState = playlistVisible ? .active : .normal
        }
        drawButton(.playlistToggle, state: plState, at: SkinElements.ShuffleRepeat.Positions.plToggle, in: context)
    }
    
    // MARK: - Time Display
    
    /// Draw the time display (LED-style digits)
    /// - Parameters:
    ///   - minutes: Minutes value (0-99)
    ///   - seconds: Seconds value (0-59)
    ///   - isNegative: Whether to show minus sign (for remaining time mode)
    ///   - context: Graphics context to draw into
    func drawTimeDisplay(minutes: Int, seconds: Int, isNegative: Bool = false, in context: CGContext) {
        // Try numbers.bmp first, then fall back to nums_ex.bmp (same layout)
        guard let numbersImage = skin.numbers ?? skin.numsEx else {
            drawFallbackTimeDisplay(minutes: minutes, seconds: seconds, isNegative: isNegative, in: context)
            return
        }
        
        // Draw minus sign if negative (remaining time mode)
        if isNegative {
            let minusRect = SkinElements.Numbers.minus
            let minusPos = SkinElements.Numbers.Positions.minus
            drawSprite(from: numbersImage, sourceRect: minusRect,
                      to: NSRect(origin: minusPos, size: minusRect.size), in: context)
        }
        
        // Draw minutes tens digit
        let minTens = minutes / 10
        drawDigit(minTens, from: numbersImage, at: SkinElements.Numbers.Positions.minuteTens, in: context)
        
        // Draw minutes ones digit
        let minOnes = minutes % 10
        drawDigit(minOnes, from: numbersImage, at: SkinElements.Numbers.Positions.minuteOnes, in: context)
        
        // Draw seconds tens digit
        let secTens = seconds / 10
        drawDigit(secTens, from: numbersImage, at: SkinElements.Numbers.Positions.secondTens, in: context)
        
        // Draw seconds ones digit
        let secOnes = seconds % 10
        drawDigit(secOnes, from: numbersImage, at: SkinElements.Numbers.Positions.secondOnes, in: context)
    }
    
    private func drawDigit(_ digit: Int, from image: NSImage, at position: NSPoint, in context: CGContext) {
        let sourceRect = SkinElements.Numbers.digit(digit)
        let destRect = NSRect(origin: position, size: sourceRect.size)
        drawSprite(from: image, sourceRect: sourceRect, to: destRect, in: context)
    }
    
    // MARK: - Public Text/Digit Drawing Methods
    
    /// Sample the actual text color from the skin's text.bmp
    /// Samples a non-background pixel from the letter 'A' to get the true text color
    func skinTextColor() -> NSColor {
        guard let textImage = skin.text else {
            return NSColor(hex: "#00FF00") ?? .green
        }
        
        // Sample from the 'A' character in text.bmp (first char, offset a bit to hit actual text pixel)
        let charRect = SkinElements.TextFont.character("A")
        let samplePoint = NSPoint(x: charRect.minX + 3, y: charRect.minY + 2)
        
        if let color = samplePixelColor(in: textImage, at: samplePoint),
           color.alphaComponent > 0.5,
           // Make sure it's not magenta (transparency color)
           !(color.redComponent > 0.9 && color.greenComponent < 0.1 && color.blueComponent > 0.9) {
            return color
        }
        
        return NSColor(hex: "#00FF00") ?? .green
    }
    
    /// Draw text using the skin's text.bmp font at any position
    /// Returns the width of the drawn text
    @discardableResult
    func drawSkinText(_ text: String, at position: NSPoint, in context: CGContext) -> CGFloat {
        guard let textImage = skin.text else {
            // Fallback to system font
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.green,
                .font: NSFont.monospacedSystemFont(ofSize: 6, weight: .regular)
            ]
            text.draw(at: position, withAttributes: attrs)
            return CGFloat(text.count) * 5
        }
        
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        var xPos = position.x
        
        for char in text.uppercased() {
            let charRect = SkinElements.TextFont.character(char)
            let destRect = NSRect(x: xPos, y: position.y, width: charWidth, height: charHeight)
            drawSprite(from: textImage, sourceRect: charRect, to: destRect, in: context)
            xPos += charWidth
        }
        
        return CGFloat(text.count) * charWidth
    }
    
    /// Draw text in white using the skin's text.bmp font as a reference
    /// Renders each character to an offscreen buffer with direct pixel conversion, then draws the result
    @discardableResult
    func drawSkinTextWhite(_ text: String, at position: NSPoint, in context: CGContext) -> CGFloat {
        guard let textImage = skin.text,
              let cgTextImage = textImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.monospacedSystemFont(ofSize: 6, weight: .regular)
            ]
            text.draw(at: position, withAttributes: attrs)
            return CGFloat(text.count) * 5
        }
        
        let charWidth = Int(SkinElements.TextFont.charWidth)
        let charHeight = Int(SkinElements.TextFont.charHeight)
        var xPos = position.x
        
        for char in text.uppercased() {
            let charRect = SkinElements.TextFont.character(char)
            let destRect = NSRect(x: xPos, y: position.y, width: CGFloat(charWidth), height: CGFloat(charHeight))
            
            // Crop the character from the text image
            let cropRect = CGRect(x: charRect.origin.x, y: charRect.origin.y, 
                                  width: charRect.width, height: charRect.height)
            guard let charImage = cgTextImage.cropping(to: cropRect) else {
                xPos += CGFloat(charWidth)
                continue
            }
            
            // Create offscreen buffer and draw character
            guard let offscreenContext = CGContext(
                data: nil,
                width: charWidth,
                height: charHeight,
                bitsPerComponent: 8,
                bytesPerRow: charWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                xPos += CGFloat(charWidth)
                continue
            }
            
            offscreenContext.draw(charImage, in: CGRect(x: 0, y: 0, width: charWidth, height: charHeight))
            
            // Direct pixel conversion: green (0, G, 0) -> white (G, G, G)
            // This preserves the brightness while making it white
            guard let data = offscreenContext.data else {
                xPos += CGFloat(charWidth)
                continue
            }
            
            let pixels = data.bindMemory(to: UInt8.self, capacity: charWidth * charHeight * 4)
            for i in 0..<(charWidth * charHeight) {
                let offset = i * 4
                let r = pixels[offset]
                let g = pixels[offset + 1]
                let b = pixels[offset + 2]
                let a = pixels[offset + 3]
                
                // Skip fully transparent pixels
                if a == 0 { continue }
                
                // Use the green channel as brightness (text is green)
                // Also check if it's magenta background (skip those)
                let isMagenta = r > 200 && g < 50 && b > 200
                if isMagenta {
                    // Make magenta transparent
                    pixels[offset + 3] = 0
                } else {
                    // Convert green to white: use green value for all channels
                    let brightness = g
                    pixels[offset] = brightness     // R
                    pixels[offset + 1] = brightness // G
                    pixels[offset + 2] = brightness // B
                    // Keep alpha as-is
                }
            }
            
            // Get the converted image
            guard let whiteCharImage = offscreenContext.makeImage() else {
                xPos += CGFloat(charWidth)
                continue
            }
            
            // Draw to main context with proper flipping
            context.saveGState()
            context.translateBy(x: destRect.origin.x, y: destRect.origin.y + destRect.height)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .none
            context.draw(whiteCharImage, in: CGRect(x: 0, y: 0, width: destRect.width, height: destRect.height))
            context.restoreGState()
            
            xPos += CGFloat(charWidth)
        }
        
        return CGFloat(text.count * charWidth)
    }
    
    /// Creates a white-tinted version of the skin's text image
    /// Detects text pixels by checking if they're NOT magenta background, then makes them white
    private func createWhiteTextImage() -> NSImage? {
        guard let textImage = skin.text,
              let cgImage = textImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        
        // Create context to read pixel data
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        // Draw original image
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        // Debug: check first few pixels
        var textPixels = 0
        var bgPixels = 0
        
        // Convert pixels: if it's text (not background), make it white
        // Background is either transparent (alpha=0) or magenta-ish
        for i in 0..<(width * height) {
            let offset = i * 4
            let r = pixels[offset]
            let g = pixels[offset + 1]
            let b = pixels[offset + 2]
            let a = pixels[offset + 3]
            
            // Check if this is a text pixel (not transparent and not magenta)
            // Magenta is high R, low G, high B
            let isMagenta = r > 200 && g < 50 && b > 200
            let isTransparent = a == 0
            
            if !isTransparent && !isMagenta {
                // This is text - make it white
                pixels[offset] = 255     // R
                pixels[offset + 1] = 255 // G
                pixels[offset + 2] = 255 // B
                pixels[offset + 3] = 255 // A (fully opaque)
                textPixels += 1
            } else {
                // This is background - make it fully transparent
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
                bgPixels += 1
            }
        }
        
        FileHandle.standardError.write("createWhiteTextImage: \(width)x\(height), text pixels: \(textPixels), bg pixels: \(bgPixels)\n".data(using: .utf8)!)
        
        guard let newCGImage = context.makeImage() else { return nil }
        
        // Create NSImage with explicit size matching
        let newImage = NSImage(size: NSSize(width: width, height: height))
        newImage.addRepresentation(NSBitmapImageRep(cgImage: newCGImage))
        return newImage
    }
    
    /// Draw digits using the skin's numbers.bmp at any position
    /// Returns the width of the drawn digits
    @discardableResult
    func drawSkinDigits(_ number: Int, at position: NSPoint, in context: CGContext, minDigits: Int = 1) -> CGFloat {
        guard let numbersImage = skin.numbers ?? skin.numsEx else {
            // Fallback to system font
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.green,
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            ]
            let str = String(number)
            str.draw(at: position, withAttributes: attrs)
            return CGFloat(str.count) * 9
        }
        
        let digitWidth = SkinElements.Numbers.digitWidth
        let digitHeight = SkinElements.Numbers.digitHeight
        
        // Convert number to string with minimum digits
        let str = String(format: "%0\(minDigits)d", number)
        var xPos = position.x
        
        for char in str {
            let digit = Int(String(char)) ?? 0
            let sourceRect = SkinElements.Numbers.digit(digit)
            let destRect = NSRect(x: xPos, y: position.y, width: digitWidth, height: digitHeight)
            drawSprite(from: numbersImage, sourceRect: sourceRect, to: destRect, in: context)
            xPos += digitWidth
        }
        
        return CGFloat(str.count) * digitWidth
    }
    
    /// Draw time in MM:SS format using skin digits at any position
    /// Returns the total width drawn
    @discardableResult
    func drawSkinTime(minutes: Int, seconds: Int, at position: NSPoint, in context: CGContext) -> CGFloat {
        guard let numbersImage = skin.numbers ?? skin.numsEx, let textImage = skin.text else {
            // Fallback
            let str = String(format: "%d:%02d", minutes, seconds)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.green,
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            ]
            str.draw(at: position, withAttributes: attrs)
            return CGFloat(str.count) * 9
        }
        
        let digitWidth = SkinElements.Numbers.digitWidth
        let digitHeight = SkinElements.Numbers.digitHeight
        var xPos = position.x
        
        // Draw minutes (variable width)
        let minStr = String(minutes)
        for char in minStr {
            let digit = Int(String(char)) ?? 0
            let sourceRect = SkinElements.Numbers.digit(digit)
            let destRect = NSRect(x: xPos, y: position.y, width: digitWidth, height: digitHeight)
            drawSprite(from: numbersImage, sourceRect: sourceRect, to: destRect, in: context)
            xPos += digitWidth
        }
        
        // Draw colon using text font (centered vertically with digits)
        let colonRect = SkinElements.TextFont.character(":")
        let colonY = position.y + (digitHeight - SkinElements.TextFont.charHeight) / 2
        let colonDest = NSRect(x: xPos, y: colonY, 
                              width: SkinElements.TextFont.charWidth, 
                              height: SkinElements.TextFont.charHeight)
        drawSprite(from: textImage, sourceRect: colonRect, to: colonDest, in: context)
        xPos += SkinElements.TextFont.charWidth
        
        // Draw seconds (always 2 digits)
        let secStr = String(format: "%02d", seconds)
        for char in secStr {
            let digit = Int(String(char)) ?? 0
            let sourceRect = SkinElements.Numbers.digit(digit)
            let destRect = NSRect(x: xPos, y: position.y, width: digitWidth, height: digitHeight)
            drawSprite(from: numbersImage, sourceRect: sourceRect, to: destRect, in: context)
            xPos += digitWidth
        }
        
        return xPos - position.x
    }
    
    // MARK: - Marquee Text
    
    /// Check if text contains characters not supported by the skin bitmap font
    /// Skin font only supports: A-Z, 0-9, and some symbols
    private func containsNonLatinCharacters(_ text: String) -> Bool {
        for char in text {
            switch char {
            case "A"..."Z", "a"..."z", "0"..."9":
                continue
            case " ", "\"", "@", ":", "(", ")", "-", "'", "!", "_", "+", "\\", "/",
                 "[", "]", "^", "&", "%", ".", "=", "$", "#", "?", "*":
                continue
            default:
                return true  // Non-Latin or unsupported character
            }
        }
        return false
    }
    
    /// Draw scrolling marquee text with circular/seamless wrapping
    func drawMarquee(text: String, offset: CGFloat, in context: CGContext) {
        let marqueeRect = SkinElements.TextFont.Positions.marqueeArea
        
        // Clip to marquee area
        context.saveGState()
        context.clip(to: marqueeRect)
        
        // Check if we need system font fallback for non-Latin characters (Japanese, Cyrillic, etc.)
        let useSystemFont = skin.text == nil || containsNonLatinCharacters(text)
        
        if useSystemFont {
            // System font rendering - supports all Unicode characters
            // The context is flipped for Winamp skin rendering, so we need to unflip
            // temporarily for NSAttributedString.draw() to render correctly
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.green,
                .font: NSFont.systemFont(ofSize: 8, weight: .regular)
            ]
            let textSize = text.size(withAttributes: attrs)
            
            // Save and unflip the context for text drawing
            context.saveGState()
            
            // Unflip: the context was flipped with translateBy(0, height) + scaleBy(1, -1)
            // We need to reverse this for the marquee area
            let centerY = marqueeRect.midY
            context.translateBy(x: 0, y: centerY)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0, y: -centerY)
            
            // If text fits, just draw it
            if textSize.width <= marqueeRect.width {
                text.draw(at: NSPoint(x: marqueeRect.minX, y: marqueeRect.minY), withAttributes: attrs)
            } else {
                // Circular scrolling with system font
                let separator = "  -  "
                let fullText = text + separator
                let fullWidth = fullText.size(withAttributes: attrs).width
                let adjustedOffset = offset.truncatingRemainder(dividingBy: fullWidth)
                
                for pass in 0..<2 {
                    let xPos = marqueeRect.minX - adjustedOffset + (CGFloat(pass) * fullWidth)
                    fullText.draw(at: NSPoint(x: xPos, y: marqueeRect.minY), withAttributes: attrs)
                }
            }
            
            context.restoreGState()
        } else {
            // Skin bitmap font rendering - Latin characters only
            let charWidth = SkinElements.TextFont.charWidth
            let textWidth = CGFloat(text.count) * charWidth
            let textImage = skin.text!
            
            // If text fits in marquee, just draw it (no scrolling needed)
            if textWidth <= marqueeRect.width {
                var xPos = marqueeRect.minX
                let yPos = marqueeRect.minY + (marqueeRect.height - SkinElements.TextFont.charHeight) / 2
                
                for char in text.uppercased() {
                    let charRect = SkinElements.TextFont.character(char)
                    let destRect = NSRect(x: xPos, y: yPos,
                                         width: charWidth,
                                         height: SkinElements.TextFont.charHeight)
                    drawSprite(from: textImage, sourceRect: charRect, to: destRect, in: context)
                    xPos += charWidth
                }
            } else {
                // Circular scrolling: draw text twice with separator for seamless wrap
                let separator = "  -  "
                let separatorWidth = CGFloat(separator.count) * charWidth
                let totalWidth = textWidth + separatorWidth
                let yPos = marqueeRect.minY + (marqueeRect.height - SkinElements.TextFont.charHeight) / 2
                
                for pass in 0..<2 {
                    var xPos = marqueeRect.minX - offset + (CGFloat(pass) * totalWidth)
                    
                    // Draw main text
                    for char in text.uppercased() {
                        if xPos + charWidth > marqueeRect.minX && xPos < marqueeRect.maxX {
                            let charRect = SkinElements.TextFont.character(char)
                            let destRect = NSRect(x: xPos, y: yPos, width: charWidth, height: SkinElements.TextFont.charHeight)
                            drawSprite(from: textImage, sourceRect: charRect, to: destRect, in: context)
                        }
                        xPos += charWidth
                    }
                    
                    // Draw separator
                    for char in separator.uppercased() {
                        if xPos + charWidth > marqueeRect.minX && xPos < marqueeRect.maxX {
                            let charRect = SkinElements.TextFont.character(char)
                            let destRect = NSRect(x: xPos, y: yPos, width: charWidth, height: SkinElements.TextFont.charHeight)
                            drawSprite(from: textImage, sourceRect: charRect, to: destRect, in: context)
                        }
                        xPos += charWidth
                    }
                }
            }
        }
        
        context.restoreGState()
    }
    
    // MARK: - Visualization
    
    /// Draw spectrum analyzer visualization
    /// - Parameters:
    ///   - levels: Array of frequency levels (0-1), typically 75 bands from FFT
    ///   - context: Graphics context to draw into
    func drawSpectrumAnalyzer(levels: [Float], in context: CGContext) {
        let displayArea = SkinElements.Visualization.displayArea
        let barCount = SkinElements.Visualization.barCount
        let barWidth = SkinElements.Visualization.barWidth
        let barSpacing = SkinElements.Visualization.barSpacing
        let maxHeight = displayArea.height
        
        // Get visualization colors from skin (24 colors, 0=darkest, 23=brightest)
        let colors = skin.visColors
        guard !colors.isEmpty else { return }
        
        // Calculate the bottom Y position (in Winamp coords where Y increases downward)
        // The bars grow upward from the bottom of the display area
        let bottomY = displayArea.minY + displayArea.height
        
        // Map input levels (75 bands) to display bars (19 bars)
        let mappedLevels: [Float]
        if levels.isEmpty {
            // No audio - show flat/empty bars
            mappedLevels = Array(repeating: 0, count: barCount)
        } else if levels.count >= barCount {
            // Average multiple FFT bands into each display bar
            let bandsPerBar = levels.count / barCount
            mappedLevels = (0..<barCount).map { barIndex in
                let start = barIndex * bandsPerBar
                let end = min(start + bandsPerBar, levels.count)
                let slice = levels[start..<end]
                return slice.reduce(0, +) / Float(slice.count)
            }
        } else {
            // Fewer levels than bars - interpolate
            mappedLevels = (0..<barCount).map { barIndex in
                let sourceIndex = Float(barIndex) * Float(levels.count - 1) / Float(barCount - 1)
                let lowerIndex = Int(sourceIndex)
                let upperIndex = min(lowerIndex + 1, levels.count - 1)
                let fraction = sourceIndex - Float(lowerIndex)
                return levels[lowerIndex] * (1 - fraction) + levels[upperIndex] * fraction
            }
        }
        
        // Draw each bar
        for (barIndex, level) in mappedLevels.enumerated() {
            let barX = displayArea.minX + CGFloat(barIndex) * (barWidth + barSpacing)
            
            // Calculate bar height (0-16 pixels based on level)
            // Level is already 0-1 from audio processing with frequency weighting
            let barHeight = Int(level * Float(maxHeight))
            
            guard barHeight > 0 else { continue }
            
            // Draw bar pixel by pixel from bottom to top
            // Each row gets progressively brighter color
            for row in 0..<barHeight {
                // Map row position to color index
                // row 0 is bottom (darkest), row barHeight-1 is top (brightest)
                // Use the bar height to determine which colors to use from the palette
                let colorIndex: Int
                if barHeight <= 1 {
                    colorIndex = 0
                } else {
                    // Scale row position to color palette (24 colors for 16 pixel max height)
                    let rowFraction = Float(row) / Float(maxHeight - 1)
                    colorIndex = min(colors.count - 1, Int(rowFraction * Float(colors.count - 1)))
                }
                
                let color = colors[colorIndex]
                color.setFill()
                
                // Draw pixel row - Y position counts from bottom up
                let pixelY = bottomY - CGFloat(row + 1)
                let pixelRect = NSRect(x: barX, y: pixelY, width: barWidth, height: 1)
                context.fill(pixelRect)
            }
        }
    }
    
    // MARK: - Status Indicators
    
    /// Draw playback status indicator (play/pause/stop)
    func drawPlaybackStatus(_ state: PlaybackState, in context: CGContext) {
        guard let playpausImage = skin.playpaus else {
            drawFallbackPlaybackStatus(state, in: context)
            return
        }
        
        let sourceRect: NSRect
        switch state {
        case .playing:
            sourceRect = SkinElements.PlayStatus.play
        case .paused:
            sourceRect = SkinElements.PlayStatus.pause
        case .stopped:
            sourceRect = SkinElements.PlayStatus.stop
        }
        
        let position = SkinElements.PlayStatus.Positions.status
        let destRect = NSRect(origin: position, size: sourceRect.size)
        drawSprite(from: playpausImage, sourceRect: sourceRect, to: destRect, in: context)
    }
    
    /// Draw stereo and cast indicators
    /// - Parameters:
    ///   - isStereo: Whether the audio is stereo (2+ channels)
    ///   - isCasting: Whether casting is currently active
    ///   - context: Graphics context to draw into
    func drawStereoAndCast(isStereo: Bool, isCasting: Bool, in context: CGContext) {
        guard let monosterImage = skin.monoster else { return }
        
        // Draw stereo indicator
        let stereoRect = isStereo ? SkinElements.MonoStereo.stereoOn : SkinElements.MonoStereo.stereoOff
        let stereoPos = SkinElements.MonoStereo.Positions.stereo
        drawSprite(from: monosterImage, sourceRect: stereoRect,
                  to: NSRect(origin: stereoPos, size: stereoRect.size), in: context)
        
        // Draw "CAST" indicator in place of mono
        // Using skin text font for consistent look
        drawCastIndicator(isActive: isCasting, in: context)
    }
    
    /// Cached cast indicator sprite (generated once)
    private static var castIndicatorSprite: NSImage?
    
    /// Generate or return cached cast indicator sprite
    /// Creates a 27x24 image with "cast" text:
    /// - Top 12 rows: lit/active state (green)
    /// - Bottom 12 rows: dim/inactive state (gray)
    private func getCastIndicatorSprite() -> NSImage {
        if let cached = SkinRenderer.castIndicatorSprite {
            return cached
        }
        
        let width = 27
        let height = 24  // 12 for on, 12 for off
        
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        
        // Clear background (transparent)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        
        // Main letter pixels for "cast" - core bright pixels
        let castPixels: [(Int, Int)] = [
            // 'c' - small open curve
            (5,5), (6,5),
            (4,6),
            (5,7), (6,7),
            
            // 'a' - small rounded
            (9,5), (10,5),
            (8,6), (11,6),
            (9,7), (10,7), (11,7),
            
            // 's' - small snake  
            (14,5), (15,5),
            (14,6),
            (13,7), (14,7),
            
            // 't' - small with crossbar
            (18,4),
            (17,5), (18,5), (19,5),
            (18,6),
            (18,7),
        ]
        
        // Glow pixels surrounding the letters (dimmer green for glow effect)
        let glowPixels: [(Int, Int)] = [
            // 'c' glow
            (4,4), (5,4), (6,4), (7,4),
            (3,5), (7,5),
            (3,6), (5,6), (6,6), (7,6),
            (3,7), (7,7),
            (4,8), (5,8), (6,8), (7,8),
            
            // 'a' glow
            (8,4), (9,4), (10,4), (11,4), (12,4),
            (7,5), (12,5),
            (7,6), (9,6), (10,6), (12,6),
            (7,7), (12,7),
            (8,8), (9,8), (10,8), (11,8), (12,8),
            
            // 's' glow
            (12,4), (13,4), (14,4), (15,4), (16,4),
            (12,5), (16,5),
            (12,6), (13,6), (15,6), (16,6),
            (12,7), (15,7), (16,7),
            (12,8), (13,8), (14,8), (15,8), (16,8),
            
            // 't' glow
            (17,3), (18,3), (19,3),
            (16,4), (19,4), (20,4),
            (16,5), (20,5),
            (16,6), (17,6), (19,6), (20,6),
            (16,7), (17,7), (19,7), (20,7),
            (17,8), (18,8), (19,8),
        ]
        
        // Colors for the glowing effect
        let activeColor = NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)  // Pure bright green
        let glowColor = NSColor(red: 0.0, green: 0.6, blue: 0.0, alpha: 1.0)  // Dimmer green for glow
        let inactiveColor = NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.35, alpha: 1.0)  // Neutral gray
        
        // Draw active/ON state in bottom half (NSImage y=0-11)
        // Draw glow first (underneath), then main pixels on top
        glowColor.setFill()
        for (px, py) in glowPixels {
            let nsY = 11 - py
            NSRect(x: px, y: nsY, width: 1, height: 1).fill()
        }
        activeColor.setFill()
        for (px, py) in castPixels {
            let nsY = 11 - py
            NSRect(x: px, y: nsY, width: 1, height: 1).fill()
        }
        
        // Draw inactive/OFF state in top half (NSImage y=12-23)
        // No glow for inactive - just flat gray letters
        inactiveColor.setFill()
        for (px, py) in castPixels {
            let nsY = 23 - py
            NSRect(x: px, y: nsY, width: 1, height: 1).fill()
        }
        
        image.unlockFocus()
        SkinRenderer.castIndicatorSprite = image
        return image
    }
    
    /// Draw the cast indicator using a generated sprite
    /// - Parameters:
    ///   - isActive: Whether casting is currently active (lit up)
    ///   - context: Graphics context to draw into
    private func drawCastIndicator(isActive: Bool, in context: CGContext) {
        let castSprite = getCastIndicatorSprite()
        let monoPos = SkinElements.MonoStereo.Positions.mono
        
        // Source rect selection accounts for drawSprite's y-flip conversion
        // y=0 in source maps to top half of NSImage (gray), y=12 maps to bottom (green)
        let sourceRect = isActive ?
            NSRect(x: 0, y: 12, width: 27, height: 12) :
            NSRect(x: 0, y: 0, width: 27, height: 12)
        
        let destRect = NSRect(origin: monoPos, size: NSSize(width: 27, height: 12))
        
        drawSprite(from: castSprite, sourceRect: sourceRect, to: destRect, in: context)
    }
    
    /// Legacy method for backward compatibility - now calls drawStereoAndCast
    func drawMonoStereo(isStereo: Bool, in context: CGContext) {
        // Call the new method with casting state from CastManager
        let isCasting = CastManager.shared.isCasting
        drawStereoAndCast(isStereo: isStereo, isCasting: isCasting, in: context)
    }
    
    /// Draw bitrate display (e.g., "128" kbps)
    /// - Parameters:
    ///   - bitrate: Bitrate value in kbps (or bps if > 10000)
    ///   - scrollOffset: Scroll offset for values > 3 digits
    ///   - context: Graphics context
    func drawBitrate(_ bitrate: Int?, scrollOffset: CGFloat = 0, in context: CGContext) {
        let displayText: String
        if let bitrate = bitrate {
            // Show bitrate in kbps (divide by 1000 if it's in bps)
            let kbps = bitrate > 10000 ? bitrate / 1000 : bitrate
            displayText = "\(kbps)"
        } else {
            displayText = ""
        }
        
        let rect = SkinElements.InfoDisplay.Positions.bitrate
        let maxChars = 3  // Display fits 3 characters
        
        if displayText.count > maxChars {
            // Scroll if more than 3 digits
            drawScrollingSmallText(displayText, at: rect, scrollOffset: scrollOffset, in: context)
        } else {
            drawSmallText(displayText, at: rect, in: context)
        }
    }
    
    /// Draw sample rate display (e.g., "44" kHz)
    func drawSampleRate(_ sampleRate: Int?, in context: CGContext) {
        let displayText: String
        if let sampleRate = sampleRate {
            // Show sample rate in kHz (divide by 1000)
            let khz = sampleRate / 1000
            displayText = "\(khz)"
        } else {
            displayText = ""
        }
        
        drawSmallText(displayText, at: SkinElements.InfoDisplay.Positions.sampleRate, in: context)
    }
    
    /// Draw small text using the skin font (for bitrate/sample rate displays)
    private func drawSmallText(_ text: String, at rect: NSRect, in context: CGContext) {
        guard !text.isEmpty else { return }
        
        if let textImage = skin.text {
            // Draw each character from skin font
            var xPos = rect.minX
            let yPos = rect.minY + (rect.height - SkinElements.TextFont.charHeight) / 2
            
            for char in text.uppercased() {
                let charRect = SkinElements.TextFont.character(char)
                let destRect = NSRect(x: xPos, y: yPos,
                                     width: SkinElements.TextFont.charWidth,
                                     height: SkinElements.TextFont.charHeight)
                
                drawSprite(from: textImage, sourceRect: charRect, to: destRect, in: context)
                xPos += SkinElements.TextFont.charWidth
            }
        } else {
            // Fallback text rendering
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.green,
                .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .regular)
            ]
            text.draw(at: NSPoint(x: rect.minX, y: rect.minY), withAttributes: attrs)
        }
    }
    
    /// Draw scrolling small text with circular wrap (for long bitrate values)
    private func drawScrollingSmallText(_ text: String, at rect: NSRect, scrollOffset: CGFloat, in context: CGContext) {
        guard !text.isEmpty else { return }
        
        // Clip to display area
        context.saveGState()
        context.clip(to: rect)
        
        let charWidth = SkinElements.TextFont.charWidth
        let textWidth = CGFloat(text.count) * charWidth
        let spacing: CGFloat = charWidth * 2  // Gap between repeated text
        let totalWidth = textWidth + spacing  // Total width of one cycle
        
        if let textImage = skin.text {
            let yPos = rect.minY + (rect.height - SkinElements.TextFont.charHeight) / 2
            
            // Draw text twice for seamless circular scroll
            for pass in 0..<2 {
                var xPos = rect.minX - scrollOffset + (CGFloat(pass) * totalWidth)
                
                for char in text.uppercased() {
                    let charRect = SkinElements.TextFont.character(char)
                    let destRect = NSRect(x: xPos, y: yPos,
                                         width: charWidth,
                                         height: SkinElements.TextFont.charHeight)
                    
                    // Only draw if visible
                    if xPos + charWidth > rect.minX && xPos < rect.maxX {
                        drawSprite(from: textImage, sourceRect: charRect, to: destRect, in: context)
                    }
                    xPos += charWidth
                }
            }
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.green,
                .font: NSFont.monospacedSystemFont(ofSize: 7, weight: .regular)
            ]
            // Draw text twice for circular scroll
            for pass in 0..<2 {
                let xPos = rect.minX - scrollOffset + (CGFloat(pass) * totalWidth)
                text.draw(at: NSPoint(x: xPos, y: rect.minY), withAttributes: attrs)
            }
        }
        
        context.restoreGState()
    }
    
    // MARK: - Sliders
    
    /// Draw position/seek slider
    func drawPositionSlider(value: CGFloat, isPressed: Bool, in context: CGContext) {
        let trackRect = SkinElements.PositionBar.Positions.track
        
        if let posbarImage = skin.posbar {
            // Draw background track
            drawSprite(from: posbarImage, sourceRect: SkinElements.PositionBar.background,
                      to: trackRect, in: context)
            
            // Calculate thumb position
            // The thumb slides along the track, from left edge to right edge minus thumb width
            let thumbWidth: CGFloat = SkinElements.PositionBar.thumbNormal.width
            let thumbHeight: CGFloat = SkinElements.PositionBar.thumbNormal.height
            let thumbX = trackRect.minX + (trackRect.width - thumbWidth) * value
            let thumbRect = NSRect(x: thumbX, y: trackRect.minY,
                                   width: thumbWidth, height: thumbHeight)
            
            // Draw thumb
            let thumbSource = isPressed ? SkinElements.PositionBar.thumbPressed : SkinElements.PositionBar.thumbNormal
            drawSprite(from: posbarImage, sourceRect: thumbSource, to: thumbRect, in: context)
        } else {
            drawFallbackSlider(value: value, rect: trackRect, in: context)
        }
    }
    
    /// Draw volume slider
    func drawVolumeSlider(value: CGFloat, isPressed: Bool, in context: CGContext) {
        let sliderRect = SkinElements.Volume.Positions.slider
        
        if let volumeImage = skin.volume {
            // Volume has 28 fill states (0-27)
            let fillLevel = Int(value * 27)
            let bgRect = SkinElements.Volume.background(level: fillLevel)
            drawSprite(from: volumeImage, sourceRect: bgRect, to: sliderRect, in: context)
            
            // Draw thumb
            let thumbWidth: CGFloat = 14
            let thumbHeight: CGFloat = 11
            let thumbX = sliderRect.minX + (sliderRect.width - thumbWidth) * value
            let thumbY = sliderRect.minY + (sliderRect.height - thumbHeight) / 2
            let thumbRect = NSRect(x: thumbX, y: thumbY, width: thumbWidth, height: thumbHeight)
            
            let thumbSource = isPressed ? SkinElements.Volume.thumbPressed : SkinElements.Volume.thumbNormal
            drawSprite(from: volumeImage, sourceRect: thumbSource, to: thumbRect, in: context)
        } else {
            drawFallbackSlider(value: value, rect: sliderRect, in: context)
        }
    }
    
    /// Draw balance slider
    func drawBalanceSlider(value: CGFloat, isPressed: Bool, in context: CGContext) {
        let sliderRect = SkinElements.Balance.Positions.slider
        
        if let balanceImage = skin.balance {
            // Balance ranges from -1 (left) to +1 (right), center is 0
            let normalizedValue = (value + 1) / 2  // Convert to 0-1 range
            let fillLevel = Int(abs(value) * 27)
            let bgRect = SkinElements.Balance.background(level: fillLevel)
            drawSprite(from: balanceImage, sourceRect: bgRect, to: sliderRect, in: context)
            
            // Draw thumb
            let thumbWidth: CGFloat = 14
            let thumbHeight: CGFloat = 11
            let thumbX = sliderRect.minX + (sliderRect.width - thumbWidth) * normalizedValue
            let thumbY = sliderRect.minY + (sliderRect.height - thumbHeight) / 2
            let thumbRect = NSRect(x: thumbX, y: thumbY, width: thumbWidth, height: thumbHeight)
            
            let thumbSource = isPressed ? SkinElements.Balance.thumbPressed : SkinElements.Balance.thumbNormal
            drawSprite(from: balanceImage, sourceRect: thumbSource, to: thumbRect, in: context)
        } else {
            // Convert value from -1...1 to 0...1 for fallback
            let normalizedValue = (value + 1) / 2
            drawFallbackSlider(value: normalizedValue, rect: sliderRect, in: context)
        }
    }
    
    // MARK: - Shade Mode Rendering
    
    /// Draw main window in shade mode
    func drawMainWindowShade(in context: CGContext, bounds: NSRect, isActive: Bool,
                             currentTime: TimeInterval, duration: TimeInterval,
                             trackTitle: String, marqueeOffset: CGFloat, pressedButton: ButtonType?) {
        // Draw shade mode background
        if let titlebarImage = skin.titlebar {
            let sourceRect = isActive ? SkinElements.MainShade.backgroundActive : SkinElements.MainShade.backgroundInactive
            drawSprite(from: titlebarImage, sourceRect: sourceRect, to: bounds, in: context)
        } else {
            // Fallback shade background
            let gradient = NSGradient(colors: [
                isActive ? NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.5, alpha: 1.0) : NSColor(calibratedWhite: 0.3, alpha: 1.0),
                isActive ? NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.3, alpha: 1.0) : NSColor(calibratedWhite: 0.2, alpha: 1.0)
            ])
            gradient?.draw(in: bounds, angle: 90)
        }
        
        // Draw window control buttons
        let controls: [(ButtonType, NSRect)] = [
            (.minimize, SkinElements.TitleBar.ShadePositions.minimizeButton),
            (.unshade, SkinElements.TitleBar.ShadePositions.unshadeButton),
            (.close, SkinElements.TitleBar.ShadePositions.closeButton)
        ]
        
        for (button, position) in controls {
            let state: ButtonState = (pressedButton == button) ? .pressed : .normal
            drawButton(button, state: state, at: position, in: context)
        }
        
        // Draw mini position bar
        if duration > 0 {
            let posRect = SkinElements.MainShade.Positions.positionBar
            let progress = CGFloat(currentTime / duration)
            
            NSColor.darkGray.setFill()
            context.fill(posRect)
            
            let fillWidth = posRect.width * progress
            NSColor.green.setFill()
            context.fill(NSRect(x: posRect.minX, y: posRect.minY, width: fillWidth, height: posRect.height))
        }
        
        // Draw scrolling title text
        let textArea = SkinElements.MainShade.textArea
        context.saveGState()
        context.clip(to: textArea)
        
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.green,
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        ]
        let textPoint = NSPoint(x: textArea.minX - marqueeOffset, y: textArea.minY)
        trackTitle.draw(at: textPoint, withAttributes: attrs)
        
        context.restoreGState()
    }
    
    /// Draw equalizer window in shade mode
    func drawEqualizerShade(in context: CGContext, bounds: NSRect, isActive: Bool, pressedButton: ButtonType?) {
        // Draw shade mode background
        if let eqImage = skin.eqmain {
            let sourceRect = isActive ? SkinElements.EQShade.backgroundActive : SkinElements.EQShade.backgroundInactive
            drawSprite(from: eqImage, sourceRect: sourceRect, to: bounds, in: context)
        } else {
            // Fallback shade background
            let gradient = NSGradient(colors: [
                isActive ? NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.5, alpha: 1.0) : NSColor(calibratedWhite: 0.3, alpha: 1.0),
                isActive ? NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.3, alpha: 1.0) : NSColor(calibratedWhite: 0.2, alpha: 1.0)
            ])
            gradient?.draw(in: bounds, angle: 90)
            
            // Draw EQ label
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.boldSystemFont(ofSize: 9)
            ]
            "EQUALIZER".draw(at: NSPoint(x: 6, y: 3), withAttributes: attrs)
        }
        
        // Draw window control buttons
        let closePos = SkinElements.EQShade.Positions.closeButton
        let shadePos = SkinElements.EQShade.Positions.shadeButton
        
        let closeState: ButtonState = (pressedButton == .close) ? .pressed : .normal
        drawButton(.close, state: closeState, at: closePos, in: context)
        
        let shadeState: ButtonState = (pressedButton == .unshade) ? .pressed : .normal
        drawButton(.unshade, state: shadeState, at: shadePos, in: context)
    }
    
    /// Draw playlist window in shade mode
    func drawPlaylistShade(in context: CGContext, bounds: NSRect, isActive: Bool, pressedButton: ButtonType?) {
        // Draw shade mode background (tiled)
        if let pleditImage = skin.pledit {
            // Left corner
            drawSprite(from: pleditImage, sourceRect: SkinElements.PlaylistShade.leftCorner,
                      to: NSRect(x: 0, y: 0, width: 25, height: 14), in: context)
            
            // Right corner
            let rightCornerX = bounds.width - 75
            drawSprite(from: pleditImage, sourceRect: SkinElements.PlaylistShade.rightCorner,
                      to: NSRect(x: rightCornerX, y: 0, width: 75, height: 14), in: context)
            
            // Tile middle
            var x: CGFloat = 25
            while x < rightCornerX {
                let tileWidth = min(25, rightCornerX - x)
                drawSprite(from: pleditImage, sourceRect: SkinElements.PlaylistShade.tile,
                          to: NSRect(x: x, y: 0, width: tileWidth, height: 14), in: context)
                x += 25
            }
        } else {
            // Fallback shade background
            let gradient = NSGradient(colors: [
                isActive ? NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.5, alpha: 1.0) : NSColor(calibratedWhite: 0.3, alpha: 1.0),
                isActive ? NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.3, alpha: 1.0) : NSColor(calibratedWhite: 0.2, alpha: 1.0)
            ])
            gradient?.draw(in: bounds, angle: 90)
            
            // Draw PL label
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.boldSystemFont(ofSize: 9)
            ]
            "PLAYLIST".draw(at: NSPoint(x: 6, y: 3), withAttributes: attrs)
        }
        
        // Draw window control buttons (relative to right edge)
        let closeRect = NSRect(x: bounds.width + SkinElements.PlaylistShade.Positions.closeButton.minX,
                               y: SkinElements.PlaylistShade.Positions.closeButton.minY,
                               width: 9, height: 9)
        let shadeRect = NSRect(x: bounds.width + SkinElements.PlaylistShade.Positions.shadeButton.minX,
                               y: SkinElements.PlaylistShade.Positions.shadeButton.minY,
                               width: 9, height: 9)
        
        let closeState: ButtonState = (pressedButton == .close) ? .pressed : .normal
        drawButton(.close, state: closeState, at: closeRect, in: context)
        
        let shadeState: ButtonState = (pressedButton == .unshade) ? .pressed : .normal
        drawButton(.unshade, state: shadeState, at: shadeRect, in: context)
    }
    
    // MARK: - Equalizer Window
    
    /// Draw equalizer window background
    func drawEqualizerBackground(in context: CGContext, bounds: NSRect, isActive: Bool) {
        if let eqImage = skin.eqmain {
            // Draw EQ background (first 116 rows of eqmain.bmp)
            let sourceRect = NSRect(x: 0, y: 0, width: 275, height: 116)
            drawSprite(from: eqImage, sourceRect: sourceRect, to: bounds, in: context)
            
            // Draw title bar
            let titleSource = isActive ? SkinElements.Equalizer.titleActive : SkinElements.Equalizer.titleInactive
            let titleDest = NSRect(x: 0, y: 0, width: bounds.width, height: 14)
            drawSprite(from: eqImage, sourceRect: titleSource, to: titleDest, in: context)
        } else {
            // Fallback EQ background
            drawFallbackEQBackground(in: context, bounds: bounds)
        }
    }
    
    /// Draw EQ slider knob at current value position with colored level indicator
    func drawEQSlider(bandIndex: Int, value: CGFloat, isPreamp: Bool, in context: CGContext) {
        let xPos: CGFloat
        if isPreamp {
            xPos = SkinElements.Equalizer.Sliders.preampX
        } else {
            xPos = SkinElements.Equalizer.Sliders.firstBandX + CGFloat(bandIndex) * SkinElements.Equalizer.Sliders.bandSpacing
        }
        
        let sliderHeight = SkinElements.Equalizer.Sliders.sliderHeight
        let sliderY = SkinElements.Equalizer.Sliders.sliderY
        let thumbSize: CGFloat = 11  // 11x11 pixels per webamp spec
        
        // Value is -12 to +12 dB, convert to 0-1
        let normalizedValue = (value + 12) / 24
        
        // Calculate thumb position - thumb slides from top (-12dB) to bottom (+12dB)
        // In Winamp coordinates (y increases downward from top)
        let thumbY = sliderY + (sliderHeight - thumbSize) * (1 - normalizedValue)
        
        // Draw colored level indicator bars on the sides of the slider
        drawEQSliderColorBars(at: xPos, sliderY: sliderY, sliderHeight: sliderHeight, 
                              normalizedValue: normalizedValue, in: context)
        
        // Draw slider knob from eqmain.bmp (coordinates from webamp: x=0, y=164, 11x11)
        let thumbRect = NSRect(x: xPos, y: thumbY, width: thumbSize, height: thumbSize)
        
        if let eqImage = skin.eqmain {
            // Use eqmain.bmp for slider knob (NOT eq_ex.bmp)
            drawSprite(from: eqImage, sourceRect: SkinElements.Equalizer.sliderThumbNormal, to: thumbRect, in: context)
        } else {
            // Fallback: Draw knob as a small rectangle
            drawFallbackEQSliderKnob(at: NSPoint(x: xPos, y: thumbY), value: normalizedValue, in: context)
        }
    }
    
    /// Draw colored bar in the EQ slider track
    /// The ENTIRE track is filled with a SINGLE color based on knob position
    /// Color scale: green (top/+12dB) → yellow (middle/0dB) → red (bottom/-12dB)
    /// - Parameters:
    ///   - xPos: X position of the slider (left edge of thumb)
    ///   - sliderY: Y position of the slider track top
    ///   - sliderHeight: Height of the slider track (63px)
    ///   - normalizedValue: Value from 0 (bottom/-12dB) to 1 (top/+12dB)
    ///   - context: Graphics context
    private func drawEQSliderColorBars(at xPos: CGFloat, sliderY: CGFloat, sliderHeight: CGFloat,
                                        normalizedValue: CGFloat, in context: CGContext) {
        let thumbSize: CGFloat = 11
        // Slim bar centered in track
        let barWidth: CGFloat = 4
        let barX = xPos + (thumbSize - barWidth) / 2  // Center in track
        
        // Color scale: knob position determines the single color for entire track
        // normalizedValue=1 (top, +12dB): RED (boost)
        // normalizedValue=0.5 (middle, 0dB): YELLOW
        // normalizedValue=0 (bottom, -12dB): GREEN (cut)
        let colorStops: [(position: CGFloat, color: NSColor)] = [
            (0.0, NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.0, alpha: 1.0)),   // Green at bottom (-12dB)
            (0.33, NSColor(calibratedRed: 0.5, green: 0.85, blue: 0.0, alpha: 1.0)),  // Yellow-green
            (0.5, NSColor(calibratedRed: 0.85, green: 0.85, blue: 0.0, alpha: 1.0)),  // Yellow at middle (0dB)
            (0.66, NSColor(calibratedRed: 0.85, green: 0.5, blue: 0.0, alpha: 1.0)),  // Orange
            (1.0, NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.0, alpha: 1.0)),  // Red at top (+12dB)
        ]
        
        // Get the single color based on knob position
        let trackColor = interpolateColor(at: normalizedValue, stops: colorStops)
        
        // Draw rounded rect for the track (rounded top and bottom)
        let barRect = NSRect(x: barX, y: sliderY, width: barWidth, height: sliderHeight)
        let cornerRadius: CGFloat = 2  // Slight rounding at top and bottom
        
        trackColor.setFill()
        let path = NSBezierPath(roundedRect: barRect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.fill()
    }
    
    /// Interpolate color between gradient stops
    private func interpolateColor(at position: CGFloat, stops: [(position: CGFloat, color: NSColor)]) -> NSColor {
        var lowerStop = stops[0]
        var upperStop = stops[stops.count - 1]
        
        for i in 0..<stops.count - 1 {
            if position >= stops[i].position && position <= stops[i + 1].position {
                lowerStop = stops[i]
                upperStop = stops[i + 1]
                break
            }
        }
        
        let range = upperStop.position - lowerStop.position
        let factor = range > 0 ? (position - lowerStop.position) / range : 0
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        lowerStop.color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        upperStop.color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        return NSColor(
            calibratedRed: r1 + (r2 - r1) * factor,
            green: g1 + (g2 - g1) * factor,
            blue: b1 + (b2 - b1) * factor,
            alpha: 1.0
        )
    }
    
    /// Draw fallback EQ slider knob when skin not available
    private func drawFallbackEQSliderKnob(at position: NSPoint, value: CGFloat, in context: CGContext) {
        let knobRect = NSRect(x: position.x, y: position.y, width: 14, height: 11)
        
        // Knob background
        NSColor(calibratedRed: 0.3, green: 0.5, blue: 0.6, alpha: 1.0).setFill()
        context.fill(knobRect)
        
        // Knob highlight lines (mimics the Winamp look)
        NSColor(calibratedWhite: 0.7, alpha: 1.0).setStroke()
        context.setLineWidth(1)
        for i in 0..<3 {
            let y = position.y + 3 + CGFloat(i) * 3
            context.move(to: CGPoint(x: position.x + 2, y: y))
            context.addLine(to: CGPoint(x: position.x + 12, y: y))
        }
        context.strokePath()
        
        // Border
        NSColor(calibratedWhite: 0.2, alpha: 1.0).setStroke()
        context.stroke(knobRect)
    }
    
    // MARK: - Milkdrop Visualization Window
    
    /// Milkdrop button types
    enum MilkdropButtonType {
        case close, shade
    }
    
    /// Draw the complete Milkdrop window chrome (title bar, borders)
    /// The visualization area itself is handled by the OpenGL view
    func drawMilkdropWindow(in context: CGContext, bounds: NSRect, isActive: Bool,
                            pressedButton: MilkdropButtonType?, isShadeMode: Bool) {
        if isShadeMode {
            drawMilkdropShade(in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
        } else {
            drawMilkdropNormal(in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
        }
    }
    
    /// Draw normal mode Milkdrop window chrome
    /// Uses PLEDIT.BMP title bar sprites (same style as playlist) with "MILKDROP" text
    private func drawMilkdropNormal(in context: CGContext, bounds: NSRect, isActive: Bool,
                                    pressedButton: MilkdropButtonType?) {
        // Fill background with black for visualization area
        NSColor.black.setFill()
        context.fill(bounds)
        
        let titleHeight = SkinElements.Playlist.titleHeight  // 20px like playlist
        let borderWidth = SkinElements.Milkdrop.Layout.leftBorder
        let bottomHeight = SkinElements.Milkdrop.Layout.bottomBorder
        
        // Draw dark borders
        let borderColor = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        borderColor.setFill()
        
        // Left border
        context.fill(NSRect(x: 0, y: titleHeight, width: borderWidth, height: bounds.height - titleHeight))
        
        // Right border  
        context.fill(NSRect(x: bounds.width - borderWidth, y: titleHeight, width: borderWidth, height: bounds.height - titleHeight))
        
        // Bottom bar
        context.fill(NSRect(x: 0, y: bounds.height - bottomHeight, width: bounds.width, height: bottomHeight))
        
        // Draw title bar using PLEDIT.BMP sprites (same style as playlist window)
        drawMilkdropTitleBarFromPledit(in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
    }
    
    /// Draw Milkdrop title bar using PLEDIT.BMP sprites with "MILKDROP" text overlay
    private func drawMilkdropTitleBarFromPledit(in context: CGContext, bounds: NSRect, isActive: Bool, pressedButton: MilkdropButtonType?) {
        guard let pleditImage = skin.pledit else {
            drawFallbackMilkdropTitleBar(in: context, bounds: bounds, isActive: isActive)
            return
        }
        
        let titleHeight = SkinElements.Playlist.titleHeight
        let leftCornerWidth: CGFloat = 25
        let rightCornerWidth: CGFloat = 25
        let tileWidth: CGFloat = 25
        
        // Get the correct sprite set for active/inactive state (same as playlist)
        let leftCorner = isActive ? SkinElements.Playlist.TitleBarActive.leftCorner : SkinElements.Playlist.TitleBarInactive.leftCorner
        let tileSprite = isActive ? SkinElements.Playlist.TitleBarActive.tile : SkinElements.Playlist.TitleBarInactive.tile
        let rightCorner = isActive ? SkinElements.Playlist.TitleBarActive.rightCorner : SkinElements.Playlist.TitleBarInactive.rightCorner
        
        // Draw left corner
        drawSprite(from: pleditImage, sourceRect: leftCorner,
                  to: NSRect(x: 0, y: 0, width: leftCornerWidth, height: titleHeight), in: context)
        
        // Draw right corner (contains window buttons)
        drawSprite(from: pleditImage, sourceRect: rightCorner,
                  to: NSRect(x: bounds.width - rightCornerWidth, y: 0, width: rightCornerWidth, height: titleHeight), in: context)
        
        // Fill the middle section with tiles
        let middleStart = leftCornerWidth
        let middleEnd = bounds.width - rightCornerWidth
        var x: CGFloat = middleStart
        while x < middleEnd {
            let w = min(tileWidth, middleEnd - x)
            drawSprite(from: pleditImage, sourceRect: tileSprite,
                      to: NSRect(x: x, y: 0, width: w, height: titleHeight), in: context)
            x += tileWidth
        }
        
        // Draw "MILKDROP" text using GenFont (active/inactive based on window state)
        drawMilkdropTitleText(in: context, bounds: bounds, titleHeight: titleHeight, isActive: isActive)
        
        // Draw close button pressed state if needed
        if pressedButton == .close {
            let closeRect = NSRect(x: bounds.width - SkinElements.Playlist.TitleBarButtons.closeOffset, 
                                   y: 3, width: 9, height: 9)
            NSColor(calibratedWhite: 0.3, alpha: 0.5).setFill()
            context.fill(closeRect)
        }
    }
    
    /// Draw "MILKDROP" text using GenFont from gen.png
    /// Creates a solid background gap in the title bar decorations for the text
    private func drawMilkdropTitleText(in context: CGContext, bounds: NSRect, titleHeight: CGFloat, isActive: Bool = true) {
        // Load gen.png from skin or bundle
        let genImage = skin.gen ?? Skin.genWindowImage
        guard let genImage = genImage,
              let cgImage = genImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return  // GenFont required - no fallback
        }
        
        let text = "MILKDROP"
        let scale = Skin.scaleFactor  // 1.25 - match other windows
        let charHeight = SkinElements.GenFont.charHeight * scale  // 6px * 1.25 = 7.5px
        let charSpacing: CGFloat = 0  // No extra spacing between letters
        
        // Calculate total text width (scaled width, tight spacing)
        var totalWidth: CGFloat = 0
        for (i, char) in text.enumerated() {
            if let charInfo = SkinElements.GenFont.character(char, active: true) {
                totalWidth += charInfo.width * scale
                if i < text.count - 1 {
                    totalWidth += charSpacing
                }
            }
        }
        
        // Add padding around text for the background gap
        let padding: CGFloat = 10
        let capWidth: CGFloat = 4  // Width of rounded end caps
        let gapWidth = totalWidth + padding * 2 + capWidth * 2
        let gapHeight: CGFloat = 14
        
        // Center the gap in the title bar
        let gapX = (bounds.width - gapWidth) / 2
        let gapY = (titleHeight - gapHeight) / 2
        
        // Draw solid dark background (the "gap" in decorative lines)
        let gapColor = isActive 
            ? NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.18, alpha: 1.0)
            : NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        gapColor.setFill()
        context.fill(NSRect(x: gapX + capWidth, y: gapY, width: gapWidth - capWidth * 2, height: gapHeight))
        
        // Draw rounded end caps (tapered edges like library window)
        let capColor = isActive
            ? NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.24, alpha: 1.0)
            : NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
        
        // Left cap - tapered inward
        for i in 0..<Int(capWidth) {
            let inset = CGFloat(Int(capWidth) - 1 - i)
            let capX = gapX + CGFloat(i)
            capColor.withAlphaComponent(CGFloat(i + 1) / capWidth).setFill()
            context.fill(NSRect(x: capX, y: gapY + inset, width: 1, height: gapHeight - inset * 2))
        }
        
        // Right cap - tapered inward
        for i in 0..<Int(capWidth) {
            let inset = CGFloat(i)
            let capX = gapX + gapWidth - capWidth + CGFloat(i)
            capColor.withAlphaComponent(CGFloat(Int(capWidth) - i) / capWidth).setFill()
            context.fill(NSRect(x: capX, y: gapY + inset, width: 1, height: gapHeight - inset * 2))
        }
        
        // Draw text centered in the gap (account for caps)
        var xPos = gapX + capWidth + padding
        let textY = gapY + (gapHeight - charHeight) / 2
        
        let chars = Array(text)
        for (i, char) in chars.enumerated() {
            if let charInfo = SkinElements.GenFont.character(char, active: isActive) {
                let sourceRect = charInfo.rect
                let scaledWidth = charInfo.width * scale
                
                // CGImage uses top-left origin - use source coordinates directly (no flip needed)
                let cropRect = CGRect(x: sourceRect.origin.x, y: sourceRect.origin.y,
                                     width: sourceRect.width, height: sourceRect.height)
                
                if let croppedChar = cgImage.cropping(to: cropRect) {
                    // Draw scaled with vertical flip for NSView (bottom-left origin)
                    context.saveGState()
                    context.translateBy(x: xPos, y: textY + charHeight)
                    context.scaleBy(x: 1, y: -1)
                    context.interpolationQuality = .none  // Keep pixel-perfect look
                    context.draw(croppedChar, in: CGRect(x: 0, y: 0, width: scaledWidth, height: charHeight))
                    context.restoreGState()
                }
                
                xPos += scaledWidth
                if i < chars.count - 1 {
                    xPos += charSpacing
                }
            }
        }
    }
    
    // MARK: - Spectrum Analyzer Window
    
    /// Draw spectrum analyzer window chrome
    /// Uses same style as Milkdrop window but with "SPECTRUM ANALYZER" title
    func drawSpectrumAnalyzerWindow(in context: CGContext, bounds: NSRect, isActive: Bool,
                                    pressedButton: MilkdropButtonType?, isShadeMode: Bool) {
        if isShadeMode {
            drawSpectrumAnalyzerShade(in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
        } else {
            drawSpectrumAnalyzerNormal(in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
        }
    }
    
    /// Draw normal mode spectrum analyzer window chrome
    private func drawSpectrumAnalyzerNormal(in context: CGContext, bounds: NSRect, isActive: Bool,
                                            pressedButton: MilkdropButtonType?) {
        // Fill background with black for visualization area
        NSColor.black.setFill()
        context.fill(bounds)
        
        let titleHeight = SkinElements.Playlist.titleHeight  // 20px like playlist
        let borderWidth = SkinElements.Milkdrop.Layout.leftBorder
        let bottomHeight = SkinElements.Milkdrop.Layout.bottomBorder
        
        // Draw dark borders
        let borderColor = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        borderColor.setFill()
        
        // Left border
        context.fill(NSRect(x: 0, y: titleHeight, width: borderWidth, height: bounds.height - titleHeight))
        
        // Right border  
        context.fill(NSRect(x: bounds.width - borderWidth, y: titleHeight, width: borderWidth, height: bounds.height - titleHeight))
        
        // Bottom bar
        context.fill(NSRect(x: 0, y: bounds.height - bottomHeight, width: bounds.width, height: bottomHeight))
        
        // Draw title bar using PLEDIT.BMP sprites
        drawSpectrumAnalyzerTitleBar(in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
    }
    
    /// Draw spectrum analyzer title bar using PLEDIT.BMP sprites with "SPECTRUM ANALYZER" text
    private func drawSpectrumAnalyzerTitleBar(in context: CGContext, bounds: NSRect, isActive: Bool, pressedButton: MilkdropButtonType?) {
        guard let pleditImage = skin.pledit else {
            drawFallbackMilkdropTitleBar(in: context, bounds: bounds, isActive: isActive)
            return
        }
        
        let titleHeight = SkinElements.Playlist.titleHeight
        let leftCornerWidth: CGFloat = 25
        let rightCornerWidth: CGFloat = 25
        let tileWidth: CGFloat = 25
        
        // Get the correct sprite set for active/inactive state (same as playlist)
        let leftCorner = isActive ? SkinElements.Playlist.TitleBarActive.leftCorner : SkinElements.Playlist.TitleBarInactive.leftCorner
        let tileSprite = isActive ? SkinElements.Playlist.TitleBarActive.tile : SkinElements.Playlist.TitleBarInactive.tile
        let rightCorner = isActive ? SkinElements.Playlist.TitleBarActive.rightCorner : SkinElements.Playlist.TitleBarInactive.rightCorner
        
        // Draw left corner
        drawSprite(from: pleditImage, sourceRect: leftCorner,
                  to: NSRect(x: 0, y: 0, width: leftCornerWidth, height: titleHeight), in: context)
        
        // Draw right corner (contains window buttons)
        drawSprite(from: pleditImage, sourceRect: rightCorner,
                  to: NSRect(x: bounds.width - rightCornerWidth, y: 0, width: rightCornerWidth, height: titleHeight), in: context)
        
        // Fill the middle section with tiles
        let middleStart = leftCornerWidth
        let middleEnd = bounds.width - rightCornerWidth
        var x: CGFloat = middleStart
        while x < middleEnd {
            let w = min(tileWidth, middleEnd - x)
            drawSprite(from: pleditImage, sourceRect: tileSprite,
                      to: NSRect(x: x, y: 0, width: w, height: titleHeight), in: context)
            x += tileWidth
        }
        
        // Draw "SPECTRUM ANALYZER" text using GenFont
        drawSpectrumAnalyzerTitleText(in: context, bounds: bounds, titleHeight: titleHeight, isActive: isActive)
        
        // Draw close button pressed state if needed
        if pressedButton == .close {
            let closeRect = NSRect(x: bounds.width - SkinElements.Playlist.TitleBarButtons.closeOffset, 
                                   y: 3, width: 9, height: 9)
            NSColor(calibratedWhite: 0.3, alpha: 0.5).setFill()
            context.fill(closeRect)
        }
    }
    
    /// Draw "SPECTRUM ANALYZER" text using GenFont from gen.png
    private func drawSpectrumAnalyzerTitleText(in context: CGContext, bounds: NSRect, titleHeight: CGFloat, isActive: Bool = true) {
        // Load gen.png from skin or bundle
        let genImage = skin.gen ?? Skin.genWindowImage
        guard let genImage = genImage,
              let cgImage = genImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return  // GenFont required - no fallback
        }
        
        let text = "SPECTRUM ANALYZER"
        let scale = Skin.scaleFactor  // 1.25 - match other windows
        let charHeight = SkinElements.GenFont.charHeight * scale  // 6px * 1.25 = 7.5px
        let charSpacing: CGFloat = 0  // No extra spacing between letters
        
        // Calculate total text width (scaled width, tight spacing)
        var totalWidth: CGFloat = 0
        for (i, char) in text.enumerated() {
            if let charInfo = SkinElements.GenFont.character(char, active: true) {
                totalWidth += charInfo.width * scale
                if i < text.count - 1 {
                    totalWidth += charSpacing
                }
            } else if char == " " {
                totalWidth += 4 * scale  // Space width
                if i < text.count - 1 {
                    totalWidth += charSpacing
                }
            }
        }
        
        // Add padding around text for the background gap
        let padding: CGFloat = 10
        let capWidth: CGFloat = 4  // Width of rounded end caps
        let gapWidth = totalWidth + padding * 2 + capWidth * 2
        let gapHeight: CGFloat = 14
        
        // Center the gap in the title bar
        let gapX = (bounds.width - gapWidth) / 2
        let gapY = (titleHeight - gapHeight) / 2
        
        // Draw solid dark background (the "gap" in decorative lines)
        let gapColor = isActive 
            ? NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.18, alpha: 1.0)
            : NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        gapColor.setFill()
        context.fill(NSRect(x: gapX + capWidth, y: gapY, width: gapWidth - capWidth * 2, height: gapHeight))
        
        // Draw rounded end caps (tapered edges like library window)
        let capColor = isActive
            ? NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.24, alpha: 1.0)
            : NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
        
        // Left cap - tapered inward
        for i in 0..<Int(capWidth) {
            let inset = CGFloat(Int(capWidth) - 1 - i)
            let capX = gapX + CGFloat(i)
            capColor.withAlphaComponent(CGFloat(i + 1) / capWidth).setFill()
            context.fill(NSRect(x: capX, y: gapY + inset, width: 1, height: gapHeight - inset * 2))
        }
        
        // Right cap - tapered inward
        for i in 0..<Int(capWidth) {
            let inset = CGFloat(i)
            let capX = gapX + gapWidth - capWidth + CGFloat(i)
            capColor.withAlphaComponent(CGFloat(Int(capWidth) - i) / capWidth).setFill()
            context.fill(NSRect(x: capX, y: gapY + inset, width: 1, height: gapHeight - inset * 2))
        }
        
        // Draw text centered in the gap (account for caps)
        var xPos = gapX + capWidth + padding
        let textY = gapY + (gapHeight - charHeight) / 2
        
        let chars = Array(text)
        for (i, char) in chars.enumerated() {
            if char == " " {
                // Handle space character
                xPos += 4 * scale
                if i < chars.count - 1 {
                    xPos += charSpacing
                }
            } else if let charInfo = SkinElements.GenFont.character(char, active: isActive) {
                let sourceRect = charInfo.rect
                let scaledWidth = charInfo.width * scale
                
                // CGImage uses top-left origin - use source coordinates directly (no flip needed)
                let cropRect = CGRect(x: sourceRect.origin.x, y: sourceRect.origin.y,
                                     width: sourceRect.width, height: sourceRect.height)
                
                if let croppedChar = cgImage.cropping(to: cropRect) {
                    // Draw scaled with vertical flip for NSView (bottom-left origin)
                    context.saveGState()
                    context.translateBy(x: xPos, y: textY + charHeight)
                    context.scaleBy(x: 1, y: -1)
                    context.interpolationQuality = .none  // Keep pixel-perfect look
                    context.draw(croppedChar, in: CGRect(x: 0, y: 0, width: scaledWidth, height: charHeight))
                    context.restoreGState()
                }
                
                xPos += scaledWidth
                if i < chars.count - 1 {
                    xPos += charSpacing
                }
            }
        }
    }
    
    /// Draw spectrum analyzer shade mode
    private func drawSpectrumAnalyzerShade(in context: CGContext, bounds: NSRect, isActive: Bool, pressedButton: MilkdropButtonType?) {
        guard let pleditImage = skin.pledit else {
            // Simple fallback
            NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.22, alpha: 1.0).setFill()
            context.fill(bounds)
            return
        }
        
        let shadeHeight = SkinElements.PlaylistShade.height  // 14px
        
        // Draw shade background using playlist shade sprites
        let leftCorner = SkinElements.PlaylistShade.leftCorner
        let rightCorner = SkinElements.PlaylistShade.rightCorner
        let tile = SkinElements.PlaylistShade.tile
        
        // Draw left corner
        drawSprite(from: pleditImage, sourceRect: leftCorner,
                  to: NSRect(x: 0, y: 0, width: leftCorner.width, height: shadeHeight), in: context)
        
        // Draw right corner
        drawSprite(from: pleditImage, sourceRect: rightCorner,
                  to: NSRect(x: bounds.width - rightCorner.width, y: 0, width: rightCorner.width, height: shadeHeight), in: context)
        
        // Fill middle with tiles
        var x = leftCorner.width
        let endX = bounds.width - rightCorner.width
        while x < endX {
            let w = min(tile.width, endX - x)
            drawSprite(from: pleditImage, sourceRect: tile,
                      to: NSRect(x: x, y: 0, width: w, height: shadeHeight), in: context)
            x += tile.width
        }
        
        // Draw "SPECTRUM ANALYZER" text (smaller for shade mode)
        drawSpectrumAnalyzerTitleText(in: context, bounds: bounds, titleHeight: shadeHeight, isActive: isActive)
        
        // Close button pressed state
        if pressedButton == .close {
            let closeRect = NSRect(x: bounds.width - 11, y: 3, width: 9, height: 9)
            NSColor(calibratedWhite: 0.3, alpha: 0.5).setFill()
            context.fill(closeRect)
        }
    }
    
    /// Draw "WINAMP LIBRARY" text using GenFont from gen.png
    /// Creates a solid background gap in the title bar decorations for the text
    private func drawLibraryTitleText(in context: CGContext, bounds: NSRect, titleHeight: CGFloat, isActive: Bool = true) {
        // Load gen.png from skin or bundle
        let genImage = skin.gen ?? Skin.genWindowImage
        guard let genImage = genImage,
              let cgImage = genImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return  // GenFont required - no fallback
        }
        
        let text = "WINAMP LIBRARY"
        let scale: CGFloat = 1.15  // Slightly smaller than other windows
        let charHeight = SkinElements.GenFont.charHeight * scale
        let charSpacing: CGFloat = 0  // No extra spacing between letters
        let spaceWidth: CGFloat = 4  // Space between words
        
        // Calculate total text width (scaled width, tight spacing)
        var totalWidth: CGFloat = 0
        for (i, char) in text.enumerated() {
            if char == " " {
                totalWidth += spaceWidth
            } else if let charInfo = SkinElements.GenFont.character(char, active: true) {
                totalWidth += charInfo.width * scale
                if i < text.count - 1 {
                    let nextChar = text[text.index(text.startIndex, offsetBy: i + 1)]
                    if nextChar != " " {
                        totalWidth += charSpacing
                    }
                }
            }
        }
        
        // Add padding around text for the background gap
        let padding: CGFloat = 10
        let capWidth: CGFloat = 4  // Width of rounded end caps
        let gapWidth = totalWidth + padding * 2 + capWidth * 2
        let gapHeight: CGFloat = 14
        
        // Center the gap in the title bar
        let gapX = (bounds.width - gapWidth) / 2
        let gapY = (titleHeight - gapHeight) / 2
        
        // Draw solid dark background (the "gap" in decorative lines)
        let gapColor = isActive 
            ? NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.18, alpha: 1.0)
            : NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        gapColor.setFill()
        context.fill(NSRect(x: gapX + capWidth, y: gapY, width: gapWidth - capWidth * 2, height: gapHeight))
        
        // Draw rounded end caps (tapered edges)
        let capColor = isActive
            ? NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.24, alpha: 1.0)
            : NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
        
        // Left cap - tapered inward
        for i in 0..<Int(capWidth) {
            let inset = CGFloat(Int(capWidth) - 1 - i)
            let capX = gapX + CGFloat(i)
            capColor.withAlphaComponent(CGFloat(i + 1) / capWidth).setFill()
            context.fill(NSRect(x: capX, y: gapY + inset, width: 1, height: gapHeight - inset * 2))
        }
        
        // Right cap - tapered inward
        for i in 0..<Int(capWidth) {
            let inset = CGFloat(i)
            let capX = gapX + gapWidth - capWidth + CGFloat(i)
            capColor.withAlphaComponent(CGFloat(Int(capWidth) - i) / capWidth).setFill()
            context.fill(NSRect(x: capX, y: gapY + inset, width: 1, height: gapHeight - inset * 2))
        }
        
        // Draw text centered in the gap (account for caps)
        var xPos = gapX + capWidth + padding
        let textY = gapY + (gapHeight - charHeight) / 2
        
        let chars = Array(text)
        for (i, char) in chars.enumerated() {
            if char == " " {
                xPos += spaceWidth
                continue
            }
            
            if let charInfo = SkinElements.GenFont.character(char, active: isActive) {
                let sourceRect = charInfo.rect
                let scaledWidth = charInfo.width * scale
                
                // CGImage uses top-left origin - use source coordinates directly (no flip needed)
                let cropRect = CGRect(x: sourceRect.origin.x, y: sourceRect.origin.y,
                                     width: sourceRect.width, height: sourceRect.height)
                
                if let croppedChar = cgImage.cropping(to: cropRect) {
                    // Draw scaled with vertical flip for NSView (bottom-left origin)
                    context.saveGState()
                    context.translateBy(x: xPos, y: textY + charHeight)
                    context.scaleBy(x: 1, y: -1)
                    context.interpolationQuality = .none  // Keep pixel-perfect look
                    context.draw(croppedChar, in: CGRect(x: 0, y: 0, width: scaledWidth, height: charHeight))
                    context.restoreGState()
                }
                
                xPos += scaledWidth
                if i < chars.count - 1 && chars[i + 1] != " " {
                    xPos += charSpacing
                }
            }
        }
    }
    
    /// Draw GEN.BMP title bar (three-part: left corner, tiled middle, right corner)
    private func drawGenTitleBar(cgImage: CGImage, in context: CGContext, bounds: NSRect, isActive: Bool) {
        let titleHeight = SkinElements.GenWindow.titleBarHeight
        
        // Select active or inactive sprites
        let leftCorner: NSRect
        let tile: NSRect
        let rightCorner: NSRect
        
        if isActive {
            leftCorner = SkinElements.GenWindow.TitleBarActive.leftCorner
            tile = SkinElements.GenWindow.TitleBarActive.tile
            rightCorner = SkinElements.GenWindow.TitleBarActive.rightCorner
        } else {
            leftCorner = SkinElements.GenWindow.TitleBarInactive.leftCorner
            tile = SkinElements.GenWindow.TitleBarInactive.tile
            rightCorner = SkinElements.GenWindow.TitleBarInactive.rightCorner
        }
        
        // Draw left corner
        drawSprite(from: cgImage, sourceRect: leftCorner,
                  destRect: NSRect(x: 0, y: 0, width: leftCorner.width, height: titleHeight),
                  in: context)
        
        // Draw right corner
        let rightCornerX = bounds.width - rightCorner.width
        drawSprite(from: cgImage, sourceRect: rightCorner,
                  destRect: NSRect(x: rightCornerX, y: 0, width: rightCorner.width, height: titleHeight),
                  in: context)
        
        // Draw tiled middle section between left and right corners
        let middleX = leftCorner.width
        let middleWidth = bounds.width - leftCorner.width - rightCorner.width
        if middleWidth > 0 {
            drawTiledSprite(from: cgImage, sourceRect: tile,
                           destRect: NSRect(x: middleX, y: 0, width: middleWidth, height: titleHeight),
                           in: context, tileVertically: false)
        }
    }
    
    /// Draw GEN.BMP bottom bar (three-part: left corner, tiled middle, right corner)
    private func drawGenBottomBar(cgImage: CGImage, in context: CGContext, bounds: NSRect) {
        let bottomLeftCorner = SkinElements.GenWindow.Chrome.bottomLeftCorner
        let bottomTile = SkinElements.GenWindow.Chrome.bottomTile
        let bottomRightCorner = SkinElements.GenWindow.Chrome.bottomRightCorner
        
        let bottomY = bounds.height - bottomLeftCorner.height
        
        // Draw left corner
        drawSprite(from: cgImage, sourceRect: bottomLeftCorner,
                  destRect: NSRect(x: 0, y: bottomY, width: bottomLeftCorner.width, height: bottomLeftCorner.height),
                  in: context)
        
        // Draw right corner
        let rightCornerX = bounds.width - bottomRightCorner.width
        drawSprite(from: cgImage, sourceRect: bottomRightCorner,
                  destRect: NSRect(x: rightCornerX, y: bottomY, width: bottomRightCorner.width, height: bottomRightCorner.height),
                  in: context)
        
        // Draw tiled middle section
        let middleX = bottomLeftCorner.width
        let middleWidth = bounds.width - bottomLeftCorner.width - bottomRightCorner.width
        if middleWidth > 0 {
            drawTiledSprite(from: cgImage, sourceRect: bottomTile,
                           destRect: NSRect(x: middleX, y: bottomY, width: middleWidth, height: bottomTile.height),
                           in: context, tileVertically: false)
        }
    }
    
    /// Draw title text using GenFont alphabet sprites from GEN.BMP (variable width)
    private func drawGenTitleText(cgImage: CGImage, text: String, in context: CGContext, bounds: NSRect, titleHeight: CGFloat, isActive: Bool = true) {
        let charHeight = SkinElements.GenFont.charHeight
        let charSpacing = SkinElements.GenFont.charSpacing
        
        let totalWidth = SkinElements.GenFont.textWidth(text)
        let startX = (bounds.width - totalWidth) / 2
        let startY = (titleHeight - charHeight) / 2
        
        let chars = Array(text)
        var xPos = startX
        for (i, char) in chars.enumerated() {
            if let charInfo = SkinElements.GenFont.character(char, active: isActive) {
                let destRect = NSRect(x: xPos, y: startY, width: charInfo.width, height: charHeight)
                drawSprite(from: cgImage, sourceRect: charInfo.rect, destRect: destRect, in: context)
                xPos += charInfo.width
                if i < chars.count - 1 {
                    xPos += charSpacing
                }
            }
        }
    }
    
    /// Draw a sprite from source image to destination
    /// CGImage cropping uses top-left origin (same as sprite sheet coordinates)
    private func drawSprite(from cgImage: CGImage, sourceRect: NSRect, destRect: NSRect, in context: CGContext) {
        // Crop the source image to get the sprite - CGImage uses top-left origin for cropping
        let cropRect = CGRect(x: sourceRect.origin.x, y: sourceRect.origin.y,
                             width: sourceRect.width, height: sourceRect.height)
        
        guard let croppedImage = cgImage.cropping(to: cropRect) else { return }
        
        // Draw the cropped sprite - flip for top-down Winamp coordinates
        // Context is already flipped (Winamp Y=0 at top), so we need to flip the sprite
        context.saveGState()
        context.translateBy(x: destRect.origin.x, y: destRect.origin.y + destRect.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none  // Pixel-perfect rendering
        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: destRect.width, height: destRect.height))
        context.restoreGState()
    }
    
    /// Draw a tiled sprite from source image to fill destination area
    private func drawTiledSprite(from cgImage: CGImage, sourceRect: NSRect, destRect: NSRect, 
                                  in context: CGContext, tileVertically: Bool) {
        // Crop the source image to get the tile sprite - CGImage uses top-left origin for cropping
        let cropRect = CGRect(x: sourceRect.origin.x, y: sourceRect.origin.y,
                             width: sourceRect.width, height: sourceRect.height)
        
        guard let tileImage = cgImage.cropping(to: cropRect) else { return }
        
        context.saveGState()
        context.clip(to: destRect)
        context.interpolationQuality = .none
        
        if tileVertically {
            // Tile vertically
            var y = destRect.origin.y
            while y < destRect.origin.y + destRect.height {
                let tileHeight = min(sourceRect.height, destRect.origin.y + destRect.height - y)
                
                // Flip for drawing
                context.saveGState()
                context.translateBy(x: destRect.origin.x, y: y + tileHeight)
                context.scaleBy(x: 1, y: -1)
                context.draw(tileImage, in: CGRect(x: 0, y: 0, width: destRect.width, height: tileHeight))
                context.restoreGState()
                
                y += sourceRect.height
            }
        } else {
            // Tile horizontally
            var x = destRect.origin.x
            while x < destRect.origin.x + destRect.width {
                let tileWidth = min(sourceRect.width, destRect.origin.x + destRect.width - x)
                
                // Flip for drawing
                context.saveGState()
                context.translateBy(x: x, y: destRect.origin.y + destRect.height)
                context.scaleBy(x: 1, y: -1)
                context.draw(tileImage, in: CGRect(x: 0, y: 0, width: tileWidth, height: destRect.height))
                context.restoreGState()
                
                x += sourceRect.width
            }
        }
        
        context.restoreGState()
    }
    
    /// Draw Milkdrop window in shade mode (title bar only)
    private func drawMilkdropShade(in context: CGContext, bounds: NSRect, isActive: Bool,
                                   pressedButton: MilkdropButtonType?) {
        // In shade mode, use playlist shade sprites
        guard let pleditImage = skin.pledit else {
            drawFallbackMilkdropTitleBar(in: context, bounds: bounds, isActive: isActive)
            return
        }
        
        let shadeHeight: CGFloat = 14
        
        // Draw shade mode background using playlist shade sprites
        let leftCorner = SkinElements.PlaylistShade.leftCorner
        let rightCorner = SkinElements.PlaylistShade.rightCorner
        let tile = SkinElements.PlaylistShade.tile
        
        // Draw left corner
        drawSprite(from: pleditImage, sourceRect: leftCorner,
                  to: NSRect(x: 0, y: 0, width: leftCorner.width, height: shadeHeight), in: context)
        
        // Draw right corner
        drawSprite(from: pleditImage, sourceRect: rightCorner,
                  to: NSRect(x: bounds.width - rightCorner.width, y: 0, width: rightCorner.width, height: shadeHeight), in: context)
        
        // Tile middle
        var x = leftCorner.width
        let endX = bounds.width - rightCorner.width
        while x < endX {
            let w = min(tile.width, endX - x)
            drawSprite(from: pleditImage, sourceRect: tile,
                      to: NSRect(x: x, y: 0, width: w, height: shadeHeight), in: context)
            x += tile.width
        }
        
        // Draw "MILKDROP" text using GenFont (active/inactive based on window state)
        drawMilkdropTitleText(in: context, bounds: bounds, titleHeight: shadeHeight, isActive: isActive)
        
        // Close button pressed state
        if pressedButton == .close {
            let closeRect = NSRect(x: bounds.width - 11, y: 3, width: 9, height: 9)
            NSColor(calibratedWhite: 0.3, alpha: 0.5).setFill()
            context.fill(closeRect)
        }
    }
    
    /// Fallback chrome drawing when GEN.BMP is not available
    private func drawFallbackMilkdropChrome(in context: CGContext, bounds: NSRect, isActive: Bool,
                                            pressedButton: MilkdropButtonType?) {
        let titleHeight = SkinElements.GenWindow.titleBarHeight
        let borderWidth: CGFloat = 11
        let bottomHeight: CGFloat = 14
        
        // Dark border colors
        let borderColor = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
        
        // Draw title bar background
        drawFallbackMilkdropTitleBar(in: context, bounds: bounds, isActive: isActive)
        
        // Draw side borders
        borderColor.setFill()
        context.fill(NSRect(x: 0, y: titleHeight, width: borderWidth, height: bounds.height - titleHeight - bottomHeight))
        context.fill(NSRect(x: bounds.width - borderWidth, y: titleHeight, width: borderWidth, height: bounds.height - titleHeight - bottomHeight))
        
        // Draw bottom bar
        context.fill(NSRect(x: 0, y: bounds.height - bottomHeight, width: bounds.width, height: bottomHeight))
        
        // Draw close button highlight when pressed
        if pressedButton == .close {
            let closeRect = NSRect(x: bounds.width - 25, y: 0, width: 25, height: titleHeight)
            NSColor(calibratedWhite: 1.0, alpha: 0.3).setFill()
            context.fill(closeRect)
        }
    }
    
    /// Fallback title bar for Milkdrop window when image not available
    private func drawFallbackMilkdropTitleBar(in context: CGContext, bounds: NSRect, isActive: Bool) {
        let titleHeight = SkinElements.GenWindow.titleBarHeight
        let titleRect = NSRect(x: 0, y: 0, width: bounds.width, height: titleHeight)
        
        // Gradient background
        let gradient = NSGradient(colors: [
            isActive ? NSColor(calibratedRed: 0.27, green: 0.29, blue: 0.42, alpha: 1.0) : NSColor(calibratedWhite: 0.25, alpha: 1.0),
            isActive ? NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.35, alpha: 1.0) : NSColor(calibratedWhite: 0.20, alpha: 1.0)
        ])
        gradient?.draw(in: titleRect, angle: 90)
        
        // Draw "MILKDROP" text using fallback pixel patterns
        drawFallbackMilkdropTitleText(centeredIn: titleRect, isActive: isActive, in: context)
        
        // Draw close button (X) in the top-right corner
        let closeX = bounds.width - 15
        let closeY: CGFloat = 5
        let closeColor = isActive ? NSColor(calibratedRed: 0.7, green: 0.6, blue: 0.3, alpha: 1.0) : NSColor(calibratedWhite: 0.4, alpha: 1.0)
        closeColor.setStroke()
        context.setLineWidth(1)
        context.move(to: CGPoint(x: closeX + 1, y: closeY + 1))
        context.addLine(to: CGPoint(x: closeX + 7, y: closeY + 7))
        context.move(to: CGPoint(x: closeX + 7, y: closeY + 1))
        context.addLine(to: CGPoint(x: closeX + 1, y: closeY + 7))
        context.strokePath()
    }
    
    /// Draw Milkdrop title text using pixel patterns (fallback only)
    private func drawFallbackMilkdropTitleText(centeredIn rect: NSRect, isActive: Bool, in context: CGContext) {
        let charWidth: CGFloat = 5
        let charHeight: CGFloat = 6
        let letterSpacing: CGFloat = 1
        
        context.saveGState()
        context.setAllowsAntialiasing(false)
        context.setShouldAntialias(false)
        context.interpolationQuality = .none
        
        let titleText = "MILKDROP"
        let chars = Array(titleText)
        let totalWidth = CGFloat(chars.count) * charWidth + CGFloat(chars.count - 1) * letterSpacing
        let startX = rect.midX - totalWidth / 2
        let startY = rect.midY - charHeight / 2
        
        let textColor = isActive ? NSColor(calibratedRed: 0.85, green: 0.75, blue: 0.35, alpha: 1.0) : NSColor(calibratedWhite: 0.4, alpha: 1.0)
        
        var xPos = startX
        for char in chars {
            if let pattern = plexTitlePixels()[char.uppercased().first ?? " "] {
                drawTitleBarPixelChar(pattern, at: NSPoint(x: xPos, y: startY), color: textColor, in: context)
            }
            xPos += charWidth + letterSpacing
        }
        
        context.restoreGState()
    }
    
    /// Get the visualization area rect (the area where OpenGL renders)
    func getMilkdropVisualizationArea(bounds: NSRect) -> NSRect {
        let titleHeight = SkinElements.Milkdrop.titleBarHeight
        let leftBorder = SkinElements.Milkdrop.Layout.leftBorder
        let rightBorder = SkinElements.Milkdrop.Layout.rightBorder
        let bottomBorder = SkinElements.Milkdrop.Layout.bottomBorder
        
        return NSRect(
            x: leftBorder,
            y: titleHeight,
            width: bounds.width - leftBorder - rightBorder,
            height: bounds.height - titleHeight - bottomBorder
        )
    }
    
    // MARK: - Playlist Window
    
    /// Playlist button types
    enum PlaylistButtonType {
        case add, rem, sel, misc, list
        case close, shade
        // Mini transport controls (existing in skin sprites)
        case miniPrevious, miniPlay, miniPause, miniStop, miniNext, miniOpen
    }
    
    /// Draw the complete playlist window using skin sprites
    func drawPlaylistWindow(in context: CGContext, bounds: NSRect, isActive: Bool,
                            pressedButton: PlaylistButtonType?, scrollPosition: CGFloat) {
        let titleHeight = SkinElements.Playlist.titleHeight
        let bottomHeight = SkinElements.Playlist.bottomHeight
        
        // Fill background with playlist colors first
        skin.playlistColors.normalBackground.setFill()
        context.fill(bounds)
        
        // Draw title bar
        drawPlaylistTitleBar(in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
        
        // Draw side borders
        drawPlaylistSideBorders(in: context, bounds: bounds)
        
        // Draw bottom bar
        drawPlaylistBottomBar(in: context, bounds: bounds, pressedButton: pressedButton)
        
        // Draw scrollbar
        let contentHeight = bounds.height - titleHeight - bottomHeight
        drawPlaylistScrollbar(in: context, bounds: bounds, scrollPosition: scrollPosition, contentHeight: contentHeight)
    }
    
    /// Draw playlist title bar with skin sprites
    /// The title text sprite (100px) should be CENTERED in the available space between corners
    func drawPlaylistTitleBar(in context: CGContext, bounds: NSRect, isActive: Bool, pressedButton: PlaylistButtonType?) {
        guard let pleditImage = skin.pledit else {
            drawFallbackPlaylistTitleBar(in: context, bounds: bounds, isActive: isActive)
            return
        }
        
        let titleHeight = SkinElements.Playlist.titleHeight
        let leftCornerWidth: CGFloat = 25
        let rightCornerWidth: CGFloat = 25
        let titleSpriteWidth: CGFloat = 100
        let tileWidth: CGFloat = 25
        
        // Get the correct sprite set for active/inactive state
        let leftCorner = isActive ? SkinElements.Playlist.TitleBarActive.leftCorner : SkinElements.Playlist.TitleBarInactive.leftCorner
        let titleSprite = isActive ? SkinElements.Playlist.TitleBarActive.title : SkinElements.Playlist.TitleBarInactive.title
        let tileSprite = isActive ? SkinElements.Playlist.TitleBarActive.tile : SkinElements.Playlist.TitleBarInactive.tile
        let rightCorner = isActive ? SkinElements.Playlist.TitleBarActive.rightCorner : SkinElements.Playlist.TitleBarInactive.rightCorner
        
        // On non-Retina, fill background first to prevent seam gaps
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        if backingScale < 1.5 {
            NSColor(calibratedRed: 0.14, green: 0.13, blue: 0.16, alpha: 1.0).setFill()
            context.fill(NSRect(x: 0, y: 0, width: bounds.width, height: titleHeight))
        }
        
        // Calculate available space for middle section
        let middleStart = leftCornerWidth
        let middleEnd = bounds.width - rightCornerWidth
        let middleWidth = middleEnd - middleStart
        
        // Fill the entire middle section with tiles FIRST
        // Overlap tiles by 1px on non-Retina to avoid seam artifacts
        let tileStep = backingScale < 1.5 ? tileWidth - 1 : tileWidth
        
        var x: CGFloat = middleStart
        while x < middleEnd {
            let w = min(tileWidth, middleEnd - x)
            drawSprite(from: pleditImage, sourceRect: tileSprite,
                      to: NSRect(x: x, y: 0, width: w, height: titleHeight), in: context)
            x += tileStep
        }
        
        // Draw corners ON TOP - slightly wider on non-Retina to cover seams
        let cornerOverlap: CGFloat = backingScale < 1.5 ? 1 : 0
        
        drawSprite(from: pleditImage, sourceRect: leftCorner,
                  to: NSRect(x: 0, y: 0, width: leftCornerWidth + cornerOverlap, height: titleHeight), in: context)
        
        drawSprite(from: pleditImage, sourceRect: rightCorner,
                  to: NSRect(x: bounds.width - rightCornerWidth - cornerOverlap, y: 0, width: rightCornerWidth + cornerOverlap, height: titleHeight), in: context)
        
        // Draw title text sprite CENTERED over the tiles
        let titleX = middleStart + (middleWidth - titleSpriteWidth) / 2
        drawSprite(from: pleditImage, sourceRect: titleSprite,
                  to: NSRect(x: titleX, y: 0, width: titleSpriteWidth, height: titleHeight), in: context)
        
        // Draw window control button pressed states if needed
        if pressedButton == .close {
            // Close button highlight - drawn over the right corner
            let closeRect = NSRect(x: bounds.width - SkinElements.Playlist.TitleBarButtons.closeOffset, 
                                   y: 3, width: 9, height: 9)
            NSColor(calibratedWhite: 0.3, alpha: 0.5).setFill()
            context.fill(closeRect)
        }
        
        if pressedButton == .shade {
            // Shade button highlight
            let shadeRect = NSRect(x: bounds.width - SkinElements.Playlist.TitleBarButtons.shadeOffset, 
                                   y: 3, width: 9, height: 9)
            NSColor(calibratedWhite: 0.3, alpha: 0.5).setFill()
            context.fill(shadeRect)
        }
    }
    
    /// Draw playlist side borders
    private func drawPlaylistSideBorders(in context: CGContext, bounds: NSRect) {
        guard let pleditImage = skin.pledit else { return }
        
        let titleHeight = SkinElements.Playlist.titleHeight
        let bottomHeight = SkinElements.Playlist.bottomHeight
        let tileHeight: CGFloat = 29
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        // On non-Retina, fill solid background first to cover any gaps
        if backingScale < 1.5 {
            // Use a dark color matching the border edge
            NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1.0).setFill()
            context.fill(NSRect(x: 0, y: titleHeight, width: 12, height: bounds.height - titleHeight - bottomHeight))
            context.fill(NSRect(x: bounds.width - 20, y: titleHeight, width: 20, height: bounds.height - titleHeight - bottomHeight))
        }
        
        // Draw tiles from BOTTOM to TOP so any partial tile is at top (under title bar)
        let contentTop = titleHeight
        let contentBottom = bounds.height - bottomHeight
        
        // Left side border - start from bottom, work up
        var y: CGFloat = contentBottom - tileHeight
        while y >= contentTop - tileHeight {
            let drawY = max(contentTop, y)
            let h = min(tileHeight, contentBottom - drawY)
            if h > 0 {
                drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.leftSideTile,
                          to: NSRect(x: 0, y: drawY, width: 12, height: h), in: context)
            }
            y -= tileHeight
        }
        
        // Right side border - start from bottom, work up
        y = contentBottom - tileHeight
        while y >= contentTop - tileHeight {
            let drawY = max(contentTop, y)
            let h = min(tileHeight, contentBottom - drawY)
            if h > 0 {
                drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.rightSideTile,
                          to: NSRect(x: bounds.width - 20, y: drawY, width: 20, height: h), in: context)
            }
            y -= tileHeight
        }
    }
    
    /// Draw playlist bottom bar with button areas
    func drawPlaylistBottomBar(in context: CGContext, bounds: NSRect, pressedButton: PlaylistButtonType?) {
        guard let pleditImage = skin.pledit else {
            drawFallbackPlaylistBottomBar(in: context, bounds: bounds, pressedButton: pressedButton)
            return
        }
        
        let bottomHeight = SkinElements.Playlist.bottomHeight
        let bottomY = bounds.height - bottomHeight
        
        // Draw left corner (125px wide) - contains ADD, REM, SEL button areas
        drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.bottomLeftCorner,
                  to: NSRect(x: 0, y: bottomY, width: 125, height: bottomHeight), in: context)
        
        // Draw right corner (150px wide) - contains MISC, LIST button areas + resize grip
        drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.bottomRightCorner,
                  to: NSRect(x: bounds.width - 150, y: bottomY, width: 150, height: bottomHeight), in: context)
        
        // Tile the middle section
        var x: CGFloat = 125
        while x < bounds.width - 150 {
            let w = min(25, bounds.width - 150 - x)
            drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.bottomTile,
                      to: NSRect(x: x, y: bottomY, width: w, height: bottomHeight), in: context)
            x += 25
        }
        
        // Draw button pressed highlights
        if let pressed = pressedButton {
            let buttonY = bottomY + 10  // Buttons are positioned 10px from bottom of bar
            var buttonRect: NSRect?
            
            switch pressed {
            case .add:
                buttonRect = NSRect(x: 11, y: buttonY, width: 25, height: 18)
            case .rem:
                buttonRect = NSRect(x: 40, y: buttonY, width: 25, height: 18)
            case .sel:
                buttonRect = NSRect(x: 70, y: buttonY, width: 25, height: 18)
            case .misc:
                buttonRect = NSRect(x: bounds.width - 150 + 10, y: buttonY, width: 25, height: 18)
            case .list:
                buttonRect = NSRect(x: bounds.width - 46, y: buttonY, width: 25, height: 18)
            default:
                break
            }
            
            if let rect = buttonRect {
                NSColor(calibratedWhite: 0.2, alpha: 0.4).setFill()
                context.fill(rect)
            }
        }
    }
    
    /// Draw playlist scrollbar
    func drawPlaylistScrollbar(in context: CGContext, bounds: NSRect, scrollPosition: CGFloat, contentHeight: CGFloat) {
        guard let pleditImage = skin.pledit else {
            drawFallbackPlaylistScrollbar(in: context, bounds: bounds, scrollPosition: scrollPosition)
            return
        }
        
        let titleHeight = SkinElements.Playlist.titleHeight
        let bottomHeight = SkinElements.Playlist.bottomHeight
        let trackHeight = bounds.height - titleHeight - bottomHeight
        let scrollbarX = bounds.width - 15
        
        // Draw scrollbar track background
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let tileHeight: CGFloat = 29
        
        // On non-Retina, fill solid background first to cover any gaps
        if backingScale < 1.5 {
            NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1.0).setFill()
            context.fill(NSRect(x: scrollbarX, y: titleHeight, width: 8, height: trackHeight))
        }
        
        // Draw tiles from bottom to top so any partial tile is at top
        var y: CGFloat = bounds.height - bottomHeight - tileHeight
        while y >= titleHeight - tileHeight {
            let drawY = max(titleHeight, y)
            let h = min(tileHeight, bounds.height - bottomHeight - drawY)
            if h > 0 {
                drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.scrollbarTrack,
                          to: NSRect(x: scrollbarX, y: drawY, width: 8, height: h), in: context)
            }
            y -= tileHeight
        }
        
        // Draw scrollbar thumb
        let thumbHeight: CGFloat = 18
        let availableTrack = trackHeight - thumbHeight
        let thumbY = titleHeight + (availableTrack * scrollPosition)
        
        drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.scrollbarThumbNormal,
                  to: NSRect(x: scrollbarX, y: thumbY, width: 8, height: thumbHeight), in: context)
    }
    
    /// Draw playlist background (handles resizable windows) - legacy method
    func drawPlaylistBackground(in context: CGContext, bounds: NSRect) {
        // Use the new complete drawing method with defaults
        drawPlaylistWindow(in: context, bounds: bounds, isActive: true, pressedButton: nil, scrollPosition: 0)
    }
    
    // MARK: - Playlist Fallback Rendering
    
    private func drawFallbackPlaylistTitleBar(in context: CGContext, bounds: NSRect, isActive: Bool) {
        let titleHeight = SkinElements.Playlist.titleHeight
        let titleRect = NSRect(x: 0, y: 0, width: bounds.width, height: titleHeight)
        
        // Draw gradient background matching main window style
        if isActive {
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.5, alpha: 1.0),
                NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.25, alpha: 1.0)
            ])
            gradient?.draw(in: titleRect, angle: 90)
        } else {
            let gradient = NSGradient(colors: [
                NSColor(calibratedWhite: 0.35, alpha: 1.0),
                NSColor(calibratedWhite: 0.25, alpha: 1.0)
            ])
            gradient?.draw(in: titleRect, angle: 90)
        }
        
        // Draw decorative left bar (similar to skin sprites)
        NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.3, alpha: 1.0).setFill()
        context.fill(NSRect(x: 4, y: 6, width: 8, height: 8))
        
        // Title text - flip back for text rendering and CENTER it
        context.saveGState()
        context.translateBy(x: 0, y: titleHeight)
        context.scaleBy(x: 1, y: -1)
        
        let title = "WINAMP PLAYLIST"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 8)
        ]
        let titleSize = title.size(withAttributes: attrs)
        let titleX = (bounds.width - titleSize.width) / 2
        title.draw(at: NSPoint(x: titleX, y: (titleHeight - titleSize.height) / 2), withAttributes: attrs)
        
        context.restoreGState()
        
        // Draw decorative pattern (dots/lines like Winamp)
        NSColor(calibratedRed: 0.3, green: 0.3, blue: 0.4, alpha: 1.0).setFill()
        var patternX: CGFloat = 16
        let titleLeft = titleX - 8
        let titleRight = titleX + titleSize.width + 8
        
        // Pattern before title
        while patternX < titleLeft {
            context.fill(NSRect(x: patternX, y: 8, width: 2, height: 4))
            patternX += 4
        }
        
        // Pattern after title
        patternX = titleRight
        while patternX < bounds.width - 30 {
            context.fill(NSRect(x: patternX, y: 8, width: 2, height: 4))
            patternX += 4
        }
        
        // Window control buttons (shade, close) - simple rectangles
        NSColor(calibratedWhite: 0.4, alpha: 1.0).setFill()
        context.fill(NSRect(x: bounds.width - 22, y: 6, width: 9, height: 9))
        context.fill(NSRect(x: bounds.width - 11, y: 6, width: 9, height: 9))
    }
    
    private func drawFallbackPlaylistBottomBar(in context: CGContext, bounds: NSRect, pressedButton: PlaylistButtonType?) {
        let bottomHeight = SkinElements.Playlist.bottomHeight
        let barRect = NSRect(x: 0, y: bounds.height - bottomHeight, width: bounds.width, height: bottomHeight)
        
        // Background
        NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.2, alpha: 1.0).setFill()
        context.fill(barRect)
        
        // Top border line
        NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.35, alpha: 1.0).setFill()
        context.fill(NSRect(x: 0, y: bounds.height - bottomHeight, width: bounds.width, height: 1))
        
        // Draw button labels
        let buttonY = bounds.height - bottomHeight + 10
        let buttonColor = NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.3, alpha: 1.0)
        let buttonHighlight = NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.4, alpha: 1.0)
        
        let buttons: [(String, CGFloat, PlaylistButtonType)] = [
            ("ADD", 11, .add),
            ("REM", 40, .rem),
            ("SEL", 70, .sel),
            ("MISC", bounds.width - 140, .misc),
            ("LIST", bounds.width - 46, .list)
        ]
        
        for (title, x, buttonType) in buttons {
            let buttonRect = NSRect(x: x, y: buttonY, width: 30, height: 18)
            
            // Button face
            let isPressed = pressedButton == buttonType
            (isPressed ? buttonHighlight : buttonColor).setFill()
            context.fill(buttonRect)
            
            // Draw text (in flipped context)
            context.saveGState()
            context.translateBy(x: 0, y: buttonY + 18)
            context.scaleBy(x: 1, y: -1)
            
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 8)
            ]
            let textSize = title.size(withAttributes: attrs)
            title.draw(at: NSPoint(x: buttonRect.midX - textSize.width / 2, y: 4), withAttributes: attrs)
            
            context.restoreGState()
        }
    }
    
    private func drawFallbackPlaylistScrollbar(in context: CGContext, bounds: NSRect, scrollPosition: CGFloat) {
        let titleHeight = SkinElements.Playlist.titleHeight
        let bottomHeight = SkinElements.Playlist.bottomHeight
        let scrollbarWidth: CGFloat = 15
        
        let scrollRect = NSRect(
            x: bounds.width - scrollbarWidth,
            y: titleHeight,
            width: scrollbarWidth,
            height: bounds.height - titleHeight - bottomHeight
        )
        
        // Track background
        NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.2, alpha: 1.0).setFill()
        context.fill(scrollRect)
        
        // Thumb
        let thumbHeight: CGFloat = max(20, scrollRect.height * 0.2)
        let availableTrack = scrollRect.height - thumbHeight
        let thumbY = scrollRect.minY + (availableTrack * scrollPosition)
        
        NSColor(calibratedRed: 0.6, green: 0.55, blue: 0.35, alpha: 1.0).setFill()
        let thumbRect = NSRect(x: scrollRect.minX + 2, y: thumbY, width: scrollRect.width - 4, height: thumbHeight)
        context.fill(thumbRect)
    }
    
    // MARK: - Plex Browser Window
    
    /// Plex browser button types
    enum PlexBrowserButtonType {
        case close, shade
    }
    
    /// Draw the complete Plex browser window using skin sprites
    /// Uses playlist sprites for frame/chrome with custom content areas
    func drawPlexBrowserWindow(in context: CGContext, bounds: NSRect, isActive: Bool,
                               pressedButton: PlexBrowserButtonType?, scrollPosition: CGFloat) {
        let layout = SkinElements.PlexBrowser.Layout.self
        let titleHeight = layout.titleBarHeight  // 20px
        let borderWidth: CGFloat = 3
        let statusHeight = layout.statusBarHeight
        
        // Fill background with black first (like Milkdrop does)
        // This ensures any gaps between sprites show black, not skin colors
        NSColor.black.setFill()
        context.fill(bounds)
        
        // Fill only the CONTENT area with playlist background (not title bar or borders)
        // This prevents skin color from showing through sprite gaps
        let contentArea = NSRect(
            x: borderWidth,
            y: titleHeight,
            width: bounds.width - borderWidth * 2,
            height: bounds.height - titleHeight - statusHeight
        )
        skin.playlistColors.normalBackground.setFill()
        context.fill(contentArea)
        
        // Draw side borders BEFORE title bar (like Milkdrop does)
        // This creates a clean background for the title bar to draw on top of
        drawPlexBrowserSideBorders(in: context, bounds: bounds)
        
        // Draw status bar at bottom
        drawPlexBrowserStatusBar(in: context, bounds: bounds)
        
        // Draw title bar LAST so it draws on top of borders (like Milkdrop)
        drawPlexBrowserTitleBar(in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
        
        // Draw scrollbar
        let contentTop = layout.titleBarHeight + layout.serverBarHeight + layout.tabBarHeight
        let contentHeight = bounds.height - contentTop - layout.statusBarHeight
        drawPlexBrowserScrollbar(in: context, bounds: bounds, scrollPosition: scrollPosition, contentHeight: contentHeight)
    }
    
    /// Draw Plex browser title bar with skin sprites
    /// Uses PLEDIT.BMP for skin following (same approach as Milkdrop window)
    func drawPlexBrowserTitleBar(in context: CGContext, bounds: NSRect, isActive: Bool, pressedButton: PlexBrowserButtonType?) {
        // Use PLEDIT sprites for skin-following (matches Milkdrop window approach)
        guard let pleditImage = skin.pledit else {
            // Fall back to library-window.png if no skin loaded
            if let libraryImage = Skin.libraryWindowImage {
                drawLibraryWindowTitleBar(from: libraryImage, in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
                return
            }
            drawFallbackPlexBrowserTitleBar(in: context, bounds: bounds, isActive: isActive)
            return
        }
        
        // Draw PLEDIT-based title bar
        drawPlexBrowserTitleBarFromPledit(pleditImage, in: context, bounds: bounds, isActive: isActive, pressedButton: pressedButton)
    }
    
    /// Draw Plex browser title bar using PLEDIT.BMP sprites
    /// Draw Plex browser title bar using PLEDIT.BMP sprites (same approach as Milkdrop)
    private func drawPlexBrowserTitleBarFromPledit(_ pleditImage: NSImage, in context: CGContext, bounds: NSRect, isActive: Bool, pressedButton: PlexBrowserButtonType?) {
        let titleHeight = SkinElements.Playlist.titleHeight
        let leftCornerWidth: CGFloat = 25
        let rightCornerWidth: CGFloat = 25
        let tileWidth: CGFloat = 25
        
        // Get the correct sprite set for active/inactive state (same as playlist/milkdrop)
        let leftCorner = isActive ? SkinElements.Playlist.TitleBarActive.leftCorner : SkinElements.Playlist.TitleBarInactive.leftCorner
        let tileSprite = isActive ? SkinElements.Playlist.TitleBarActive.tile : SkinElements.Playlist.TitleBarInactive.tile
        let rightCorner = isActive ? SkinElements.Playlist.TitleBarActive.rightCorner : SkinElements.Playlist.TitleBarInactive.rightCorner
        
        // Use NSImage-based drawing (same as Milkdrop) to avoid interpolation artifacts
        drawSprite(from: pleditImage, sourceRect: leftCorner,
                  to: NSRect(x: 0, y: 0, width: leftCornerWidth, height: titleHeight), in: context)
        
        drawSprite(from: pleditImage, sourceRect: rightCorner,
                  to: NSRect(x: bounds.width - rightCornerWidth, y: 0, width: rightCornerWidth, height: titleHeight), in: context)
        
        // Fill the middle section with tiles
        let middleStart = leftCornerWidth
        let middleEnd = bounds.width - rightCornerWidth
        var x: CGFloat = middleStart
        while x < middleEnd {
            let w = min(tileWidth, middleEnd - x)
            drawSprite(from: pleditImage, sourceRect: tileSprite,
                      to: NSRect(x: x, y: 0, width: w, height: titleHeight), in: context)
            x += tileWidth
        }
        
        drawLibraryTitleText(in: context, bounds: bounds, titleHeight: titleHeight, isActive: isActive)
        
        if pressedButton == .close {
            let closeRect = NSRect(x: bounds.width - SkinElements.Playlist.TitleBarButtons.closeOffset,
                                   y: 3, width: 9, height: 9)
            NSColor(calibratedWhite: 0.3, alpha: 0.5).setFill()
            context.fill(closeRect)
        }
        
        if pressedButton == .shade {
            let shadeRect = NSRect(x: bounds.width - SkinElements.Playlist.TitleBarButtons.shadeOffset,
                                   y: 3, width: 9, height: 9)
            NSColor(calibratedWhite: 0.3, alpha: 0.5).setFill()
            context.fill(shadeRect)
        }
    }
    
    /// Draw title bar using library-window.png sprites
    private func drawLibraryWindowTitleBar(from image: NSImage, in context: CGContext, bounds: NSRect, isActive: Bool, pressedButton: PlexBrowserButtonType?) {
        let layout = SkinElements.LibraryWindow.TitleBar.self
        let titleHeight = layout.height
        let leftCornerWidth: CGFloat = 25
        let tileWidth: CGFloat = 25
        let buttonAreaWidth: CGFloat = 25  // Space reserved for buttons on the right
        
        // Draw left corner
        drawSprite(from: image, sourceRect: layout.leftCorner,
                  to: NSRect(x: 0, y: 0, width: leftCornerWidth, height: titleHeight), in: context)
        
        // Fill middle section with tiles, stopping before button area
        var x: CGFloat = leftCornerWidth
        let tileEnd = bounds.width - buttonAreaWidth
        while x < tileEnd {
            let w = min(tileWidth, tileEnd - x)
            drawSprite(from: image, sourceRect: layout.tile,
                      to: NSRect(x: x, y: 0, width: w, height: titleHeight), in: context)
            x += tileWidth
        }
        
        // Fill the button area with a solid color matching the title bar
        NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.18, alpha: 1.0).setFill()
        context.fill(NSRect(x: tileEnd, y: 0, width: buttonAreaWidth, height: titleHeight))
        
        // Draw "WINAMP LIBRARY" text using GenFont with proper active/inactive colors
        drawLibraryTitleText(in: context, bounds: bounds, titleHeight: titleHeight, isActive: isActive)
        
        // Draw window control buttons using skin titlebar sprites (same style as main window)
        let closeRect = NSRect(x: bounds.width - SkinElements.LibraryWindow.TitleBarButtons.closeOffset - 9, 
                               y: 4, width: 9, height: 9)
        let shadeRect = NSRect(x: bounds.width - SkinElements.LibraryWindow.TitleBarButtons.shadeOffset - 9, 
                               y: 4, width: 9, height: 9)
        
        let closeState: ButtonState = (pressedButton == .close) ? .pressed : .normal
        let shadeState: ButtonState = (pressedButton == .shade) ? .pressed : .normal
        
        drawButton(.close, state: closeState, at: closeRect, in: context)
        drawButton(.shade, state: shadeState, at: shadeRect, in: context)
    }
    
    /// Draw Plex browser title text using sprite glyphs
    private func drawPlexTitleText(centeredIn rect: NSRect, isActive: Bool, in context: CGContext) {
        let charWidth: CGFloat = 6
        let charHeight: CGFloat = 7
        let letterSpacing: CGFloat = 1
        let spaceWidth: CGFloat = charWidth + letterSpacing

        context.saveGState()
        context.setAllowsAntialiasing(false)
        context.setShouldAntialias(false)
        context.interpolationQuality = .none

        let chars = Array(plexTitleText)
        let totalWidth = plexTitleTextWidth(chars, letterSpacing: letterSpacing, spaceWidth: spaceWidth)
        let startX = rect.midX - totalWidth / 2
        let startY = rect.midY - charHeight / 2

        let manualColor = plexTitleManualColor(isActive: isActive)
        var xPos = startX

        for (index, char) in chars.enumerated() {
            if char == " " {
                xPos += spaceWidth
                continue
            }

            if let pattern = plexTitlePixels()[char.uppercased().first ?? " "] {
                drawTitleBarPixelChar(pattern, at: NSPoint(x: xPos, y: startY), color: manualColor, in: context)
                xPos += charWidth
            } else {
                drawTitleBarFallbackChar(char, at: NSPoint(x: xPos, y: startY), color: manualColor, in: context)
                xPos += charWidth
            }

            if index < chars.count - 1, chars[index + 1] != " " {
                xPos += letterSpacing
            }
        }

        context.restoreGState()
    }

    /// Draw title bar text using the skin's TEXT.BMP font sprites
    private func drawTitleBarText(_ text: String, centeredIn rect: NSRect, in context: CGContext) {
        let charWidth = SkinElements.TextFont.charWidth
        let charHeight = SkinElements.TextFont.charHeight
        let charSpacing: CGFloat = 0
        
        // Calculate total text width
        let totalWidth = CGFloat(text.count) * (charWidth + charSpacing)
        let startX = rect.midX - totalWidth / 2
        let startY = rect.midY - charHeight / 2
        
        guard let textImage = skin.text else {
            // Fallback if no TEXT.BMP
            drawTitleBarTextFallback(text, centeredIn: rect, in: context)
            return
        }
        
        // Draw each character from TEXT.BMP
        var xPos = startX
        for char in text.uppercased() {
            let sourceRect = SkinElements.TextFont.character(char)
            let destRect = NSRect(x: xPos, y: startY, width: charWidth, height: charHeight)
            drawSprite(from: textImage, sourceRect: sourceRect, to: destRect, in: context)
            xPos += charWidth + charSpacing
        }
    }

    private func drawTitleBarFallbackChar(_ char: Character, at origin: NSPoint, color: NSColor?, in context: CGContext) {
        let pixels = SkinElements.TitleBarFont.fallbackPixels(for: char)
        let fillColor = color ?? NSColor(calibratedWhite: 0.55, alpha: 1.0)
        fillColor.setFill()

        for (rowIndex, rowBits) in pixels.enumerated() {
            for col in 0..<5 {
                let mask = UInt8(1 << (4 - col))
                guard (rowBits & mask) != 0 else { continue }
                let pixelRect = NSRect(x: origin.x + CGFloat(col),
                                       y: origin.y + CGFloat(rowIndex),
                                       width: 1, height: 1)
                context.fill(pixelRect)
            }
        }
    }

    private func titleBarFallbackColor() -> NSColor? {
        if let pleditImage = skin.pledit,
           let color = sampleSpriteTextColor(in: pleditImage, for: "A") {
            return color
        }
        if let eqmainImage = skin.eqmain,
           let color = sampleSpriteTextColor(in: eqmainImage, for: "E") {
            return color
        }
        return nil
    }

    private func sampleSpriteTextColor(in image: NSImage, for char: Character) -> NSColor? {
        let source = SkinElements.TitleBarFont.charSource(for: char)
        let point: NSPoint?
        switch source {
        case .pledit(let x, let y), .eqmain(let x, let y):
            point = NSPoint(x: x + 2, y: y + 2)
        case .fallback:
            point = nil
        }

        guard let samplePoint = point,
              let color = samplePixelColor(in: image, at: samplePoint),
              color.alphaComponent > 0.2 else {
            return nil
        }

        return color
    }

    private func samplePixelColor(in image: NSImage, at point: NSPoint) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let x = Int(point.x)
        let flippedY = Int(image.size.height - point.y - 1)
        guard x >= 0, flippedY >= 0, x < cgImage.width, flippedY < cgImage.height else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixelData,
                                      width: 1,
                                      height: 1,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        context.draw(cgImage, in: CGRect(x: -x, y: -flippedY,
                                         width: cgImage.width, height: cgImage.height))

        return NSColor(red: CGFloat(pixelData[0]) / 255.0,
                       green: CGFloat(pixelData[1]) / 255.0,
                       blue: CGFloat(pixelData[2]) / 255.0,
                       alpha: CGFloat(pixelData[3]) / 255.0)
    }

    private func plexTitleTileBackgroundColor(from image: NSImage, sourceRect: NSRect) -> NSColor? {
        // Sample a background pixel from the title bar tile sprite
        let samplePoint = NSPoint(x: sourceRect.minX + sourceRect.width / 2,
                                  y: sourceRect.minY + sourceRect.height / 2)
        return samplePixelColor(in: image, at: samplePoint)
    }

    private func plexTitleTextWidth(_ chars: [Character], letterSpacing: CGFloat, spaceWidth: CGFloat) -> CGFloat {
        var width: CGFloat = 0
        var lastWasLetter = false

        for char in chars {
            if char == " " {
                width += spaceWidth
                lastWasLetter = false
                continue
            }

            if lastWasLetter {
                width += letterSpacing
            }

            width += 5
            lastWasLetter = true
        }

        return width
    }

    private func plexTitleManualColor(isActive: Bool) -> NSColor? {
        // Use muted colors matching the main window's title bar appearance
        // Active: slightly brighter, Inactive: dimmer
        if isActive {
            return NSColor(calibratedWhite: 0.55, alpha: 1.0)
        } else {
            return NSColor(calibratedWhite: 0.35, alpha: 1.0)
        }
    }


    private func plexTitlePixels() -> [Character: [UInt8]] {
        return [
            // Original letters from "PLEX BROWSER"
            "P": [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000],
            "L": [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
            "E": [0b11111, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
            "R": [0b11110, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001],
            "W": [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b01010],
            "S": [0b01111, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110],
            "X": [0b10001, 0b01010, 0b00100, 0b00100, 0b01010, 0b10001],
            "B": [0b11110, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110],
            "O": [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
            // Additional letters for "WINAMP LIBRARY"
            "I": [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b11111],
            "N": [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001],
            "A": [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001],
            "M": [0b10001, 0b11011, 0b10101, 0b10001, 0b10001, 0b10001],
            "Y": [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100],
            // Additional letters for "MILKDROP"
            "K": [0b10001, 0b10010, 0b11100, 0b10010, 0b10001, 0b10001],
            "D": [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110],
        ]
    }

    private func drawTitleBarPixelChar(_ pixels: [UInt8], at origin: NSPoint, color: NSColor?, in context: CGContext) {
        let fillColor = color ?? NSColor(calibratedWhite: 0.55, alpha: 1.0)
        fillColor.setFill()

        for (rowIndex, rowBits) in pixels.enumerated() {
            for col in 0..<5 {
                let mask = UInt8(1 << (4 - col))
                guard (rowBits & mask) != 0 else { continue }
                let pixelRect = NSRect(x: origin.x + CGFloat(col),
                                       y: origin.y + CGFloat(rowIndex),
                                       width: 1, height: 1)
                context.fill(pixelRect)
            }
        }
    }

    // MARK: - Title Sprite Font Extraction

    private struct TitleSpriteFont {
        struct Glyph {
            let image: NSImage
            let rect: NSRect
        }

        var glyphs: [Character: Glyph]
        var letterSpacing: CGFloat
        var spaceWidth: CGFloat
        var height: CGFloat
    }

    private func titleSpriteFont() -> TitleSpriteFont? {
        nil
    }

    private func buildTitleSpriteFont() -> TitleSpriteFont? {
        let playlistText = "WINAMP PLAYLIST"
        let eqText = "EQUALIZER"

        let playlistFont = skin.pledit.flatMap { image in
            extractTitleSpriteFont(from: image, titleRect: SkinElements.Playlist.TitleBarActive.title, text: playlistText)
        }

        let eqFont = skin.eqmain.flatMap { image in
            extractTitleSpriteFont(from: image, titleRect: SkinElements.Equalizer.titleActive, text: eqText)
        }

        guard playlistFont != nil || eqFont != nil else {
            return nil
        }

        var glyphs: [Character: TitleSpriteFont.Glyph] = [:]
        if let playlistFont = playlistFont {
            glyphs.merge(playlistFont.glyphs, uniquingKeysWith: { first, _ in first })
        }
        if let eqFont = eqFont {
            for (char, glyph) in eqFont.glyphs where glyphs[char] == nil {
                glyphs[char] = glyph
            }
        }

        let letterSpacing = playlistFont?.letterSpacing ?? eqFont?.letterSpacing ?? SkinElements.TitleBarFont.charSpacing
        let spaceWidth = playlistFont?.spaceWidth ?? eqFont?.spaceWidth ?? (SkinElements.TitleBarFont.charWidth + letterSpacing)
        let height = playlistFont?.height ?? eqFont?.height ?? SkinElements.TitleBarFont.charHeight

        return TitleSpriteFont(glyphs: glyphs,
                               letterSpacing: letterSpacing,
                               spaceWidth: spaceWidth,
                               height: height)
    }

    private func extractTitleSpriteFont(from image: NSImage, titleRect: NSRect, text: String) -> TitleSpriteFont? {
        guard let buffer = spriteBuffer(from: image, rect: titleRect) else { return nil }

        let width = buffer.width
        let height = buffer.height
        let background = mostCommonColor(in: buffer)

        let textMask = buildTextMask(width: width, height: height, buffer: buffer, background: background)
        guard let textRows = textRowRange(mask: textMask, width: width, height: height) else { return nil }

        let colMask = columnMask(mask: textMask, width: width, rowRange: textRows)
        let segments = mergeSegments(findSegments(in: colMask), gapThreshold: 1)

        let letters = text.uppercased().filter { $0 != " " }
        guard segments.count == letters.count else { return nil }

        var glyphs: [Character: TitleSpriteFont.Glyph] = [:]
        let textHeight = CGFloat(textRows.max - textRows.min + 1)
        var segmentIndex = 0
        var prevSegmentIndex: Int?
        var hadSpaceSincePrev = false
        var letterGaps: [Int] = []
        var spaceGaps: [Int] = []

        for char in text.uppercased() {
            if char == " " {
                hadSpaceSincePrev = true
                continue
            }

            let segment = segments[segmentIndex]
            if glyphs[char] == nil {
                let rect = NSRect(x: titleRect.origin.x + CGFloat(segment.start),
                                  y: titleRect.origin.y + CGFloat(textRows.min),
                                  width: CGFloat(segment.end - segment.start + 1),
                                  height: textHeight)
                glyphs[char] = TitleSpriteFont.Glyph(image: image, rect: rect)
            }

            if let prevIndex = prevSegmentIndex {
                let gap = segment.start - segments[prevIndex].end - 1
                if hadSpaceSincePrev {
                    spaceGaps.append(gap)
                } else {
                    letterGaps.append(gap)
                }
            }

            prevSegmentIndex = segmentIndex
            segmentIndex += 1
            hadSpaceSincePrev = false
        }

        guard !glyphs.isEmpty else { return nil }

        let letterSpacing = letterGaps.isEmpty
            ? SkinElements.TitleBarFont.charSpacing
            : CGFloat(letterGaps.reduce(0, +)) / CGFloat(letterGaps.count)
        let spaceWidth = spaceGaps.isEmpty
            ? (SkinElements.TitleBarFont.charWidth + letterSpacing)
            : CGFloat(spaceGaps.reduce(0, +)) / CGFloat(spaceGaps.count)

        return TitleSpriteFont(glyphs: glyphs,
                               letterSpacing: letterSpacing,
                               spaceWidth: spaceWidth,
                               height: textHeight)
    }

    private func titleSpriteTextWidth(_ chars: [Character],
                                      font: TitleSpriteFont?,
                                      letterSpacing: CGFloat,
                                      spaceWidth: CGFloat) -> CGFloat {
        var width: CGFloat = 0
        var lastWasLetter = false

        for char in chars {
            if char == " " {
                width += spaceWidth
                lastWasLetter = false
                continue
            }

            if lastWasLetter {
                width += letterSpacing
            }

            let glyphWidth = font?.glyphs[char]?.rect.width ?? SkinElements.TitleBarFont.charWidth
            width += glyphWidth
            lastWasLetter = true
        }

        return width
    }

    private struct SpriteBuffer {
        let data: [UInt8]
        let width: Int
        let height: Int
    }

    private func spriteBuffer(from image: NSImage, rect: NSRect) -> SpriteBuffer? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let flippedY = image.size.height - rect.origin.y - rect.height
        let sourceInCG = CGRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
        guard let cropped = cgImage.cropping(to: sourceInCG) else { return nil }

        let width = cropped.width
        let height = cropped.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(data: &data,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return SpriteBuffer(data: data, width: width, height: height)
    }

    private func mostCommonColor(in buffer: SpriteBuffer) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var counts: [UInt32: Int] = [:]
        let data = buffer.data
        let pixelCount = buffer.width * buffer.height

        for i in 0..<pixelCount {
            let idx = i * 4
            let r = data[idx]
            let g = data[idx + 1]
            let b = data[idx + 2]
            let a = data[idx + 3]
            guard a > 0 else { continue }
            let packed = (UInt32(r) << 24) | (UInt32(g) << 16) | (UInt32(b) << 8) | UInt32(a)
            counts[packed, default: 0] += 1
        }

        let most = counts.max { $0.value < $1.value }?.key ?? 0
        return (r: UInt8((most >> 24) & 0xFF),
                g: UInt8((most >> 16) & 0xFF),
                b: UInt8((most >> 8) & 0xFF),
                a: UInt8(most & 0xFF))
    }

    private func buildTextMask(width: Int,
                               height: Int,
                               buffer: SpriteBuffer,
                               background: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> [Bool] {
        let data = buffer.data
        var mask = [Bool](repeating: false, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let r = data[index]
                let g = data[index + 1]
                let b = data[index + 2]
                let a = data[index + 3]
                guard a > 80 else { continue }

                let dr = abs(Int(r) - Int(background.r))
                let dg = abs(Int(g) - Int(background.g))
                let db = abs(Int(b) - Int(background.b))
                let diff = dr + dg + db

                if diff > 20 {
                    mask[y * width + x] = true
                }
            }
        }

        return mask
    }

    private func textRowRange(mask: [Bool], width: Int, height: Int) -> (min: Int, max: Int)? {
        var minRow: Int?
        var maxRow: Int?

        for y in 0..<height {
            let rowStart = y * width
            let hasText = mask[rowStart..<(rowStart + width)].contains(true)
            if hasText {
                minRow = minRow ?? y
                maxRow = y
            }
        }

        guard let minRow, let maxRow else { return nil }
        return (min: minRow, max: maxRow)
    }

    private func columnMask(mask: [Bool], width: Int, rowRange: (min: Int, max: Int)) -> [Bool] {
        var columns = [Bool](repeating: false, count: width)
        for x in 0..<width {
            for y in rowRange.min...rowRange.max {
                if mask[y * width + x] {
                    columns[x] = true
                    break
                }
            }
        }
        return columns
    }

    private func findSegments(in columnMask: [Bool]) -> [(start: Int, end: Int)] {
        var segments: [(Int, Int)] = []
        var start: Int?

        for (index, on) in columnMask.enumerated() {
            if on {
                if start == nil { start = index }
            } else if let s = start {
                segments.append((s, index - 1))
                start = nil
            }
        }
        if let s = start {
            segments.append((s, columnMask.count - 1))
        }
        return segments
    }

    private func mergeSegments(_ segments: [(start: Int, end: Int)], gapThreshold: Int) -> [(start: Int, end: Int)] {
        guard !segments.isEmpty else { return segments }
        var merged: [(start: Int, end: Int)] = [segments[0]]

        for segment in segments.dropFirst() {
            if let last = merged.last, segment.start - last.end - 1 <= gapThreshold {
                merged[merged.count - 1] = (start: last.start, end: segment.end)
            } else {
                merged.append(segment)
            }
        }
        return merged
    }

    
    /// Fallback title bar text if TEXT.BMP not available
    private func drawTitleBarTextFallback(_ text: String, centeredIn rect: NSRect, in context: CGContext) {
        context.saveGState()
        let textCenterY = rect.midY
        context.translateBy(x: 0, y: textCenterY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -textCenterY)
        
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 8, weight: .bold)
        ]
        let textSize = text.size(withAttributes: attrs)
        let textX = rect.midX - textSize.width / 2
        let textY = rect.midY - textSize.height / 2
        text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
        context.restoreGState()
    }
    
    /// Draw Plex browser side borders
    private func drawPlexBrowserSideBorders(in context: CGContext, bounds: NSRect) {
        // Try to use library-window.png first
        if let libraryImage = Skin.libraryWindowImage {
            drawLibraryWindowSideBorders(from: libraryImage, in: context, bounds: bounds)
            return
        }
        
        // Fall back to pledit sprites
        guard let pleditImage = skin.pledit else { return }
        
        let layout = SkinElements.PlexBrowser.Layout.self
        let titleHeight = layout.titleBarHeight
        let statusHeight = layout.statusBarHeight
        
        // Left side border
        var y: CGFloat = titleHeight
        while y < bounds.height - statusHeight {
            let h = min(29, bounds.height - statusHeight - y)
            drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.leftSideTile,
                      to: NSRect(x: 0, y: y, width: 12, height: h), in: context)
            y += 29
        }
        
        // Right side border (before scrollbar)
        y = titleHeight
        while y < bounds.height - statusHeight {
            let h = min(29, bounds.height - statusHeight - y)
            drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.rightSideTile,
                      to: NSRect(x: bounds.width - 20, y: y, width: 20, height: h), in: context)
            y += 29
        }
    }
    
    /// Draw thin side borders to match other windows
    /// Uses PlexBrowser title height (20px) to match PLEDIT sprites used for title bar
    private func drawLibraryWindowSideBorders(from image: NSImage, in context: CGContext, bounds: NSRect) {
        // Use PlexBrowser titleBarHeight (20px) to match PLEDIT title bar sprites
        // NOT LibraryWindow.Layout.titleBarHeight (18px) which would leave a gap
        let titleHeight = SkinElements.PlexBrowser.Layout.titleBarHeight
        let borderHeight: CGFloat = 3  // Thin bottom border
        let borderWidth: CGFloat = 3   // Thin side borders
        
        // Left side border - thin line
        NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.18, alpha: 1.0).setFill()
        context.fill(NSRect(x: 0, y: titleHeight, width: borderWidth, height: bounds.height - titleHeight - borderHeight))
        
        // Left highlight - skip on non-Retina displays to prevent visible lines
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        if backingScale >= 1.5 {
            NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.30, alpha: 1.0).setFill()
            context.fill(NSRect(x: borderWidth - 1, y: titleHeight, width: 1, height: bounds.height - titleHeight - borderHeight))
        }
        
        // Right side - thin edge after scrollbar area
        NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.18, alpha: 1.0).setFill()
        context.fill(NSRect(x: bounds.width - borderWidth, y: titleHeight, width: borderWidth, height: bounds.height - titleHeight - borderHeight))
    }
    
    /// Draw Plex browser status bar at bottom
    private func drawPlexBrowserStatusBar(in context: CGContext, bounds: NSRect) {
        // Try to use library-window.png first
        if let libraryImage = Skin.libraryWindowImage {
            drawLibraryWindowStatusBar(from: libraryImage, in: context, bounds: bounds)
            return
        }
        
        // Fall back to playlist colors
        let layout = SkinElements.PlexBrowser.Layout.self
        let statusHeight = layout.statusBarHeight
        let statusY = bounds.height - statusHeight
        
        // Use playlist colors for consistent look
        let colors = skin.playlistColors
        
        // Draw status bar background
        colors.normalBackground.withAlphaComponent(0.8).setFill()
        context.fill(NSRect(x: 0, y: statusY, width: bounds.width, height: statusHeight))
        
        // Draw top border line - skip on non-Retina displays to prevent visible lines
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        if backingScale >= 1.5 {
            NSColor(calibratedWhite: 0.3, alpha: 0.5).setFill()
            context.fill(NSRect(x: 0, y: statusY, width: bounds.width, height: 1))
        }
    }
    
    /// Draw bottom border using a thin line like other windows
    private func drawLibraryWindowStatusBar(from image: NSImage, in context: CGContext, bounds: NSRect) {
        // Just draw a thin bottom border line (2-3 pixels) to match playlist/EQ windows
        let borderHeight: CGFloat = 3
        let statusY = bounds.height - borderHeight
        
        // Draw thin bottom border matching the window chrome color
        NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.18, alpha: 1.0).setFill()
        context.fill(NSRect(x: 0, y: statusY, width: bounds.width, height: borderHeight))
        
        // Draw highlight line at top of border - skip on non-Retina displays to prevent visible lines
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        if backingScale >= 1.5 {
            NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.30, alpha: 1.0).setFill()
            context.fill(NSRect(x: 0, y: statusY, width: bounds.width, height: 1))
        }
    }
    
    /// Draw Plex browser scrollbar
    func drawPlexBrowserScrollbar(in context: CGContext, bounds: NSRect, scrollPosition: CGFloat, contentHeight: CGFloat) {
        // Try to use library-window.png first
        if let libraryImage = Skin.libraryWindowImage {
            drawLibraryWindowScrollbar(from: libraryImage, in: context, bounds: bounds, scrollPosition: scrollPosition)
            return
        }
        
        // Fall back to pledit sprites
        guard let pleditImage = skin.pledit else {
            drawFallbackPlexBrowserScrollbar(in: context, bounds: bounds, scrollPosition: scrollPosition)
            return
        }
        
        let layout = SkinElements.PlexBrowser.Layout.self
        let titleHeight = layout.titleBarHeight + layout.serverBarHeight + layout.tabBarHeight
        let statusHeight = layout.statusBarHeight
        let trackHeight = bounds.height - titleHeight - statusHeight
        let scrollbarX = bounds.width - 15
        
        // Draw scrollbar track background
        var y: CGFloat = titleHeight
        while y < bounds.height - statusHeight {
            let h = min(29, bounds.height - statusHeight - y)
            drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.scrollbarTrack,
                      to: NSRect(x: scrollbarX, y: y, width: 8, height: h), in: context)
            y += 29
        }
        
        // Draw scrollbar thumb
        let thumbHeight: CGFloat = 18
        let availableTrack = trackHeight - thumbHeight
        let thumbY = titleHeight + (availableTrack * scrollPosition)
        
        drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.scrollbarThumbNormal,
                  to: NSRect(x: scrollbarX, y: thumbY, width: 8, height: thumbHeight), in: context)
    }
    
    /// Draw scrollbar for library window using pledit sprites (same style as playlist)
    private func drawLibraryWindowScrollbar(from image: NSImage, in context: CGContext, bounds: NSRect, scrollPosition: CGFloat) {
        // Use pledit sprites for consistent look with playlist window
        guard let pleditImage = skin.pledit else {
            drawFallbackPlexBrowserScrollbar(in: context, bounds: bounds, scrollPosition: scrollPosition)
            return
        }
        
        // Use the PlexBrowser layout since that's what the view uses
        let plexLayout = SkinElements.PlexBrowser.Layout.self
        let titleHeight = plexLayout.titleBarHeight + plexLayout.serverBarHeight + plexLayout.tabBarHeight
        let statusHeight: CGFloat = 3  // Thin bottom border
        let scrollbarWidth: CGFloat = 8  // Standard playlist scrollbar width
        let scrollbarX = bounds.width - scrollbarWidth - 3  // Right at the edge
        
        let trackHeight = bounds.height - titleHeight - statusHeight
        
        // Draw scrollbar track background (tiled)
        var y: CGFloat = titleHeight
        while y < bounds.height - statusHeight {
            let h = min(29, bounds.height - statusHeight - y)
            drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.scrollbarTrack,
                      to: NSRect(x: scrollbarX, y: y, width: scrollbarWidth, height: h), in: context)
            y += 29
        }
        
        // Draw scrollbar thumb
        let thumbHeight: CGFloat = 18
        let availableTrack = trackHeight - thumbHeight
        let thumbY = titleHeight + (availableTrack * max(0, min(1, scrollPosition)))
        
        drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.scrollbarThumbNormal,
                  to: NSRect(x: scrollbarX, y: thumbY, width: scrollbarWidth, height: thumbHeight), in: context)
    }
    
    /// Draw Plex browser in shade mode
    func drawPlexBrowserShade(in context: CGContext, bounds: NSRect, isActive: Bool, pressedButton: PlexBrowserButtonType?) {
        // Use playlist shade sprites
        if let pleditImage = skin.pledit {
            // Left corner
            drawSprite(from: pleditImage, sourceRect: SkinElements.PlaylistShade.leftCorner,
                      to: NSRect(x: 0, y: 0, width: 25, height: 14), in: context)
            
            // Right corner
            let rightCornerX = bounds.width - 75
            drawSprite(from: pleditImage, sourceRect: SkinElements.PlaylistShade.rightCorner,
                      to: NSRect(x: rightCornerX, y: 0, width: 75, height: 14), in: context)
            
            // Tile middle
            var x: CGFloat = 25
            while x < rightCornerX {
                let tileWidth = min(25, rightCornerX - x)
                drawSprite(from: pleditImage, sourceRect: SkinElements.PlaylistShade.tile,
                          to: NSRect(x: x, y: 0, width: tileWidth, height: 14), in: context)
                x += 25
            }
            
            // Draw "PLEX" text in shade mode using the same pixel font style
            drawTitleBarText("PLEX", centeredIn: NSRect(x: 25, y: 0, width: 50, height: 14), in: context)
        } else {
            // Fallback shade background
            let gradient = NSGradient(colors: [
                isActive ? NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.5, alpha: 1.0) : NSColor(calibratedWhite: 0.3, alpha: 1.0),
                isActive ? NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.3, alpha: 1.0) : NSColor(calibratedWhite: 0.2, alpha: 1.0)
            ])
            gradient?.draw(in: bounds, angle: 90)
            
            // Draw PLEX label
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.boldSystemFont(ofSize: 9)
            ]
            "PLEX".draw(at: NSPoint(x: 6, y: 3), withAttributes: attrs)
        }
        
        // Draw window control buttons (relative to right edge)
        let closeRect = NSRect(x: bounds.width + SkinElements.PlaylistShade.Positions.closeButton.minX,
                               y: SkinElements.PlaylistShade.Positions.closeButton.minY,
                               width: 9, height: 9)
        let shadeRect = NSRect(x: bounds.width + SkinElements.PlaylistShade.Positions.shadeButton.minX,
                               y: SkinElements.PlaylistShade.Positions.shadeButton.minY,
                               width: 9, height: 9)
        
        let closeState: ButtonState = (pressedButton == .close) ? .pressed : .normal
        drawButton(.close, state: closeState, at: closeRect, in: context)
        
        let shadeState: ButtonState = (pressedButton == .shade) ? .pressed : .normal
        drawButton(.unshade, state: shadeState, at: shadeRect, in: context)
    }
    
    // MARK: - Plex Browser Fallback Rendering
    
    private func drawFallbackPlexBrowserTitleBar(in context: CGContext, bounds: NSRect, isActive: Bool) {
        let titleHeight = SkinElements.PlexBrowser.Layout.titleBarHeight
        let titleRect = NSRect(x: 0, y: 0, width: bounds.width, height: titleHeight)
        
        // Draw gradient background
        if isActive {
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.5, alpha: 1.0),
                NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.25, alpha: 1.0)
            ])
            gradient?.draw(in: titleRect, angle: 90)
        } else {
            let gradient = NSGradient(colors: [
                NSColor(calibratedWhite: 0.35, alpha: 1.0),
                NSColor(calibratedWhite: 0.25, alpha: 1.0)
            ])
            gradient?.draw(in: titleRect, angle: 90)
        }
        
        // Draw decorative left bar
        NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.3, alpha: 1.0).setFill()
        context.fill(NSRect(x: 4, y: 6, width: 8, height: 8))
        
        // Title text - flip back for text rendering
        context.saveGState()
        context.translateBy(x: 0, y: titleHeight)
        context.scaleBy(x: 1, y: -1)
        
        let title = "PLEX BROWSER"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 8)
        ]
        let titleSize = title.size(withAttributes: attrs)
        let titleX = (bounds.width - titleSize.width) / 2
        title.draw(at: NSPoint(x: titleX, y: (titleHeight - titleSize.height) / 2), withAttributes: attrs)
        
        context.restoreGState()
        
        // Window control buttons
        NSColor(calibratedWhite: 0.4, alpha: 1.0).setFill()
        context.fill(NSRect(x: bounds.width - 22, y: 6, width: 9, height: 9))
        context.fill(NSRect(x: bounds.width - 11, y: 6, width: 9, height: 9))
    }
    
    private func drawFallbackPlexBrowserScrollbar(in context: CGContext, bounds: NSRect, scrollPosition: CGFloat) {
        let layout = SkinElements.PlexBrowser.Layout.self
        let titleHeight = layout.titleBarHeight + layout.serverBarHeight + layout.tabBarHeight
        let statusHeight = layout.statusBarHeight
        let scrollbarWidth: CGFloat = 15
        
        let scrollRect = NSRect(
            x: bounds.width - scrollbarWidth,
            y: titleHeight,
            width: scrollbarWidth,
            height: bounds.height - titleHeight - statusHeight
        )
        
        // Track background
        NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.2, alpha: 1.0).setFill()
        context.fill(scrollRect)
        
        // Thumb
        let thumbHeight: CGFloat = max(20, scrollRect.height * 0.2)
        let availableTrack = scrollRect.height - thumbHeight
        let thumbY = scrollRect.minY + (availableTrack * scrollPosition)
        
        NSColor(calibratedRed: 0.6, green: 0.55, blue: 0.35, alpha: 1.0).setFill()
        let thumbRect = NSRect(x: scrollRect.minX + 2, y: thumbY, width: scrollRect.width - 4, height: thumbHeight)
        context.fill(thumbRect)
    }
    
    // MARK: - Core Drawing Methods
    
    /// Draw a sprite from a sprite sheet to a destination rect
    /// - Parameters:
    ///   - image: The sprite sheet image
    ///   - sourceRect: Source rectangle in Winamp coordinates (origin top-left)
    ///   - destRect: Destination rectangle (already in transformed context coordinates)
    ///   - context: The graphics context to draw into
    func drawSprite(from image: NSImage, sourceRect: NSRect, to destRect: NSRect, in context: CGContext) {
        // The context is already flipped (Y-axis inverted) to match Winamp's top-down coordinate system.
        // Source rect is in Winamp coordinates (origin top-left).
        // NSImage source coordinates use origin at bottom-left.
        // With respectFlipped: false, we draw the image in its natural orientation
        // and handle all coordinate transforms ourselves.
        
        let imageHeight = image.size.height
        let convertedSourceRect = NSRect(
            x: sourceRect.origin.x,
            y: imageHeight - sourceRect.origin.y - sourceRect.height,
            width: sourceRect.width,
            height: sourceRect.height
        )
        
        // Save context state to apply local transform for this sprite
        context.saveGState()
        
        // To draw correctly in the flipped context without NSImage's respectFlipped
        // fighting with our transform, we need to flip locally around the dest rect center
        // and draw with respectFlipped: false
        
        // Move to the destination, flip vertically around dest center, then draw
        let centerY = destRect.midY
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        
        image.draw(in: destRect,
                   from: convertedSourceRect,
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: false,
                   hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
        
        context.restoreGState()
    }
    
    /// Draw a full image to a rect
    func drawImage(_ image: NSImage, in rect: NSRect, context: CGContext) {
        context.saveGState()
        
        let centerY = rect.midY
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        
        image.draw(in: rect,
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: false,
                   hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
        
        context.restoreGState()
    }
    
    /// Draw a sprite for tiled sections - uses default interpolation for smoother tile seams
    /// Use this for repeating tile patterns where seams between tiles should blend smoothly
    func drawTiledSprite(from image: NSImage, sourceRect: NSRect, to destRect: NSRect, in context: CGContext) {
        let imageHeight = image.size.height
        let convertedSourceRect = NSRect(
            x: sourceRect.origin.x,
            y: imageHeight - sourceRect.origin.y - sourceRect.height,
            width: sourceRect.width,
            height: sourceRect.height
        )
        
        context.saveGState()
        
        let centerY = destRect.midY
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        
        // Use default interpolation (no hint) for smoother tile seams on non-Retina displays
        image.draw(in: destRect,
                   from: convertedSourceRect,
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: false,
                   hints: nil)
        
        context.restoreGState()
    }
    
    // MARK: - Fallback Rendering
    
    private func drawFallbackMainBackground(in context: CGContext, bounds: NSRect, isActive: Bool) {
        // Classic Winamp dark gray background
        NSColor(calibratedWhite: 0.18, alpha: 1.0).setFill()
        context.fill(bounds)
        
        // Title bar gradient
        let titleRect = NSRect(x: 0, y: bounds.height - SkinElements.titleBarHeight,
                               width: bounds.width, height: SkinElements.titleBarHeight)
        
        if isActive {
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.6, alpha: 1.0),
                NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.3, alpha: 1.0)
            ])
            gradient?.draw(in: titleRect, angle: 90)
        } else {
            NSColor(calibratedWhite: 0.3, alpha: 1.0).setFill()
            context.fill(titleRect)
        }
        
        // Draw border
        NSColor.black.setStroke()
        context.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
    }
    
    private func drawFallbackButton(_ button: ButtonType, state: ButtonState, at position: NSRect, in context: CGContext) {
        // Button background
        let isPressed = (state == .pressed || state == .activePressed)
        let bgColor = isPressed ? NSColor(calibratedWhite: 0.25, alpha: 1.0) : NSColor(calibratedWhite: 0.15, alpha: 1.0)
        bgColor.setFill()
        
        let path = NSBezierPath(roundedRect: position, xRadius: 2, yRadius: 2)
        path.fill()
        
        NSColor.darkGray.setStroke()
        path.stroke()
        
        // Draw button symbol
        NSColor.lightGray.setFill()
        let cx = position.midX
        let cy = position.midY
        
        switch button {
        case .previous:
            drawSymbol(in: context, cx: cx, cy: cy, type: .previous)
        case .play:
            drawSymbol(in: context, cx: cx, cy: cy, type: .play)
        case .pause:
            drawSymbol(in: context, cx: cx, cy: cy, type: .pause)
        case .stop:
            drawSymbol(in: context, cx: cx, cy: cy, type: .stop)
        case .next:
            drawSymbol(in: context, cx: cx, cy: cy, type: .next)
        case .eject:
            drawSymbol(in: context, cx: cx, cy: cy, type: .eject)
        default:
            break
        }
    }
    
    private enum SymbolType {
        case previous, play, pause, stop, next, eject
    }
    
    private func drawSymbol(in context: CGContext, cx: CGFloat, cy: CGFloat, type: SymbolType) {
        let path = NSBezierPath()
        
        switch type {
        case .previous:
            // |<<
            path.move(to: NSPoint(x: cx - 6, y: cy - 5))
            path.line(to: NSPoint(x: cx - 6, y: cy + 5))
            path.line(to: NSPoint(x: cx - 4, y: cy + 5))
            path.line(to: NSPoint(x: cx - 4, y: cy - 5))
            path.close()
            path.move(to: NSPoint(x: cx - 2, y: cy))
            path.line(to: NSPoint(x: cx + 3, y: cy - 5))
            path.line(to: NSPoint(x: cx + 3, y: cy + 5))
            path.close()
            
        case .play:
            // >
            path.move(to: NSPoint(x: cx - 4, y: cy - 5))
            path.line(to: NSPoint(x: cx - 4, y: cy + 5))
            path.line(to: NSPoint(x: cx + 5, y: cy))
            path.close()
            
        case .pause:
            // ||
            path.appendRect(NSRect(x: cx - 5, y: cy - 5, width: 3, height: 10))
            path.appendRect(NSRect(x: cx + 2, y: cy - 5, width: 3, height: 10))
            
        case .stop:
            // Square
            path.appendRect(NSRect(x: cx - 4, y: cy - 4, width: 8, height: 8))
            
        case .next:
            // >>|
            path.move(to: NSPoint(x: cx - 7, y: cy - 5))
            path.line(to: NSPoint(x: cx - 7, y: cy + 5))
            path.line(to: NSPoint(x: cx - 2, y: cy))
            path.close()
            path.move(to: NSPoint(x: cx - 2, y: cy - 5))
            path.line(to: NSPoint(x: cx - 2, y: cy + 5))
            path.line(to: NSPoint(x: cx + 3, y: cy))
            path.close()
            path.appendRect(NSRect(x: cx + 4, y: cy - 5, width: 2, height: 10))
            
        case .eject:
            // Triangle + line
            path.move(to: NSPoint(x: cx - 5, y: cy - 2))
            path.line(to: NSPoint(x: cx + 5, y: cy - 2))
            path.line(to: NSPoint(x: cx, y: cy + 4))
            path.close()
            path.appendRect(NSRect(x: cx - 5, y: cy - 5, width: 10, height: 2))
        }
        
        path.fill()
    }
    
    private func drawFallbackTimeDisplay(minutes: Int, seconds: Int, isNegative: Bool = false, in context: CGContext) {
        let prefix = isNegative ? "-" : ""
        let timeString = String(format: "%@%02d:%02d", prefix, minutes, seconds)
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.green,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        ]
        
        let rect = NSRect(x: 48, y: 26, width: 63, height: 13)
        timeString.draw(in: rect, withAttributes: attrs)
    }
    
    private func drawFallbackPlaybackStatus(_ state: PlaybackState, in context: CGContext) {
        let position = SkinElements.PlayStatus.Positions.status
        let rect = NSRect(origin: position, size: NSSize(width: 9, height: 9))
        
        switch state {
        case .playing:
            NSColor.green.setFill()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
            path.close()
            path.fill()
        case .paused:
            NSColor.yellow.setFill()
            context.fill(NSRect(x: rect.minX, y: rect.minY, width: 3, height: rect.height))
            context.fill(NSRect(x: rect.minX + 5, y: rect.minY, width: 3, height: rect.height))
        case .stopped:
            NSColor.gray.setFill()
            context.fill(rect.insetBy(dx: 1, dy: 1))
        }
    }
    
    private func drawFallbackSlider(value: CGFloat, rect: NSRect, in context: CGContext) {
        // Background
        NSColor.darkGray.setFill()
        context.fill(rect)
        
        // Progress fill
        let fillRect = NSRect(x: rect.minX, y: rect.minY,
                             width: rect.width * value, height: rect.height)
        NSColor.green.setFill()
        context.fill(fillRect)
        
        // Border
        NSColor.gray.setStroke()
        context.stroke(rect)
    }
    
    private func drawFallbackEQBackground(in context: CGContext, bounds: NSRect) {
        // Dark background
        NSColor(calibratedWhite: 0.15, alpha: 1.0).setFill()
        context.fill(bounds)
        
        // Title bar
        let titleRect = NSRect(x: 0, y: bounds.height - 14, width: bounds.width, height: 14)
        NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.5, alpha: 1.0).setFill()
        context.fill(titleRect)
        
        // Draw EQ text
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 9)
        ]
        "EQUALIZER".draw(at: NSPoint(x: 6, y: bounds.height - 12), withAttributes: attrs)
        
        // Draw frequency labels
        let freqs = ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"]
        let smallAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.green,
            .font: NSFont.systemFont(ofSize: 6)
        ]
        
        for (i, freq) in freqs.enumerated() {
            let x = SkinElements.Equalizer.Sliders.firstBandX + CGFloat(i) * SkinElements.Equalizer.Sliders.bandSpacing
            freq.draw(at: NSPoint(x: x, y: 20), withAttributes: smallAttrs)
        }
    }
}

// MARK: - Convenience Methods

extension SkinRenderer {
    
    /// Create a renderer with the current skin from WindowManager
    static var current: SkinRenderer {
        let skin = WindowManager.shared.currentSkin ?? SkinLoader.shared.loadDefault()
        return SkinRenderer(skin: skin)
    }
}
