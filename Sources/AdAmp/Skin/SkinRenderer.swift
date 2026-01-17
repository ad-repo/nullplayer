import AppKit

// =============================================================================
// SKIN RENDERER - Drawing code for all skin elements
// =============================================================================
// For comprehensive documentation on Winamp skin format, sprite coordinates,
// and implementation notes, see: docs/SKIN_FORMAT_RESEARCH.md
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
        guard let numbersImage = skin.numbers else {
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
    
    // MARK: - Visualization
    
    /// Draw spectrum analyzer visualization
    func drawSpectrumAnalyzer(levels: [Float], in context: CGContext) {
        // Spectrum analyzer disabled - the skin background already has this area styled
        // TODO: Implement proper skin-based visualization when needed
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
    
    /// Draw colored bar indicators on EQ slider - fills the track from knob down to bottom
    /// Colors: GREEN at top of track, YELLOW middle, ORANGE, RED at bottom
    private func drawEQSliderColorBars(at xPos: CGFloat, sliderY: CGFloat, sliderHeight: CGFloat,
                                        normalizedValue: CGFloat, in context: CGContext) {
        // Color bars disabled for now - the background already has track graphics
        // TODO: Implement proper colored bar sprites from eqmain.bmp
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
    
    // MARK: - Playlist Window
    
    /// Draw playlist window background (handles resizable windows)
    func drawPlaylistBackground(in context: CGContext, bounds: NSRect) {
        if let pleditImage = skin.pledit {
            // Title bar height is 20 pixels
            let titleHeight: CGFloat = 20
            // Bottom bar height is 38 pixels
            let bottomHeight: CGFloat = 38
            
            // For standard width (275), draw without tiling
            // For wider windows, tile the middle sections
            let standardWidth: CGFloat = 275
            
            // === TITLE BAR (TOP) ===
            if bounds.width <= standardWidth {
                // Draw the full title bar as one piece (no stretching)
                let fullTitleRect = NSRect(x: 0, y: 0, width: 275, height: 20)
                drawSprite(from: pleditImage, sourceRect: fullTitleRect,
                          to: NSRect(x: 0, y: 0, width: min(bounds.width, 275), height: titleHeight), in: context)
            } else {
                // Left corner (25 pixels)
                drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.topLeftCorner,
                          to: NSRect(x: 0, y: 0, width: 25, height: titleHeight), in: context)
                
                // Right corner (25 pixels) - positioned at right edge
                drawSprite(from: pleditImage, sourceRect: SkinElements.Playlist.topRightCorner,
                          to: NSRect(x: bounds.width - 25, y: 0, width: 25, height: titleHeight), in: context)
                
                // Middle section - tile the title bar pattern (not stretch)
                var x: CGFloat = 25
                let tileWidth: CGFloat = 25  // Use small tiles to avoid text repetition
                while x < bounds.width - 25 {
                    let w = min(tileWidth, bounds.width - 25 - x)
                    // Use a small section from the title bar that's just pattern
                    let tileSource = NSRect(x: 127, y: 0, width: 25, height: 20)
                    drawSprite(from: pleditImage, sourceRect: tileSource,
                              to: NSRect(x: x, y: 0, width: w, height: titleHeight), in: context)
                    x += tileWidth
                }
            }
            
            // === BOTTOM BAR ===
            // The bottom bar is complex - for now, draw a solid background matching the skin theme
            // This avoids rendering incorrect graphics from wrong skin coordinates
            let bottomBarRect = NSRect(x: 0, y: bounds.height - bottomHeight, width: bounds.width, height: bottomHeight)
            
            // Use a dark color that matches Winamp's playlist style
            NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.18, alpha: 1.0).setFill()
            context.fill(bottomBarRect)
            
            // Draw a subtle top border
            NSColor(calibratedWhite: 0.3, alpha: 1.0).setStroke()
            context.setLineWidth(1)
            context.move(to: CGPoint(x: 0, y: bounds.height - bottomHeight))
            context.addLine(to: CGPoint(x: bounds.width, y: bounds.height - bottomHeight))
            context.strokePath()
            
            // === CENTER CONTENT AREA ===
            // Fill the entire content area with the playlist background color
            // (Skip side borders as their coordinates may not match this skin)
            let centerRect = NSRect(
                x: 0,
                y: titleHeight,
                width: bounds.width,
                height: bounds.height - titleHeight - bottomHeight
            )
            skin.playlistColors.normalBackground.setFill()
            context.fill(centerRect)
        } else {
            // Fallback playlist background
            skin.playlistColors.normalBackground.setFill()
            context.fill(bounds)
        }
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
