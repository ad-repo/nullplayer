# UI & Skin Rendering Guide

Reference for working on NullPlayer's skin-style UI and skin system.

## Coordinate Systems

**skin**: Y=0 at top, Y increases downward  
**macOS**: Y=0 at bottom, Y increases upward

Apply this transform before drawing:

```swift
context.translateBy(x: 0, y: bounds.height)
context.scaleBy(x: 1, y: -1)
```

**Text requires counter-flip** (NSString draws upside-down after the transform):

```swift
context.saveGState()
let centerY = textY + fontSize / 2
context.translateBy(x: 0, y: centerY)
context.scaleBy(x: 1, y: -1)
context.translateBy(x: 0, y: -centerY)
text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
context.restoreGState()
```

## Scaling Architecture

NullPlayer uses two different resize modes for windows:

### Scaling Mode (Main Window, EQ)

Windows scale via context transform. Draw at original size, everything gets bigger/smaller proportionally:

```swift
var scaleFactor: CGFloat {
    bounds.width / originalWindowSize.width
}

override func draw(_ dirtyRect: NSRect) {
    let scale = scaleFactor
    context.translateBy(x: 0, y: bounds.height)
    context.scaleBy(x: 1, y: -1)
    
    // Use low interpolation for clean sprite scaling on large monitors
    // .none causes artifacts, .high causes blur
    // NOTE: For non-Retina specific fixes, see NON_RETINA_DISPLAY_FIXES.md
    context.interpolationQuality = .low
    
    if scale != 1.0 {
        let scaledWidth = originalWindowSize.width * scale
        let scaledHeight = originalWindowSize.height * scale
        let offsetX = (bounds.width - scaledWidth) / 2
        let offsetY = (bounds.height - scaledHeight) / 2
        context.translateBy(x: offsetX, y: offsetY)
        context.scaleBy(x: scale, y: scale)
    }
    
    let drawBounds = NSRect(origin: .zero, size: originalWindowSize)
    // Draw using drawBounds, NOT bounds
}
```

### Vertical Expansion Mode (Playlist)

The playlist window uses **vertical expansion with width-based scaling** - width is locked to match the main window, only height can change:
- Width matches main window (fixed, no horizontal resizing)
- Height expands to show more tracks (drag bottom edge)
- Title bar (20px), bottom bar (38px), and side borders stay fixed size
- SkinRenderer tiles sprites vertically to fill the space
- Scale factor is based on WIDTH only (not min of width/height like other windows)

The width lock is enforced via `minSize.width == maxSize.width`:

```swift
// Lock width (only vertical resizing allowed)
window.minSize = NSSize(width: mainFrame.width, height: Skin.playlistMinSize.height)
window.maxSize = NSSize(width: mainFrame.width, height: CGFloat.greatestFiniteMagnitude)
```

The `effectiveWindowSize` allows the height to expand beyond the minimum:

```swift
private var effectiveWindowSize: NSSize {
    let scale = scaleFactor  // width-based only
    let effectiveHeight = bounds.height / scale
    return NSSize(width: originalWindowSize.width, height: max(originalWindowSize.height, effectiveHeight))
}
```

## Hit Testing (Scaling Mode)

Convert view coordinates to skin coordinates:

```swift
private func convertToskinCoordinates(_ point: NSPoint) -> NSPoint {
    let scale = scaleFactor
    let scaledWidth = originalWindowSize.width * scale
    let scaledHeight = originalWindowSize.height * scale
    let offsetX = (bounds.width - scaledWidth) / 2
    let offsetY = (bounds.height - scaledHeight) / 2
    
    let unscaledX = (point.x - offsetX) / scale
    let unscaledY = (point.y - offsetY) / scale
    let skinY = originalWindowSize.height - unscaledY
    
    return NSPoint(x: unscaledX, y: skinY)
}
```

## Skin File Structure

`.wsz` files are ZIP archives containing:

| File | Purpose |
|------|---------|
| MAIN.BMP | Main window background |
| CBUTTONS.BMP | Transport buttons |
| TITLEBAR.BMP | Title bar sprites |
| SHUFREP.BMP | Shuffle/repeat/EQ/playlist toggles |
| POSBAR.BMP | Position slider |
| VOLUME.BMP | Volume slider |
| NUMBERS.BMP | Time display digits |
| TEXT.BMP | Marquee font |
| EQMAIN.BMP | Equalizer (275x315) |
| PLEDIT.BMP | Playlist sprites |
| PLEDIT.TXT | Playlist colors |

