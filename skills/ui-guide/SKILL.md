---
name: ui-guide
description: Coordinate systems, scaling architecture, hit testing, skin sprite rendering, window layout, and Compact Mode for NullPlayer's UI. Use when working on window scaling, skin rendering, coordinate transforms, visual layout, compact/status-item windows, or playlist/marquee text rendering.
---

# UI & Skin Rendering Guide

Reference for working on NullPlayer's skin-style UI and skin system.

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

NullPlayer uses two different resize modes for windows:

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
    // NOTE: For non-Retina specific fixes, see non-retina-fixes skill
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

### Stretch Expansion Mode (Playlist, Spectrum, Waveform)

Center-stack secondary windows now support horizontal and vertical stretching:
- Playlist, Spectrum, and Waveform use skin minimum sizes and `maxSize = .greatestFiniteMagnitude`
- Default open width still aligns to main window width
- Reopen without a saved frame resets to default docked frame below main
- Restored classic frames preserve width for windows that support stretch (playlist + waveform)

For classic playlist rendering, UI scale is derived from main-window Large UI mode, not the stretched playlist width. This keeps bitmap text and chrome stable while allowing wider windows:

```swift
private var scaleFactor: CGFloat {
    if let mainWidth = WindowManager.shared.mainWindowController?.window?.frame.width,
       mainWidth > 0 {
        return mainWidth / Skin.baseMainSize.width
    }
    let largeUIMultiplier: CGFloat = WindowManager.shared.isDoubleSize ? 1.5 : 1.0
    return Skin.scaleFactor * largeUIMultiplier
}
```

Anti-pattern (regression source):
- Letting classic playlist width stretch freely while deriving scale from a different source can create fractional skin-space widths.
- With `PLEDIT` tiled title bars, fractional widths produce visible section seams/line artifacts in the top decorative bar.

Safe pattern:
- Derive classic playlist render scale from current main-window width.
- Snap classic playlist width in skin space to `width = (N * 25) + 50` before applying frame updates.

`effectiveWindowSize` expands in both dimensions in skin space:

```swift
private var effectiveWindowSize: NSSize {
    let scale = scaleFactor
    let effectiveWidth = bounds.width / scale
    let effectiveHeight = bounds.height / scale
    return NSSize(width: effectiveWidth, height: max(originalWindowSize.height, effectiveHeight))
}
```

## Hit Testing (Scaling Mode)

Convert view coordinates to skin coordinates:

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

**Non-Retina displays**: Even with aligned widths, tile seams may be visible on 1x displays. See the non-retina-fixes skill for techniques like background fill, tile overlap, and bottom-to-top drawing.

## Classic Playlist-Style Window Chrome

`drawPlaylistWindow` / `drawSpectrumAnalyzerWindow` / `drawProjectMNormal` / `drawPlexBrowserWindow` all share three helpers in `SkinRenderer` and render as one continuous U-shape outline:

- **`drawPlaylistStyleSideBorders`** — vertical `leftSideTile` (mirrored on the right). The side borders extend to `bounds.height`, INCLUDING the bottom-corner regions, so the outer gold trim runs continuously down each side.
- **`drawPlaylistStyleBottomBorder`** — rotated `leftSideTile` strip inset between the side borders (`x = 12` to `bounds.width − 12`), plus a 2px-tall gold-trim row tiled across the FULL window width at the very bottom. The gold trim is cropped from the rotated tile's bottom 2 rows, which come from the source's gold-bevel column, so every pixel matches the side borders' outer trim color.
- **Top-right corner fix** — the right corner of the title bar is rendered by MIRRORING the `leftCorner` sprite (not by drawing the original `rightCorner`). The original `rightCorner` artwork was designed to abut the legacy 20-wide scrollbar tile, so its inner bevel sits too far inward and leaves the interior content area visibly wider under the title bar than below. The close (and shade, where applicable) button icons baked into the original `rightCorner` are re-drawn on top from sprite coords `(167, 3, 9, 9)` and `(158, 3, 9, 9)` (with `+21` y offset for the inactive state).

**Bottom-border thickness lives in layout structs**: `Playlist.bottomHeight`, `SpectrumWindow.Layout.bottomBorder`, `WaveformWindow.Layout.bottomBorder`, `ProjectM.Layout.bottomBorder`, `PlexBrowser.Layout.statusBarHeight`, and `LibraryWindow.Layout.statusBarHeight` are all `7 * Skin.scaleFactor`. Interior content rendering uses these constants, so keep them in sync if you change the strip height.

