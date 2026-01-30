# Non-Retina Display Fixes

This document details the work done to fix rendering artifacts on non-Retina (1x) displays, specifically with the default Winamp skin.

## Overview

Three main issues were identified on non-Retina displays:
1. **Blue line artifacts** - Blue-tinted pixels in the skin became visible as harsh lines/artifacts
2. **Lines under titles** - Horizontal lines appearing below window titles (Library Browser, Milkdrop)
3. **Tile seam artifacts** - Visible vertical and horizontal lines at sprite tile boundaries (Playlist window title bar, side borders, scrollbar)

## Root Causes

### Blue Line Artifacts

The default Winamp skin (`base-2.91.wsz`) contains many subtle blue-tinted pixels throughout its BMP sprite sheets. On Retina (2x) displays, these blend smoothly due to higher pixel density and anti-aliasing. On non-Retina displays, these blue pixels become visible as distinct colored lines/artifacts due to:
- Lower pixel density (1x vs 2x)
- Less effective anti-aliasing at 1x scale
- Sub-pixel rendering differences

Affected skin files: `PLEDIT.BMP`, `EQMAIN.BMP`, `MAIN.BMP`, `TITLEBAR.BMP`, `GEN.BMP`, `VOLUME.BMP`, `BALANCE.BMP`, and others.

### Lines Under Titles

This issue was caused by specific code changes that disabled anti-aliasing on non-Retina displays. When `context.setShouldAntialias(false)` was applied to `PlexBrowserView`, it created hard edges at sprite boundaries that appeared as lines under window titles.

### Tile Seam Artifacts (Playlist Window)

On non-Retina displays, visible lines appeared at boundaries where tiled sprites meet. This occurred because:
- Sprite tiles drawn edge-to-edge can have sub-pixel gaps on 1x displays
- Without anti-aliasing to blend edges, tile boundaries become visible as thin lines
- The Playlist window uses multiple tiled areas: title bar (horizontal tiles), side borders (vertical tiles), and scrollbar track (vertical tiles)

## Approaches That Did NOT Work

### 1. Modifying Skin BMP Files Directly

**Approach**: Created Swift scripts to extract the `.wsz` skin archive, modify BMP files (converting blue pixels to grayscale), and repackage.

**Problems**:
- BMP files saved by `NSBitmapImageRep` had different format characteristics than the originals
- This caused rendering artifacts, including the "lines under titles" problem
- Some attempts resulted in magenta (transparency color) becoming visible
- The modified BMPs worked differently than originals when loaded by the skin renderer

**Scripts tried**:
- `fix_blues.swift` - Basic blue-to-grayscale conversion
- `fix_blues_preserve_titlebar.swift` - Preserved title bar rows in PLEDIT.BMP
- Various iterations with different pixel selection criteria

### 2. Disabling Anti-Aliasing in Views

**Approach**: Added conditional code to disable anti-aliasing on non-Retina displays:

```swift
let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
if backingScale < 1.5 {
    context.interpolationQuality = .none
    context.setShouldAntialias(false)
    context.setAllowsAntialiasing(false)
}
```

**Problems**:
- Made the blue line artifacts MORE pronounced, not less
- Created harsh edges at sprite boundaries (the "lines under titles")
- Anti-aliasing was actually helping to blend the problematic pixels

### 3. Masking Specific Rows in Title Bars

**Approach**: Added code to `SkinRenderer.swift` to fill specific Y-coordinate rows with background color to hide highlight lines.

**Problems**:
- Required precise knowledge of which rows contained artifacts
- Different skins have different sprite layouts
- Fragile solution that could break with other skins

## Approaches That DID Work

### 1. Runtime Image Processing in SkinLoader (Current Solution)

**Approach**: Process skin images at load time, converting blue-tinted pixels to grayscale only on non-Retina displays.

**Implementation** in `SkinLoader.swift`:

