# Marquee and Playlist Text Rendering

## Overview

This document describes the text rendering approach for the main window marquee and playlist view, with emphasis on achieving consistent bitmap font rendering and preventing cross-window graphics interference.

## Current Architecture

### Main Window Marquee (`MarqueeLayer`)

The main window uses a CALayer-based marquee for GPU-accelerated scrolling:

- **File**: `Sources/NullPlayer/Skin/MarqueeLayer.swift`
- **Font**: Bitmap font from `TEXT.BMP` (skin skin)
- **Rendering**: Pre-renders text to CGImage, uses CABasicAnimation for smooth scrolling
- **Key technique**: Caches `CGImage` from `TEXT.BMP` outside of render cycle to prevent NSGraphicsContext interference

### Playlist Window (`PlaylistView`)

The playlist renders all text directly using the same bitmap font as the main window:

- **File**: `Sources/NullPlayer/Windows/Playlist/PlaylistView.swift`
- **Font**: Bitmap font from `TEXT.BMP` (same as main window)
- **Rendering**: Direct CGContext drawing in the view's `draw()` method
- **Marquee**: Timer-based offset for current track (8Hz update)
- **Selection**: White text via pixel manipulation (green-to-white conversion)

## Key Implementation Details

### Cross-Window Interference Prevention

A critical issue was discovered where scrolling the playlist would cause the main window marquee to switch to a system font. The root cause was `NSImage.cgImage(forProposedRect:context:hints:)` affecting shared graphics state when called during render cycles.

**Solution**: Cache `CGImage` representations of `TEXT.BMP` outside of draw cycles:

```swift
// In MarqueeLayer
var skinTextImage: NSImage? {
    didSet {
        cacheSkinCGImage()  // Cache CGImage immediately
        renderText()
    }
}

private func cacheSkinCGImage() {
    cachedSkinCGImage = skinTextImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

// In PlaylistView
private func cacheTextBitmapCGImage() {
    guard let skin = WindowManager.shared.currentSkin,
          let textImage = skin.text else { return }
    cachedTextBitmapCGImage = textImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
}
```

### Coordinate System Handling

skin skins use top-left origin (Y=0 at top), while macOS uses bottom-left (Y=0 at bottom). Different approaches are used:

**MarqueeLayer** (rendering to NSBitmapImageRep):
- Converts `cachedSkinCGImage` back to `NSImage` temporarily
- Uses `NSImage.draw(in:from:...)` which handles coordinate flipping internally
- Source rect Y is flipped: `skinImageHeight - charRect.origin.y - charRect.height`

**PlaylistView** (rendering to CGContext):
- Uses `CGImage.cropping()` directly (no Y-flip needed - CGImage uses same coords as skin)
- Applies per-character transform to flip for CGContext drawing:
  ```swift
  context.translateBy(x: xPos, y: position.y + CGFloat(charHeight))
  context.scaleBy(x: 1, y: -1)
  context.draw(imageToDraw, in: CGRect(x: 0, y: 0, width: charWidth, height: charHeight))
  ```

### White Text for Selected Tracks

Selected tracks in the playlist display white text instead of green. This uses pixel manipulation similar to `SkinRenderer.drawSkinTextWhite()`:

```swift
private func convertToWhite(_ charImage: CGImage, charWidth: Int, charHeight: Int) -> CGImage? {
    // Create offscreen context and draw character
    // Iterate through pixels:
    //   - If green (0, G, 0): convert to white (G, G, G)
    //   - If magenta (255, 0, 255): treat as transparent
    // Return new CGImage
}
```

### Auto-Selection of Current Track

When the playlist opens while music is already playing, the currently playing track is automatically selected:

```swift
override func viewDidMoveToWindow() {
    // ... other setup ...
    
    // Auto-select the currently playing track when playlist opens
    let engine = WindowManager.shared.audioEngine
    if selectedIndices.isEmpty && engine.currentIndex >= 0 {
        selectedIndices = [engine.currentIndex]
        selectionAnchor = engine.currentIndex
    }
}
```

## Files

| File | Purpose |
|------|---------|
| `Sources/NullPlayer/Skin/MarqueeLayer.swift` | CALayer-based GPU-accelerated marquee for main window |
| `Sources/NullPlayer/Windows/Playlist/PlaylistView.swift` | Playlist view with bitmap font rendering and marquee |
| `Sources/NullPlayer/Skin/SkinElements.swift` | Character sprite coordinates from TEXT.BMP |
| `Sources/NullPlayer/Skin/SkinRenderer.swift` | Utility methods including `drawSkinTextWhite()` |

## Issues Resolved

1. **Cross-window font interference**: Cached CGImage outside of render cycles
2. **Inconsistent fonts**: Both windows now use bitmap font from TEXT.BMP
3. **Coordinate system issues**: Proper Y-flipping for each rendering context
4. **Selected track appearance**: Pixel manipulation for white text
5. **Auto-selection on open**: Current track selected when playlist opens
