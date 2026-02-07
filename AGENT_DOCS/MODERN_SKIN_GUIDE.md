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
        "titleSize": 10,
        "bodySize": 9,
        "smallSize": 7,
        "timeSize": 20
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
        "color": "#00ffcc"
    },
    "window": {
        "borderWidth": 1,
        "borderColor": "#00ffcc",
        "cornerRadius": 8
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

The palette defines 12 named colors used throughout the UI:

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
| `info_bitrate` | 95,58,60,10 | normal | Bitrate label |
| `info_samplerate` | 155,58,50,10 | normal | Sample rate label |
| `info_stereo` | 210,58,30,10 | off, on | Stereo indicator |
| `info_mono` | 210,58,30,10 | off, on | Mono indicator |
| `info_cast` | 242,58,25,10 | off, on | Cast active indicator |

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
    "color": "#00ffcc"
}
```

- `enabled`: Master on/off
- `radius`: Blur kernel size (larger = softer glow)
- `intensity`: Bloom brightness multiplier
- `threshold`: Brightness threshold (0-1, pixels above this glow)
- `color`: Override glow color (defaults to palette primary)

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
