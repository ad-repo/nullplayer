# Advanced Modern Skin Features

This document covers advanced topics: title text system, animations, UI Size mode, and adding new sub-windows.

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
| `marqueeSize` | Scrolling title text | 12.7 |
| `playlistSize` | Playlist track list | 8 |

### Default Font (System Font)

The modern/metal UI renders text in the **macOS system font**, not a retro bitmap font.
Historically the bundled **Departure Mono** was the default, but `ModernSkinFont.resolveFont`
now deliberately **skips** `DepartureMono-Regular` (the "lo-fi" default) and substitutes
`NSFont.systemFont`. Numeric displays (the time/track digits) fall back to
`NSFont.monospacedDigitSystemFont` so digits stay aligned. Existing skin JSONs can still list
`"primaryName": "DepartureMono-Regular"` for compatibility — it just resolves to the system font.

This substitution happens in one place (`ModernSkinFont.resolveFont`), so every modern window
(main, playlist, EQ, spectrum, library) picks it up automatically.

### Using a Custom Font

Include a TTF/OTF in `fonts/` and reference it by PostScript name. Any `primaryName` **other than
the lo-fi default** is honored as-is, so a real custom font keeps the skin's identity:

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
- Applied to modern text-like channels:
  - modern string text (`NSAttributedString` foreground colors) across main/EQ/playlist/library,
  - marquee text (main + playlist),
  - main time digits (sprite and programmatic 7-segment fallback).
- Text paths are rendered at full context alpha so `window.areaOpacity.*.content` does not re-attenuate text.
- Not applied to non-text rendering (fills, borders, strokes, panel backgrounds, icon/shape geometry).
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

### Practical Notes

- If `textOpacity` is `1.0`, text keeps its original alpha (no additional dimming).
- To verify quickly, set `textOpacity` to `0.4` temporarily; library row data, marquee text, and time digits should visibly darken while window glass opacity remains unchanged.

## Main Window Spectrum Opacity (`window.mainSpectrumOpacity`)

Modern skins also support an independent opacity override for the main window's mini spectrum analyzer.

- `window.mainSpectrumOpacity`: optional `0.0...1.0` override.
- Applies only to the main-window spectrum region:
  - 8-bar CPU spectrum content,
  - embedded Metal overlay modes shown in the same panel.
- Does not override spectrum panel fill/border alpha; those follow `window.opacity` + `window.areaOpacity.spectrumArea` so panel border weight stays consistent with other main-window panels.
- Does not affect standalone spectrum window opacity.
- Does not alter base window translucency (`window.opacity`) or text opacity (`window.textOpacity`).
- If omitted, mini spectrum opacity follows existing `window.opacity` + `window.areaOpacity.spectrumArea` resolution.

### Example

```json
"window": {
    "opacity": 0.52,
    "textOpacity": 0.8,
    "mainSpectrumOpacity": 0.9,
    "areaOpacity": {
        "spectrumArea": { "background": 0.8, "border": 0.8, "content": 0.8 }
    }
}
```

## Spectrum and Waveform Window Transparency

### Spectrum Window (`window.spectrumTransparentBackground`)

Boolean toggle — when `true`, the vis_classic visualization renders with a transparent background (matching the in-app Transparent Background toggle). The window chrome continues to use `window.opacity` as normal. When `false` or omitted, the visualization uses its default opaque background.

`visualization.visClassic.spectrumWindowTransparentBackground` overrides this if both are set.

```json
"window": {
    "opacity": 0.85,
    "spectrumTransparentBackground": true
}
```

### Waveform Window (`window.waveformWindowOpacity`)

Float `0.0...1.0` opacity override for the waveform window background. Falls back to `window.opacity` when omitted.

```json
"window": {
    "opacity": 0.85,
    "waveformWindowOpacity": 0.5
}
```

## UI Size Mode

UI label is **UI Size**. Choose **50%**, **90%**, **100%**, **105%**, **110%**, **115%**, **125%**, **135%**, **150%**, or **200%** from the Windows menu or right-click context menu. Available in modern, metal, and classic UI modes.

- **Modern UI**: live change -- windows resize immediately, views recreate their renderers
- **Classic UI**: live change -- windows resize immediately with no restart

### How It Works (Modern UI)

`ModernSkinElements.scaleFactor` is a computed property: `baseScaleFactor * sizeMultiplier`.

- `baseScaleFactor` -- set by skin.json `window.scale` (default 1.25)
- `sizeMultiplier` -- set by UI Size (0.5 = 50%, 1.0 = 100%, 2.0 = 200%)

When UI Size changes:
1. `WindowManager` sets `ModernSkinElements.sizeMultiplier` from `uiScaleLevel.scaleFactor`
2. All computed sizes automatically update (window sizes, title bar heights, border widths, etc.)
3. `WindowManager.applyDoubleSize(previousScale:)` resizes all windows
4. `doubleSizeDidChange` notification triggers views to recreate their renderers
5. All rendering scales correctly with the updated `scaleFactor`