## Sprite Drawing

Sprites are defined in `SkinElements.swift` and drawn via `SkinRenderer`:

```swift
private func drawSprite(from image: NSImage, sourceRect: NSRect, to destRect: NSRect, in context: CGContext) {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let flippedY = image.size.height - sourceRect.origin.y - sourceRect.height
    let sourceInCG = CGRect(x: sourceRect.origin.x, y: flippedY, width: sourceRect.width, height: sourceRect.height)
    if let cropped = cgImage.cropping(to: sourceInCG) {
        context.draw(cropped, in: destRect)
    }
}
```

## Tile-Aligned Widths

Windows using PLEDIT tiles (25px) must have tile-aligned widths to avoid artifacts:

```
Width = (N * 25) + 50  (50 = left corner + right corner)
```

Valid widths: 275, 300, 425, 450, 475, 500, 550px

**Non-Retina displays**: Even with aligned widths, tile seams may be visible on 1x displays. See [NON_RETINA_DISPLAY_FIXES.md](NON_RETINA_DISPLAY_FIXES.md) for techniques like background fill, tile overlap, and bottom-to-top drawing.

## Custom Sprites

For on/off states, stack vertically in NSImage:
- y=0-11: ON state (active)
- y=12-23: OFF state (inactive)

Due to coordinate flipping:
- `sourceRect y=12` selects bottom half (active)
- `sourceRect y=0` selects top half (inactive)

```swift
let sourceRect = isActive ?
    NSRect(x: 0, y: 12, width: 27, height: 12) :
    NSRect(x: 0, y: 0, width: 27, height: 12)
```

## EQ Slider Colors

Sliders use programmatic color based on knob position (not sprites):

| Position | dB | Color |
|----------|-----|-------|
| Top | +12 | Red |
| Middle | 0 | Yellow |
| Bottom | -12 | Green |

## Playlist Text Rendering

The playlist window renders all text using the same bitmap font (`TEXT.BMP`) as the main window, ensuring visual consistency across the application.

### Implementation

Located in `Windows/Playlist/PlaylistView.swift`:

```swift
// All playlist text uses bitmap font from TEXT.BMP
// CGImage is cached outside draw cycle to prevent cross-window interference
private var cachedTextBitmapCGImage: CGImage?

private func cacheTextBitmapCGImage() {
    guard let skin = WindowManager.shared.currentSkin,
          let textImage = skin.text else { return }
    cachedTextBitmapCGImage = textImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

// Characters are drawn using CGContext with proper coordinate flipping
private func drawBitmapText(_ text: String, at position: NSPoint, in context: CGContext, skin: Skin?, isSelected: Bool = false) {
    // Crop each character from cached CGImage
    // Apply Y-flip for CGContext coordinate system
    // For selected tracks, convert green pixels to white
}
```

### Marquee Scrolling

The currently playing track marquees when its title is too long:

```swift
// Timer-based marquee offset (8Hz update rate)
private var marqueeOffset: CGFloat = 0
private var currentTrackTextWidth: CGFloat = 0

// In drawTrackText(), current track uses marqueeOffset for scrolling
let xOffset = needsMarquee ? -marqueeOffset : 0
```

### Selected Track Appearance

Selected tracks display white text instead of green. This uses pixel manipulation:

```swift
private func convertToWhite(_ charImage: CGImage, charWidth: Int, charHeight: Int) -> CGImage? {
    // Convert green (0, G, 0) pixels to white (G, G, G)
    // Magenta (255, 0, 255) pixels are treated as transparent
}
```

### Auto-Selection

When the playlist opens while music is playing, the current track is auto-selected:

```swift
override func viewDidMoveToWindow() {
    // Auto-select the currently playing track when playlist opens
    if selectedIndices.isEmpty && engine.currentIndex >= 0 {
        selectedIndices = [engine.currentIndex]
    }
}
```

### Cross-Window Interference Prevention

A key issue was `NSImage.cgImage()` affecting shared graphics state during render cycles, causing the main window marquee to switch fonts when the playlist scrolled.

**Solution**: Cache `CGImage` representation of `TEXT.BMP` outside of draw cycles, called only when skin changes or view initializes.

## Main Window Marquee

The main window uses a scrolling marquee to display the current track title.

