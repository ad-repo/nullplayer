---
name: Skin Plex Browser Window
overview: Rewrite the Plex browser window to use the Winamp skin sprite system, matching the visual style of the main window, equalizer, and playlist windows. The window will use playlist sprites for the frame/chrome and maintain existing functionality.
todos:
  - id: skin-elements
    content: Add PlexBrowser layout constants to SkinElements.swift
    status: completed
  - id: skin-renderer
    content: Add Plex browser rendering methods to SkinRenderer.swift
    status: completed
  - id: view-rewrite
    content: Rewrite PlexBrowserView.swift with skin sprite drawing and coordinate transforms
    status: completed
  - id: hit-testing
    content: Implement coordinate-converted hit testing for all interactive areas
    status: completed
  - id: skin-colors
    content: Integrate playlist colors for custom content areas
    status: completed
  - id: testing
    content: Test window matches reference style and all functionality works
    status: pending
---

# Skin Plex Browser Window

## Reference Images

The user provided a screenshot showing the Winamp interface with 4 windows:

- Main window (top-left) - fully skinned with transport controls
- Equalizer (below main) - fully skinned with sliders and buttons
- Playlist (below EQ) - fully skinned with track list and bottom bar buttons
- Milkdrop visualizer (right side) - simple skinned frame with dark content area

The Milkdrop window serves as the reference style for the Plex browser: a simple skinned title bar with close/shade buttons, side borders, and a dark content area.

## Current State

The Plex browser ([`PlexBrowserView.swift`](Sources/AdAmp/Windows/PlexBrowser/PlexBrowserView.swift)) currently uses:

- **Programmatic drawing** with hardcoded colors in the `Colors` struct
- **isFlipped = true** for coordinate system (different from other windows)
- **No skin sprites** - everything drawn programmatically
- Custom title bar, tab bar, server bar, status bar

## Target Architecture

Match the playlist window pattern documented in [`docs/PLAYLIST_IMPLEMENTATION_NOTES.md`](docs/PLAYLIST_IMPLEMENTATION_NOTES.md):