```swift
private func loadSkin(from directory: URL) throws -> Skin {
    // Check if we're on a non-Retina display
    let isNonRetina = (NSScreen.main?.backingScaleFactor ?? 2.0) < 1.5
    
    func loadImage(_ name: String) -> NSImage? {
        // ... load BMP ...
        if var image = loadBMP(from: url) {
            if isNonRetina {
                image = processForNonRetina(image)
            }
            return image
        }
    }
}

private func processForNonRetina(_ image: NSImage) -> NSImage {
    // Convert blue-tinted pixels to grayscale while preserving:
    // - Magenta transparency (255, 0, 255)
    // - Bright/white pixels
    // - Warm colors (red/yellow/orange)
    
    for each pixel:
        if b > r || b > g:  // Has blue tint
            gray = luminance(r, g, b)
            set pixel to (gray, gray, gray)
}
```

**Why it works**:
- Original skin files remain unchanged
- Processing happens in memory, avoiding BMP format issues
- Only affects non-Retina displays
- Preserves transparency and warm colors

### 2. Rounded Coordinates for Text/Scroll

**Approach**: Round pixel coordinates to integers on non-Retina displays to prevent sub-pixel positioning artifacts.

**Implementation** in `PlexBrowserView.swift` and `PlaylistView.swift`:

```swift
let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
let roundedScrollOffset = backingScale < 1.5 ? round(scrollOffset) : scrollOffset
```

**Why it works**:
- Prevents text "shimmering" during scroll
- Ensures pixels align to display grid
- No visual impact on Retina displays

### 3. Opaque Backgrounds on Non-Retina

**Approach**: Use fully opaque colors instead of alpha-blended backgrounds on non-Retina displays.

**Implementation** in `PlexBrowserView.swift`:

```swift
if backingScaleForBg < 1.5 {
    colors.normalBackground.setFill()  // Opaque
} else {
    colors.normalBackground.withAlphaComponent(0.6).setFill()  // Semi-transparent
}
```

**Why it works**:
- Prevents compositing artifacts from alpha blending
- Ensures consistent background appearance

### 4. Opaque Window on Non-Retina

**Approach**: Make the Library Browser window opaque on non-Retina displays.

**Implementation** in `PlexBrowserWindowController.swift`:

```swift
let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
if backingScale < 1.5 {
    window.backgroundColor = .black
    window.isOpaque = true
} else {
    window.backgroundColor = .clear
    window.isOpaque = false
}
```

### 5. Skip Highlight Lines in SkinRenderer

**Approach**: Conditionally skip drawing certain 1-pixel highlight lines on non-Retina displays.

**Implementation** in `SkinRenderer.swift`:

```swift
let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
if backingScale >= 1.5 {
    // Only draw highlight on Retina
    NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.30, alpha: 1.0).setFill()
    context.fill(NSRect(x: borderWidth - 1, y: titleHeight, width: 1, height: ...))
}
```

### 6. NSImage-Based Title Bar Rendering (Library Browser)

**Approach**: Use NSImage-based sprite drawing instead of CGImage with `interpolationQuality = .none` for title bars.

**Problem**: The Library Browser title bar had visible horizontal lines while Milkdrop's title bar looked clean. The difference was:
- Library Browser used `CGImage`-based `drawSprite` with `context.interpolationQuality = .none`
- Milkdrop used `NSImage`-based `drawSprite` without forcing interpolation off

**Solution**: Changed `drawPlexBrowserTitleBarFromPledit` to use the same NSImage-based rendering approach as Milkdrop:

```swift
// Before (caused horizontal lines):
drawSprite(from: cgImage, sourceRect: leftCorner,
          destRect: NSRect(...), in: context)

// After (matches Milkdrop - no lines):
drawSprite(from: pleditImage, sourceRect: leftCorner,
          to: NSRect(...), in: context)
```

**Why it works**:
- NSImage-based drawing uses default interpolation which blends pixel edges
- CGImage with `.none` interpolation makes every pixel edge sharp, revealing lines in sprites
- Both title bars now use identical rendering path

### 7. Playlist Window Tile Seam Fixes

