# Modern Skin Creation Guide

This guide covers creating custom skins for NullPlayer's modern UI mode.

## Overview

Modern skins are built on the **ModernSkin Engine**, a theme-agnostic system that renders UI elements from a combination of:

1. **JSON configuration** (`skin.json`) -- colors, fonts, layout, animations
2. **PNG image assets** -- optional per-element images
3. **Programmatic fallback** -- elements without images are drawn using palette colors

This means you can create a skin with just a `skin.json` (pure programmatic) or provide custom images for every element.

## Skin Directory Structure

```
MySkin/
├── skin.json              # Required: skin configuration
└── images/                # Optional: PNG assets
    ├── btn_play_normal.png
    ├── btn_play_pressed.png
    ├── btn_play_normal@2x.png    # Optional Retina version
    ├── btn_play_pressed@2x.png
    ├── time_digit_0.png
    ├── ...
    └── background.png
```

## `skin.json` Schema

```json
{
    "meta": {
        "name": "My Skin",
        "author": "Your Name",
        "version": "1.0",
        "description": "A custom modern skin"
    },
    "palette": {
        "primary": "#00ffcc",
        "secondary": "#00aaff",
        "accent": "#ff00aa",
        "highlight": "#00ffee",
        "background": "#0a0a12",
        "surface": "#0d1117",
        "text": "#00ffcc",
        "textDim": "#006655",
        "positive": "#00ff88",
        "negative": "#ff3366",
        "warning": "#ffaa00",
        "border": "#00ffcc"
    },
    "fonts": {
        "primaryName": "DepartureMono-Regular",
        "fallbackName": "Menlo",
        "titleSize": 8,
        "bodySize": 9,
        "smallSize": 7,
        "timeSize": 20,
        "infoSize": 6.5,
        "eqLabelSize": 7,
        "eqValueSize": 6,
        "marqueeSize": 11.7,
        "playlistSize": 8
    },
    "background": {
        "image": "background.png",
        "grid": {
            "color": "#0a2a2a",
            "spacing": 20,
            "angle": 75,
            "opacity": 0.15,
            "perspective": true
        }
    },
    "glow": {
        "enabled": true,
        "radius": 8,
        "intensity": 0.6,
        "threshold": 0.7,
        "color": "#00ffcc",
        "elementBlur": 1.0
    },
    "window": {
        "borderWidth": 1,
        "borderColor": "#00ffcc",
        "cornerRadius": 8,
        "scale": 1.25
    },
    "marquee": {
        "scrollSpeed": 30,
        "scrollGap": 50
    },
    "elements": {
        "btn_play": {
            "color": "#00ff00",
            "x": 33, "y": 8, "width": 23, "height": 20
        }
    },
    "animations": {
        "seek_fill": {
            "type": "glow",
            "duration": 3.0,
            "minValue": 0.4,
            "maxValue": 1.0
        }
    }
}
```

## Color Palette

The palette defines 17 named colors used throughout the UI:

| Key | Purpose | Fallback |
|-----|---------|----------|
| `primary` | Main accent color (buttons, text, indicators) | Required |
| `secondary` | Secondary accent | Required |
| `accent` | Highlight accent (spectrum bars, volume gradient) | Required |
| `highlight` | Bright highlight | Defaults to `primary` |
| `background` | Window fill color | Required |
| `surface` | Panel/recessed area background | Required |
| `text` | Primary text color | Required |
| `textDim` | Dimmed/inactive text | Required |
| `positive` | Positive indicator | `#00ff00` |
| `negative` | Error/negative indicator | `#ff0000` |
| `warning` | Warning indicator | `#ffaa00` |
| `border` | Window border color | Same as `primary` |
| `timeColor` | Time display digit color | `#d9d900` (warm yellow) |
| `marqueeColor` | Scrolling title/marquee text color | `#d9d900` (warm yellow) |
| `eqLow` | EQ color at -12dB (bottom of slider) | `#00d900` (green) |
| `eqMid` | EQ color at 0dB (middle of slider) | `#d9d900` (yellow) |
| `eqHigh` | EQ color at +12dB (top of slider) | `#d92600` (red) |

All colors are hex strings (e.g., `"#00ffcc"`).

## Element Catalog

Every skinnable element has an ID, default position/size, and valid states.

### Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `window_background` | 0,0,275,116 | normal | Full window background |
| `window_border` | 0,0,275,116 | normal | Window border overlay |