### Skin Bitmap Font

By default, the marquee uses the skin's `TEXT.BMP` bitmap font, which provides the authentic skin look. This font only supports:
- A-Z (case-insensitive)
- 0-9
- Common symbols: `" @ : ( ) - ' ! _ + \ / [ ] ^ & % . = $ # ? *`

### Unicode Fallback

When track titles contain characters not supported by the skin font (Japanese, Cyrillic, Chinese, Korean, accented characters, etc.), the marquee automatically falls back to system font rendering:

```swift
private func containsNonLatinCharacters(_ text: String) -> Bool {
    for char in text {
        switch char {
        case "A"..."Z", "a"..."z", "0"..."9":
            continue
        case " ", "\"", "@", ":", "(", ")", "-", "'", "!", "_", "+", "\\", "/",
             "[", "]", "^", "&", "%", ".", "=", "$", "#", "?", "*":
            continue
        default:
            return true  // Non-Latin character detected
        }
    }
    return false
}
```

This ensures:
- **Latin text**: Uses skin bitmap font for authentic look
- **Non-Latin text**: Falls back to system font for proper Unicode display
- **Mixed text**: Falls back to system font if any non-Latin characters present

The system font fallback maintains the green color and scrolling behavior, just with full Unicode support.

## White Text Rendering

Some UI elements (like library/server names in the browser) require white text instead of the standard green skin font. This is implemented in `SkinRenderer.drawSkinTextWhite()`.

### Implementation

White text is rendered using an offscreen buffer approach to avoid blend mode artifacts:

```swift
// For each character:
// 1. Crop character from TEXT.BMP
// 2. Draw to small offscreen CGContext at 1x scale
// 3. Convert pixels: green channel (0, G, 0) → white (G, G, G)
// 4. Draw result to main context

for i in 0..<(charWidth * charHeight) {
    let offset = i * 4
    let g = pixels[offset + 1]  // Green channel = brightness
    
    // Skip transparent and magenta background pixels
    if a == 0 || isMagenta { continue }
    
    // Convert to white using green channel as brightness
    pixels[offset] = g     // R
    pixels[offset + 1] = g // G  
    pixels[offset + 2] = g // B
}
```

### Why Not Blend Modes?

Previous approaches using CGContext blend modes (`.color`, `.saturation`) caused artifacts:
- Green edges visible at scaled text boundaries
- Artifacts appearing/disappearing when switching views
- Sub-pixel rendering issues with scaled contexts

The offscreen buffer approach processes pixels at native resolution before scaling, eliminating these issues.

## Common Pitfalls

1. **Using `bounds` instead of `drawBounds`** after scaling transform
2. **Forgetting text counter-flip** - text appears upside-down
3. **Hit testing in view coords** - must convert to skin coords first
4. **Non-tile-aligned widths** - causes sprite interpolation artifacts
5. **Drawing over skin sprites** - they already contain labels
6. **Using blend modes for color conversion** - causes sub-pixel artifacts when scaling; use offscreen pixel manipulation instead
7. **Tile seams on non-Retina** - visible lines at tile boundaries on 1x displays; requires background fill, overlap, and careful draw order (see [NON_RETINA_DISPLAY_FIXES.md](NON_RETINA_DISPLAY_FIXES.md))

## Key Files

| File | Purpose |
|------|---------|
| `Skin/SkinElements.swift` | All sprite coordinates |
| `Skin/SkinRenderer.swift` | Drawing code |
| `Skin/SkinLoader.swift` | WSZ loading, BMP parsing |
| `Skin/MarqueeLayer.swift` | Main window marquee (bitmap font, CALayer-based) |
| `Windows/Playlist/PlaylistView.swift` | Playlist view with bitmap font rendering |
| `Windows/*/View.swift` | Window views |

## Art Visualizer Window

The Art Visualizer is an audio-reactive album art visualization window that uses Metal shaders to transform album artwork based on music frequencies.

### Key Files

| File | Purpose |
|------|---------|
| `Visualization/AudioReactiveUniforms.swift` | Audio data struct for shaders |
| `Visualization/ShaderManager.swift` | Metal pipeline management |
| `Visualization/ArtworkVisualizerView.swift` | MTKView rendering |
| `Windows/ArtVisualizer/ArtVisualizerWindowController.swift` | Window controller |
| `Windows/ArtVisualizer/ArtVisualizerContainerView.swift` | Window chrome |