**Problem**: The Playlist window showed vertical and horizontal line artifacts at tile boundaries on non-Retina displays. These appeared in:
- Title bar (vertical lines between corner sprites and tiled middle section)
- Side borders (horizontal lines where 29px tall tiles meet)
- Scrollbar track (horizontal lines at tile boundaries)

**Solution**: A multi-part approach for each tiled area:

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
drawSprite(from: pleditImage, sourceRect: rightCorner,
          to: NSRect(x: bounds.width - rightCornerWidth - cornerOverlap, y: 0, 
                     width: rightCornerWidth + cornerOverlap, height: titleHeight), in: context)
```

#### Side Borders and Scrollbar Fix

1. Fill solid dark background first
2. Draw tiles from BOTTOM to TOP (so any partial tile is at top, hidden under title bar)

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
- Background fill ensures any sub-pixel gaps between tiles show a matching dark color instead of artifacts
- Drawing corners on top covers any imperfect seams at corner/tile boundaries
- Bottom-to-top tiling places partial tiles at the top where they're less visible
- The overlap ensures tiles blend together rather than having visible seams

### 8. Targeted Redraw for Visualization Animation

**Problem**: When the Album Art Visualizer is enabled in the Library Browser's ART mode, the top menu items (title bar, server bar) would shimmer/flicker on non-Retina displays. This happened because the visualizer timer (running at 60fps) was marking the entire view for redraw with `needsDisplay = true`.

**Solution**: Use `setNeedsDisplay(rect)` to only redraw the visualization content area, excluding the menu areas.

**Implementation** in `PlexBrowserView.swift`:

```swift
// In the visualizer timer callback:

// Only redraw the visualization content area, not the entire view
// This prevents menu items (title bar, server bar) from shimmering on non-Retina displays
let contentY = self.Layout.titleBarHeight + self.Layout.serverBarHeight
let contentHeight = self.bounds.height - contentY - self.Layout.statusBarHeight
// Convert from Winamp top-down coordinates to macOS bottom-up coordinates
let nativeY = self.Layout.statusBarHeight
let contentRect = NSRect(x: 0, y: nativeY, width: self.bounds.width, height: contentHeight)
self.setNeedsDisplay(contentRect)
```

**Why it works**:
- The visualizer timer runs at 60fps for smooth animation
- Instead of redrawing the entire view (including title bar, server bar, tabs), only the content area where the visualization is displayed gets redrawn
- The menu items remain stable since they're not part of the dirty rect
- This is a non-Retina-specific visual issue, but the fix improves performance on all displays

### 9. Targeted Redraw for Loading Animation

**Problem**: When refreshing the Library Browser, the loading spinner animation caused the top menu items (title bar, server bar, tabs) to shimmer on non-Retina displays.

**Solution**: Apply the same targeted redraw approach to the loading animation timer.

**Implementation** in `PlexBrowserView.swift`:

```swift
// In startLoadingAnimation():