1. Use coordinate transformation (flip to Winamp's top-down system)
2. Use `originalWindowSize` and `scaleFactor` for window scaling
3. Use `convertToWinampCoordinates()` for hit testing
4. Draw frame elements using `SkinRenderer` and PLEDIT.BMP sprites
5. Draw custom content (tabs, list, etc.) within the skinned frame

## Implementation Plan

### 1. Add Plex Browser Sprite Constants to SkinElements.swift

Add a new `PlexBrowser` struct that references the existing `Playlist` sprites for the frame, and define a fallback path when sprites are unavailable:

```swift
struct PlexBrowser {
    // Window dimensions (wider than playlist to fit tabs)
    static let minSize = NSSize(width: 480, height: 300)
    
    // Reuse playlist frame sprites from PLEDIT.BMP
    // Title bar, side borders, scrollbar use Playlist constants
    // Fallback if missing: draw programmatic borders + title bar with skin colors
    
    // Custom layout for Plex-specific areas
    struct Layout {
        static let titleBarHeight: CGFloat = 20
        static let tabBarHeight: CGFloat = 24
        static let serverBarHeight: CGFloat = 24
        static let statusBarHeight: CGFloat = 20
        static let scrollbarWidth: CGFloat = 20
    }
}
```

### 2. Add Plex Browser Rendering Methods to SkinRenderer.swift

Add methods that mirror the playlist rendering but adapted for the Plex browser layout:

- `drawPlexBrowserWindow(in:bounds:isActive:pressedButton:scrollPosition:)` - main entry point
- `drawPlexBrowserTitleBar(in:bounds:isActive:pressedButton:)` - using playlist title sprites
- `drawPlexBrowserSideBorders(in:bounds:)` - using playlist side tile sprites
- `drawPlexBrowserScrollbar(in:bounds:scrollPosition:contentHeight:)` - using playlist scrollbar sprites
- Fallback methods for when skin sprites are unavailable (non-crashing)

The title bar will display "PLEX BROWSER" using the skin's text font (TEXT.BMP) centered in the title area. If no existing helper exists for skinned text, add one to `SkinRenderer` and reuse it in the playlist window for consistency.

### 3. Rewrite PlexBrowserView.swift Drawing

Transform the view to match the playlist pattern:

**Remove:**

- `isFlipped` override (switch to transform-based approach)
- Hardcoded `Colors` struct
- Programmatic title bar drawing

**Add:**

- `originalWindowSize` property for scaling
- `scaleFactor` computed property
- `convertToWinampCoordinates()` method
- Transform-based drawing with coordinate flip

**Drawing order:**

1. Apply coordinate flip transformation
2. Apply scaling transformation
3. Draw skinned title bar using SkinRenderer
4. Draw skinned side borders
5. Draw custom content areas (tab bar, server bar, list, status bar) using skin colors
6. Draw skinned scrollbar

### 4. Update Hit Testing in PlexBrowserView.swift

Implement proper hit testing following the playlist pattern. Inventory and convert all existing event paths that depend on flipped coordinates (mouse down/up/drag/move, tracking areas, scroll wheel):

- Convert mouse coordinates using `convertToWinampCoordinates()`
- `hitTestTitleBar()` - for window dragging
- `hitTestCloseButton()` / `hitTestShadeButton()` - window controls
- `hitTestTabBar()` - tab selection
- `hitTestServerBar()` - server/library menus
- `hitTestScrollbar()` - scrollbar dragging
- `hitTestListArea()` - item selection

### 5. Integrate with Skin Color System

Use playlist colors from the skin for content areas:

```swift
let colors = skin?.playlistColors ?? .default
colors.normalBackground  // List background
colors.normalText        // Normal text color (green)
colors.selectedBackground // Selection highlight
colors.currentText       // Current/highlighted text
```

### 6. Add Shade Mode Support (Optional Enhancement)

Like the playlist window, add shade mode that collapses to just the title bar:

- Use `PlaylistShade` sprites
- Store `isShadeMode` state (mirror playlist pattern and persist in controller if needed)
- Double-click title bar to toggle
- Ensure layout calculations and hit testing respect shade state

## Files to Modify

1. [`SkinElements.swift`](Sources/AdAmp/Skin/SkinElements.swift) - Add PlexBrowser layout constants
2. [`SkinRenderer.swift`](Sources/AdAmp/Skin/SkinRenderer.swift) - Add Plex browser rendering methods
3. [`PlexBrowserView.swift`](Sources/AdAmp/Windows/PlexBrowser/PlexBrowserView.swift) - Complete rewrite of drawing and hit testing
4. [`PlexBrowserWindowController.swift`](Sources/AdAmp/Windows/PlexBrowser/PlexBrowserWindowController.swift) - Minor updates for shade mode
5. [`docs/PLAYLIST_IMPLEMENTATION_NOTES.md`](docs/PLAYLIST_IMPLEMENTATION_NOTES.md) - Document Plex browser frame + hit-testing pattern

## Key Patterns to Follow

From [`docs/PLAYLIST_IMPLEMENTATION_NOTES.md`](docs/PLAYLIST_IMPLEMENTATION_NOTES.md):

**Coordinate Transform:**

```swift
context.translateBy(x: 0, y: bounds.height)
context.scaleBy(x: 1, y: -1)
```

**Scaling Transform:**

```swift
if scale != 1.0 {
    let scaledWidth = originalSize.width * scale
    let scaledHeight = originalSize.height * scale
    let offsetX = (bounds.width - scaledWidth) / 2
    let offsetY = (bounds.height - scaledHeight) / 2
    context.translateBy(x: offsetX, y: offsetY)
    context.scaleBy(x: scale, y: scale)
}
```

**Coordinate Conversion:**

```swift
private func convertToWinampCoordinates(_ point: NSPoint) -> NSPoint {
    // Convert from macOS bottom-left to Winamp top-left
    let winampY = originalSize.height - ((point.y - offsetY) / scale)
    return NSPoint(x: unscaledX, y: winampY)
}
```

**Text Rendering (needs counter-flip):**

```swift
context.saveGState()
context.translateBy(x: 0, y: centerY)
context.scaleBy(x: 1, y: -1)
context.translateBy(x: 0, y: -centerY)
text.draw(at: position, withAttributes: attrs)
context.restoreGState()
```