### Title Bar

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `titlebar` | 0,102,275,14 | normal | Title bar background |
| `titlebar_text` | 50,102,175,14 | normal | Title text area |
| `btn_close` | 255,103,12,12 | normal, pressed | Close button |
| `btn_minimize` | 228,103,12,12 | normal, pressed | Minimize button |
| `btn_shade` | 241,103,12,12 | normal, pressed | Shade mode button |

### Time Display

| Element ID | Default Rect | Description |
|-----------|-------------|-------------|
| `time_display` | 10,66,80,30 | Time display area |
| `time_digit_0` through `time_digit_9` | 14x22 each | 7-segment LED digits |
| `time_colon` | 7x22 | Colon separator |
| `time_minus` | 14x22 | Minus sign (remaining time) |

### Info Panel

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `marquee_bg` | 95,66,170,30 | normal | Marquee background panel |
| `info_bitrate` | 95,62,40,9 | normal | Bitrate label |
| `info_samplerate` | 135,62,30,9 | normal | Sample rate label |
| `info_bpm` | 165,62,30,9 | normal | BPM label |
| `info_stereo` | 198,62,32,9 | off, on | Stereo indicator |
| `info_mono` | 198,62,32,9 | off, on | Mono indicator |
| `info_cast` | 232,62,34,9 | off, on | Cast active indicator |

### Status & Spectrum

| Element ID | Default Rect | Description |
|-----------|-------------|-------------|
| `status_play` | 10,48,12,12 | Play status indicator |
| `status_pause` | 10,48,12,12 | Pause status indicator |
| `status_stop` | 10,48,12,12 | Stop status indicator |
| `spectrum_area` | 24,44,60,20 | Mini spectrum analyzer |

### Seek Bar

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `seek_track` | 10,36,255,6 | normal | Seek bar track |
| `seek_fill` | 10,36,*,6 | normal | Filled portion |
| `seek_thumb` | *,34,10,10 | normal, pressed | Seek position thumb |

### Transport Buttons

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `btn_prev` | 10,8,23,20 | normal, pressed, disabled | Previous track |
| `btn_play` | 33,8,23,20 | normal, pressed, disabled | Play |
| `btn_pause` | 56,8,23,20 | normal, pressed, disabled | Pause |
| `btn_stop` | 79,8,23,20 | normal, pressed, disabled | Stop |
| `btn_next` | 102,8,23,20 | normal, pressed, disabled | Next track |
| `btn_eject` | 125,8,23,20 | normal, pressed | Open file |

### Toggle Buttons

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `btn_shuffle` | 154,8,40,20 | off, on, off_pressed, on_pressed | Shuffle toggle |
| `btn_repeat` | 196,8,40,20 | off, on, off_pressed, on_pressed | Repeat toggle |
| `btn_eq` | 154,8,23,12 | off, on, off_pressed, on_pressed | EQ window toggle |
| `btn_playlist` | 178,8,23,12 | off, on, off_pressed, on_pressed | Playlist toggle |

### Volume

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `volume_track` | 240,8,28,6 | normal | Volume bar track |
| `volume_fill` | 240,8,*,6 | normal | Filled portion |
| `volume_thumb` | *,6,8,10 | normal, pressed | Volume thumb |

### Spectrum Window Chrome

The standalone Spectrum Analyzer window uses the modern skin system for its chrome. By default it shares the main window's chrome elements (`window_background`, `window_border`). Skins can optionally provide spectrum-specific images for per-window customization:

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `spectrum_titlebar` | 0,102,275,14 | normal | Spectrum window title bar (falls back to `titlebar` rendering) |
| `spectrum_btn_close` | 261,104,10,10 | normal, pressed | Spectrum window close button (falls back to `btn_close` rendering) |

### Playlist Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `playlist_titlebar` | 0,102,275,14 | normal | Playlist window title bar (falls back to `titlebar` rendering) |
| `playlist_btn_close` | 261,104,10,10 | normal, pressed | Playlist close button (falls back to `btn_close`) |
| `playlist_btn_shade` | 249,104,10,10 | normal, pressed | Playlist shade button (falls back to `btn_shade`) |

The modern playlist does not have bottom bar buttons -- all playlist operations (add, remove, sort, etc.) are available via the right-click context menu and keyboard shortcuts. The currently playing track is rendered in `accent` color (magenta in NeonWave).

