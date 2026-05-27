---
name: spectrum-analyzer-window
description: The dedicated Metal-based spectrum analyzer window — 84-bar mode list, window geometry, docking behavior, the cropped analyzer curve used by Classic/Enhanced/Ultra, vis_classic exact mode and its waveform demand. Use when modifying the spectrum window chrome, mode list, controls, or analyzer curve.
---

# Spectrum Analyzer Window

Dedicated Metal-based spectrum analyzer providing larger, more detailed view than the main window's 19-bar analyzer. Two implementations (classic/modern UI modes) both embed `SpectrumAnalyzerView`. For per-mode shader internals see [gpu-vis-modes](../gpu-vis-modes/SKILL.md).

## Accessing

- **Click** the spectrum analyzer display in the main window
- Context Menu → Spectrum Analyzer
- Window menu → Spectrum Analyzer

## Features

- **Bar Count**: 84 bars (vs 19 in main window)
- **Rendering**: Metal GPU shaders at 60Hz
- **Window Geometry**: default 275×116 at 1×; supports horizontal + vertical stretching with skin minimum size constraints
- **Color Source**: skin's `viscolor.txt` (24-color palette)

## Docking

Participates in the docking system with Main, EQ, and Playlist:
- Docks and moves with the window group
- Opens below the current vertical stack
- State saved with "Remember State on Quit"

## Quality Modes

| Mode | Description |
|------|-------------|
| **Classic** | Low-fi stepped bars from the skin palette with chunky peak caps, hard LED bands, and the shared cropped analyzer sub curve (default) |
| **Enhanced** | Compact professional LED analyzer with cropped logarithmic frequency mapping, controlled low-bass shaping, clean peak caps, short release trails |
| **Ultra** | Dense professional analyzer with cropped logarithmic frequency mapping, controlled low-bass shaping, fast decay, clean peak caps |
| **Fire** | GPU fire simulation with audio-reactive flame tongues (4 color styles) |
| **JWST** | Deep space flythrough with 3D star field, JWST diffraction flares |
| **Lightning** | GPU lightning storm with fractal bolts mapped to spectrum peaks (8 color schemes) |
| **Matrix** | Falling digital rain with procedural glyphs (5 color schemes, 2 intensity presets) |
| **Snow** | Layered procedural snowfall with spectrum-shaped density, gusting drift, soft atmospheric haze |
| **EKG** | Beat-synced ECG monitor with phosphor trace, medical grid, scan glow, BPM-driven QRS pulses, PCM-driven peak height |
| **vis_classic** | Exact-port vis_classic analyzer core with profile-compatible INI behavior |

## Switching Modes

- **Double-click** the spectrum window to cycle through modes
- **Right-click** → Mode to select specific mode
- **Left/Right arrows**: cycle flame/lightning/matrix styles (or prev/next profile in `vis_classic`)
- **[ / ]**: previous/next profile in `vis_classic`

## Spectrum Analyzer Curve

Classic, Enhanced, and Ultra avoid spending visible columns on the deepest sub range because these modes don't render frequency labels. `SpectrumAnalyzerView` maps the visible analyzer width over a cropped logarithmic source range starting at 48 Hz, then applies controlled low-bass tapers that begin around 42 Hz before the values reach the mode-specific renderers.

- **Classic** keeps its low-fi identity after the shared curve: 19/84 stepped bars, hard palette bands, quantized heights, chunky peak caps
- **Enhanced** uses the same standard cropped curve as Classic, with smoother LED release trails and clean peak caps
- **Ultra** uses the same analyzer strategy at a denser bar count, with slightly faster decay and air lift for the larger spectrum window

## vis_classic Exact Mode and Waveform Demand

`vis_classic` exact mode consumes the shared 576-sample waveform notification stream (`.audioWaveform576DataUpdated`), not just generic spectrum data.

- `SpectrumAnalyzerView` registers a waveform consumer only while `qualityMode == .visClassicExact`
- The registration is tied to active rendering, so hidden/occluded analyzers do not keep the waveform side path alive
- This is separate from `spectrumConsumers` — do NOT merge the two demand signals when refactoring

For full vis_classic details (profile menus, persistence, keyboard controls, INI import/export) see [vis-classic-guide](../vis-classic-guide/SKILL.md).

## Responsiveness Modes

Bar fall speed:

| Mode | Retention | Feel |
|------|-----------|------|
| Instant | 0% | No smoothing |
| Snappy | 25% | Fast and punchy (default) |
| Balanced | 40% | Middle ground |
| Smooth | 55% | Original Winamp feel |

## Key Files

- `Windows/Spectrum/SpectrumWindowController.swift` — window controller (classic)
- `Windows/Spectrum/SpectrumView.swift` — container with classic chrome
- `Windows/ModernSpectrum/ModernSpectrumWindowController.swift` — window controller (modern)
- `Windows/ModernSpectrum/ModernSpectrumView.swift` — container with modern chrome
- `Visualization/SpectrumAnalyzerView.swift` — Metal rendering + vis_classic frame upload (shared)
- `Visualization/VisClassicBridge.swift` — Swift bridge to C vis_classic core
- `Sources/CVisClassicCore/` — portable C/C++ vis_classic core + C API
- `App/SpectrumWindowProviding.swift` — protocol abstracting classic/modern