### Side Windows (Library Browser, ProjectM)

Side windows scale their width by `sizeMultiplier` and match the vertical stack height. Internal layout constants (`itemHeight`, `tabBarHeight`, etc.) and fonts also scale by `sizeMultiplier`.

### Interaction with Skin Scale

A skin with `"window": { "scale": 1.5 }` sets `baseScaleFactor` to 1.5. At 125% UI Size, effective `scaleFactor` becomes 1.875 (1.5 x 1.25); at 200%, it becomes 3.0 (1.5 x 2.0).

## Marquee Album Art

The modern main window marquee (`ModernMarqueeLayer`) shows a square album art thumbnail prepended to the scrolling title/artist text. Art and text scroll as a single unit in one seamless loop.

### Layout

- Art square size = `bounds.height` of the marquee layer (fills the full layer height)
- Art gap = 8 pt between the art square and the text
- `artScrollOffset = artSize + artGap` (0 when no art)
- Loop content: `[pad | art | gap | text | scrollGap | pad | art | gap | text | scrollGap]`
- `loopWidth = artScrollOffset + textWidth + scrollGap`

When no art is present, `artScrollOffset = 0` and the layout is identical to the pre-art behaviour.

### Graceful Entry

Art never pops into a mid-scroll position. When a new image arrives while the marquee is scrolling:

1. The bitmap is re-rendered immediately with the art in the new layout
2. `scrollOffset` is bumped by `artScrollOffset` so the currently visible text stays at the same screen position
3. The art sits to the right of the current visible window and scrolls in naturally as the loop progresses

Clearing art (`artworkImage = nil`) is always immediate — stale art never lingers across track changes.

### `artworkImage` property

```swift
// ModernMarqueeLayer
var artworkImage: NSImage?   // backed by _artworkImage via scheduleArtwork(_:)
```

- Setting to `nil`: clears immediately, re-renders
- Setting to an image while scrolling: compensates `scrollOffset`, re-renders with art entering from right
- Setting to an image while static: renders immediately

### Artwork Loading in ModernMainWindowView

`ModernMainWindowView` loads artwork itself — it does **not** depend on `NowPlayingManager` or any other window being open.

Loading is triggered from `updateTrackInfo(_ track:)` via a private `loadArtwork(for:)` method:

| Source | Key used | Notes |
|--------|----------|-------|
| Plex | `plexRatingKey` | Requires `artworkThumb` for URL |
| Subsonic | `subsonicId` (as cover art ID) | Does not require `artworkThumb` |
| Jellyfin | `jellyfinId`, `imageTag: nil` | Server picks image; does not require `artworkThumb` |
| Emby | `embyId`, `artworkThumb` as imageTag | Falls back gracefully if `artworkThumb` is nil |
| Local | `track.url` | Extracts from ID3/iTunes/common metadata via `AVURLAsset` |

**Critical**: Subsonic and Jellyfin do not require `artworkThumb` to be set — the loaders fall back to server-side defaults. Using `artworkThumb` as a required guard (as `NowPlayingManager` does) silently skips tracks where the field is absent.

### Caching

`ModernMainWindowView` maintains a private `static let artworkCache = NSCache<NSString, NSImage>()` keyed by source + ID (e.g. `"marquee_plex:{ratingKey}"`). Subsequent plays of the same track are served from cache with no network request.

### Race Condition Prevention

`loadArtwork(for:)` captures `expectedId = track.id` before the async task. The `MainActor.run` block guards `currentTrack?.id == expectedId` before applying the image. Fast track changes (user clicking Next repeatedly) cannot cause stale art from a cancelled/slow load to appear on the new track.

### Key Files

| File | Role |
|------|------|
| `ModernSkin/ModernMarqueeLayer.swift` | `artworkImage` property, `scheduleArtwork`, scroll compensation |
| `Windows/ModernMainWindow/ModernMainWindowView.swift` | `loadArtwork(for:)`, `artworkLoadTask`, `artworkCache`, `skinDidChange` re-apply |

## Adding a Modern Sub-Window (Developer Guide)

This section documents the repeatable pattern for creating modern-skinned versions of sub-windows.

**Reference implementation**: `ModernSpectrumWindowController` + `ModernSpectrumView` (simplest sub-window).

### Layer-by-Layer Checklist

1. **`ModernSkinElements.swift`** -- Add window layout constants (size, shade height, title bar height, border width) and optional per-window element IDs (e.g., `{window}_titlebar`, `{window}_btn_close`). Add new elements to `allElements` array.

2. **`ModernSkinRenderer.swift`** -- Add any new element IDs to the fallback switch in `drawWindowControlButton` (e.g., `"spectrum_btn_close"` alongside `"btn_close"`).

