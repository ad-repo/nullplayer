---
name: main-window-visualization
description: The main window's built-in 76×16 (Winamp coordinates) visualization area — eleven display modes, mode switching, persistence, per-mode settings, and the embedded SpectrumAnalyzerView lifecycle. Use when modifying the in-skin visualizer area or its menu.
---

# Main Window Visualization

The main window's built-in visualization area (76×16 pixels in Winamp coordinates) supports eleven display modes. For per-mode shader/algorithm internals see [gpu-vis-modes](../gpu-vis-modes/SKILL.md).

## Modes

| Mode | Description |
|------|-------------|
| **Off** | No main-window visualization; leaves the skin's prepared display artwork visible |
| **Classic** | Low-fi 19-bar spectrum analyzer with skin colors and cropped analyzer sub curve (default; persisted internally as `Spectrum`) |
| **Enhanced** | Compact professional LED analyzer with cropped sub range, clean peak caps, and restrained meter colors |
| **Ultra** | Dense professional spectrum analyzer with cropped sub range, fast decay, clean peak caps, and restrained meter colors |
| **Fire** | GPU flame simulation using Metal compute shaders |
| **JWST** | Deep space flythrough with 3D star field and JWST diffraction flares |
| **Lightning** | GPU lightning storm with fractal bolts mapped to spectrum peaks |
| **Matrix** | Falling digital rain with procedural glyphs mapped to spectrum bands |
| **Snow** | Audio-reactive snowfall with flurry-to-blizzard intensity and bass-driven wind gusts |
| **EKG** | Oscilloscope-style ECG monitor; each detected audio peak fires one QRS, height scales with peak prominence (no BPM clock) |
| **vis_classic** | Exact-port vis_classic analyzer core with profile-compatible rendering (see [vis-classic-guide](../vis-classic-guide/SKILL.md)) |

## Switching Modes

- **Double-click** the visualization area to cycle through modes
- **Right-click** → Spectrum Analyzer → Main Window → Mode to select a specific mode, including **Off**
- Persisted as `mainWindowVisMode` (UserDefaults)

## Settings

All non-`vis_classic` GPU modes share:
- **Responsiveness** — bar decay (Instant/Snappy/Balanced/Smooth) — `mainWindowDecayMode`
- **Normalization** — level scaling (Accurate/Adaptive/Dynamic) — `mainWindowNormalizationMode`

Mode-specific:
- **Fire** — Flame Style + Fire Intensity — `mainWindowFlameStyle`, `mainWindowFlameIntensity`
- **Lightning** — Lightning Style — `mainWindowLightningStyle`
- **Matrix** — Matrix Color + Matrix Intensity — `mainWindowMatrixColorScheme`, `mainWindowMatrixIntensity`
- **vis_classic** — Profile + Fit to Width (window-scoped UserDefaults keys; see vis-classic-guide)

## Implementation

- **Overlay**: `SpectrumAnalyzerView` with `isEmbedded = true` as a subview of the main window
- **vis_classic core**: CPU frame generation via `VisClassicBridge` + `CVisClassicCore`, uploaded to a Metal texture
- **Positioning**: Winamp coordinates → macOS view coordinates
- **Lifecycle**: Created lazily on first GPU mode activation
- **CPU efficiency**: Display link pauses when window is minimized/occluded, in Spectrum mode, or in Off mode
- **vis_classic state is window-scoped** — main window and spectrum window keep independent profile/fit/transparent-bg. Use `VisClassicBridge.PreferenceScope` and `*.mainWindow` keys

## Key Files

- `Windows/MainWindow/MainWindowView.swift` — mode switching, overlay (classic UI)
- `Windows/ModernMainWindow/ModernMainWindowView.swift` — mode switching, overlay (modern UI)
- `Visualization/SpectrumAnalyzerView.swift` — shared Metal rendering