### Effect Presets

| Effect | Description |
|--------|-------------|
| Clean | Original artwork, no effects |
| Subtle Pulse | Gentle brightness/scale pulse on beats |
| Liquid Dreams | Flowing displacement with color shifts |
| Glitch City | Heavy RGB split and block glitches |
| Cosmic Mirror | Kaleidoscope with chromatic aberration |
| Deep Bass | Intense displacement on low frequencies |

### Keyboard Controls (when focused)

- `Escape` - Close window (or exit fullscreen)
- `Enter` - Toggle fullscreen
- `Left/Right` - Cycle through effects
- `Up/Down` - Adjust intensity

### Browser Integration

When in ART-only mode in the Library Browser, a "VIS" button appears next to the ART button. Clicking it opens the Art Visualizer window with the currently displayed artwork.

### Audio Analysis

The visualizer uses the existing 75-band spectrum data from `AudioEngine`:
- Bands 0-9: Bass (20-250Hz)
- Bands 10-35: Mid (250-4000Hz)
- Bands 36-74: Treble (4000-20000Hz)

Beat detection triggers on bass energy spikes above threshold.

## Spectrum Analyzer Window

A standalone Metal-based spectrum analyzer visualization window that provides a larger, more detailed view of the audio spectrum than the main window's built-in analyzer.

### Opening the Window

- **Click** the spectrum analyzer display in the main window
- Context Menu → Spectrum Analyzer
- Window menu → Spectrum Analyzer

**Note:** Double-clicking the visualization area cycles the main window vis mode (Spectrum → Fire) instead of opening this window.

### Window Docking

The Spectrum Analyzer participates in the docking system alongside Main, EQ, and Playlist:
- Docks and moves with the window group when dragged
- Opens below the current vertical stack (Main → EQ → Playlist → Spectrum)
- State (visibility and position) saved with "Remember State on Quit"

### Key Files

| File | Purpose |
|------|---------|
| `Visualization/SpectrumAnalyzerView.swift` | Metal-based spectrum view component |
| `Visualization/SpectrumShaders.metal` | GPU shaders for bar rendering |
| `Windows/Spectrum/SpectrumWindowController.swift` | Window controller |
| `Windows/Spectrum/SpectrumView.swift` | Container view with skin chrome |

### Quality Modes

| Mode | Description |
|------|-------------|
| **skin** | Discrete color bands from skin's `viscolor.txt` with floating peak indicators, 3D bar shading, and segmented LED gaps |
| **Enhanced** | Rainbow LED matrix with gravity-bouncing peaks, warm amber fade trails, 3D inner glow cells, and anti-aliased rounded corners |
| **Ultra** | Maximum fidelity seamless gradient with smooth exponential decay, perceptual gamma, and warm color trails |
| **Fire** | GPU fire simulation with audio-reactive flame tongues in 4 color styles |
| **JWST** | Deep space flythrough with 3D star field, vivid JWST diffraction flares as intensity indicators, and rare giant flare events |

### Decay/Responsiveness Modes

Controls how quickly spectrum bars fall after peaks:

| Mode | Retention | Feel |
|------|-----------|------|
| Instant | 0% | No smoothing, immediate response |
| Snappy | 25% | Fast and punchy (default) |
| Balanced | 40% | Good middle ground |
| Smooth | 55% | Original skin feel |

### Window Specifications

- **Size**: 275x116 (same as main window for docking)
- **Bar count**: 55 bars (vs 19 in main window)
- **Refresh**: 60Hz via CVDisplayLink
- **Skin colors**: Uses skin's `viscolor.txt` (24 colors)

### Context Menu

Right-click on the spectrum window for:
- **Mode** submenu - Switch between skin/Enhanced/Fire/JWST modes
- **Responsiveness** submenu - Adjust decay behavior
- **Flame Style** - Choose flame color preset (Fire mode only)
- **Fire Intensity** - Choose Mellow or Intense reactivity (Fire mode only)
- **Close** - Close the window

Settings are persisted across app restarts.

## Related Documentation

- [NON_RETINA_DISPLAY_FIXES.md](NON_RETINA_DISPLAY_FIXES.md) - Fixes for rendering artifacts on 1x displays (blue lines, tile seams, text shimmering)

## External References

- [Skin Archive](https://skins.webamp.org/) - Community skin downloads