**Pixel snapping**: Both helpers snap tile destinations with `.rounded(.down)` to avoid sub-pixel rendering that bleeds the default Winamp skin's blue-tinted edge pixels between adjacent tiles. See non-retina-fixes skill for the underlying issue.

## Menu Bar Integration (AppKit)

When adding or refactoring top menu bar content:

- Build dedicated menu-bar trees (`buildMenuBar*`) instead of reusing context-menu `NSMenuItem` instances.
- Avoid `NSMenuItem.copy()` for action-bearing items; copied items can lose expected target/action behavior in this app.
- Keep side effects (network discovery, long-running work) out of menu construction.
- Prefer lifecycle startup for services and `menuNeedsUpdate(_:)` for state refresh when a menu opens.
- For Sonos room selection UX, use `SonosRoomCheckboxView` when persistent-open submenu behavior is required.
- For library-browser column visibility menus, use `ColumnVisibilityCheckboxView` for persistent-open checkbox rows. Keep column preferences mode-scoped: Modern uses `BrowserVisible*Columns`; Classic uses `ClassicBrowserVisible*Columns`.

## Dockable Center-Stack Windows

Main, EQ, Playlist, Spectrum, and Waveform all participate in the center stack managed by `WindowManager`.

- Width is normalized to the main stack
- Height is window-specific
- Saved frames are restored through `WindowManager` rather than ad hoc per-window logic
- Modern and classic implementations should expose a provider protocol in `App/` so `WindowManager` can manage both without mode-specific branching outside window creation

For new center-stack windows, follow the waveform/spectrum pattern:

1. Shared non-UI logic in a neutral folder (for example `Waveform/`)
2. Classic chrome in `Windows/...`
3. Modern chrome in `Windows/Modern...`
4. Registration and docking behavior in `WindowManager`

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

## Playlist Text Rendering

The playlist window renders all text using the same bitmap font (`TEXT.BMP`) as the main window, ensuring visual consistency across the application.

### Implementation

Located in `Windows/Playlist/PlaylistView.swift`:

```swift
// All playlist text uses bitmap font from TEXT.BMP
// CGImage is cached outside draw cycle to prevent cross-window interference
private var cachedTextBitmapCGImage: CGImage?

private func cacheTextBitmapCGImage() {
    guard let skin = WindowManager.shared.currentSkin,
          let textImage = skin.text else { return }
    cachedTextBitmapCGImage = textImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

// Characters are drawn using CGContext with proper coordinate flipping
private func drawBitmapText(_ text: String, at position: NSPoint, in context: CGContext, skin: Skin?, isSelected: Bool = false) {
    // Crop each character from cached CGImage
    // Apply Y-flip for CGContext coordinate system
    // For selected tracks, convert green pixels to white
}
```

### Marquee Scrolling

The currently playing track marquees when its title is too long:

```swift
// Timer-based marquee offset (8Hz update rate)
private var marqueeOffset: CGFloat = 0
private var currentTrackTextWidth: CGFloat = 0

// In drawTrackText(), current track uses marqueeOffset for scrolling
let xOffset = needsMarquee ? -marqueeOffset : 0
```

### Unicode Fallback

The bitmap font (`TEXT.BMP`) only supports ASCII characters. Track titles with Japanese, Chinese, Korean, Cyrillic, Arabic, or other non-Latin characters are automatically detected and rendered using system font fallback, matching the behavior of the main window marquee.

```swift
private func containsNonLatinCharacters(_ text: String) -> Bool {
    // Returns true if text contains characters outside A-Z, 0-9, and common symbols
}
```

This ensures:
- **Latin text**: Uses skin bitmap font for authentic look
- **Non-Latin text**: Falls back to system font for proper Unicode display
- **Mixed text**: Falls back to system font if any non-Latin characters present

### Selected Track Appearance

Selected tracks display white text instead of green. This uses pixel manipulation:

```swift
private func convertToWhite(_ charImage: CGImage, charWidth: Int, charHeight: Int) -> CGImage? {
    // Convert green (0, G, 0) pixels to white (G, G, G)
    // Magenta (255, 0, 255) pixels are treated as transparent
}
```

### Auto-Selection

When the playlist opens while music is playing, the current track is auto-selected:

