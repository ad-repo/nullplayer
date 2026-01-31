# UI & Skin Rendering Guide

Reference for working on AdAmp's Winamp-style UI and skin system.

## Coordinate Systems

**Winamp**: Y=0 at top, Y increases downward  
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

AdAmp uses two different resize modes for windows:

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

Convert view coordinates to Winamp coordinates:

```swift
private func convertToWinampCoordinates(_ point: NSPoint) -> NSPoint {
    let scale = scaleFactor
    let scaledWidth = originalWindowSize.width * scale
    let scaledHeight = originalWindowSize.height * scale
    let offsetX = (bounds.width - scaledWidth) / 2
    let offsetY = (bounds.height - scaledHeight) / 2
    
    let unscaledX = (point.x - offsetX) / scale
    let unscaledY = (point.y - offsetY) / scale
    let winampY = originalWindowSize.height - unscaledY
    
    return NSPoint(x: unscaledX, y: winampY)
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

## Playlist Marquee Scrolling

The playlist window features marquee scrolling for the currently playing track when its title is too long to fit in the available space.

### Implementation

Located in `Windows/Playlist/PlaylistView.swift`:

```swift
private var marqueeOffset: CGFloat = 0

// Timer fires at 30fps with 1px increments for smooth scrolling
displayTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
    self?.marqueeOffset += 1
    self?.needsDisplay = true
}
```

### Drawing Logic

In `drawTrackText()`:
1. Calculate available width (item width minus duration area)
2. If current track AND text width exceeds available width:
   - Draw text twice with simple spacing for seamless loop
   - Use `marqueeOffset` modulo cycle width for smooth wrapping
3. Clip all tracks to prevent text/duration overlap

```swift
if isCurrentTrack && textWidth > titleMaxWidth {
    let fullText = titleText + "     "  // Simple spacing between repeats
    let cycleWidth = fullText.size(withAttributes: attrs).width
    let offset = marqueeOffset.truncatingRemainder(dividingBy: cycleWidth)
    
    fullText.draw(at: NSPoint(x: titleX - offset, y: textY), withAttributes: attrs)
    fullText.draw(at: NSPoint(x: titleX - offset + cycleWidth, y: textY), withAttributes: attrs)
}
```

### Text Clipping

All track titles are clipped to prevent overlap with the duration column:

```swift
context.clip(to: NSRect(x: titleX, y: rect.minY, width: titleMaxWidth, height: rect.height))
```

This ensures long titles don't bleed into the duration area, even when not marquee scrolling.

## Main Window Marquee

The main window uses a scrolling marquee to display the current track title.

### Skin Bitmap Font

By default, the marquee uses the skin's `TEXT.BMP` bitmap font, which provides the authentic Winamp look. This font only supports:
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
3. **Hit testing in view coords** - must convert to Winamp coords first
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

## Related Documentation

- [NON_RETINA_DISPLAY_FIXES.md](NON_RETINA_DISPLAY_FIXES.md) - Fixes for rendering artifacts on 1x displays (blue lines, tile seams, text shimmering)

## External References

- [Webamp skinSprites.ts](https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts) - Authoritative sprite coordinates
- [Winamp Skin Museum](https://skins.webamp.org/) - Skin downloads
