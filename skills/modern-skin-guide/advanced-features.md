# Advanced Modern Skin Features

This document covers advanced topics: title text system, animations, Double Size mode, and adding new sub-windows.

## Title Text System

The title text system supports three rendering tiers with automatic fallback, allowing pixel-art character sprites or pre-rendered title images.

### TitleTextConfig Schema

All fields are optional. Omitting the entire `titleText` section defaults to font-based rendering.

| Field | JSON Key | Type | Default | Notes |
|-------|----------|------|---------|-------|
| mode | `"mode"` | `"image"` or `"font"` | `"font"` | Must be `"image"` to enable sprite/image rendering |
| charSpacing | `"charSpacing"` | CGFloat | 1 | Extra pixels between glyphs |
| charHeight | `"charHeight"` | CGFloat | 10 | Height in base coords (title bar is 14 units) |
| alignment | `"alignment"` | `"left"` / `"center"` / `"right"` | `"center"` | Horizontal alignment |
| tintColor | `"tintColor"` | Hex string | nil | Colorizes grayscale sprites |
| padLeft | `"padLeft"` | CGFloat | 0 | Left inset |
| padRight | `"padRight"` | CGFloat | 0 | Right inset |
| verticalOffset | `"verticalOffset"` | CGFloat | 0 | Positive moves text up |
| decorationLeft | `"decorationLeft"` | String | nil | Image key for left decoration |
| decorationRight | `"decorationRight"` | String | nil | Image key for right decoration |
| decorationSpacing | `"decorationSpacing"` | CGFloat | 3 | Space between decorations and text |

### Three-Tier Fallback Pipeline

Implemented in `ModernSkinRenderer.drawTitleBar()`:

**Tier 1: Full pre-rendered title image**
- Look up: `{prefix}titlebar_text` → `titlebar_text`
- If found: center in title bar, apply tint, draw with pixel art interpolation, RETURN

**Tier 2: Character sprite compositing**
- Check: `skin.hasTitleCharSprites` (any title_upper_/title_lower_/title_char_ images?)
- For each character: try `skin.titleCharImage(for: char)` → returns sprite or nil
- If sprite found: measure width from aspect ratio, apply tint
- If sprite missing: use system font for just that character (mixed mode)
- Layout glyphs with charSpacing, alignment, padding, verticalOffset
- Draw with `drawPixelArtImage()` (nearest-neighbor)
- If at least 1 sprite found: RETURN

**Tier 3: System font fallback**
- Render with NSAttributedString + NSFont
- Uses `fonts.titleSize` from skin.json

### Character-to-Image-Key Mapping (Filesystem-Safe)

Uses `title_upper_`/`title_lower_` prefixes for letters to avoid case collisions on macOS's case-insensitive filesystem.

| Character | Image Key | Filename Example |
|-----------|-----------|-----------------|
| `A`-`Z` | `title_upper_A` ... `title_upper_Z` | `title_upper_N.png` |
| `a`-`z` | `title_lower_a` ... `title_lower_z` | `title_lower_n.png` |
| `0`-`9` | `title_char_0` ... `title_char_9` | `title_char_5.png` |
| Space | `title_char_space` | `title_char_space.png` |
| `-` | `title_char_dash` | `title_char_dash.png` |
| `.` | `title_char_dot` | `title_char_dot.png` |
| Other symbols | `title_char_{name}` | Various |

**Lowercase fallback**: `titleCharImage(for: 'p')` tries `title_lower_p` first, then falls back to `title_upper_P`. Skin authors can ship just uppercase sprites.

### Tint Color Resolution

Priority chain (implemented in `resolveTitleTintColor(prefix:)`):

1. Per-window element config: `elements["{prefix}titlebar_text"]["color"]`
2. Shared element config: `elements["titlebar_text"]["color"]` (if prefix is non-empty)
3. Global titleText config: `titleText.tintColor`
4. No tinting (sprites drawn as-is)

Tinted images are cached in `ModernSkin.tintedImageCache` by `"{imageKey}_{colorHex}"`. Cache invalidated on skin change.

### Title Decorations

Decorative sprites can be drawn on either side of title text on all windows. Configured via `decorationLeft`, `decorationRight`, and `decorationSpacing`.

Decorations work with all three tiers:
- **Tier 1** (full image): Decorations flank the pre-rendered image
- **Tier 2** (sprites): Decorations drawn before/after glyph sequence
- **Tier 3** (font): Decorations flank rendered text

