# Modern Skin Element Catalog

Complete reference of all skinnable elements with IDs, default positions, and states.

## Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `window_background` | 0,0,275,116 | normal | Full window background |
| `window_border` | 0,0,275,116 | normal | Window border overlay |

## Title Bar

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `titlebar` | 0,102,275,14 | normal | Title bar background |
| `titlebar_text` | 50,102,175,14 | normal | Title text area |
| `btn_close` | 255,103,12,12 | normal, pressed | Close button |
| `btn_minimize` | 228,103,12,12 | normal, pressed | Minimize button |
| `btn_shade` | 241,103,12,12 | normal, pressed | Shade mode button |

## Time Display

| Element ID | Default Rect | Description |
|-----------|-------------|-------------|
| `time_display` | 10,66,80,30 | Time display area |
| `time_digit_0` through `time_digit_9` | 14x22 each | 7-segment LED digits |
| `time_colon` | 7x22 | Colon separator |
| `time_minus` | 14x22 | Minus sign (remaining time) |

## Info Panel

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `marquee_bg` | 95,66,170,30 | normal | Marquee background panel |
| `info_bitrate` | 95,62,40,9 | normal | Bitrate label |
| `info_samplerate` | 135,62,30,9 | normal | Sample rate label |
| `info_bpm` | 165,62,30,9 | normal | BPM label |
| `info_stereo` | 198,62,32,9 | off, on | Stereo indicator |
| `info_mono` | 198,62,32,9 | off, on | Mono indicator |
| `info_cast` | 232,62,34,9 | off, on | Cast active indicator |

## Status & Spectrum

| Element ID | Default Rect | Description |
|-----------|-------------|-------------|
| `status_play` | 10,48,12,12 | Play status indicator |
| `status_pause` | 10,48,12,12 | Pause status indicator |
| `status_stop` | 10,48,12,12 | Stop status indicator |
| `spectrum_area` | 24,44,60,20 | Mini spectrum analyzer |

## Seek Bar

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `seek_track` | 10,36,255,6 | normal | Seek bar track |
| `seek_fill` | 10,36,*,6 | normal | Filled portion |
| `seek_thumb` | *,34,10,10 | normal, pressed | Seek position thumb |

**Color:** Set `seek_fill.color` in `elements` to control the fill and thumb color. Falls back to `palette.primary`.

```json
"elements": {
    "seek_fill": { "color": "#00ffcc" }
}
```

## Transport Buttons

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `btn_prev` | 10,8,23,20 | normal, pressed, disabled | Previous track |
| `btn_play` | 33,8,23,20 | normal, pressed, disabled | Play |
| `btn_pause` | 56,8,23,20 | normal, pressed, disabled | Pause |
| `btn_stop` | 79,8,23,20 | normal, pressed, disabled | Stop |
| `btn_next` | 102,8,23,20 | normal, pressed, disabled | Next track |
| `btn_eject` | 125,8,23,20 | normal, pressed | Open file |

**Color:** Use `play_controls` in `elements` to set one color for all transport button icons. Per-button entries (e.g. `btn_play`) take precedence over `play_controls`. Both fall back to `palette.primary`.

```json
"elements": {
    "play_controls": { "color": "#00ffcc" },
    "btn_eject":     { "color": "#ff00aa" }
}
```

## Toggle Buttons

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `btn_shuffle` | 154,8,40,20 | off, on, off_pressed, on_pressed | Shuffle toggle |
| `btn_repeat` | 196,8,40,20 | off, on, off_pressed, on_pressed | Repeat toggle |
| `btn_eq` | 154,8,23,12 | off, on, off_pressed, on_pressed | EQ window toggle |
| `btn_playlist` | 178,8,23,12 | off, on, off_pressed, on_pressed | Playlist toggle |

**Color:** Use `minicontrol_buttons` in `elements` to control the ON state color for all main window toggle buttons. Falls back to `palette.accent`.

```json
"elements": {
    "minicontrol_buttons": { "color": "#ff00aa" }
}
```

## Volume

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `volume_track` | 240,8,28,6 | normal | Volume bar track |
| `volume_fill` | 240,8,*,6 | normal | Filled portion |
| `volume_thumb` | *,6,8,10 | normal, pressed | Volume thumb |

**Color:** Set `volume_fill.color` in `elements` to control the fill and thumb color independently from the seek bar. Falls back to `seek_fill.color`, then `palette.primary`.

```json
"elements": {
    "seek_fill":   { "color": "#00ffcc" },
    "volume_fill": { "color": "#ff00aa" }
}
```

## Spectrum Window Chrome

Per-window chrome elements (fall back to shared elements if missing):

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `spectrum_titlebar` | 0,102,275,14 | normal | Spectrum window title bar |
| `spectrum_btn_close` | 261,104,10,10 | normal, pressed | Spectrum close button |

## Playlist Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `playlist_titlebar` | 0,102,275,14 | normal | Playlist window title bar |
| `playlist_btn_close` | 261,104,10,10 | normal, pressed | Playlist close button |
| `playlist_btn_shade` | 249,104,10,10 | normal, pressed | Playlist shade button |

The modern playlist has no bottom bar -- all operations via context menu and keyboard shortcuts. Currently playing track rendered in `accent` color.

**Track text colors:**
- Current track: `palette.accent`
- Selected track: `palette.text`
- Normal track: `playlist_text` element (fallback `palette.textDim`)

```json
"elements": {
    "playlist_text": { "color": "#00ffcc" }
}
```

**Library Browser Tabs:** Use `tab_text` (active label color, fallback `palette.accent`) and `tab_outline` (active border + glow color, fallback `palette.accent`) in `elements`.

```json
"elements": {
    "tab_text":    { "color": "#00ffcc" },
    "tab_outline": { "color": "#00ffcc" }
}
```

## EQ Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `eq_titlebar` | 0,102,275,14 | normal | EQ window title bar |
| `eq_btn_close` | 261,104,10,10 | normal, pressed | EQ close button |
| `eq_btn_shade` | 249,104,10,10 | normal, pressed | EQ shade button |

The modern EQ window renders a 10-band graphic equalizer with preamp, ON/OFF toggle, AUTO toggle, and PRESETS menu. Sliders use color-coded fill: green (-12dB) through yellow (0dB) to red (+12dB).

## ProjectM Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `projectm_titlebar` | 0,102,275,14 | normal | ProjectM window title bar |
| `projectm_btn_close` | 256,104,10,10 | normal, pressed | ProjectM close button |

Embeds the same `VisualizationGLView` (OpenGL) used by classic version. Supports full multi-edge resizing and custom fullscreen.

## Library Browser Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `library_titlebar` | 0,102,275,14 | normal | Library browser title bar |
| `library_btn_close` | 256,104,10,10 | normal, pressed | Library close button |
| `library_btn_shade` | 244,104,10,10 | normal, pressed | Library shade button |

Provides multi-source browsing (Local/Plex/Subsonic/Radio) with multiple browse modes. Supports multi-edge resizing.

## Element Image Fallback Chain

When the renderer looks up an image:

1. `{window}_{element}_{state}.png` (e.g., `spectrum_btn_close_pressed.png`)
2. `{window}_{element}.png` (e.g., `spectrum_btn_close.png`)
3. `{element}_{state}.png` (e.g., `btn_close_pressed.png`)
4. `{element}.png` (e.g., `btn_close.png`)
5. Programmatic fallback using palette colors