```swift
override func viewDidMoveToWindow() {
    // Auto-select the currently playing track when playlist opens
    if selectedIndices.isEmpty && engine.currentIndex >= 0 {
        selectedIndices = [engine.currentIndex]
    }
}
```

### Cross-Window Interference Prevention

A key issue was `NSImage.cgImage()` affecting shared graphics state during render cycles, causing the main window marquee to switch fonts when the playlist scrolled.

**Solution**: Cache `CGImage` representation of `TEXT.BMP` outside of draw cycles, called only when skin changes or view initializes.

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
3. **Hit testing in view coords** - must convert to skin coords first
4. **Non-tile-aligned widths** - causes sprite interpolation artifacts
5. **Drawing over skin sprites** - they already contain labels
6. **Using blend modes for color conversion** - causes sub-pixel artifacts when scaling; use offscreen pixel manipulation instead
7. **Tile seams on non-Retina** - visible lines at tile boundaries on 1x displays; requires background fill, overlap, and careful draw order (see non-retina-fixes skill)

## Key Files

| File | Purpose |
|------|---------|
| `Skin/SkinElements.swift` | All sprite coordinates |
| `Skin/SkinRenderer.swift` | Drawing code |
| `Skin/SkinLoader.swift` | WSZ loading, BMP parsing |
| `Skin/MarqueeLayer.swift` | Main window marquee (bitmap font, CALayer-based) |
| `Windows/Playlist/PlaylistView.swift` | Playlist view with bitmap font rendering |
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

## Spectrum Analyzer Window

A standalone Metal-based spectrum analyzer visualization window that provides a larger, more detailed view of the audio spectrum than the main window's built-in analyzer.

### Opening the Window

- **Click** the spectrum analyzer display in the main window
- Context Menu → Spectrum Analyzer
- Window menu → Spectrum Analyzer

**Note:** Double-clicking the visualization area cycles the main window vis mode (Spectrum → Fire) instead of opening this window.

### Window Docking

The Spectrum Analyzer participates in the docking system alongside Main, EQ, and Playlist:
- Docks and moves with the window group when dragged
- Opens below the current vertical stack (Main → EQ → Playlist → Spectrum)
- State (visibility and position) saved with "Remember State on Quit"
- **Center stack collapse**: hiding a stack window (EQ, Playlist, Spectrum) slides windows below it up by the closed window's height. Implemented via `slideUpWindowsBelow(closingFrame:)` in `WindowManager`. The closing frame must be captured BEFORE `orderOut`.

### Key Files

| File | Purpose |
|------|---------|
| `Visualization/SpectrumAnalyzerView.swift` | Metal-based spectrum view component |
| `Visualization/SpectrumShaders.metal` | GPU shaders for bar rendering |
| `Visualization/FlameShaders.metal` | Fire mode shaders (compute + render) |
| `Visualization/CosmicShaders.metal` | JWST mode shader |
| `Visualization/ElectricityShaders.metal` | Lightning mode shader |
| `Visualization/MatrixShaders.metal` | Matrix mode shader |
| `Visualization/SnowShaders.metal` | Snow mode shader |
| `Windows/Spectrum/SpectrumWindowController.swift` | Window controller |
| `Windows/Spectrum/SpectrumView.swift` | Container view with skin chrome |

### Quality Modes

| Mode | Description |
|------|-------------|
| **Winamp** | Discrete color bands from skin's `viscolor.txt` with floating peak indicators, 3D bar shading, and segmented LED gaps |
| **Enhanced** | Rainbow LED matrix with gravity-bouncing peaks, warm amber fade trails, 3D inner glow cells, and anti-aliased rounded corners |
| **Ultra** | Maximum fidelity seamless gradient with smooth exponential decay, perceptual gamma, and warm color trails |
| **Fire** | GPU fire simulation with audio-reactive flame tongues in 4 color styles |
| **JWST** | Deep space flythrough with 3D star field, vivid JWST diffraction flares as intensity indicators, and rare giant flare events |
| **Lightning** | GPU lightning storm with fractal bolts mapped to spectrum peaks and multiple color schemes |
| **Matrix** | Falling digital rain with procedural glyphs and selectable color/intensity styles |
| **Snow** | Audio-reactive layered snowfall with smooth flurry-to-blizzard intensity shifts |

### Decay/Responsiveness Modes

Controls how quickly spectrum bars fall after peaks:

