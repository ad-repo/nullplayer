---
name: Library Window Skin
overview: Replace the Plex browser window frame/borders with the new library-window.png asset, using the established scaling and coordinate system patterns from the playlist window. Only the window chrome (title bar, borders, scrollbar) changes - interior content remains unchanged.
todos:
  - id: load-image
    content: Add libraryWindowImage property to load library-window.png from bundle
    status: completed
  - id: sprite-coords
    content: Add LibraryWindow sprite coordinates to SkinElements.swift based on PNG dimensions
    status: completed
  - id: update-renderer
    content: Update SkinRenderer Plex browser methods to use library-window.png sprites
    status: completed
  - id: update-title
    content: Change title text from PLEX BROWSER to WINAMP LIBRARY
    status: completed
  - id: test-scaling
    content: Verify window scales correctly at different sizes
    status: completed
---

# Replace Plex Browser Window with Library Window Skin

## Overview

The Plex browser currently uses playlist sprites (`PLEDIT.BMP`) for its window chrome. This plan replaces that with a custom `library-window.png` asset for the window borders/title while keeping the interior content unchanged.

## Key Files to Modify

- [`SkinElements.swift`](Sources/AdAmp/Skin/SkinElements.swift) - Add LibraryWindow sprite coordinates
- [`SkinRenderer.swift`](Sources/AdAmp/Skin/SkinRenderer.swift) - Update Plex browser drawing methods to use library-window.png
- [`Skin.swift`](Sources/AdAmp/Skin/Skin.swift) - Add property for library window image

## Library Window Sprite Regions

Based on the `library-window.png` asset (approximately 500x400 pixels showing a classic Winamp library window), extract these regions:

**Title Bar (20px height)**:

- Left corner: `(0, 0, 25, 20)` - contains window drag area
- Tile: `(25, 0, 25, 20)` - repeatable middle section
- Right corner: `(width-25, 0, 25, 20)` - contains close/shade buttons

**Side Borders**:

- Left tile: `(0, 20, 12, 29)` - repeatable vertically
- Right tile: `(width-20, 20, 20, 29)` - includes scrollbar area, repeatable vertically

**Bottom/Status Bar (20px height)**:

- Left corner: `(0, height-20, 12, 20)`
- Tile: `(12, height-20, 25, 20)` - repeatable horizontally
- Right corner: `(width-20, height-20, 20, 20)`

**Scrollbar**:

- Track background: extract from right border area
- Thumb: `(8x18)` as per Winamp standard

## Implementation Steps

### 1. Add Library Window Image to Skin System

In [`Skin.swift`](Sources/AdAmp/Skin/Skin.swift), the image will be loaded from the bundle (not from .wsz skins):

```swift
// Add computed property to load from bundle
static var libraryWindowImage: NSImage? {
    guard let url = Bundle.module.url(forResource: "library-window", withExtension: "png") else { return nil }
    return NSImage(contentsOf: url)
}
```

### 2. Define Sprite Coordinates in SkinElements.swift

Add new `LibraryWindow` struct with sprite regions extracted from the PNG:

```swift
struct LibraryWindow {
    // The PNG dimensions (will be determined from actual image)
    static let imageSize = NSSize(width: 500, height: 400)
    
    struct TitleBar {
        static let leftCorner = NSRect(x: 0, y: 0, width: 25, height: 20)
        static let tile = NSRect(x: 25, y: 0, width: 25, height: 20)
        static let rightCorner = NSRect(x: 475, y: 0, width: 25, height: 20)
    }
    // ... side borders, status bar, scrollbar
}
```

### 3. Update SkinRenderer.swift

Modify the Plex browser drawing methods to use the library window image:

- `drawPlexBrowserWindow()` - main entry point (no change needed, delegates to sub-methods)
- `drawPlexBrowserTitleBar()` - use library-window.png sprites instead of pledit sprites
- `drawPlexBrowserSideBorders()` - use library-window.png sprites
- `drawPlexBrowserStatusBar()` - use library-window.png sprites
- `drawPlexBrowserScrollbar()` - use library-window.png sprites

**Title text change**: Update `plexTitleText` constant from `"PLEX BROWSER"` to `"WINAMP LIBRARY"`.

### 4. Scaling Architecture (Matching Playlist Pattern)

The existing scaling in `PlexBrowserView.swift` already follows the established pattern:

```swift
private var originalWindowSize: NSSize {
    return SkinElements.PlexBrowser.minSize  // 480x300
}

private var scaleFactor: CGFloat {
    let originalSize = originalWindowSize
    let scaleX = bounds.width / originalSize.width
    let scaleY = bounds.height / originalSize.height
    return min(scaleX, scaleY)
}
```

This pattern is correct and matches Main/EQ/Playlist windows. No changes needed to the view's scaling logic.

### 5. Coordinate Conversion (Already Implemented)

The `convertToWinampCoordinates()` method in `PlexBrowserView.swift` already handles the coordinate transformation correctly - no changes needed.

## No Changes Required To

- Interior content drawing (server bar, tab bar, search bar, list area, status bar text)
- Hit testing logic (uses same coordinate regions)
- Shade mode (continues to use playlist shade sprites - can be updated separately if desired)
- Window controller logic

## Testing Checklist

- Window renders with new library-window.png borders at default size
- Window scales correctly when resized (borders scale proportionally)
- Title bar shows "WINAMP LIBRARY" text
- Close/shade buttons remain functional at correct positions
- Scrollbar renders and functions correctly
- Window drag from title bar still works
- All interior content (tabs, server bar, list, etc.) unchanged