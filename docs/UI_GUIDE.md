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

Windows scale via context transform. Draw at original size:

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

## Hit Testing

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

## Common Pitfalls

1. **Using `bounds` instead of `drawBounds`** after scaling transform
2. **Forgetting text counter-flip** - text appears upside-down
3. **Hit testing in view coords** - must convert to Winamp coords first
4. **Non-tile-aligned widths** - causes sprite interpolation artifacts
5. **Drawing over skin sprites** - they already contain labels

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

## External References

- [Webamp skinSprites.ts](https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts) - Authoritative sprite coordinates
- [Winamp Skin Museum](https://skins.webamp.org/) - Skin downloads
