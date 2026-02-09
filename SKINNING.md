# Creating NullPlayer Modern Skins

This guide walks you through creating custom skins for NullPlayer's modern UI mode. You can create a skin with nothing more than a text editor -- no programming required.

> **Classic Mode skins**: NullPlayer also supports classic `.wsz` skins in Classic Mode. No skins are bundled -- load a `.wsz` file via **Skins > Load Skin...** or place files in `~/Library/Application Support/NullPlayer/Skins/`. Official skin packages are available in `dist/Skins/`. Use **Skins > Get More Skins...** to find community-created skins online.

## Two Approaches

There are two ways to skin NullPlayer's modern UI:

1. **Palette-only (JSON only)** -- Define colors, fonts, and effects in a single `skin.json` file. All UI elements are drawn programmatically using your color palette. This is the fastest way to create a skin and what the bundled "NeonWave" skin uses.

2. **Image-based (JSON + PNGs)** -- Provide custom PNG images for some or all UI elements alongside your `skin.json`. Any element without a custom image falls back to programmatic rendering using your palette. Mix and match freely.

Both approaches use the same `skin.json` configuration file. The difference is whether you also include an `images/` directory with PNG assets.

---

## Quick Start: Your First Skin in 5 Minutes

1. Create a folder for your skin:
   ```
   ~/Library/Application Support/NullPlayer/ModernSkins/MyFirstSkin/
   ```

2. Create a file called `skin.json` inside it with this content:
   ```json
   {
       "meta": {
           "name": "My First Skin",
           "author": "Your Name",
           "version": "1.0",
           "description": "A warm orange theme"
       },
       "palette": {
           "primary": "#ff6600",
           "secondary": "#ffaa00",
           "accent": "#ff0066",
           "background": "#1a1a2e",
           "surface": "#16213e",
           "text": "#ff6600",
           "textDim": "#664400"
       }
   }
   ```

3. Right-click the player, go to **Modern UI > Select Skin**, and choose "My First Skin".

That's it. Every button, slider, label, and window border now uses your orange palette.

---

## Approach 1: Palette-Only Skins

A palette-only skin consists of a single `skin.json` file. The engine draws every UI element programmatically using your colors.

### Skin Directory

```
MyPaletteSkin/
└── skin.json
```

### Full skin.json Reference

```json
{
    "meta": {
        "name": "My Skin",
        "author": "Your Name",
        "version": "1.0",
        "description": "Description of your skin"
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
    "marquee": {
        "scrollSpeed": 30,
        "scrollGap": 50
    },
    "window": {
        "borderWidth": 1,
        "borderColor": "#00ffcc",
        "cornerRadius": 8,
        "scale": 1.25
    }
}
```

Every section except `meta` and `palette` is optional -- the engine provides sensible defaults.

### Color Palette

The palette is the heart of a palette-only skin. These 12 colors control the entire UI:

| Key | What it controls | Required? |
|-----|-----------------|-----------|
| `primary` | Main UI color: buttons, text, borders, indicators | Yes |
| `secondary` | Secondary highlights | Yes |
| `accent` | Spectrum bars, volume gradient, active track highlight | Yes |
| `highlight` | Bright highlight for focused elements | No (defaults to `primary`) |
| `background` | Window fill / main background color | Yes |
| `surface` | Recessed panels (marquee, time display area) | Yes |
| `text` | Primary text color | Yes |
| `textDim` | Dimmed text (inactive labels, off-state toggles) | Yes |
| `positive` | Success/positive indicators | No (defaults to `#00ff00`) |
| `negative` | Error/negative indicators | No (defaults to `#ff0000`) |
| `warning` | Warning indicators | No (defaults to `#ffaa00`) |
| `border` | Window border color | No (defaults to `primary`) |
| `timeColor` | Time display digit color | No (defaults to `#d9d900` warm yellow) |
| `marqueeColor` | Scrolling title text color | No (defaults to `#d9d900` warm yellow) |

All colors are hex strings: `"#rrggbb"`.

**Design tip**: Pick a strong primary color, a contrasting accent, and a dark background. The `textDim` color should be a muted version of your primary -- it's used for inactive/off-state elements.

### Fonts

NullPlayer bundles **Departure Mono**, a retro pixel-style monospace font. You can use it or any system-installed font:

```json
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
}
```

All sizes are **unscaled base values** -- the engine multiplies them by the UI scale factor (`window.scale`, default 1.25) automatically.

