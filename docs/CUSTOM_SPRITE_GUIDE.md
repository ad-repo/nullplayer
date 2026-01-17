# Custom Sprite Creation Guide

This guide documents how to create custom pixel-art sprites for the Winamp-style skin system, based on the "cast" indicator implementation.

## Overview

The skin system uses bitmap sprites for UI elements. When you need to create a new indicator or modify an existing one, you can programmatically generate sprites using NSImage and pixel-by-pixel drawing.

## Key Concepts

### Coordinate Systems

There are THREE coordinate systems to be aware of:

1. **Winamp/Design coordinates**: Origin at top-left, Y increases downward
2. **NSImage coordinates**: Origin at bottom-left, Y increases upward  
3. **drawSprite conversion**: The `drawSprite` function converts between these

When generating sprites in NSImage:
- If you design pixels at y=4-7 (top of design), they appear at nsY=7-4 in NSImage
- The formula `nsY = 11 - py` flips within a 12px section

### Sprite Layout for On/Off States

Standard Winamp sprites have ON and OFF states stacked vertically:
- **y=0-11**: ON state (lit/active)
- **y=12-23**: OFF state (dim/inactive)

But due to `drawSprite`'s coordinate conversion:
- Source rect `y=0` selects what's at NSImage y=12-23 (top half)
- Source rect `y=12` selects what's at NSImage y=0-11 (bottom half)

### Source Rect Selection

```swift
// When drawSprite flips coordinates, the selection is inverted:
let sourceRect = isActive ?
    NSRect(x: 0, y: 12, width: 27, height: 12) :  // Selects NSImage bottom (active)
    NSRect(x: 0, y: 0, width: 27, height: 12)     // Selects NSImage top (inactive)
```

## Implementation Pattern

### 1. Define Pixel Patterns

Define your text/icon as coordinate pairs. Design in Winamp coordinates (y=0 at top):

```swift
let mainPixels: [(Int, Int)] = [
    // Letter 'c'
    (5,5), (6,5),    // top of c
    (4,6),           // left side
    (5,7), (6,7),    // bottom of c
    // ... more letters
]
```

### 2. Add Glow Pixels (Optional)

For a glowing effect, define surrounding pixels:

```swift
let glowPixels: [(Int, Int)] = [
    // Pixels surrounding the main letter pixels
    (4,4), (5,4), (6,4), (7,4),  // above
    (3,5), (7,5),                 // sides
    // ... etc
]
```

### 3. Define Colors

```swift
let activeColor = NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)  // Bright
let glowColor = NSColor(red: 0.0, green: 0.6, blue: 0.0, alpha: 1.0)    // Dimmer
let inactiveColor = NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.35, alpha: 1.0)
```

### 4. Generate the Sprite

```swift
private func getCustomSprite() -> NSImage {
    if let cached = Self.cachedSprite { return cached }
    
    let width = 27
    let height = 24  // 12 for on, 12 for off
    
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    
    // Clear background
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    
    // Draw ACTIVE state in bottom half of NSImage (will be selected with y=12)
    // Draw glow first (underneath)
    glowColor.setFill()
    for (px, py) in glowPixels {
        let nsY = 11 - py  // Flip within 0-11 range
        NSRect(x: px, y: nsY, width: 1, height: 1).fill()
    }
    // Draw main pixels on top
    activeColor.setFill()
    for (px, py) in mainPixels {
        let nsY = 11 - py
        NSRect(x: px, y: nsY, width: 1, height: 1).fill()
    }
    
    // Draw INACTIVE state in top half of NSImage (will be selected with y=0)
    // No glow for inactive state
    inactiveColor.setFill()
    for (px, py) in mainPixels {
        let nsY = 23 - py  // Flip within 12-23 range
        NSRect(x: px, y: nsY, width: 1, height: 1).fill()
    }
    
    image.unlockFocus()
    Self.cachedSprite = image
    return image
}
```

### 5. Draw the Sprite

```swift
private func drawCustomIndicator(isActive: Bool, in context: CGContext) {
    let sprite = getCustomSprite()
    let position = NSPoint(x: 212, y: 41)  // Position in main window
    
    // Source rect accounts for drawSprite's y-flip
    let sourceRect = isActive ?
        NSRect(x: 0, y: 12, width: 27, height: 12) :
        NSRect(x: 0, y: 0, width: 27, height: 12)
    
    let destRect = NSRect(origin: position, size: NSSize(width: 27, height: 12))
    drawSprite(from: sprite, sourceRect: sourceRect, to: destRect, in: context)
}
```

## Debugging Tips

1. **Add NSLog statements** to verify which state is being rendered
2. **Check coordinate flipping** - if image appears upside down, the y-flip formula is wrong
3. **Verify source rect selection** - if wrong state shows, swap the y values in sourceRect
4. **Use static caching** - regenerate sprite only when needed, cache with `private static var`

## Example: Cast Indicator

The cast indicator replaces the mono indicator with:
- Lowercase "cast" text in pixel art
- Green glow effect when casting is active
- Flat gray when inactive
- Same size/position as original mono indicator (27x12 pixels)

See `SkinRenderer.swift` → `getCastIndicatorSprite()` for the full implementation.
