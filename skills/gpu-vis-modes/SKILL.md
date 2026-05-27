---
name: gpu-vis-modes
description: Per-mode shader and algorithm internals for the GPU visualization modes shared by both the main window and spectrum window — Fire, JWST, Lightning, Matrix, Snow, EKG. Includes Metal pass counts, audio mappings, color schemes, intensity presets, and the shader file names. Use when editing a specific mode's shader or audio response.
---

# GPU Visualization Modes

Internals of the shader modes shared between [main-window-visualization](../main-window-visualization/SKILL.md) and [spectrum-analyzer-window](../spectrum-analyzer-window/SKILL.md). See [metal-gotchas](../metal-gotchas/SKILL.md) for cross-cutting Metal pitfalls.

## Fire Mode

**Flame Styles**: Inferno (orange/red), Aurora (green/cyan/purple), Electric (blue/white/purple), Ocean (deep blue/teal/white)

**Fire Intensity**:
- **Mellow** — gentle ambient flame, smooth transitions
- **Intense** — punchy beat-reactive flame, sharp spikes

**Audio Reactivity**:
- Bass (bands 0–15) — heat injection intensity
- Mids (bands 16–49) — flame sway and motion
- Treble (bands 50–74) — ember sparks

**Technical**: 128×96 simulation grid with per-column propagation. Two-pass separable Gaussian blur (11H + 11V = 22 samples/pixel vs 121 for a single-pass 11×11). **3 Metal passes**:
1. compute `propagate_fire` (128×96 grid)
2. render `flame_blur_h` (horizontal blur, fire grid → r16Float intermediate texture at drawable size)
3. render `flame_blur_v` (vertical blur + color mapping → drawable)

The `flameBlurTexture` intermediate is lazily created/resized when drawable size changes (`flameBlurLastDrawableSize`). `isPipelineAvailable(.flame)` requires all three pipelines. 60 FPS.

Shader file: `Visualization/FlameShaders.metal`

## JWST Mode

Deep space flythrough inspired by James Webb Space Telescope.

**Visual Elements**:
- 3D perspective star field with 5 depth layers and radial streaking
- JWST 6-axis diffraction flares with authentic spike pattern and chromatic fringing
- Rare, richly colored galaxies/nebula patches
- Giant flare events on major peaks (screen-filling, 5.5s decay)
- JWST color palette: 10-stop gradient (navy → indigo → violet → cream → white)
- Gossamer nebula wisps (transparent gas layers with vertical stretch)

**Audio Reactivity**:
- Music intensity drives flight speed
- Flare frequency tied to overall dB level
- Flare position aligned to frequency peaks
- Giant flare on strong bass peaks (6s cooldown)
- Stars twinkle with treble energy

**Technical**: Single render pass with procedural FBM noise, parametric JWST flare function, filmic tone mapping. 60 FPS.

Shader file: `Visualization/CosmicShaders.metal`

## Lightning Mode

GPU lightning storm with fractal bolts mapped to spectrum peaks. 8 color schemes selectable via Left/Right arrows in the spectrum window.

Shader file: `Visualization/ElectricityShaders.metal`

## Matrix Mode

Iconic falling digital rain from The Matrix.

**Color Schemes**:
- **Classic** — white head, bright green trail, dark green fade
- **Amber** — warm white head, amber/orange trail, dark brown fade
- **Blue Pill** — white head, cyan/electric blue trail, navy fade
- **Bloodshot** — pink-white head, crimson trail, dark maroon fade
- **Neon** — magenta-white head, hot magenta trail, purple fade

**Intensity**:
- **Subtle** — sparse rain, gentle glow, zen-like ambient
- **Intense** — dense rain, strong glow, punchy beat reactions

**Visual Elements**:
- 75 columns mapping to spectrum bands
- Procedural glyph patterns (katakana-inspired)
- Spectrum-driven column speed, brightness, trail length
- Phosphor glow + CRT scanlines
- Reflection pool at bottom 18%
- Beat pulse (bass hits flash white)
- Dramatic awakening (sweep-down on major peaks)

**Technical**: Single render pass with hash-based segment patterns, multi-stream rain simulation. Phosphor glow samples 8 neighbors (glowRange capped to 1 for both Subtle and Intense). 60 FPS.

Shader file: `Visualization/MatrixShaders.metal`

## Snow Mode

Layered procedural snowfall with spectrum-shaped density, gusting drift, and soft atmospheric haze. Bass-driven wind gusts; flurry-to-blizzard intensity range.

Shader file: `Visualization/SnowShaders.metal`

## EKG Mode

Realistic electrocardiogram monitor visualization.

**Visual Elements**:
- Procedural P-QRS-T ECG waveform with smooth antialiasing
- Medical monitor grid with fine and major subdivisions
- Green phosphor trace, glow, scan head, scanlines, vignette, analog monitor noise
- QRS timing pulses from the BPM clock
- R-peaks placed on a fixed seconds-wide monitor timebase, so faster BPM = closer peak spacing
- Peak height follows smoothed raw PCM amplitude (no frequency energy used)
- Persistent ping-pong trace texture preserves already-drawn history; only the scan-head region is redrawn
- Larger vertical scale and lower baseline use more of the monitor area
- Selectable styles: Clinical, Cyan, Amber, Neon, Crimson, Ice
- Subtle per-beat procedural variance keeps the trace alive without fighting amplitude response

**Audio Reactivity**:
- Detected BPM drives the cardiac clock when available, folded into a 40–100 BPM display range
- Fast tempos are halved until they fit; unusually slow readings are doubled
- Smoothed raw PCM amplitude controls QRS/R-peak height
- **No spectrum or frequency-band energy is sampled in this mode**
- Defaults to 80 BPM when no confident BPM has been detected yet
- EKG Style appears in the spectrum window context menu and the main-window Visuals menu when EKG is active

**Technical**: Two-pass Metal path:
1. update pass — scrolls/preserves the persistent trace texture and draws only the scan-head band
2. composite pass — renders the monitor grid, glow, and stored trace

Uses `.bpmUpdated` notifications for timing and `.audioPCMDataUpdated` for raw-amplitude scaling. 60 FPS.

Shader file: `Visualization/EKGShaders.metal`

## Classic / Enhanced / Ultra (analyzer modes)

Cropped logarithmic source range starting at 48 Hz with low-bass tapers from ~42 Hz. See [spectrum-analyzer-window](../spectrum-analyzer-window/SKILL.md) for the analyzer curve details.

Shader file: `Visualization/SpectrumShaders.metal`