| Mode | Retention | Feel |
|------|-----------|------|
| Instant | 0% | No smoothing, immediate response |
| Snappy | 25% | Fast and punchy (default) |
| Balanced | 40% | Good middle ground |
| Smooth | 55% | Original Winamp feel |

### Window Specifications

- **Default size**: 275x116 (same as main window at 1x)
- **Stretching**: Width and height can expand; minimum width stays skin-defined
- **Bar count**: 84 bars (vs 19 in main window)
- **Refresh**: 60Hz via CVDisplayLink
- **Skin colors**: Uses skin's `viscolor.txt` (24 colors)

### Context Menu

Right-click on the spectrum window for:
- **Mode** submenu - Switch between Winamp/Enhanced/Ultra/Fire/JWST/Lightning/Matrix/Snow modes
- **Responsiveness** submenu - Adjust decay behavior
- **Normalization** submenu - Choose Accurate/Adaptive/Dynamic scaling
- **Flame Style** - Choose flame color preset (Fire mode only)
- **Fire Intensity** - Choose Mellow or Intense reactivity (Fire mode only)
- **Lightning Style** - Choose lightning palette (Lightning mode only)
- **Matrix Color** - Choose matrix palette (Matrix mode only)
- **Matrix Intensity** - Choose matrix reactivity profile (Matrix mode only)
- **Close** - Close the window

Settings are persisted across app restarts.

## Hide Title Bars Mode (Modern UI Only)

Two-tier behavior controlled by `effectiveHideTitleBars(for:)` in `WindowManager`:

- **HT Off (default baseline)**: EQ/Playlist/Spectrum/Waveform always hide titlebars when docked, regardless of the HT setting. Main, ProjectM, and Library Browser show titlebars.
- **HT On**: ALL 6 windows hide titlebars unconditionally (docked or not). Main window frame size remains unchanged; the main view internally remaps/scales content to fill the reclaimed titlebar area with no top gap.

Key implementation details:
- `toggleHideTitleBars()` keeps the modern main window at full-height geometry and refreshes all managed window views (`needsDisplay` + `needsLayout`)
- **Startup**: `showMainWindow()` normalizes legacy compact HT frames back to full-height geometry via `normalizeModernMainWindowForHTIfNeeded()`
- `ModernMainWindowView` applies HT-only internal reflow in draw with a Y-axis context transform (`withMainContentLayoutTransform`, `contentLayoutScaleY`)
- HT internal reflow is mirrored in interaction math (`basePoint`/`scaledRect`) so hit testing, dirty-rect invalidation, marquee frame, and Metal mini-spectrum overlay geometry stay aligned with rendered controls
- Each view's `titleBarHeight` computed property returns `borderWidth` (not 0) when hidden, preserving the top border line
- ProjectM shade mode is always drawn (uses `isShadeMode || !effectiveHideTitleBars` condition) so HT + shade never produces a blank window
- Library Browser uses lazy drag: `mouseDown` records `windowDragStartPoint`; `mouseDragged` starts the drag on first movement when HT is on

## Large UI Mode (1.5x, Both UI Modes)

UI label is **Large UI**. Internal state key remains `isDoubleSize`.

- **Scale amount**: 1.5x (not 2x)
- **Modern UI**: live toggle — `ModernSkinElements.scaleFactor` is computed (`baseScaleFactor * sizeMultiplier`). Do NOT cache `scaleFactor` in a `let` property. Views should refresh renderers on `.doubleSizeDidChange`.
- **Classic UI**: requires restart. `MenuActions.toggleDoubleSize()` shows a "Restart Required" dialog and relaunches if confirmed.
- **Startup restoration**: `isDoubleSize` is restored in `AppStateManager.restoreSettingsState()` before sub-windows are shown, so saved 1.5x geometry is not double-applied during restore.
- When title bars are hidden, all window drags pass `fromTitleBar: true` to allow undocking
- Classic windows use drawing transform offset (`translateBy`) to shift the skin image up; modern windows use conditional `titleBarHeight`

## Live UI Mode Switching (Modern ↔ Classic, no restart)

Switching UI mode rebuilds **only the mode-dependent window layer** in-process — no app
restart. `AudioEngine` is owned by `WindowManager` (not by any window), so playback,
casting, playlist, current track, seek position, and play/pause survive the switch
untouched; audio state is deliberately never snapshotted.