Decoration sprites are:
- Rendered at same height as title text
- Aspect-ratio-preserved
- Drawn with `drawPixelArtImage()` for crisp scaling
- Tinted using same color resolution chain

### Per-Window Prefixes

Each window passes its prefix to `drawTitleBar` for per-window image resolution:

| Window | Prefix | Title String |
|--------|--------|-------------|
| Main | `""` | `"NULLPLAYER"` |
| Playlist | `"playlist_"` | `"NULLPLAYER PLAYLIST"` |
| EQ | `"eq_"` | `"NULLPLAYER EQUALIZER"` |
| Spectrum | `"spectrum_"` | `"NULLPLAYER ANALYZER"` |
| ProjectM | `"projectm_"` | `"projectM"` |
| Library | `"library_"` | `"NULLPLAYER LIBRARY"` |

## Animation Configuration

### Sprite Frame Animation

```json
"animations": {
    "status_play": {
        "type": "spriteFrames",
        "frames": ["status_play_0.png", "status_play_1.png", "status_play_2.png"],
        "duration": 1.0,
        "repeatMode": "loop"
    }
}
```

### Parametric Animation

```json
"animations": {
    "seek_fill": {
        "type": "glow",
        "duration": 3.0,
        "minValue": 0.4,
        "maxValue": 1.0
    }
}
```

Types: `pulse`, `glow`, `rotate`, `colorCycle`  
Repeat modes: `loop`, `reverse`, `once`

## Background Configuration

### Image Background

```json
"background": {
    "image": "background.png"
}
```

### Grid Background

```json
"background": {
    "grid": {
        "color": "#0a2a2a",
        "spacing": 20,
        "angle": 75,
        "opacity": 0.15,
        "perspective": true
    }
}
```

- `color`: Grid line color
- `spacing`: Distance between lines (points)
- `angle`: Line angle in degrees
- `opacity`: Line opacity (0-1)
- `perspective`: Enable Tron-style vanishing point effect

## Glow/Bloom Configuration

```json
"glow": {
    "enabled": true,
    "radius": 8,
    "intensity": 0.6,
    "threshold": 0.7,
    "color": "#00ffcc",
    "elementBlur": 1.0
}
```

- `enabled`: Master on/off
- `radius`: Blur kernel size (larger = softer glow)
- `intensity`: Bloom brightness multiplier
- `threshold`: Brightness threshold (0-1, pixels above this glow)
- `color`: Override glow color (defaults to palette primary)
- `elementBlur`: Multiplier for per-element glow blur (default 1.0, set 0 for flat)

## Font Configuration

All font sizes are **unscaled base values**. The engine multiplies by `window.scale` automatically.

| Key | Used for | Default |
|-----|----------|---------|
| `titleSize` | Title bar text | 8 |
| `bodySize` | Body text, source/tab labels | 9 |
| `smallSize` | Small labels, toggle buttons | 7 |
| `timeSize` | Time display digits | 20 |
| `infoSize` | Info labels (bitrate, samplerate, BPM) | 6.5 |
| `eqLabelSize` | EQ frequency labels | 7 |
| `eqValueSize` | EQ dB value text | 6 |
| `marqueeSize` | Scrolling title text | 11.7 |
| `playlistSize` | Playlist track list | 8 |

### Using the Bundled Font

The app ships with **Departure Mono** (SIL OFL license):

```json
"fonts": {
    "primaryName": "DepartureMono-Regular",
    "fallbackName": "Menlo"
}
```

### Using a Custom Font

Include a TTF/OTF in `fonts/` and reference by PostScript name:

```json
"fonts": {
    "primaryName": "MyCustomFont"
}
```

## Seamless Docked Borders

When windows are docked, the `seamlessDocking` property controls shared-edge border suppression:

| Value | Effect |
|-------|--------|
| `0.0` | Full double borders (default) |
| `0.5` | Shared edges faded to 50% |
| `0.8` | Mostly hidden |
| `1.0` | Fully hidden (seamless) |

```json
"window": {
    "borderWidth": 1.5,
    "seamlessDocking": 1.0
}
```

At 1.0, shared edges are clipped entirely, also removing glow effects on those edges.

## Glass Skin Darkening and Seam Stability

This section documents the March 2026 fix for modern glass skins where windows could become too dark or flicker over time, and docked interior edges could show dark seam lines.

