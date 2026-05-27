---
name: album-art-visualizer
description: The Library Browser ART-mode visualizer — 30 Core Image GPU effects that transform album artwork based on audio. Use when adding/editing visualizer effects, intensity, keyboard shortcuts, or the ART-mode lifecycle.
---

# Album Art Visualizer

GPU-accelerated effects that transform album artwork based on audio.

## Accessing

1. Open **Library Browser** window
2. Switch to **ART** mode (click ART tab)
3. Visualizer activates automatically when music plays
4. Right-click for visualizer context menu

## Effects (30 Total)

All effects use Core Image filters for GPU acceleration and respond to audio levels (bass/mid/treble).

### Rotation & Scaling
Psychedelic, Kaleidoscope, Vortex, Spin, Fractal, Tunnel

### Distortion
Melt, Wave, Glitch, RGB Split, Twist, Fisheye, Shatter, Stretch

### Motion
Zoom, Shake, Bounce, Feedback, Strobe, Jitter

### Copies & Mirrors
Mirror, Tile, Prism, Double Vision, Flipbook, Mosaic

### Pixel Effects
Pixelate, Scanlines, Datamosh, Blocky

## Controls

**Keyboard:**
- **Click** / **← →** — Previous/Next effect
- **↑ ↓** — Decrease/Increase intensity
- **R** — Toggle Random mode (changes effect on beat hits)
- **C** — Toggle Cycle mode (advances at intervals)
- **F** — Toggle Fullscreen
- **Escape** — Exit fullscreen / Turn off visualizer

**Context Menu:**
- Next/Previous Effect
- Random Mode, Auto-Cycle Mode, Cycle Interval (5s/10s/20s/30s)
- All Effects submenu
- Intensity (Low/Medium/Normal/High/Extreme)
- Fullscreen / Turn Off

## Technical

- **Rendering**: Core Image filters with Metal GPU
- **Frame Rate**: 60 FPS animation timer
- **Audio Reactivity**: spectrum bands (bass/mid/treble)
- **Auto-Stop**: effects pause after ~0.5s of silence
- **Intensity Range**: 0.5×–2.0× effect strength

## Key Files

- `Visualization/AudioReactiveUniforms.swift` — audio data struct for shaders
- `Visualization/ShaderManager.swift` — Metal pipeline management
- `Visualization/ArtworkVisualizerView.swift` — MTKView rendering
- `Windows/ArtVisualizer/ArtVisualizerWindowController.swift` — window controller
- `Windows/ArtVisualizer/ArtVisualizerContainerView.swift` — window chrome

## Troubleshooting

**Effects not showing**: ensure ART mode in Library Browser; music playing; try clicking to cycle.

**Performance**: lower intensity; some effects (Feedback) are more demanding.
