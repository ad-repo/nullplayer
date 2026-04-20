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
| `titlebar` | 0,98,275,18 | normal | Title bar background |
| `titlebar_text` | 50,98,175,18 | normal | Title text area |
| `btn_close` | 261,102,10,10 | normal, pressed | Close button |
| `btn_minimize` | 237,102,10,10 | normal, pressed | Minimize button |
| `btn_shade` | 249,102,10,10 | normal, pressed | Shade mode button |

## Time Display

| Element ID | Default Rect | Description |
|-----------|-------------|-------------|
| `time_display` | 14,64,76,26 | Time display area |
| `time_digit_0` through `time_digit_9` | 12x20 each | 7-segment LED digits |
| `time_colon` | 5x20 | Colon separator |
| `time_minus` | 12x20 | Minus sign (remaining time) |

## Info Panel

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `marquee_bg` | 93,60,176,34 | normal | Marquee background panel |
| `info_bitrate` | 95,62,40,9 | normal | Bitrate label |
| `info_samplerate` | 135,62,30,9 | normal | Sample rate label |
| `info_bpm` | 165,62,30,9 | normal | BPM label |
| `info_stereo` | 198,62,32,9 | off, on | Stereo indicator |
| `info_mono` | 198,62,32,9 | off, on | Mono indicator |
| `info_cast` | 230,62,34,9 | off, on | Cast active indicator |

## Status & Spectrum

| Element ID | Default Rect | Description |
|-----------|-------------|-------------|
| `status_play` | 6,72,8,10 | Play status indicator |
| `status_pause` | 6,72,8,10 | Pause status indicator |
| `status_stop` | 6,72,8,10 | Stop status indicator |
| `spectrum_area` | 6,39,84,18 | Mini spectrum analyzer |

## Seek Bar

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `seek_track` | 6,32,263,3 | normal | Seek bar track |
| `seek_fill` | 6,32,*,3 | normal | Filled portion |
| `seek_thumb` | *,30,6,6 | normal, pressed | Seek position thumb |

**Color:** Set `seek_fill.color` in `elements` to control the fill and thumb color. Falls back to `palette.primary`.

```json
"elements": {
    "seek_fill": { "color": "#00ffcc" }
}
```

## Transport Buttons

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `btn_prev` | 6,3,28,24 | normal, pressed, disabled | Previous track |
| `btn_play` | 34,3,28,24 | normal, pressed, disabled | Play |
| `btn_pause` | 62,3,28,24 | normal, pressed, disabled | Pause |
| `btn_stop` | 90,3,28,24 | normal, pressed, disabled | Stop |
| `btn_next` | 118,3,28,24 | normal, pressed, disabled | Next track |

**Color:** Use `play_controls` in `elements` to set one color for all transport button icons. Per-button entries (e.g. `btn_play`) take precedence over `play_controls`. Both fall back to `palette.primary`.

```json
"elements": {
    "play_controls": { "color": "#00ffcc" },
    "btn_play":      { "color": "#ff00aa" }
}
```

## Window Toggle Buttons

These buttons appear between the seek bar and transport row, toggling window visibility.

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `btn_2x` | 140,42,20,14 | off, on, off_pressed, on_pressed | Large UI (1.5x) toggle |
| `btn_eq` | 152,42,20,14 | off, on, off_pressed, on_pressed | EQ window toggle |
| `btn_playlist` | 174,42,20,14 | off, on, off_pressed, on_pressed | Playlist window toggle |
| `btn_library` | 196,42,20,14 | off, on, off_pressed, on_pressed | Library browser toggle |
| `btn_projectm` | 218,42,22,14 | off, on, off_pressed, on_pressed | ProjectM window toggle |
| `btn_spectrum` | 242,42,22,14 | off, on, off_pressed, on_pressed | Spectrum window toggle |

**Color:** Use `minicontrol_buttons` in `elements` to control the ON state color for all main window toggle buttons. Falls back to `palette.accent`.

```json
"elements": {
    "minicontrol_buttons": { "color": "#ff00aa" }
}
```

## Volume

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `volume_track` | 157,12,107,3 | normal | Volume bar track |
| `volume_fill` | 157,12,*,3 | normal | Filled portion |
| `volume_thumb` | *,10,6,6 | normal, pressed | Volume thumb |

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
| `spectrum_titlebar` | 0,98,275,18 | normal | Spectrum window title bar |
| `spectrum_btn_close` | 261,102,10,10 | normal, pressed | Spectrum close button |

## Playlist Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `playlist_titlebar` | 0,98,275,18 | normal | Playlist window title bar |
| `playlist_btn_close` | 261,102,10,10 | normal, pressed | Playlist close button |
| `playlist_btn_shade` | 249,102,10,10 | normal, pressed | Playlist shade button |

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
| `eq_titlebar` | 0,98,275,18 | normal | EQ window title bar |
| `eq_btn_close` | 261,102,10,10 | normal, pressed | EQ close button |
| `eq_btn_shade` | 249,102,10,10 | normal, pressed | EQ shade button |

The modern EQ window renders a 21-band graphic equalizer with an integrated `PRE` control, ON/OFF toggle, AUTO toggle, and compact preset buttons (`FLAT`, `ROCK`, `POP`, `ELEC`, `HIP`, `JAZZ`, `CLSC`). The old dedicated preamp slider lane is gone; the `PRE` control now lives in the graph strip. Sliders still use color-coded fill from green (-12dB) through yellow (0dB) to red (+12dB), and the graph background now uses slim per-band mini tracks so it visually matches the fader lanes.

## ProjectM Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `projectm_titlebar` | 0,98,275,18 | normal | ProjectM window title bar |
| `projectm_btn_close` | 256,102,10,10 | normal, pressed | ProjectM close button |

Embeds the same `VisualizationGLView` (OpenGL) used by classic version. Supports full multi-edge resizing and custom fullscreen.

## Library Browser Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `library_titlebar` | 0,98,275,18 | normal | Library browser title bar |
| `library_btn_close` | 256,102,10,10 | normal, pressed | Library close button |
| `library_btn_shade` | 244,102,10,10 | normal, pressed | Library shade button |

Provides multi-source browsing (Local/Plex/Subsonic/Radio) with multiple browse modes. Supports multi-edge resizing.

## Waveform Window Chrome

| Element ID | Default Rect | States | Description |
|-----------|-------------|--------|-------------|
| `waveform_titlebar` | 0,98,275,18 | normal | Waveform window title bar |
| `waveform_btn_close` | 261,102,10,10 | normal, pressed | Waveform close button |

## Element Image Fallback Chain

When the renderer looks up an image:

1. `{window}_{element}_{state}.png` (e.g., `spectrum_btn_close_pressed.png`)
2. `{window}_{element}.png` (e.g., `spectrum_btn_close.png`)
3. `{element}_{state}.png` (e.g., `btn_close_pressed.png`)
4. `{element}.png` (e.g., `btn_close.png`)
5. Programmatic fallback using palette colors
