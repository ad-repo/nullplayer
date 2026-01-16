import AppKit

/// Handles pixel-perfect rendering of Winamp skin sprites
/// Renders to an offscreen 1x buffer and scales for Retina displays
class SkinRenderer {
    
    // MARK: - Properties
    
    /// The skin to render
    let skin: Skin
    
    /// Scale factor for Retina displays (renders at 1x then scales)
    var scaleFactor: CGFloat = 2.0
    
    // MARK: - Initialization
    
    init(skin: Skin) {
        self.skin = skin
    }
    
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
        case .close, .minimize, .shade:
            spriteSheet = skin.titlebar
        case .shuffle, .repeatTrack, .eqToggle, .playlistToggle:
            spriteSheet = skin.shufrep
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
    func drawTimeDisplay(minutes: Int, seconds: Int, in context: CGContext) {
        guard let numbersImage = skin.numbers else {
            drawFallbackTimeDisplay(minutes: minutes, seconds: seconds, in: context)
            return
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
    
    // MARK: - Marquee Text
    
    /// Draw scrolling marquee text
    func drawMarquee(text: String, offset: CGFloat, in context: CGContext) {
        let marqueeRect = SkinElements.TextFont.Positions.marqueeArea
        
        // Clip to marquee area
        context.saveGState()
        context.clip(to: marqueeRect)
        
        if let textImage = skin.text {
            // Draw each character from skin font
            var xPos = marqueeRect.minX - offset
            let yPos = marqueeRect.minY + (marqueeRect.height - SkinElements.TextFont.charHeight) / 2
            
            for char in text.uppercased() {
                let charRect = SkinElements.TextFont.character(char)
                let destRect = NSRect(x: xPos, y: yPos,
                                     width: SkinElements.TextFont.charWidth,
                                     height: SkinElements.TextFont.charHeight)
                
                // Only draw if visible
                if xPos + SkinElements.TextFont.charWidth > marqueeRect.minX &&
                   xPos < marqueeRect.maxX {
                    drawSprite(from: textImage, sourceRect: charRect, to: destRect, in: context)
                }
                
                xPos += SkinElements.TextFont.charWidth
            }
        } else {
            // Fallback text rendering
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.green,
                .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
            ]
            let drawPoint = NSPoint(x: marqueeRect.minX - offset, y: marqueeRect.minY + 2)
            text.draw(at: drawPoint, withAttributes: attrs)
        }
        
        context.restoreGState()
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
    
    /// Draw mono/stereo indicator
    func drawMonoStereo(isStereo: Bool, in context: CGContext) {
        guard let monosterImage = skin.monoster else { return }
        
        // Draw stereo indicator
        let stereoRect = isStereo ? SkinElements.MonoStereo.stereoOn : SkinElements.MonoStereo.stereoOff
        let stereoPos = SkinElements.MonoStereo.Positions.stereo
        drawSprite(from: monosterImage, sourceRect: stereoRect,
                  to: NSRect(origin: stereoPos, size: stereoRect.size), in: context)
        
        // Draw mono indicator (opposite state)
        let monoRect = isStereo ? SkinElements.MonoStereo.monoOff : SkinElements.MonoStereo.monoOn
        let monoPos = SkinElements.MonoStereo.Positions.mono
        drawSprite(from: monosterImage, sourceRect: monoRect,
                  to: NSRect(origin: monoPos, size: monoRect.size), in: context)
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
            let thumbWidth: CGFloat = 29
            let thumbX = trackRect.minX + (trackRect.width - thumbWidth) * value
            let thumbRect = NSRect(x: thumbX, y: trackRect.minY,
                                   width: thumbWidth, height: trackRect.height)
            
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
    
    /// Draw EQ slider (vertical)
    func drawEQSlider(bandIndex: Int, value: CGFloat, isPreamp: Bool, in context: CGContext) {
        let xPos: CGFloat
        if isPreamp {
            xPos = SkinElements.Equalizer.Sliders.preampX
        } else {
            xPos = SkinElements.Equalizer.Sliders.firstBandX + CGFloat(bandIndex) * SkinElements.Equalizer.Sliders.bandSpacing
        }
        
        let sliderHeight = SkinElements.Equalizer.Sliders.sliderHeight
        let sliderY = SkinElements.Equalizer.Sliders.sliderY
        
        // Value is -12 to +12 dB, convert to 0-1
        let normalizedValue = (value + 12) / 24
        let thumbY = sliderY + sliderHeight * (1 - normalizedValue) - 7  // 7 = half thumb height
        
        // Draw thumb
        if let eqImage = skin.eqmain {
            let thumbRect = NSRect(x: xPos, y: thumbY, width: 14, height: 11)
            drawSprite(from: eqImage, sourceRect: SkinElements.Equalizer.sliderThumbNormal, to: thumbRect, in: context)
        } else {
            // Fallback thumb
            NSColor.green.setFill()
            context.fill(NSRect(x: xPos, y: thumbY, width: 14, height: 11))
        }
    }
    
    // MARK: - Playlist Window
    
    /// Draw playlist window background (handles resizable windows)
    func drawPlaylistBackground(in context: CGContext, bounds: NSRect) {
        if let pleditImage = skin.pledit {
            // Draw corners
            drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.topLeftCorner,
                      to: NSRect(x: 0, y: 0, width: 25, height: 20), in: context)
            
            drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.topRightCorner,
                      to: NSRect(x: bounds.width - 25, y: 0, width: 25, height: 20), in: context)
            
            drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.bottomLeftCorner,
                      to: NSRect(x: 0, y: bounds.height - 38, width: 125, height: 38), in: context)
            
            drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.bottomRightCorner,
                      to: NSRect(x: bounds.width - 150, y: bounds.height - 38, width: 150, height: 38), in: context)
            
            // Tile the middle sections
            // Top tile
            var x = CGFloat(25)
            while x < bounds.width - 25 {
                let tileWidth = min(100, bounds.width - 25 - x)
                drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.topTile,
                          to: NSRect(x: x, y: 0, width: tileWidth, height: 20), in: context)
                x += 100
            }
            
            // Fill center with playlist background color
            let centerRect = NSRect(
                x: 12,
                y: SkinElements.Playlist.titleHeight,
                width: bounds.width - 31,
                height: bounds.height - SkinElements.Playlist.titleHeight - 38
            )
            skin.playlistColors.normalBackground.setFill()
            context.fill(centerRect)
        } else {
            // Fallback playlist background
            skin.playlistColors.normalBackground.setFill()
            context.fill(bounds)
            
            // Title bar
            NSColor.darkGray.setFill()
            context.fill(NSRect(x: 0, y: bounds.height - 20, width: bounds.width, height: 20))
        }
    }
    
    // MARK: - Core Drawing Methods
    
    /// Draw a sprite from a sprite sheet to a destination rect
    func drawSprite(from image: NSImage, sourceRect: NSRect, to destRect: NSRect, in context: CGContext) {
        // NSImage draws with origin at bottom-left, matching macOS coordinate system
        image.draw(in: destRect,
                   from: sourceRect,
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
    }
    
    /// Draw a full image to a rect
    func drawImage(_ image: NSImage, in rect: NSRect, context: CGContext) {
        image.draw(in: rect,
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
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
    
    private func drawFallbackTimeDisplay(minutes: Int, seconds: Int, in context: CGContext) {
        let timeString = String(format: "%02d:%02d", minutes, seconds)
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
