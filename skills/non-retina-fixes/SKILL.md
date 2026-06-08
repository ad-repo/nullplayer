---
name: non-retina-fixes
description: Non-Retina display artifact fixes, blue line issues, tile seam corrections, and targeted redraw optimizations. Use when debugging rendering issues on 1x displays or working on skin rendering code.
---

# Non-Retina Display Fixes

This guide details fixes for rendering artifacts on non-Retina (1x) displays.

## Overview

Three main issues were identified on non-Retina displays:
1. **Blue line artifacts** - Blue-tinted pixels became visible as harsh lines
2. **Lines under titles** - Horizontal lines below window titles
3. **Tile seam artifacts** - Visible lines at sprite tile boundaries

## Root Causes

### Blue Line Artifacts

The default Winamp skin contains many subtle blue-tinted pixels. On Retina (2x) displays, these blend smoothly. On non-Retina displays, they become visible due to:
- Lower pixel density (1x vs 2x)
- Less effective anti-aliasing
- Sub-pixel rendering differences

### Lines Under Titles

Caused by code that disabled anti-aliasing on non-Retina displays (`context.setShouldAntialias(false)`), creating hard edges at sprite boundaries.

### Tile Seam Artifacts

Visible lines at tile boundaries occurred because:
- Sprite tiles drawn edge-to-edge can have sub-pixel gaps on 1x displays
- Without anti-aliasing to blend edges, boundaries become visible

## Working Solutions

### 1. Rounded Coordinates for Text/Scroll

Round pixel coordinates to integers on non-Retina displays to prevent sub-pixel positioning artifacts.

**Implementation**:
```swift
let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
let roundedScrollOffset = backingScale < 1.5 ? round(scrollOffset) : scrollOffset
```

**Why it works**: Prevents text "shimmering" during scroll.

### 2. NSImage-Based Title Bar Rendering

Use NSImage-based sprite drawing instead of CGImage with `interpolationQuality = .none`.

**Solution**:
```swift
// Before (caused horizontal lines):
drawSprite(from: cgImage, sourceRect: leftCorner,
          destRect: NSRect(...), in: context)

// After (matches working windows - no lines):
drawSprite(from: pleditImage, sourceRect: leftCorner,
          to: NSRect(...), in: context)
```

**Why it works**: NSImage-based drawing uses default interpolation which blends pixel edges smoothly.

### 3. Playlist Window Tile Seam Fixes

**Problem**: Vertical and horizontal line artifacts at tile boundaries on non-Retina displays.

**Solution**: Multi-part approach for each tiled area:

#### Title Bar Fix

1. Fill solid background first to cover any gaps
2. Draw tiles with 1px overlap (step by 24px instead of 25px)
3. Draw corners ON TOP of tiles, slightly wider (+1px) to cover seams

```swift
// On non-Retina, fill background first to prevent seam gaps
let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
if backingScale < 1.5 {
    NSColor(calibratedRed: 0.14, green: 0.13, blue: 0.16, alpha: 1.0).setFill()
    context.fill(NSRect(x: 0, y: 0, width: bounds.width, height: titleHeight))
}

// Fill tiles first with overlap
let tileStep = backingScale < 1.5 ? tileWidth - 1 : tileWidth
var x: CGFloat = middleStart
while x < middleEnd {
    // ... draw tile ...
    x += tileStep
}

// Draw corners ON TOP - slightly wider on non-Retina to cover seams
let cornerOverlap: CGFloat = backingScale < 1.5 ? 1 : 0
drawSprite(from: pleditImage, sourceRect: leftCorner,
          to: NSRect(x: 0, y: 0, width: leftCornerWidth + cornerOverlap, height: titleHeight), in: context)
```

#### Side Borders and Scrollbar Fix

1. Fill solid dark background first
2. Draw tiles from BOTTOM to TOP (partial tile at top, hidden under title bar)

