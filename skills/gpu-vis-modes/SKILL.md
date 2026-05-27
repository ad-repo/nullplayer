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

Oscilloscope-style electrocardiogram monitor — pure peak-driven, no BPM or tempo clock.

**Visual Elements**:
- Procedural P-QRS-T ECG waveform with smooth antialiasing
- Medical monitor grid with fine and major subdivisions
- Phosphor trace, glow, scan head, scanlines, vignette, analog monitor noise
- Each detected audio peak fires one QRS complex at the scan head; flat baseline between peaks
- Per-beat amplitude (the prominence of the detected peak) drives that specific QRS's height — quiet peaks read as small blips, loud peaks tower
- Persistent ping-pong trace texture preserves already-drawn history; only the scan-head region is redrawn
- Wide vertical clamp `[0.020, 0.980]` plus loudness range `mix(0.08, 3.40, sqrt(amp))` gives oscilloscope-like headroom
- Selectable styles: Clinical, Cyan, Amber, Neon, Crimson, Ice

**Audio Reactivity**:
- Pure peak detector driven directly from `.audioPCMDataUpdated`. **Does not use BPM, aubio tempo, or spectrum energy.**
- Detection runs on *raw RMS* per PCM frame (NOT the perceptual `level` formula, which saturates at 1.0 on compressed audio and would pin the input flat)
- State machine: tracks rising peak and running valley between bumps. On a rising-to-falling transition, fires a beat with `amplitude = (peak − valley) × 2.5` clamped to `[0,1]`
- Peak-prominence gate (`> 0.004`) replaces ratio-vs-envelope gating — works at any volume including brick-walled material where absolute peak is pinned at 1.0
- 50 ms refractory (~20 Hz max trigger rate); shared 8-slot ring buffer of `(timestamp, amplitude)` feeds the shader
- Shader sums QRS gaussians around stored beat timestamps; scan-head glow / noise modulation tracks the perceptual `level` for separate scan-head pulse feel
- EKG Style appears in the spectrum window context menu and the main-window Visuals menu when EKG is active

**Technical**: Two-pass Metal path:
1. update pass — scrolls/preserves the persistent trace texture and draws only the scan-head band
2. composite pass — renders the monitor grid, glow, and stored trace

`EKGParams` packs up to 8 beat timestamps (`beatTimes[2]` float4 array) and matching amplitudes (`beatAmps[2]`). Unused slots use sentinel `-1000`. Shared static ring buffer in `SpectrumAnalyzerView` (`ekgBeatTimeRing` / `ekgBeatAmpRing`) is written from the audio tap thread via `ekgRecordBeat` under `ekgBeatRingLock`. Embedded main-window EKG rendering quantizes persistent trace scroll to whole drawable pixels with a fractional carry accumulator, avoiding blur from repeatedly sampling the history texture at subpixel offsets in the 76×16 skin display. The standalone spectrum window keeps fractional scroll because its larger drawable does not show the same softness. 60 FPS.

Shader file: `Visualization/EKGShaders.metal`

## Classic / Enhanced / Ultra (analyzer modes)

Cropped logarithmic source range starting at 48 Hz with low-bass tapers from ~42 Hz. See [spectrum-analyzer-window](../spectrum-analyzer-window/SKILL.md) for the analyzer curve details.

Shader file: `Visualization/SpectrumShaders.metal`