// Only redraw the list area where the loading spinner is displayed
// This prevents menu items from shimmering on non-Retina displays
var listY = self.Layout.titleBarHeight + self.Layout.serverBarHeight + self.Layout.tabBarHeight
if self.browseMode == .search {
    listY += self.Layout.searchBarHeight
}
let listHeight = self.bounds.height - listY - self.Layout.statusBarHeight
// Convert from Winamp top-down coordinates to macOS bottom-up coordinates
let nativeY = self.Layout.statusBarHeight
let listRect = NSRect(x: 0, y: nativeY, width: self.bounds.width, height: listHeight)
self.setNeedsDisplay(listRect)
```

## Current State

### Files Changed from `main`

1. **`Sources/AdAmp/Skin/SkinLoader.swift`**
   - Added `processForNonRetina()` function for blue-to-grayscale conversion
   - Applied processing to loaded images on non-Retina displays
   - Skips green-dominant pixels to preserve stereo/mono indicators

2. **`Sources/AdAmp/Skin/SkinRenderer.swift`**
   - Skip certain highlight lines on non-Retina displays
   - Use NSImage-based rendering for Library Browser title bar (matches Milkdrop)
   - Playlist title bar: background fill + tile overlap + corners drawn on top (wider)
   - Playlist side borders: background fill + bottom-to-top tiling
   - Playlist scrollbar track: background fill + bottom-to-top tiling

3. **`Sources/AdAmp/Windows/PlexBrowser/PlexBrowserView.swift`**
   - Rounded coordinates for text positioning
   - Rounded scroll offset
   - Opaque backgrounds on non-Retina
   - Fill list area background to prevent gaps
   - Optimized scroll redraw
   - Targeted redraw for visualization animation (only content area, not menu items)

4. **`Sources/AdAmp/Windows/PlexBrowser/PlexBrowserWindowController.swift`**
   - Opaque window on non-Retina displays

5. **`Sources/AdAmp/Windows/Playlist/PlaylistView.swift`**
   - Rounded scroll offset on non-Retina

## Remaining Considerations

1. **Blue artifacts may still appear in some areas** - The grayscale conversion helps but may not catch all problematic pixels in all skins

2. **Other skins untested** - The runtime processing currently applies to all skins; may need refinement for skins that intentionally use blue tints

3. **Performance consideration** - Image processing at load time adds startup overhead on non-Retina displays (minimal impact in practice)

## Known Issues (Future Fixes)

### Multi-Monitor Window Rendering

**Problem**: When dragging a window across two monitors, the window cannot render across both screens simultaneously. At approximately 60% dragged onto the new monitor, the window "transitions" - it suddenly appears on the new monitor while the portion on the old monitor goes blank. Continuing to drag reveals the rest of the window on the new monitor.

**Symptoms**:
- Window content disappears from the original monitor before fully appearing on the new monitor
- Affects all windows (main, EQ, playlist, browser, milkdrop)
- More noticeable when crossing between Retina and non-Retina displays

**Likely Causes**:
1. **Backing scale factor changes** - When crossing between Retina (2x) and non-Retina (1x) displays, the window's backing properties change, potentially triggering a redraw that can't span both displays
2. **Custom drawing context** - The skin renderer's custom `draw()` implementation may assume a single-screen context
3. **GPU/display binding** - The window's layer may be bound to one display's GPU at a time

**Investigation Areas**:
- `viewDidChangeBackingProperties()` notifications in view classes
- How `SkinRenderer` handles drawing context when backing scale changes
- Whether using `wantsLayer = true` and CALayer-based rendering would help
- NSWindow's `displaysWhenScreenProfileChanges` property

**Workaround**: None currently. Windows must fully transition to one monitor before content renders correctly.

## Key Learnings

1. **Don't disable anti-aliasing** - It actually helps blend problematic pixels
2. **Avoid modifying BMP files** - Format differences cause rendering issues
3. **Runtime processing is safer** - Keeps original assets intact
4. **Test on actual hardware** - Simulator behavior differs from real non-Retina displays
5. **Blue detection needs careful thresholds** - Must preserve intended colors (green indicators, warm colors) while removing artifacts
6. **NSImage vs CGImage rendering matters** - CGImage with `interpolationQuality = .none` makes sprite edges harsh; NSImage with default interpolation blends them smoothly
7. **Tile seams need multiple strategies**:
   - Fill solid background FIRST so gaps show matching color
   - Overlap tiles by 1px to prevent visible seams
   - Draw corner sprites ON TOP (and slightly wider) to cover tile boundaries
   - Draw from bottom-to-top so partial tiles are hidden at top
8. **Non-Retina fixes must be conditional** - Always check `backingScaleFactor < 1.5` and only apply fixes on 1x displays to avoid affecting Retina rendering
9. **Use targeted redraws for animations** - When using timers for animation (like visualizers), use `setNeedsDisplay(rect)` instead of `needsDisplay = true` to only redraw the animated area. This prevents non-animated UI elements from shimmering on non-Retina displays.