| Key | Purpose | Default |
|-----|---------|---------|
| `primaryName` | Main font (by PostScript name) | Required |
| `fallbackName` | Fallback if primary can't be loaded | `"Menlo"` |
| `titleSize` | Title bar text | 8 |
| `bodySize` | General body text, source/tab labels | 9 |
| `smallSize` | Small labels, toggle buttons | 7 |
| `timeSize` | Large time display digits | 20 |
| `infoSize` | Info labels (bitrate, sample rate, BPM) | 6.5 |
| `eqLabelSize` | EQ frequency labels | 7 |
| `eqValueSize` | EQ dB value text | 6 |
| `marqueeSize` | Scrolling title/marquee text | 11.7 |
| `playlistSize` | Playlist track list text | 8 |

**Using a custom font**: Include a `.ttf` or `.otf` file in a `fonts/` directory inside your skin folder, then reference it by its PostScript name.

### Background

Choose between a procedural grid or a background image (or both):

**Grid background** (the Tron-style lines):
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

| Key | What it does |
|-----|-------------|
| `color` | Grid line color |
| `spacing` | Distance between lines in points |
| `angle` | Line angle in degrees (75 = nearly vertical) |
| `opacity` | Line opacity, 0.0 to 1.0 (keep this low, 0.05-0.2) |
| `perspective` | `true` for vanishing-point Tron effect, `false` for flat parallel lines |

**Image background**:
```json
"background": {
    "image": "background.png"
}
```

Place the image file in your skin's `images/` directory.

### Glow/Bloom Effects

The bloom post-processor adds a soft glow to bright UI elements:

```json
"glow": {
    "enabled": true,
    "radius": 8,
    "intensity": 0.6,
    "threshold": 0.7,
    "color": "#00ffcc"
}
```

| Key | What it does | Range |
|-----|-------------|-------|
| `enabled` | Turn glow on/off | `true`/`false` |
| `radius` | Blur size (bigger = softer, wider glow) | 1-20 |
| `intensity` | Glow brightness | 0.0-2.0 |
| `threshold` | How bright a pixel must be before it glows | 0.0-1.0 |
| `color` | Override glow tint color | Hex string |
| `elementBlur` | Multiplier for per-element glow blur (buttons, text, sliders) | 0.0-3.0 (default 1.0) |

The `elementBlur` multiplier scales the glow halos on individual UI elements (separate from the bloom post-processor). Set to `0` for completely flat elements, or `2.0` for extra neon intensity.

**Performance note**: Glow uses Metal GPU shaders. Set `"enabled": false` if you want maximum performance or a flat aesthetic.

### Window Chrome

```json
"window": {
    "borderWidth": 1,
    "borderColor": "#00ffcc",
    "cornerRadius": 8
}
```

| Key | What it does |
|-----|-------------|
| `borderWidth` | Border thickness in points (0 = no border) |
| `borderColor` | Border color (defaults to palette `border` or `primary`) |
| `cornerRadius` | Rounded corner radius (0 = square corners) |
| `scale` | UI scale factor (default 1.25). Smaller = more compact, larger = bigger UI |

### Marquee (Scrolling Title Text)

```json
"marquee": {
    "scrollSpeed": 30,
    "scrollGap": 50
}
```

| Key | What it does | Default |
|-----|-------------|---------|
| `scrollSpeed` | Scroll speed in points per second | 30 |
| `scrollGap` | Gap between repeated text in points | 50 |

### Per-Window Titlebar Colors

You can give each window its own titlebar color using the `elements` section:

```json
"elements": {
    "titlebar": { "color": "#0c1018" },
    "spectrum_titlebar": { "color": "#1a0010" },
    "playlist_titlebar": { "color": "#001a10" },
    "eq_titlebar": { "color": "#10001a" },
    "projectm_titlebar": { "color": "#0c1018" },
    "library_titlebar": { "color": "#0c1018" }
}
```

If you don't specify a window-specific titlebar, it falls back to the main `titlebar` element, then to the palette `surface` color.

### Animations

Add animated effects to elements:

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

Animation types: `pulse` (opacity), `glow` (bloom intensity), `rotate` (rotation), `colorCycle` (color interpolation).

---

## Approach 2: Image-Based Skins

For full visual customization, provide PNG images for individual UI elements. Any element without an image falls back to palette-based programmatic rendering.

### Skin Directory

