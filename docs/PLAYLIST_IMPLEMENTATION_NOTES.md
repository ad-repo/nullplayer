# Playlist Window Implementation Notes

This document captures lessons learned while implementing the Winamp-style playlist window. Future agents should read this before modifying playlist or skin-related code.

## Table of Contents
1. [Coordinate System Fundamentals](#coordinate-system-fundamentals)
2. [Scaling Architecture](#scaling-architecture)
3. [Skin Sprite System](#skin-sprite-system)
4. [Hit Testing Pattern](#hit-testing-pattern)
5. [Bottom Bar Layout](#bottom-bar-layout)
6. [Common Pitfalls](#common-pitfalls)
7. [Code Patterns to Follow](#code-patterns-to-follow)

---

## Coordinate System Fundamentals

### The Core Problem
Winamp uses a **top-left origin** coordinate system (Y increases downward), while macOS uses a **bottom-left origin** (Y increases upward). Every drawing and hit-testing operation must account for this.

### The Solution
In the `draw()` method, apply a coordinate flip transformation BEFORE any drawing:

```swift
// Flip to Winamp coordinate system (origin at top-left)
context.translateBy(x: 0, y: bounds.height)
context.scaleBy(x: 1, y: -1)
```

After this transformation:
- Y=0 is at the TOP of the view
- Positive Y goes DOWN (like Winamp expects)
- All sprite coordinates from `SkinElements.swift` work directly

### Important: Text Rendering
Text drawn with `NSString.draw(at:)` will appear upside-down after the flip. You must apply a LOCAL counter-flip around each text draw:

```swift
context.saveGState()
let centerY = textY + fontSize / 2
context.translateBy(x: 0, y: centerY)
context.scaleBy(x: 1, y: -1)
context.translateBy(x: 0, y: -centerY)
text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
context.restoreGState()
```

---

## Scaling Architecture

### Why Scaling Matters
The `WindowManager` scales windows to match the main window width. When a window is resized:
- The `NSView` frame changes (e.g., 550x200)
- But we still want to draw as if it's the original size (e.g., 275x116)
- The graphics context must be scaled to make sprites appear larger

### The Pattern (Used in MainWindowView, EQView, PlaylistView)

```swift
// Properties needed
private var originalWindowSize: NSSize = NSSize(width: 275, height: 116)

var scaleFactor: CGFloat {
    guard originalWindowSize.width > 0 else { return 1.0 }
    return bounds.width / originalWindowSize.width
}

// In draw():
let scale = scaleFactor
let originalSize = originalWindowSize

// First flip to Winamp coords
context.translateBy(x: 0, y: bounds.height)
context.scaleBy(x: 1, y: -1)

// Then apply scaling
if scale != 1.0 {
    let scaledWidth = originalSize.width * scale
    let scaledHeight = originalSize.height * scale
    let offsetX = (bounds.width - scaledWidth) / 2
    let offsetY = (bounds.height - scaledHeight) / 2
    context.translateBy(x: offsetX, y: offsetY)
    context.scaleBy(x: scale, y: scale)
}

// Now draw using ORIGINAL dimensions
let drawBounds = NSRect(origin: .zero, size: originalSize)
renderer.drawPlaylistWindow(in: context, bounds: drawBounds, ...)
```

### Critical: All Drawing Uses Original Bounds
After the transformation, ALL drawing code operates on `drawBounds` (the original unscaled size). The context transformation handles making it appear at the correct scaled size.

---

## Skin Sprite System

### File Structure
Winamp skins are ZIP files (renamed to .wsz) containing BMP images:
- `main.bmp` - Main window elements
- `titlebar.bmp` - Title bar buttons and states
- `pledit.bmp` - Playlist window elements (title bar, buttons, scrollbar)
- `eqmain.bmp` - Equalizer elements
- `text.bmp` - Font sprites
- `nums_ex.bmp` / `numbers.bmp` - Number displays

### SkinElements.swift Structure
All sprite coordinates are defined in `SkinElements.swift` as `NSRect` constants:

```swift
struct SkinElements {
    struct Playlist {
        // Title bar components
        static let titleBarLeftCornerActive = NSRect(x: 0, y: 0, width: 25, height: 20)
        static let titleBarMiddleTile = NSRect(x: 26, y: 0, width: 25, height: 20)
        // ... etc
        
        struct Buttons {
            static let addURLNormal = NSRect(x: 0, y: 111, width: 22, height: 18)
            static let addURLPressed = NSRect(x: 23, y: 111, width: 22, height: 18)
            // ... etc
        }
    }
}
```

### How Sprites Are Drawn (SkinRenderer)
The `SkinRenderer` class has a `drawSprite` method:

```swift
private func drawSprite(from image: NSImage, sourceRect: NSRect, to destRect: NSRect, in context: CGContext) {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    
    // Convert from top-left (Winamp) to bottom-left (CGImage) coordinates
    let flippedY = image.size.height - sourceRect.origin.y - sourceRect.height
    let sourceInCG = CGRect(x: sourceRect.origin.x, y: flippedY, 
                            width: sourceRect.width, height: sourceRect.height)
    
    if let cropped = cgImage.cropping(to: sourceInCG) {
        context.draw(cropped, in: destRect)
    }
}
```

### Tiling Pattern
For resizable areas (title bar middle, side borders), sprites are TILED:

```swift
var x: CGFloat = startX
while x < endX {
    let tileWidth = min(spriteWidth, endX - x)
    drawSprite(from: image, sourceRect: tileSprite,
               to: NSRect(x: x, y: y, width: tileWidth, height: height), in: context)
    x += spriteWidth
}
```

---

## Hit Testing Pattern

### The Challenge
Mouse events come in VIEW coordinates (scaled, bottom-left origin), but we need to test against WINAMP coordinates (unscaled, top-left origin).

### The Solution: Coordinate Conversion Helper

```swift
private func convertToWinampCoordinates(_ point: NSPoint) -> NSPoint {
    let scale = scaleFactor
    let originalSize = originalWindowSize
    
    // Calculate offset (for centered scaling)
    let scaledWidth = originalSize.width * scale
    let scaledHeight = originalSize.height * scale
    let offsetX = (bounds.width - scaledWidth) / 2
    let offsetY = (bounds.height - scaledHeight) / 2
    
    // Remove offset and scale
    let unscaledX = (point.x - offsetX) / scale
    let unscaledY = (point.y - offsetY) / scale
    
    // Flip Y to Winamp coordinates (top-left origin)
    let winampY = originalSize.height - unscaledY
    
    return NSPoint(x: unscaledX, y: winampY)
}
```

### Using It in Mouse Handlers

```swift
override func mouseDown(with event: NSEvent) {
    let viewPoint = convert(event.locationInWindow, from: nil)
    let winampPoint = convertToWinampCoordinates(viewPoint)
    
    // Now test against original-size regions
    if winampPoint.y < Layout.titleBarHeight {
        // In title bar (top 20 pixels in Winamp coords)
    }
}
```

---

## Bottom Bar Layout

### Sprite Composition
The playlist bottom bar is composed of two corner sprites that together span the full width:

```
|<--- bottomLeftCorner (125px) --->|<--- bottomRightCorner (150px) --->|
|  ADD  |  REM  |  SEL  |         |        MISC        |  LIST OPTS   |
```

For a 275px window: 125 + 150 = 275 (no middle section needed)

For wider windows, a middle tile fills the gap.

### Critical Lesson: Don't Draw Over Skin Sprites
The skin sprites ALREADY CONTAIN the button labels (ADD, REM, SEL, MISC, LIST OPTS). Drawing additional text or UI elements over them causes visual issues like:
- Overlapping text
- Misaligned labels
- Extra controls appearing

**Rule: Only draw custom content in areas NOT covered by skin sprites (e.g., the track list area).**

### Button Hit Regions
Buttons are hit-tested by position, not by actual button sprites:

```swift
private func hitTestBottomButton(at point: NSPoint, in bounds: NSRect) -> PlaylistButtonType? {
    let bottomY = bounds.height - Layout.bottomBarHeight
    guard point.y >= bottomY else { return nil }
    
    let buttonY = point.y - bottomY
    guard buttonY >= 10 && buttonY <= 28 else { return nil }  // 18px button height
    
    // Left side buttons (ADD, REM, SEL)
    if point.x >= 11 && point.x < 33 { return .add }
    if point.x >= 40 && point.x < 62 { return .rem }
    // ... etc
}
```

---

## Common Pitfalls

### 1. Forgetting to Use `drawBounds` After Scaling
❌ **Wrong:**
```swift
// Uses actual view bounds, ignoring scale transform
drawTrackList(in: context, bounds: bounds)
```

✅ **Correct:**
```swift
let drawBounds = NSRect(origin: .zero, size: originalWindowSize)
drawTrackList(in: context, drawBounds: drawBounds)
```

### 2. Drawing Text Without Counter-Flip
❌ **Wrong:**
```swift
// Text appears upside-down
text.draw(at: NSPoint(x: 10, y: 50), withAttributes: attrs)
```

✅ **Correct:**
```swift
context.saveGState()
// Apply local flip around text center
context.translateBy(x: 0, y: textCenterY)
context.scaleBy(x: 1, y: -1)
context.translateBy(x: 0, y: -textCenterY)
text.draw(at: NSPoint(x: 10, y: 50), withAttributes: attrs)
context.restoreGState()
```

### 3. Hit Testing in View Coordinates Instead of Winamp Coordinates
❌ **Wrong:**
```swift
let point = convert(event.locationInWindow, from: nil)
if point.y < 20 {  // WRONG: view coords, scaled, bottom-left origin
    // title bar click
}
```

✅ **Correct:**
```swift
let point = convert(event.locationInWindow, from: nil)
let winampPoint = convertToWinampCoordinates(point)
if winampPoint.y < Layout.titleBarHeight {  // Correct: unscaled, top-left origin
    // title bar click
}
```

### 4. Inconsistent Scaling Across Windows
All three main windows (Main, EQ, Playlist) MUST use the same scaling pattern. If one window looks different (thinner title bar, smaller fonts), check:
1. Is `scaleFactor` calculated correctly?
2. Is the scale transform applied in `draw()`?
3. Are all drawing methods using `drawBounds` not `bounds`?

### 5. Adding UI Elements That Overlap Skin Sprites
The skin sprites contain pre-rendered graphics. Don't draw:
- Time displays over the bottom bar
- Extra buttons over existing button areas
- Custom text over title bars

Only add custom rendering in the track list area or explicitly designed extension areas.

---

## Code Patterns to Follow

### Pattern 1: Consistent Window View Structure

```swift
class PlaylistView: NSView {
    // MARK: - Properties
    private var originalWindowSize: NSSize = NSSize(width: 275, height: 116)
    
    var scaleFactor: CGFloat {
        guard originalWindowSize.width > 0 else { return 1.0 }
        return bounds.width / originalWindowSize.width
    }
    
    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let scale = scaleFactor
        let originalSize = originalWindowSize
        
        context.saveGState()
        
        // 1. Flip to Winamp coordinates
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        
        // 2. Apply scaling
        if scale != 1.0 {
            let scaledWidth = originalSize.width * scale
            let scaledHeight = originalSize.height * scale
            let offsetX = (bounds.width - scaledWidth) / 2
            let offsetY = (bounds.height - scaledHeight) / 2
            context.translateBy(x: offsetX, y: offsetY)
            context.scaleBy(x: scale, y: scale)
        }
        
        // 3. Draw using original dimensions
        let drawBounds = NSRect(origin: .zero, size: originalSize)
        // ... drawing code using drawBounds ...
        
        context.restoreGState()
    }
    
    // MARK: - Coordinate Conversion
    private func convertToWinampCoordinates(_ point: NSPoint) -> NSPoint {
        // ... conversion logic ...
    }
    
    // MARK: - Mouse Handling
    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let winampPoint = convertToWinampCoordinates(viewPoint)
        // ... hit testing using winampPoint ...
    }
}
```

### Pattern 2: Button State Management

```swift
enum PlaylistButtonType {
    case add, rem, sel, misc, list
    case close, shade
    // etc
}

private var pressedButton: PlaylistButtonType?

override func mouseDown(with event: NSEvent) {
    let winampPoint = convertToWinampCoordinates(convert(event.locationInWindow, from: nil))
    
    if let button = hitTestBottomButton(at: winampPoint, in: drawBounds) {
        pressedButton = button
        needsDisplay = true
    }
}

override func mouseUp(with event: NSEvent) {
    if let button = pressedButton {
        // Execute button action
        handleButtonAction(button)
    }
    pressedButton = nil
    needsDisplay = true
}
```

### Pattern 3: Popup Menus from Buttons

```swift
private func showAddMenu(from point: NSPoint) {
    let menu = NSMenu()
    
    let addURL = NSMenuItem(title: "Add URL...", action: #selector(addURL(_:)), keyEquivalent: "")
    addURL.target = self
    menu.addItem(addURL)
    
    // ... more items ...
    
    // Convert to screen coordinates for popup
    let screenPoint = window?.convertPoint(toScreen: convert(point, to: nil)) ?? .zero
    menu.popUp(positioning: nil, at: screenPoint, in: nil)
}
```

---

## Reference: Layout Constants

```swift
struct Layout {
    static let titleBarHeight: CGFloat = 20
    static let bottomBarHeight: CGFloat = 38
    static let scrollbarWidth: CGFloat = 20
    static let sideBorderWidth: CGFloat = 12  // Left: 12px, Right: 20px (includes scrollbar)
    static let trackRowHeight: CGFloat = 13
    static let minWidth: CGFloat = 275
    static let minHeight: CGFloat = 116
}
```

---

## Summary

The key insights for working on the Winamp-style UI:

1. **Coordinate systems matter** - Always flip Y for Winamp compatibility, and counter-flip for text
2. **Scaling is applied via context transform** - Draw at original size, let the transform handle scaling
3. **Hit testing needs coordinate conversion** - Convert view coords → Winamp coords before testing
4. **Skin sprites are pre-rendered** - Don't draw custom UI over them
5. **Follow established patterns** - Look at MainWindowView and EQView for reference implementations
6. **Test at different window sizes** - Scaling bugs often only appear when windows are resized

When in doubt, check how MainWindowView or EQView handles the same situation.

---

## Plex Browser Window Pattern

The Plex browser window (`PlexBrowserView.swift`) follows the same pattern as the Playlist window, reusing playlist sprites for frame/chrome with custom content areas.

### Architecture Overview

```
+--------------------------------------------------+
|  Title Bar (playlist sprites)                    | 20px
+--------------------------------------------------+
|  Server Bar (custom content area)                | 24px
+--------------------------------------------------+
|  Tab Bar (custom content area)                   | 24px
+--------------------------------------------------+
|  Search Bar (only in search mode)                | 26px
+--------------------------------------------------+
|                                                  |
|  List Area (custom content with playlist colors) |
|                                               |S |
|                                               |C |
|                                               |R |
|                                               |O |
|                                               |L |
|                                               |L |
+--------------------------------------------------+
|  Status Bar (custom content area)                | 20px
+--------------------------------------------------+
```

### Key Implementation Details

1. **Uses Playlist Sprites**: The Plex browser reuses `PLEDIT.BMP` sprites for:
   - Title bar (corners, tiles, window buttons)
   - Side borders
   - Scrollbar track and thumb
   - Shade mode background

2. **Custom Content Areas**: The following areas use playlist colors but custom drawing:
   - Server/library selector bar
   - Tab bar for browse modes
   - Search bar
   - List area with items
   - Status bar

3. **Layout Constants**: Defined in `SkinElements.PlexBrowser.Layout`:
```swift
struct Layout {
    static let titleBarHeight: CGFloat = 20
    static let tabBarHeight: CGFloat = 24
    static let serverBarHeight: CGFloat = 24
    static let searchBarHeight: CGFloat = 26
    static let statusBarHeight: CGFloat = 20
    static let scrollbarWidth: CGFloat = 20
    static let alphabetWidth: CGFloat = 16
    static let leftBorder: CGFloat = 12
    static let rightBorder: CGFloat = 20
}
```

4. **SkinRenderer Methods**:
   - `drawPlexBrowserWindow()` - main entry point
   - `drawPlexBrowserTitleBar()` - uses playlist title sprites
   - `drawPlexBrowserSideBorders()` - uses playlist side tile sprites
   - `drawPlexBrowserScrollbar()` - uses playlist scrollbar sprites
   - `drawPlexBrowserShade()` - shade mode using playlist shade sprites

### Hit Testing Pattern

The Plex browser uses the same coordinate conversion as Playlist:

```swift
private func convertToWinampCoordinates(_ point: NSPoint) -> NSPoint {
    let scale = scaleFactor
    let originalSize = originalWindowSize
    
    let scaledWidth = originalSize.width * scale
    let scaledHeight = originalSize.height * scale
    let offsetX = (bounds.width - scaledWidth) / 2
    let offsetY = (bounds.height - scaledHeight) / 2
    
    let x = (point.x - offsetX) / scale
    let y = originalSize.height - ((point.y - offsetY) / scale)
    
    return NSPoint(x: x, y: y)
}
```

Hit test methods for each interactive area:
- `hitTestTitleBar()` - for window dragging
- `hitTestCloseButton()` / `hitTestShadeButton()` - window controls
- `hitTestServerBar()` - server/library selection
- `hitTestTabBar()` - returns tab index
- `hitTestSearchBar()` - for focus
- `hitTestAlphabetIndex()` - quick navigation
- `hitTestScrollbar()` - scrollbar dragging
- `hitTestListArea()` - returns item index

### Shade Mode

Like the Playlist window, the Plex browser supports shade mode:
- Toggle via double-click on title bar or shade button
- Uses `PlaylistShade` sprites for background
- Controller manages window frame animation
- View state controlled by `setShadeMode()` method