**Entry points** (`ContextMenuBuilder` / `MenuActions`): `setClassicMode()` /
`setModernMode()`, plus the skin-driven switches `selectClassicSkin` / `selectModernSkin` /
`loadDefaultClassicSkin` (picking a skin for the other mode switches into it). All call
`WindowManager.reloadUI(toModernUI:)`. Only classic **Large UI** (Double Size) still
restarts — it's a size change, not a mode switch.

**`WindowManager.reloadUI(toModernUI:)`** orchestration:
1. `captureModeDependentLayout()` — snapshot which mode-dependent windows are open + frames; snapshot Compact Mode.
2. `teardownModeDependentWindows()` — synchronous; completion gates recreation. Orders out, calls `prepareForUITeardown()` on each controller (cancels tasks/timers, stops render loops, unregisters audio consumers), detaches docked children, `close()` + nils the mode-dependent controllers, clears drag/snap/dock state, and flushes the `ObjectIdentifier`-keyed geometry caches. **Preserves `videoPlayerWindowController`** (mode-independent — closing it stops playback/casts).
3. Flip `isModernUIEnabled` — the `show*()` paths read it to choose classic vs. modern controllers, so it must change *between* teardown and recreate.
4. `prepareUIRuntime(forModernUI:)` — `ModernSkinEngine.shared.loadPreferredSkin()` entering modern; reset classic spectrum transparent-bg keys entering classic. Classic `currentSkin` is loaded once at init and survives, so no classic reload is needed for a plain mode toggle (skin-driven classic switches load the chosen skin via `loadSkin` *before* `reloadUI`).
5. `audioEngine.applyEQLayout(forModernUI:)` — reprograms the shared fixed-21-band EQ node to the target layout (mirrors to the streaming player internally); guard-idempotent.
6. `rebuildMainMenu()` via `(NSApp.delegate as? AppDelegate)?`.
7. `recreateModeDependentLayout(snapshot)` — `showMainWindow()` + `makeKeyAndOrderFront`, restore sub-window visibility/frames via `show*(at:)`, re-push presentation state; restore Compact Mode last.

**Audio-consumer ordering safety**: consumer sets in `AudioEngine` (spectrum/waveform/
stereo/magnitudes) are **ref-counted** (`[String: Int]`), so a late `remove` from an old
view's deferred `deinit` cannot wipe a same-id registration the replacement already made.

