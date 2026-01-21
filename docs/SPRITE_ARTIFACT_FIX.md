# Fixing Blue Line / Sprite Rendering Artifacts

## Problem

When using PLEDIT.BMP sprites for window title bars (like PlexBrowser), a colored line artifact may appear. The line:
- Changes color with different skins
- Appears connected to decorative elements (e.g., right corner)
- Does NOT appear in windows with tile-aligned widths (e.g., Milkdrop at 275px)

## Root Cause

The artifact is caused by **partial tile scaling** when the window width doesn't divide evenly into tile widths.

### Example (PlexBrowser)

PLEDIT title bar tiles are 25px wide. The middle section width is:
```
middleWidth = windowWidth - leftCorner(25) - rightCorner(25) = windowWidth - 50
```

**Before (broken):**
- Window width: 480px
- Middle section: 480 - 50 = 430px
- Tiles needed: 430 / 25 = **17.2 tiles** (fractional!)
- Last tile: 5px wide destination for 25px source = **scaled down**
- Scaling causes interpolation artifacts (the "blue line")

**After (fixed):**
- Window width: 500px  
- Middle section: 500 - 50 = 450px
- Tiles needed: 450 / 25 = **18 tiles** (exactly!)
- No partial tiles = no scaling = no artifacts

## Solution Checklist

When adding PLEDIT sprite support to a new window:

### 1. Use Tile-Aligned Width
```swift
// Width formula: (N * tileWidth) + leftCorner + rightCorner
// For 25px tiles: (N * 25) + 50
static let minSize = NSSize(width: 500, height: 300)  // 18 tiles
```

Common tile-aligned widths:
- 275px = 9 tiles (Milkdrop, Playlist)
- 300px = 10 tiles
- 425px = 15 tiles
- 450px = 16 tiles
- 475px = 17 tiles
- 500px = 18 tiles
- 550px = 20 tiles

### 2. Use CGImage for Sprite Drawing
```swift
guard let cgImage = pleditImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    return
}
// Use drawSprite(from: cgImage, ...) instead of NSImage version
```

The CGImage version explicitly sets `interpolationQuality = .none` for pixel-perfect rendering.

### 3. Black Background Fill
```swift
// Fill background BLACK first (not skin color)
NSColor.black.setFill()
context.fill(bounds)

// Fill only CONTENT area with skin color (below title bar)
let contentArea = NSRect(x: borderWidth, y: titleHeight, ...)
skin.playlistColors.normalBackground.setFill()
context.fill(contentArea)
```

This ensures any gaps between sprites show black (invisible) instead of skin colors.

### 4. Proper Drawing Order
Draw in this order (like Milkdrop):
1. Black background fill
2. Content area fill (skin color)
3. Side borders
4. Status bar
5. Title bar **LAST** (draws on top)

### 5. Consistent Title Bar Height
Ensure side borders start at the same Y as the title bar ends:
```swift
// Use the SAME height constant everywhere
let titleHeight = SkinElements.PlexBrowser.Layout.titleBarHeight  // 20px
// NOT LibraryWindow.Layout.titleBarHeight (18px) - this creates gaps!
```

## Debugging Tips

1. **Line changes color with skins** → Skin color bleeding through gaps
2. **Line connected to right corner** → Partial tile scaling on right side
3. **Works in Milkdrop but not PlexBrowser** → Check width alignment
4. **Line at Y=18-20** → Height mismatch between title bar and borders

## Files Involved

- `SkinElements.swift` - Window size constants (must be tile-aligned)
- `SkinRenderer.swift` - Sprite drawing functions
- `*View.swift` - View draw() methods (background fills, drawing order)