### Symptoms

- Main and EQ glass windows appeared darker than expected.
- Library window remained darker than main/EQ (inconsistent opacity behavior).
- Timer-driven redraw regions (especially library chrome) could visually fluctuate.
- Docked interior edges could show a dark 1px seam.

### Root Causes

1. **Alpha accumulation risk in partial redraws**  
   Translucent background passes composited over existing pixels can drift darker when repeatedly redrawn in dirty regions.

2. **Near-full docking interval gaps**  
   Window docking geometry can produce occlusion intervals that are visually full-edge but numerically short by ~1-3 px, leaving tiny unsuppressed border slivers.

3. **Area opacity semantics mismatch**  
   Glass skins used:
   - `window.opacity` around `0.5`
   - `window.areaOpacity.*` around `0.8`
   
   Treating `areaOpacity` as absolute alpha made windows too opaque/dark. These channels are now interpreted as multipliers of `window.opacity`.

4. **Library draw path inconsistency**  
   `ModernLibraryBrowserView` did not apply resolved `mainWindow` area channels for background/border/content, so its appearance diverged from main/EQ.

### Implementation

- `ModernSkinRenderer.drawWindowBackground(...)`
  - Uses `.copy` for the base background fill pass to make repeated redraws idempotent.

- `ModernSkinRenderer.drawWindowBorder(...)`
  - Normalizes near-full occlusion intervals before suppression.
  - Merges close segment gaps and increases suppression strip coverage to remove tiny interior seam slivers.

- `ModernSkin.resolvedOpacity(for:)`
  - Area channels are resolved as:
    - `resolved = clamp(window.opacity) * clamp(areaChannelOr1.0)`
  - Missing area/channel defaults to multiplier `1.0`.

- `ModernLibraryBrowserView.draw(_:)`
  - Uses `skin.resolvedOpacity(for: .mainWindow)` and applies:
    - `backgroundOpacity` in `drawWindowBackground(...)`
    - `borderOpacity` in `drawWindowBorder(...)`
    - `content` alpha around foreground chrome/content drawing

### Files Changed

- `Sources/NullPlayer/ModernSkin/ModernSkinRenderer.swift`
- `Sources/NullPlayer/ModernSkin/ModernSkin.swift`
- `Sources/NullPlayer/ModernSkin/ModernSkinConfig.swift`
- `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift`
- `Tests/NullPlayerTests/ModernSkinOpacityConfigTests.swift`

### Regression Tests

- `testWindowBackgroundDrawIsStableAcrossRepeatedRedraws`
- `testSeamSuppressedBorderIsStableAcrossRepeatedRedraws`
- `testAreaOpacityFallbackUsesWindowOpacityAndMultiplierSemantics`

### Verification Command

```bash
DYLD_LIBRARY_PATH="/Users/ad/Projects/nullplayer/Frameworks" \
/Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  -XCTest ModernSkinOpacityConfigTests \
  .build/arm64-apple-macosx/debug/NullPlayerPackageTests.xctest
```

## Text-Only Opacity Channel (`window.textOpacity`)

Modern skins support a dedicated text opacity multiplier that is independent from window/panel translucency:

- `window.opacity`: background/border/content base alpha channels.
- `window.areaOpacity.*`: per-area multipliers for those channels.
- `window.textOpacity`: global multiplier for string text alpha only.

### Why this exists

Glass skins often need darker text for readability while keeping the same translucent window body.  
`window.textOpacity` lets you tune text darkness without changing panel/background opacity.

### Behavior

- Optional field, range `0.0...1.0`, default `1.0`.
- Applied only to modern string text drawing paths (`NSAttributedString` foreground colors).
- Not applied to non-text rendering (fills, borders, strokes, icons, glow geometry).
- Resolved as:
  - `resolvedTextAlpha = clamp(inputTextAlpha) * clamp(window.textOpacity)`

### Example

```json
"window": {
    "opacity": 0.52,
    "textOpacity": 0.8,
    "areaOpacity": {
        "mainWindow": { "background": 0.8, "border": 0.8, "content": 0.8 }
    }
}
```

With this configuration:
- Window translucency remains driven by `window.opacity` and `areaOpacity`.
- Text alpha is reduced to 80% of its original text color alpha.

## Double Size (2x) Mode

Toggle via the **2X** button on the main window or right-click context menu → **Double Size** (available in both modern and classic UI). Doubles all window dimensions and rendering scale.