3. **Create `App/{Window}WindowProviding.swift`** -- Protocol matching `MainWindowProviding` / `SpectrumWindowProviding` pattern with `window`, `showWindow`, `skinDidChange`, etc.

4. **Add conformance to existing classic controller** -- The classic controller already has the required methods; just add the protocol conformance declaration.

5. **Create `Windows/Modern{Window}/Modern{Window}WindowController.swift`** -- Borderless window, fullscreen, `NSWindowDelegate` for docking, conforms to the protocol. Zero classic skin imports.

6. **Create `Windows/Modern{Window}/Modern{Window}View.swift`** -- Compose `ModernSkinRenderer` methods for chrome (`drawWindowBackground`, `drawWindowBorder`, `drawTitleBar`, `drawWindowControlButton`), skin change observation via `ModernSkinDidChange` notification. Zero classic skin imports. Note: `GridBackgroundLayer` is only used in the main window; sub-windows use solid backgrounds.

7. **Update `WindowManager.swift`** -- Change the controller property type to the protocol. Conditionally create modern or classic controller in the show method based on `isModernUIEnabled`.

8. **Update NeonWave `skin.json`** -- Add per-window element entries if needed (e.g., `"spectrum_titlebar": { "color": "#0c1018" }`).

9. **Update docs** -- Update skill documentation as needed.

### Key Rules

- **Zero classic imports**: Files in `ModernSkin/` and `Windows/Modern{Window}/` must NEVER import or reference anything from `Skin/` or `Windows/{ClassicWindow}/`
- **Skin changes**: Observe `ModernSkinEngine.skinDidChangeNotification` to re-create renderer
- **UI Size changes**: Observe `.doubleSizeDidChange` notification and call `skinDidChange()` to recreate the renderer with the updated scale factor
- **Scale factor**: Use `ModernSkinElements.scaleFactor` for all geometry. This is a computed property: `baseScaleFactor * sizeMultiplier`. Do NOT cache in a `let` -- use a computed `var` or reference `ModernSkinElements.scaleFactor` directly
- **Coordinates**: Standard macOS bottom-left origin (no flipping needed, unlike classic skin system)
- **Dockable borders**: Dockable sub-windows must use `ModernSkinElements.auxiliaryWindowBorderWidth` for their outer chrome/content inset. Do not add per-window Metal border constants; Metal intentionally uses the smallest shared border width.
- **Joined edges (all render styles)**: If a dockable window draws its own animated/content rect directly (rather than hosting a child view that naturally fills the content area), pass that rect through `expandingThroughJoinedEdges(in:borderWidth:adjacentEdges:)` before drawing. This bleeds the content back across a docked edge so no leftover background strip shows wherever the shared border is suppressed — modern seamless docking, Metal's thin border, **and classic flush docking** alike. It is **not** metal-only: skipping it in non-metal modes leaves the ~1px seam of issue #364. The helper self-guards (`borderWidth > 0 && !adjacentEdges.isEmpty`), so non-docked edges are untouched.
- **Extra content padding**: Avoid Metal-only outer padding on dockable windows. If normal Modern needs breathing room, make the padding conditional so Metal uses the standard thin border only.

### Dockable Window Checklist

Metal skins share the Modern window classes, but the chrome is visually thinner. When creating or changing any dockable window:

1. Use `ModernSkinElements.auxiliaryWindowBorderWidth` for the view's `borderWidth`.
2. Draw chrome with `drawWindowBackground(... adjacentEdges:sharpCorners:)` and `drawWindowBorder(... occlusionSegments:)`.
3. Subscribe to `.windowLayoutDidChange` and refresh `adjacentEdges`, `sharpCorners`, and `edgeOcclusionSegments` from `WindowManager`.
4. Do not add permanent extra outer padding around content in Metal mode.
5. If the window draws content itself, expand the content rect through joined edges (`expandingThroughJoinedEdges`) before filling/drawing it — in **every** render style, not just Metal.
6. If the window hosts a child content view, keep the child view's frame aligned to the same standardized content rect.

Self-drawn content should follow this shape:

```swift
private var borderWidth: CGFloat { ModernSkinElements.auxiliaryWindowBorderWidth }

private func contentAreaRect() -> NSRect {
    let rect = NSRect(
        x: borderWidth,
        y: borderWidth,
        width: max(0, bounds.width - borderWidth * 2),
        height: max(0, bounds.height - titleBarHeight - borderWidth)
    )
    return rect.expandingThroughJoinedEdges(
        in: bounds,
        borderWidth: borderWidth,
        adjacentEdges: adjacentEdges
    )
}
```

This is required for windows like Flow and PeppyMeter: their animated content fills a rect directly, so a joined edge would otherwise show a leftover strip of window background after the shared border stroke is suppressed. This applies in every render style — the seam of issue #364 appeared precisely because the helper used to bail out in non-metal modes.