```swift
// On non-Retina, fill solid background first to cover any gaps
if backingScale < 1.5 {
    NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1.0).setFill()
    context.fill(NSRect(x: 0, y: titleHeight, width: 12, height: bounds.height - titleHeight - bottomHeight))
}

// Draw tiles from BOTTOM to TOP so any partial tile is at top (under title bar)
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
```

**Why it works**:
- Background fill ensures gaps show a matching dark color instead of artifacts
- Drawing corners on top covers imperfect seams at boundaries
- Bottom-to-top tiling places partial tiles where they're less visible
- Overlap ensures tiles blend together

### 4. Targeted Redraw for Visualizer Animation

**Problem**: Album Art Visualizer running at 60fps caused title bar/menu items to shimmer on non-Retina displays when marking entire view for redraw.

**Solution**: Use `setNeedsDisplay(rect)` to only redraw the visualization content area.

**Implementation** in `PlexBrowserView.swift`:

```swift
// In the visualizer timer callback:

// Only redraw the visualization content area, not the entire view
let contentY = self.Layout.titleBarHeight + self.Layout.serverBarHeight
let contentHeight = self.bounds.height - contentY - self.Layout.statusBarHeight
// Convert from Winamp top-down coordinates to macOS bottom-up coordinates
let nativeY = self.Layout.statusBarHeight
let contentRect = NSRect(x: 0, y: nativeY, width: self.bounds.width, height: contentHeight)
self.setNeedsDisplay(contentRect)
```

**Why it works**: Only the animated area gets redrawn, menu items remain stable.

### 5. Targeted Redraw for Loading Animation

**Solution**: Apply the same targeted redraw approach to the loading spinner animation.

```swift
// In startLoadingAnimation():

// Only redraw the list area where the loading spinner is displayed
var listY = self.Layout.titleBarHeight + self.Layout.serverBarHeight + self.Layout.tabBarHeight
if self.browseMode == .search {
    listY += self.Layout.searchBarHeight
}
let listHeight = self.bounds.height - listY - self.Layout.statusBarHeight
// Convert coordinates
let nativeY = self.Layout.statusBarHeight
let listRect = NSRect(x: 0, y: nativeY, width: self.bounds.width, height: listHeight)
self.setNeedsDisplay(listRect)
```

## Files Changed

1. **`Skin/SkinRenderer.swift`** - NSImage rendering for title bars, playlist tile fixes
2. **`Windows/PlexBrowser/PlexBrowserView.swift`** - Rounded coordinates, targeted redraws
3. **`Windows/Playlist/PlaylistView.swift`** - Rounded scroll offset

## Key Learnings

1. **Don't disable anti-aliasing** - It actually helps blend problematic pixels
2. **Avoid modifying BMP files** - Format differences cause rendering issues
3. **Blanket color conversion is risky** - The blue-to-grayscale conversion (issue #256) was removed because it discolored legitimate blue tones across all classic skins on 1× displays. If blue-line artifacts resurface, address them via the anti-aliasing and rounded-coordinate strategies documented in sections 1–5 above, not by mangling pixel colors.
4. **NSImage vs CGImage matters** - CGImage with `.none` makes edges harsh
5. **Tile seams need multiple strategies** - Background fill, overlap, draw order
6. **Non-Retina fixes must be conditional** - Always check `backingScaleFactor < 1.5`
7. **Use targeted redraws for animations** - Use `setNeedsDisplay(rect)` instead of `needsDisplay = true`

## Known Issues (Future Fixes)

### Multi-Monitor Window Rendering

When dragging windows across monitors, the window cannot render across both screens simultaneously. At ~60% dragged onto the new monitor, the window "transitions" - it suddenly appears on the new monitor while the portion on the old monitor goes blank.

**Likely Causes**:
1. Backing scale factor changes when crossing between Retina/non-Retina displays
2. Custom drawing context may assume single-screen context
3. Window's layer may be bound to one display's GPU at a time

**Investigation Areas**:
- `viewDidChangeBackingProperties()` notifications
- How `SkinRenderer` handles drawing context when backing scale changes
- Whether CALayer-based rendering would help
