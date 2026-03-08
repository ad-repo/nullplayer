---
name: modern-skin-guide
description: Modern skin engine, skin.json schema, element catalog, and custom skin creation. Use when creating or modifying modern skins, working on ModernSkin components, or adding UI elements to the modern system.
---

# Modern Skin Creation Guide

This guide covers creating custom skins for NullPlayer's modern UI mode.

## Overview

Modern skins are built on the **ModernSkin Engine**, a theme-agnostic system that renders UI elements from:

1. **JSON configuration** (`skin.json`) -- colors, fonts, layout, animations
2. **PNG image assets** -- optional per-element images
3. **Programmatic fallback** -- elements without images are drawn using palette colors

You can create a skin with just a `skin.json` (pure programmatic) or provide custom images for every element.

## Skin Directory Structure

```
MySkin/
├── skin.json              # Required: skin configuration
├── images/                # Optional: PNG assets
│   ├── btn_play_normal.png
│   ├── btn_play_pressed.png
│   ├── btn_play_normal@2x.png    # Optional Retina
│   └── background.png
└── fonts/                 # Optional: custom fonts
    └── MyFont.ttf
```

## skin.json Schema

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
        "border": "#00ffcc",
        "timeColor": "#d9d900",
        "marqueeColor": "#d9d900",
        "dataColor": "#d9d900",
        "eqLow": "#00d900",
        "eqMid": "#d9d900",
        "eqHigh": "#d92600"
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
        "scale": 1.25,
        "opacity": 0.9,
        "textOpacity": 1.0,
        "seamlessDocking": 1.0
    },
    "marquee": {
        "scrollSpeed": 30,
        "scrollGap": 50
    },
    "titleText": {
        "mode": "image",
        "charSpacing": 1,
        "charHeight": 10,
        "alignment": "center",
        "tintColor": "#d4cfc0"
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

17 named colors used throughout the UI:

| Key | Purpose |
|-----|---------|
| `primary` | Main accent (buttons, text, indicators) |
| `secondary` | Secondary accent |
| `accent` | Highlight accent (spectrum, volume gradient) |
| `highlight` | Bright highlight |
| `background` | Window fill |
| `surface` | Panel/recessed areas |
| `text` | Primary text |
| `textDim` | Dimmed/inactive text |
| `timeColor` | Time display digits |
| `marqueeColor` | Scrolling title text |
| `dataColor` | Track numbers, info fields |
| `eqLow`, `eqMid`, `eqHigh` | EQ gradient colors |

## Image Naming Convention

Images go in the `images/` subdirectory:

```
{element_id}_{state}.png       # State-specific
{element_id}.png               # All states
{element_id}_{state}@2x.png   # Retina (optional)
```

**Examples:**
- `btn_play_normal.png` -- Play button, normal state
- `btn_play_pressed.png` -- Play button, pressed state
- `time_digit_5.png` -- Digit "5" for time display

The engine automatically checks for `@2x` variants on Retina displays.

## Creating a Minimal Skin

The simplest skin is just a `skin.json` with palette colors:

```json
{
    "meta": { "name": "Minimal", "author": "Me", "version": "1.0" },
    "palette": {
        "primary": "#ff6600",
        "accent": "#ff0066",
        "background": "#1a1a2e",
        "surface": "#16213e",
        "text": "#ff6600",
        "textDim": "#664400"
    },
    "fonts": { "primaryName": "DepartureMono-Regular", "fallbackName": "Menlo" },
    "background": { "grid": { "color": "#332200", "spacing": 15, "angle": 80, "opacity": 0.1 } },
    "glow": { "enabled": true, "radius": 6, "intensity": 0.5, "threshold": 0.6 },
    "window": { "borderWidth": 1, "cornerRadius": 6, "opacity": 0.9, "textOpacity": 1.0, "seamlessDocking": 1.0 }
}
```

All elements render programmatically using the palette colors.

## Bundled Skins

### NeonWave (Default)
- Cyan/magenta palette
- Sprite-based title text (7x11 pixel art)
- Procedural elements (no button images)
- Glow effects and perspective grid
- Seamless docking (`seamlessDocking: 1.0`)

### Skulls (Reference)
- Cream/amber palette with skull decorations
- Bold 7x11 pixel character sprites
- Amber 7-segment time digits
- Beveled transport buttons
- Lo-fi receiver aesthetic

## Packaging for Distribution

ZIP your skin directory and rename to `.nps`:

```bash
cd MySkin/
zip -r ../MySkin.nps .
```

Users place `.nps` files or folders in:
```
~/Library/Application Support/NullPlayer/ModernSkins/
```

## Installation

### Selecting a Skin

Right-click the player → **Modern UI** → **Select Skin** → choose from the list.

Skin changes take effect immediately. Switching between Classic and Modern mode requires a restart.

## Multi-Window Support

The modern skin system renders multiple windows:

- **Main Window** -- transport controls, time, marquee, mini spectrum
- **Playlist Window** -- track list with selection, scrolling
- **EQ Window** -- 10-band graphic equalizer with curve graph
- **Spectrum Analyzer Window** -- standalone visualization
- **ProjectM Window** -- MilkDrop visualization with presets
- **Library Browser Window** -- multi-source browser with columns

All windows share palette colors, glow, grid, and font settings. Customize individual windows by prefixing element IDs (e.g., `spectrum_titlebar` vs `titlebar`).

## Key Source Files

| File | Purpose |
|------|---------|
| `ModernSkin/ModernSkinEngine.swift` | Singleton manager, skin loading |
| `ModernSkin/ModernSkinConfig.swift` | JSON schema, Codable structs |
| `ModernSkin/ModernSkinLoader.swift` | Load skin.json and images |
| `ModernSkin/ModernSkinRenderer.swift` | Drawing code for all elements |
| `ModernSkin/ModernSkinElements.swift` | Layout constants, element IDs |
| `Windows/ModernMainWindow/` | Main window implementation |
| `Windows/ModernSpectrum/` | Spectrum window (simplest sub-window) |
| `Windows/ModernPlaylist/` | Playlist window |
| `Windows/ModernEQ/` | EQ window |
| `Windows/ModernProjectM/` | ProjectM window |
| `Windows/ModernLibraryBrowser/` | Library browser window |

## Additional Documentation

For detailed information, see:
- [element-reference.md](element-reference.md) - Complete element catalog with all IDs, positions, states
- [advanced-features.md](advanced-features.md) - Title text system, animations, Double Size mode, sub-window creation checklist