- **Modern UI**: live toggle — windows resize immediately, views recreate their renderers
- **Classic UI**: requires restart — a "Restart Required" dialog is shown before any UI change; the flag is toggled then `relaunchApp()` is called so `saveState()` captures the new value on termination

### How It Works (Modern UI)

`ModernSkinElements.scaleFactor` is a computed property: `baseScaleFactor * sizeMultiplier`.

- `baseScaleFactor` -- set by skin.json `window.scale` (default 1.25)
- `sizeMultiplier` -- set by double size mode (1.0 normal, 2.0 double)

When double size is toggled:
1. `WindowManager` sets `ModernSkinElements.sizeMultiplier` to 2.0 (or 1.0)
2. All computed sizes automatically update (window sizes, title bar heights, border widths, etc.)
3. `WindowManager.applyDoubleSize()` resizes all windows
4. `doubleSizeDidChange` notification triggers views to recreate their renderers
5. All rendering scales correctly with the updated `scaleFactor`

### Side Windows (Library Browser, ProjectM)

Side windows scale their width by `sizeMultiplier` and match the vertical stack height. Internal layout constants (`itemHeight`, `tabBarHeight`, etc.) and fonts also scale by `sizeMultiplier`.

### Interaction with Skin Scale

A skin with `"window": { "scale": 1.5 }` sets `baseScaleFactor` to 1.5. In double size mode, the effective `scaleFactor` becomes 3.0 (1.5 x 2.0).

## Adding a Modern Sub-Window (Developer Guide)

This section documents the repeatable pattern for creating modern-skinned versions of sub-windows.

**Reference implementation**: `ModernSpectrumWindowController` + `ModernSpectrumView` (simplest sub-window).

### Layer-by-Layer Checklist

1. **`ModernSkinElements.swift`** -- Add window layout constants (size, shade height, title bar height, border width) and optional per-window element IDs (e.g., `{window}_titlebar`, `{window}_btn_close`). Add new elements to `allElements` array.

2. **`ModernSkinRenderer.swift`** -- Add any new element IDs to the fallback switch in `drawWindowControlButton` (e.g., `"spectrum_btn_close"` alongside `"btn_close"`).

3. **Create `App/{Window}WindowProviding.swift`** -- Protocol matching `MainWindowProviding` / `SpectrumWindowProviding` pattern with `window`, `showWindow`, `skinDidChange`, etc.

4. **Add conformance to existing classic controller** -- The classic controller already has the required methods; just add the protocol conformance declaration.

5. **Create `Windows/Modern{Window}/Modern{Window}WindowController.swift`** -- Borderless window, shade mode, fullscreen, `NSWindowDelegate` for docking, conforms to the protocol. Zero classic skin imports.

6. **Create `Windows/Modern{Window}/Modern{Window}View.swift`** -- Compose `ModernSkinRenderer` methods for chrome (`drawWindowBackground`, `drawWindowBorder`, `drawTitleBar`, `drawWindowControlButton`), skin change observation via `ModernSkinDidChange` notification. Zero classic skin imports. Note: `GridBackgroundLayer` is only used in the main window; sub-windows use solid backgrounds.

7. **Update `WindowManager.swift`** -- Change the controller property type to the protocol. Conditionally create modern or classic controller in the show method based on `isModernUIEnabled`.

8. **Update NeonWave `skin.json`** -- Add per-window element entries if needed (e.g., `"spectrum_titlebar": { "color": "#0c1018" }`).

9. **Update docs** -- Update skill documentation as needed.

### Key Rules

- **Zero classic imports**: Files in `ModernSkin/` and `Windows/Modern{Window}/` must NEVER import or reference anything from `Skin/` or `Windows/{ClassicWindow}/`
- **Skin changes**: Observe `ModernSkinEngine.skinDidChangeNotification` to re-create renderer
- **Double size changes**: Observe `.doubleSizeDidChange` notification and call `skinDidChange()` to recreate the renderer with the updated scale factor
- **Scale factor**: Use `ModernSkinElements.scaleFactor` for all geometry. This is a computed property: `baseScaleFactor * sizeMultiplier`. Do NOT cache in a `let` -- use a computed `var` or reference `ModernSkinElements.scaleFactor` directly
- **Coordinates**: Standard macOS bottom-left origin (no flipping needed, unlike classic skin system)