```
MyImageSkin/
├── skin.json
└── images/
    ├── btn_play_normal.png
    ├── btn_play_pressed.png
    ├── btn_play_normal@2x.png      # Optional Retina version
    ├── btn_play_pressed@2x.png
    ├── time_digit_0.png
    ├── time_digit_1.png
    ├── ...
    ├── time_colon.png
    ├── background.png
    └── titlebar.png
```

### Image Naming Convention

Images follow a strict naming pattern:

```
{element_id}_{state}.png          State-specific image
{element_id}.png                  Used for all states
{element_id}_{state}@2x.png      Retina (2x) version
```

**Examples**:
- `btn_play_normal.png` -- Play button in normal state
- `btn_play_pressed.png` -- Play button when pressed
- `seek_thumb.png` -- Seek thumb for all states
- `time_digit_5.png` -- The digit "5" for the time display
- `time_colon.png` -- The colon separator in the time display

The engine automatically uses `@2x` images on Retina displays when available.

### Skinnable Elements

Here is every element you can provide images for:

**Transport Buttons** (states: `normal`, `pressed`, `disabled`):
- `btn_prev` -- Previous track
- `btn_play` -- Play
- `btn_pause` -- Pause
- `btn_stop` -- Stop
- `btn_next` -- Next track
- `btn_eject` -- Open file

**Toggle Buttons** (states: `off`, `on`, `off_pressed`, `on_pressed`):
- `btn_shuffle` -- Shuffle toggle
- `btn_repeat` -- Repeat toggle
- `btn_eq` -- EQ window toggle
- `btn_playlist` -- Playlist window toggle

**Time Display**:
- `time_digit_0` through `time_digit_9` -- 7-segment digit images (14x22 points each)
- `time_colon` -- Colon separator (7x22 points)
- `time_minus` -- Minus sign for remaining time mode (14x22 points)

**Seek Bar**:
- `seek_track` -- The full seek bar track background
- `seek_fill` -- The filled/played portion
- `seek_thumb` (states: `normal`, `pressed`) -- The draggable position indicator

**Volume**:
- `volume_track` -- Volume bar background
- `volume_fill` -- Filled portion
- `volume_thumb` (states: `normal`, `pressed`) -- Volume drag handle

**Window Chrome**:
- `window_background` -- Full window background
- `window_border` -- Window border overlay
- `titlebar` -- Title bar background strip
- `btn_close` (states: `normal`, `pressed`) -- Close button
- `btn_minimize` (states: `normal`, `pressed`) -- Minimize button
- `btn_shade` (states: `normal`, `pressed`) -- Shade/compact mode button

**Info Panel**:
- `marquee_bg` -- Scrolling text area background
- `info_cast` (states: `off`, `on`) -- Cast active indicator
- `info_stereo` (states: `off`, `on`) -- Stereo indicator
- `info_mono` (states: `off`, `on`) -- Mono indicator

**Status Indicators**:
- `status_play` -- Playing status icon
- `status_pause` -- Paused status icon
- `status_stop` -- Stopped status icon

**Spectrum**:
- `spectrum_area` -- Mini spectrum background