### EQ Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `eq_titlebar` | 0,102,275,14 | normal | EQ window title bar (falls back to `titlebar` rendering) |
| `eq_btn_close` | 261,104,10,10 | normal, pressed | EQ close button (falls back to `btn_close`) |
| `eq_btn_shade` | 249,104,10,10 | normal, pressed | EQ shade button (falls back to `btn_shade`) |

The modern EQ window renders a 10-band graphic equalizer with preamp, ON/OFF toggle, AUTO toggle (genre-based presets), and PRESETS menu. Sliders use a color-coded fill: green (-12dB) through yellow (0dB) to red (+12dB). The EQ curve graph displays the current band values with the same color mapping and glow effects.

If a skin provides no window-specific images, the renderer falls back to the shared chrome elements, then to programmatic fallback using palette colors.

### ProjectM Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `projectm_titlebar` | 0,102,275,14 | normal | ProjectM window title bar (falls back to `titlebar` rendering) |
| `projectm_btn_close` | 256,104,10,10 | normal, pressed | ProjectM close button (falls back to `btn_close`) |

The modern ProjectM window embeds the same `VisualizationGLView` (OpenGL) used by the classic version. It supports full multi-edge resizing and custom fullscreen mode (borderless windows don't support native macOS fullscreen). All preset navigation, visualization engine selection, audio/beat sensitivity controls, and performance mode options are available via the right-click context menu and keyboard shortcuts.

### Library Browser Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `library_titlebar` | 0,102,275,14 | normal | Library browser title bar (falls back to `titlebar` rendering) |
| `library_btn_close` | 256,104,10,10 | normal, pressed | Library browser close button (falls back to `btn_close`) |
| `library_btn_shade` | 244,104,10,10 | normal, pressed | Library browser shade button (falls back to `btn_shade`) |

The modern library browser provides multi-source browsing (Local Files, Plex, Subsonic/Navidrome, Internet Radio) with multiple browse modes (Artists, Albums, Tracks, Playlists, Movies, Shows, Search, Radio). Tabs and selections use the modern boxed toggle style with `accent` color when active and `textDim` color when inactive. The window supports multi-edge resizing (all four edges and corners).

**Configurable columns:** The library browser displays metadata in resizable, toggleable columns. Users can drag column borders to resize, right-click the header to show/hide columns, and sort by clicking headers. Column widths, visibility, and sort preferences persist in UserDefaults (`BrowserColumnWidths`, `BrowserVisibleTrackColumns`, `BrowserVisibleAlbumColumns`, `BrowserVisibleArtistColumns`, `BrowserColumnSortId`, `BrowserColumnSortAscending`). Available track columns include: #, Title, Artist, Album, Album Artist, Year, Genre, Time, Bitrate, Sample Rate, Channels, Size, Rating, Plays, Disc, Date Added, Last Played, Path. The `currentVisibleColumns()` method returns the filtered/ordered column set for rendering and hit testing. The resize threshold scales with `sizeMultiplier` for Double Size mode compatibility.

## Multi-Window Support

The modern skin system renders multiple windows:

- **Main Window** -- transport controls, time display, marquee, mini spectrum
- **Playlist Window** -- track list with selection, scrolling, marquee, accent-colored playing track
- **EQ Window** -- 10-band graphic equalizer with preamp, Auto EQ, presets, curve graph
- **Spectrum Analyzer Window** -- standalone visualization with skin chrome
- **ProjectM Window** -- ProjectM visualization with skin chrome, presets, fullscreen
- **Library Browser Window** -- multi-source browser (Local/Plex/Subsonic/Radio) with hierarchy, columns, artwork, visualizer

All windows share the same `window_background`, `window_border`, palette colors, glow, grid, and font settings from the active skin. To customize individual windows differently, prefix element IDs with the window name (e.g., `spectrum_titlebar` vs `titlebar`).

## NeonWave Default Skin

The bundled default skin ("NeonWave") is fully programmatic -- it contains zero PNG image assets and relies entirely on the palette colors and the renderer's programmatic fallback.

**Windows covered**: Main window + Playlist window + EQ window + Spectrum Analyzer window + ProjectM window + Library Browser window

**Palette**: `#00ffcc` (cyan primary), `#ff00aa` (magenta accent), `#080810` (background)

**Spectrum colors**: Auto-derived gradient from `palette.accent` (bottom, magenta) to `palette.primary` (top, cyan) via `ModernSkin.spectrumColors()`. These colors are applied to the Metal-based `SpectrumAnalyzerView`.

## Image Naming Convention

Images go in the `images/` subdirectory with this naming:

```
{element_id}_{state}.png       # State-specific image
{element_id}.png               # Used for all states (if no state-specific image)
{element_id}_{state}@2x.png   # Retina version (optional)
```

**Examples:**
- `btn_play_normal.png` -- Play button, normal state
- `btn_play_pressed.png` -- Play button, pressed state
- `seek_thumb.png` -- Seek thumb, all states
- `time_digit_5.png` -- Digit "5" for time display
- `time_colon.png` -- Colon for time display

The engine automatically checks for `@2x` variants on Retina displays.

## Background Configuration

You can use either a background image or a procedural grid (or both):

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

The bloom post-processor adds glow effects to bright elements:

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
- `elementBlur`: Multiplier for per-element glow blur on buttons, text, sliders (default 1.0, set 0 for flat)

## Animation Configuration

Two animation types are supported:

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

## Font Configuration

All font sizes are **unscaled base values**. The engine multiplies them by the UI scale factor (`window.scale`, default 1.25) automatically. The 9 configurable sizes cover every text context in the player chrome windows. The library browser uses proportional system fonts for readability in dense data views, scaled by `window.scale` but not affected by font name settings.

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

The app ships with **Departure Mono** (SIL OFL license). Use it by name:

```json
"fonts": {
    "primaryName": "DepartureMono-Regular",
    "fallbackName": "Menlo"
}
```

### Using a Custom Font

Include a TTF/OTF in `fonts/` within your skin bundle:

```
MySkin/
├── skin.json
├── fonts/
│   └── MyCustomFont.ttf
└── images/
```

Reference by PostScript name:

```json
"fonts": {
    "primaryName": "MyCustomFont"
}
```

## Creating a Minimal Skin

The simplest skin is just a `skin.json` with palette colors:

```json
{
    "meta": { "name": "Minimal", "author": "Me", "version": "1.0" },
    "palette": {
        "primary": "#ff6600",
        "secondary": "#ffaa00",
        "accent": "#ff0066",
        "background": "#1a1a2e",
        "surface": "#16213e",
        "text": "#ff6600",
        "textDim": "#664400"
    },
    "fonts": { "primaryName": "DepartureMono-Regular", "fallbackName": "Menlo" },
    "background": { "grid": { "color": "#332200", "spacing": 15, "angle": 80, "opacity": 0.1, "perspective": false } },
    "glow": { "enabled": true, "radius": 6, "intensity": 0.5, "threshold": 0.6 },
    "window": { "borderWidth": 1, "cornerRadius": 6 }
}
```

All elements will render programmatically using the palette colors.

## Packaging for Distribution (`.nps` Bundle)

ZIP your skin directory and rename the extension to `.nps`:

```bash
cd MySkin/
zip -r ../MySkin.nps .
```

Users can place `.nps` files in:
```
~/Library/Application Support/NullPlayer/ModernSkins/
```

Or use folder-based skins for development (unzipped directory in the same location).

## Installation

### User Skins Directory

Place skin folders or `.nps` files at:
```
~/Library/Application Support/NullPlayer/ModernSkins/
```

### Selecting a Skin

Right-click the player → **Modern UI** → **Select Skin** → choose from the list.

Skin changes take effect immediately (no restart needed for skin change -- only for switching between Classic/Modern mode).

## Double Size (2x) Mode

Toggle via the **2X** button on the main window (first toggle button in the row) or right-click context menu → **Double Size** (modern UI only). This doubles all window dimensions and rendering scale.

### How It Works

`ModernSkinElements.scaleFactor` is a computed property: `baseScaleFactor * sizeMultiplier`.

- `baseScaleFactor` -- set by skin.json `window.scale` (default 1.25)
- `sizeMultiplier` -- set by double size mode (1.0 normal, 2.0 double)

When double size is toggled:
1. `WindowManager` sets `ModernSkinElements.sizeMultiplier` to 2.0 (or 1.0)
2. All computed sizes in `ModernSkinElements` automatically update (window sizes, title bar heights, border widths, shade heights, etc.)
3. `WindowManager.applyDoubleSize()` resizes all windows to the new sizes
4. The `doubleSizeDidChange` notification triggers views to recreate their renderers with the new `scaleFactor`
5. All rendering scales correctly because the renderer receives the updated `scaleFactor`

### Interaction with Hide Title Bars

Both features compose naturally because they both derive from `scaleFactor`. In double size mode, title bar heights also double. When title bars are hidden in double size mode, the doubled title bar height is correctly subtracted from the doubled window size.

### Side Windows (Library Browser, ProjectM)

Side windows (Library Browser, ProjectM) scale their width by `sizeMultiplier` and match the vertical stack height. Their internal layout constants (`itemHeight`, `tabBarHeight`, `serverBarHeight`, etc.) and fonts (`scaledSystemFont`, `sideWindowFont`) also scale by `sizeMultiplier` so the content is proportionally correct in 2x mode. Hardcoded pixel padding values in drawing methods must be multiplied by `ModernSkinElements.sizeMultiplier` to maintain proportions.

### Interaction with Skin Scale

A skin with `"window": { "scale": 1.5 }` sets `baseScaleFactor` to 1.5. In double size mode, the effective `scaleFactor` becomes 3.0 (1.5 x 2.0). All rendering and window sizing adjusts accordingly.

## Adding a Modern Sub-Window (Developer Guide)

This section documents the repeatable pattern for creating modern-skinned versions of sub-windows. Future agents creating Modern EQ, Modern Playlist, Modern ProjectM, etc. should follow this recipe.

**Reference implementation**: `ModernSpectrumWindowController` + `ModernSpectrumView` (simplest sub-window -- just chrome + embedded content).

### Layer-by-Layer Checklist

1. **`ModernSkinElements.swift`** -- Add window layout constants (size, shade height, title bar height, border width) and optional per-window element IDs (e.g., `{window}_titlebar`, `{window}_btn_close`). Add new elements to `allElements` array.

2. **`ModernSkinRenderer.swift`** -- Add any new element IDs to the fallback switch in `drawWindowControlButton` (e.g., `"spectrum_btn_close"` alongside `"btn_close"`).

3. **Create `App/{Window}WindowProviding.swift`** -- Protocol matching `MainWindowProviding` / `SpectrumWindowProviding` pattern with `window`, `showWindow`, `skinDidChange`, etc.

4. **Add conformance to existing classic controller** -- The classic controller already has the required methods; just add the protocol conformance declaration.

5. **Create `Windows/Modern{Window}/Modern{Window}WindowController.swift`** -- Borderless window, shade mode, fullscreen, `NSWindowDelegate` for docking, conforms to the protocol. Zero classic skin imports.

6. **Create `Windows/Modern{Window}/Modern{Window}View.swift`** -- Compose `ModernSkinRenderer` methods for chrome (`drawWindowBackground`, `drawWindowBorder`, `drawTitleBar`, `drawWindowControlButton`), skin change observation via `ModernSkinDidChange` notification. Zero classic skin imports. Note: `GridBackgroundLayer` is only used in the main window; sub-windows use solid backgrounds.

7. **Update `WindowManager.swift`** -- Change the controller property type to the protocol. Conditionally create modern or classic controller in the show method based on `isModernUIEnabled`.

8. **Update NeonWave `skin.json`** -- Add per-window element entries if needed (e.g., `"spectrum_titlebar": { "color": "#0c1018" }`).

9. **Update docs** -- `MODERN_SKIN_GUIDE.md` (element catalog), `CLAUDE.md` (key files, architecture), relevant `AGENT_DOCS/` files.

### Key Rules

- **Zero classic imports**: Files in `ModernSkin/` and `Windows/Modern{Window}/` must NEVER import or reference anything from `Skin/` or `Windows/{ClassicWindow}/`
- **Skin changes**: Observe `ModernSkinEngine.skinDidChangeNotification` to re-create renderer
- **Double size changes**: Observe `.doubleSizeDidChange` notification and call `skinDidChange()` to recreate the renderer with the updated scale factor
- **Scale factor**: Use `ModernSkinElements.scaleFactor` for all geometry. This is a computed property: `baseScaleFactor * sizeMultiplier`. The `baseScaleFactor` is set by skin.json `window.scale` (default 1.25); the `sizeMultiplier` is set by double size mode (1.0 or 2.0). Do NOT cache `scaleFactor` in a `let` -- use a computed `var` or reference `ModernSkinElements.scaleFactor` directly
- **Coordinates**: Standard macOS bottom-left origin (no flipping needed, unlike classic skin system)

### Element Image Fallback Chain

When the renderer looks up an image for a per-window element:

1. `{window}_{element}_{state}.png` (e.g., `spectrum_btn_close_pressed.png`)
2. `{window}_{element}.png` (e.g., `spectrum_btn_close.png`)
3. Programmatic fallback using palette colors (e.g., X icon drawn with `textDimColor`)