**DEBUG-only** `debugRecreateModeDependentWindows()` (Window menu → "Recreate Windows
(Debug)") runs the same teardown/rebuild in the *same* mode — the leak/lifecycle test that
de-risks the live switch. Requires a debug build: `./scripts/kill_build_run.sh --debug`.

## Compact Mode

Compact Mode is a WindowManager state transition, not a second main window style.

Key implementation details:
- `WindowManager.enterCompactMode(revealWindow:)` snapshots regular windows, establishes the compact window's presence on the current Space, detaches docked child windows, orders regular windows out, switches the app to `.accessory`, **re-activates NullPlayer** (`NSApp.activate`) so the `.accessory` transition doesn't hand the Space to a fullscreen app, creates the status item, and owns the Compact Mode state (`regular`, `compactVisible`, `compactHidden`). See the Spaces gotchas below.
- `Windows/CompactMode/CompactModeWindowController.swift` owns a private browser controller (`PlexBrowserWindowController` or `ModernLibraryBrowserWindowController`) and calls `setCompactMode(true)`. Do not replace this with a custom compact-only view; Compact Mode must keep the same browser compact surface and embedded compact player bar behavior as the old implementation.
- Compact updates are forwarded through the compact controller (`updateCompactBarTime`, `updateCompactBarTrack`, `updateCompactBarPlaybackState`) so playback state stays live while the regular windows are hidden.
- The status item left-click toggles compact visibility. Right-click opens the compact menu. Hidden compact mode remains in `.accessory` until explicitly exited.
- Exiting Compact Mode removes the status item, switches back to `.regular`, rebuilds the main menu asynchronously, restores the regular window snapshot, then reattaches/restores docked windows. It then calls `reassertRegularActivation()` (activate + make the main window key + re-apply the Dock icon) and runs it **a second time on the next runloop turn**. See the `.accessory → .regular` settling gotcha below.
- Entry points: the **Compact Mode** item in the main-window right-click menu and the `Windows` menu (placed on its own line, separated, above Always On Top), plus the modern main window's **CP** toggle button (`btn_compact`). The CP button click forces the button's active (on) highlight and `display()`s it synchronously *before* deferring `toggleCompactMode()` to the next runloop — `enterCompactMode` is heavy synchronous AppKit work (activation-policy switch, window teardown, status-item creation) that, run inline in `mouseUp`, would block the press repaint and beachball. The fallback toggle-button renderer keys its highlight off the on-state only (not `isPressed`), so `compactButtonActivating` forces the on-look during the transition.

Placement rules:
- The compact window is positioned by `CompactModeWindowController.position(anchoredTo:)`.
- On show, align the compact window's top edge to the current screen `visibleFrame.maxY`; do not leave a top margin/gap below the menu bar.
- Use side/bottom margins only. Do not clamp the top edge with the same edge margin used for the sides.
- When the status item button is not available yet, fall back to top-right placement on the main screen, then reassert positioning shortly after entry once AppKit has created the status item window.
- Keep the compact width based on the browser surface's `minimumCompactContentWidth`. Do not force a narrower hard-coded width, and do not abbreviate/truncate browser tab labels just to make the window thinner.
- Use `.moveToActiveSpace` for the compact window, not `.canJoinAllSpaces`. Showing/hiding from the status item should reveal the compact window on the user's current desktop/Space, not stick to a previous Space or appear everywhere.
- Avoid transition flashes by giving the compact window a top-right fallback frame during setup, using `display: false` for hidden frame changes, and delaying shadow/key/display until the final frame is applied on reveal.

### Spaces / virtual-desktop gotchas (hard-won)

These are subtle and only reproduce with multiple Spaces / a fullscreen app on another desktop. Verify any change to the enter/exit sequence against that setup.

- **`.accessory` transition steals the Space.** `NSApp.setActivationPolicy(.accessory)` makes macOS resign NullPlayer and **activate the next app in the stack**. If that app is in native fullscreen on another Space (e.g. Console), macOS switches the user to that Space, and the `.moveToActiveSpace` compact window then follows. The diagnostic signature is a `NSWorkspace.didActivateApplicationNotification` for another app firing immediately after the policy change. Fix: call `NSApp.activate(ignoringOtherApps:)` right after `setActivationPolicy(.accessory)` so NullPlayer stays frontmost on the current Space. The exit path already does this after `setActivationPolicy(.regular)`; entry must mirror it. (Merely ordering the compact window front/key does **not** prevent the handoff — the policy change yields activation regardless.)
- **Re-activation needs a current-Space window to land on.** Because the regular windows are ordered out before the policy change, call `compactWindowController?.establishPresenceOnActiveSpace()` (orders the invisible alpha-0 compact window front on the current Space) *before* `orderOutRegularWindows()`, so the `NSApp.activate` above has a NullPlayer window on the current Space to focus.
- **Never `orderOut`/`orderFront` a native-fullscreen window.** Doing so forces macOS to switch to that window's own Space to run the show/hide animation. `orderOutRegularWindows`, `orderOutOrphanedAppWindows`, and `restoreRegularWindowSnapshot` all skip windows where `isInNativeFullScreen(_:)` (`styleMask.contains(.fullScreen)`); leave them untouched on their Space.
- **`.accessory → .regular` settles asynchronously — re-assert activation, menu, and Dock icon.** On exit the transition lands over a runloop turn or two, and two things lag behind it intermittently: (1) macOS rebuilds the Dock tile and substitutes the **generic executable icon**, and (2) the **menu-bar menus stay missing** (the symptom was "menu options gone until you minimize/restore a window"). The menu bar only reflects the new `NSApp.mainMenu` once the app is genuinely re-activated **with a key window** — `restoreRegularWindowSnapshot` only `orderFront`s the main window, never makes it key, so a single `NSApp.activate` in the same turn can fail to take. Fix: `reassertRegularActivation()` does `NSApp.activate` + `mainWindow.makeKey()` + `restoreDockIconImage()`, and `exitCompactMode` calls it once in the deferred block and **again on the next runloop turn** (guarded by `compactModeState == .regular`) so neither depends on winning the race. Both symptoms are non-deterministic; verify by toggling in/out of Compact Mode ~20× and confirming the logo icon and full menu bar every time. The `restoreRegularWindows: false` live-UI-switch path skips this (it re-enters compact immediately).

### Live UI switch (Classic↔Modern) while in Compact Mode

`reloadUI(toModernUI:)` must not naively call `exitCompactMode()` then `enterCompactMode()`:

- `exitCompactMode` restores asynchronously (state stays `.exiting` until a deferred block), so a synchronous re-enter hits the `.regular` guard and is silently dropped. `exitCompactMode` is **completion-based**; run the teardown/rebuild/re-enter inside the completion.
- Pass `exitCompactMode(restoreRegularWindows: false)` on this path: re-showing the still-hidden `.managed` regular windows would pull the user to whatever Space they live on. Derive the rebuild snapshot from the pre-compact capture (`modeDependentLayout(from: regularWindowSnapshot)`) instead of the live (hidden) windows.
- `enterCompactMode()` re-captures `regularWindowSnapshot` from the live windows, which **loses the mode-independent windows** (video player, debug console, app panels — they survive teardown but stay hidden). Carry those fields forward with `reapplyModeIndependentWindows(from:)` after the rebuild, or a video player open before the switch won't restore on the eventual Compact-Mode exit.

### Compact window reveal positioning

- Reveal readiness (`isStatusAnchorReady`) must validate **both** the status item's Y (menu-bar proximity) **and** X. A freshly created status item can report a settled Y while its X is still near the screen origin; centering on that X clamps the window hard against the left margin (intermittent "left-aligned" bug). Require the anchor's center to be right of the screen's left quarter before revealing, and retry until it is.

## Window Docking

Complex snapping logic in `WindowManager`:
- Multi-monitor: Screen edge snapping is skipped if it would cause docked windows to end up on different screens
- `Snap to Default` centers main window on its current screen (not always the primary display)
- Coordinated minimize: uses `addChildWindow`/`removeChildWindow` in `windowWillMiniaturize`/`windowDidDeminiaturize` to temporarily make docked windows children of the main window so they animate into the dock together. Child relationships are removed on restore.
- **Center stack collapse**: `slideUpWindowsBelow(closingFrame:)` in `WindowManager` slides docked windows up when a stack window is hidden. Called from `toggleEqualizer/Playlist/Spectrum/Waveform` — capture the frame BEFORE `orderOut`, then call it. Uses BFS over `dockThreshold`-adjacent windows (by vertical gap + horizontal overlap). Must set `isSnappingWindow = true` during moves to prevent the docking feedback loop.

### Hold-Duration Drag Model

Dragging a docked window uses a time-based mode determined at the first `mouseDragged` event:

| Hold duration | Drag mode | Behaviour |
|---|---|---|
| < 400 ms (`holdThreshold`) | `.separate` | Dragged window detaches; peers stay connected to each other |
| ≥ 400 ms | `.group` | All connected windows move together |

Implementation details:
- `DragMode` enum: `.pending` (not yet decided) / `.separate` / `.group`
- Hold timing can be primed at `mouseDown` (`windowWillPrimeDragging`) before actual drag start for lazy-drag views (for example HT-on library browser)
- Mode resolves on first `windowWillMove` via `determineDragMode(holdStart:currentTime:threshold:isWindowLayoutLocked:)` (pure static, unit-tested)
- If `isWindowLayoutLocked == true`, drag mode is forced to `.group` regardless of hold duration
- Separate mode: peers are restored to their pre-drag origins before the dock is broken
- Group mode: connected windows move using stored offsets from drag start to prevent drift; child windows of the dragging window are skipped (AppKit moves them automatically); group top is clamped so no window goes off-screen
- Mid-drag window close: `NSWindow.willCloseNotification` observer cleans up hold state and clears highlights
- Mid-flight drag (AppKit-initiated, no prior `mouseDown`): always `.group` mode (override)
- Programmatic moves are filtered by `shouldTreatMoveAsDrag(...)` so startup restore/snapping does not arm drag state or post false highlights
- **Connected window highlight**: at `mouseDown`, all peer windows receive a `white @ 15% opacity` overlay via `connectedWindowHighlightDidChange` notification. Cleared when drag ends or `.separate` mode is resolved. All 10 dockable views (5 classic + 5 modern) observe this notification.
- `isMovingDockedWindows` flag prevents re-entrant `windowWillMove` calls while peers are being repositioned

## Related Documentation

- **non-retina-fixes skill** - Fixes for rendering artifacts on 1x displays (blue lines, tile seams, text shimmering)

## External References

- [Winamp Skin Archive](https://skins.webamp.org/) - Community skin downloads