**Per-Window Chrome** (each falls back to the main window's chrome if not provided):
- `spectrum_titlebar`, `spectrum_btn_close`
- `playlist_titlebar`, `playlist_btn_close`, `playlist_btn_shade`
- `eq_titlebar`, `eq_btn_close`, `eq_btn_shade`
- `projectm_titlebar`, `projectm_btn_close`
- `library_titlebar`, `library_btn_close`, `library_btn_shade`

### Sprite Frame Animations

For image-based skins, you can define frame-by-frame animations:

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

Place the frame images in your `images/` directory. Repeat modes: `loop`, `reverse`, `once`.

---

## Example Skins

### Warm Sunset (Palette-Only)

```json
{
    "meta": { "name": "Warm Sunset", "author": "Me", "version": "1.0" },
    "palette": {
        "primary": "#ff6b35",
        "secondary": "#ffc233",
        "accent": "#e63946",
        "highlight": "#ffb347",
        "background": "#1d1128",
        "surface": "#2b1a3d",
        "text": "#ff6b35",
        "textDim": "#7a3a1a",
        "positive": "#52b788",
        "negative": "#e63946",
        "warning": "#ffc233",
        "border": "#ff6b35"
    },
    "fonts": { "primaryName": "DepartureMono-Regular", "fallbackName": "Menlo" },
    "background": { "grid": { "color": "#ff6b35", "spacing": 22, "angle": 80, "opacity": 0.04, "perspective": true } },
    "glow": { "enabled": true, "radius": 10, "intensity": 0.5, "threshold": 0.6 },
    "window": { "borderWidth": 1.5, "cornerRadius": 0 }
}
```

### Monochrome Terminal (Palette-Only)

```json
{
    "meta": { "name": "Monochrome Terminal", "author": "Me", "version": "1.0" },
    "palette": {
        "primary": "#33ff33",
        "secondary": "#22cc22",
        "accent": "#66ff66",
        "background": "#0a0a0a",
        "surface": "#111111",
        "text": "#33ff33",
        "textDim": "#1a7a1a"
    },
    "fonts": { "primaryName": "Menlo", "fallbackName": "Monaco" },
    "background": { "grid": { "color": "#33ff33", "spacing": 16, "angle": 90, "opacity": 0.03, "perspective": false } },
    "glow": { "enabled": true, "radius": 4, "intensity": 0.8, "threshold": 0.5 },
    "window": { "borderWidth": 1, "cornerRadius": 0 }
}
```

### Arctic Blue (Palette-Only)

```json
{
    "meta": { "name": "Arctic Blue", "author": "Me", "version": "1.0" },
    "palette": {
        "primary": "#4fc3f7",
        "secondary": "#81d4fa",
        "accent": "#e040fb",
        "highlight": "#b3e5fc",
        "background": "#0d1b2a",
        "surface": "#1b2838",
        "text": "#4fc3f7",
        "textDim": "#1a5276",
        "border": "#4fc3f7"
    },
    "fonts": { "primaryName": "DepartureMono-Regular", "fallbackName": "Menlo", "timeSize": 24 },
    "background": { "grid": { "color": "#4fc3f7", "spacing": 24, "angle": 70, "opacity": 0.05, "perspective": true } },
    "glow": { "enabled": true, "radius": 6, "intensity": 0.7, "threshold": 0.5 },
    "window": { "borderWidth": 1.5, "cornerRadius": 0 }
}
```

---

## Installing and Sharing Skins

### Installing a Skin

Place your skin folder in:
```
~/Library/Application Support/NullPlayer/ModernSkins/
```

Then right-click the player and select your skin from **Modern UI > Select Skin**.

Skin changes take effect immediately -- no restart needed.

### Packaging for Distribution

To share your skin, ZIP the contents and rename to `.nps`:

```bash
cd MyAwesomeSkin/
zip -r ../MyAwesomeSkin.nps .
```

Other users drop the `.nps` file into their `ModernSkins/` directory.

### Using Folder-Based Skins (Development)

During development, keep your skin as an unzipped folder in the `ModernSkins/` directory. Changes to `skin.json` and images take effect when you re-select the skin from the menu -- great for rapid iteration.

---

## Tips and Tricks

- **Start with palette-only**: Get your colors right first, then add images for specific elements if you want custom artwork.
- **The accent color matters**: It's used for the spectrum analyzer gradient, the volume slider gradient, and the currently playing track in the playlist. Make it contrast with your primary.
- **Keep grid opacity low**: Values between 0.03 and 0.15 work best. Higher values make the grid distracting.
- **Test the glow threshold**: Lower values (0.4-0.5) make more elements glow; higher values (0.7-0.9) restrict glow to only the brightest elements.
- **Mix and match images**: You don't need images for everything. Provide images just for the elements you want custom artwork on (like transport buttons or time digits) and let the palette handle the rest.
- **Retina images are optional**: If you provide `btn_play_normal.png` without a `@2x` variant, the engine scales the 1x image. For crisp Retina rendering, provide both.
- **NeonWave as reference**: The bundled NeonWave skin is a good starting point. Copy its `skin.json`, change the palette colors, and you have a new skin.

## Windows Covered

Modern skins apply to all six windows:

- **Main Window** -- Transport controls, time display, scrolling marquee, mini spectrum analyzer
- **Playlist** -- Track list with selection, scrolling, album art background
- **Equalizer** -- 10-band graphic EQ with preamp, presets, curve graph
- **Spectrum Analyzer** -- Standalone visualization window
- **ProjectM Visualizer** -- OpenGL music visualizations with preset navigation
- **Library Browser** -- Multi-source browser (Local, Plex, Subsonic/Navidrome, Internet Radio)

All windows share your skin's palette, fonts, glow settings, and window chrome. Each window can optionally have its own titlebar color via the `elements` section.
