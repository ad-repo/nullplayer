---
name: visualizations
description: Album art visualizer, ProjectM/MilkDrop integration, spectrum analyzer window modes, and main window visualization modes. Use when working on visualization features, ProjectM integration, Metal shaders, or audio-reactive effects.
---

# NullPlayer Visualization Systems

NullPlayer features multiple visualization systems for audio-reactive visual effects.

Related but separate from the visualization stack is the standalone waveform window. It reuses the audio system's waveform notifications and cache service, but it is not a Metal visualization mode and should not be documented or implemented as one.

## Main Window Visualization

The main window's built-in visualization area (76x16 pixels in Winamp coordinates) supports nine rendering modes.

### Modes

| Mode | Description |
|------|-------------|
| **Spectrum** | Classic 19-bar spectrum analyzer drawn with skin colors via CGContext (default) |
| **vis_classic** | Exact-port vis_classic analyzer core with profile-compatible rendering |
| **Fire** | GPU flame simulation using Metal compute shaders |
| **Enhanced** | LED matrix with rainbow gradient, gravity-bouncing peaks, amber fade trails |
| **Ultra** | Maximum fidelity seamless gradient with smooth decay, physics-based peaks, reflections |
| **JWST** | Deep space flythrough with 3D star field and JWST diffraction flares |
| **Lightning** | GPU lightning storm with fractal bolts mapped to spectrum peaks |
| **Matrix** | Falling digital rain with procedural glyphs mapped to spectrum bands |
| **Snow** | Audio-reactive snowfall with flurry-to-blizzard intensity and bass-driven wind gusts |

### Switching Modes

- **Double-click** the visualization area to cycle through modes
- **Right-click** → Spectrum Analyzer → Main Window → Mode to select specific mode
- Setting persisted: `mainWindowVisMode` (UserDefaults)

### Settings

All non-`vis_classic` GPU modes share:
- **Responsiveness**: Bar decay speed (Instant/Snappy/Balanced/Smooth) — `mainWindowDecayMode`
- **Normalization**: Level scaling (Accurate/Adaptive/Dynamic) — `mainWindowNormalizationMode`

Mode-specific:
- **Fire**: Flame Style + Fire Intensity — `mainWindowFlameStyle`, `mainWindowFlameIntensity`
- **Lightning**: Lightning Style — `mainWindowLightningStyle`
- **Matrix**: Matrix Color + Matrix Intensity — `mainWindowMatrixColorScheme`, `mainWindowMatrixIntensity`
- **vis_classic**: Profile selection + Fit to Width — window-scoped UserDefaults keys

### Technical Details

- **Implementation**: Metal overlay (`SpectrumAnalyzerView` with `isEmbedded = true`) as subview
- **vis_classic Core**: CPU frame generation via `VisClassicBridge` + `CVisClassicCore`, uploaded to a Metal texture
- **Positioning**: Converted from Winamp coordinates to macOS view coordinates
- **Lifecycle**: Created lazily on first GPU mode activation
- **CPU Efficiency**: Display link pauses when window is minimized/occluded or in Spectrum mode

## Album Art Visualizer

GPU-accelerated effects that transform album artwork based on audio.

### Accessing

1. Open **Library Browser** window
2. Switch to **ART** mode (click ART tab)
3. Visualizer activates automatically when music plays
4. Right-click for visualizer context menu

### Effects (30 Total)

All effects use Core Image filters for GPU acceleration and respond to audio levels (bass/mid/treble).

#### Rotation & Scaling
- **Psychedelic**: Twirl distortion + hue rotation + bloom glow
- **Kaleidoscope**: Multi-segment kaleidoscope with rotating pattern
- **Vortex**: Swirling vortex distortion
- **Spin**: Continuous rotation with zoom blur trails
- **Fractal**: Zooming scale effect with rotation and bloom
- **Tunnel**: Hole distortion creating tunnel/portal effect

#### Distortion
- **Melt**: Glass distortion simulating melting effect
- **Wave**: Bump distortion moving across the image
- **Glitch**: RGB offset + posterization on bass hits
- **RGB Split**: Chromatic aberration
- **Twist**: Strong twirl distortion that follows the beat
- **Fisheye**, **Shatter**, **Stretch**: Various lens effects

#### Motion
- **Zoom**: Zoom blur pulsing with the bass
- **Shake**: Earthquake shake with motion blur
- **Bounce**: Squash and stretch bouncing animation
- **Feedback**: Multiple scaled/rotated copies with bloom
- **Strobe**: Exposure flashing synchronized to beat
- **Jitter**: Random position/scale jitter on beats

#### Copies & Mirrors
- **Mirror**: Four-fold reflected tile pattern
- **Tile**: Op-art style tiling with rotation
- **Prism**: Triangle kaleidoscope with decay
- **Double Vision**: Offset duplicate images
- **Flipbook**: Rapid flipping between orientations
- **Mosaic**: Hexagonal pixelation pattern

#### Pixel Effects
- **Pixelate**: Square pixelation responsive to audio
- **Scanlines**: CRT-style scanlines with bloom
- **Datamosh**: Edge detection + color shift effect
- **Blocky**: Large pixelation with vibrance boost

### Controls

**Keyboard Shortcuts:**
- **Click** / **← →**: Previous/Next effect
- **↑ ↓**: Decrease/Increase intensity
- **R**: Toggle Random mode
- **C**: Toggle Cycle mode
- **F**: Toggle Fullscreen
- **Escape**: Exit fullscreen / Turn off visualizer

**Context Menu:**
- Next/Previous Effect
- Random Mode (changes effect on beat hits)
- Auto-Cycle Mode (advances at intervals)
- Cycle Interval (5s, 10s, 20s, 30s)
- All Effects submenu
- Intensity (Low/Medium/Normal/High/Extreme)
- Fullscreen
- Turn Off

### Technical Details

- **Rendering**: Core Image filters with Metal GPU
- **Frame Rate**: 60 FPS animation timer
- **Audio Reactivity**: Reads spectrum data (bass/mid/treble bands)
- **Auto-Stop**: Effects pause after ~0.5s of silence
- **Intensity Range**: 0.5x to 2.0x effect strength

## ProjectM/MilkDrop Visualizer

Renders classic MilkDrop presets using OpenGL. Window has two implementations (classic/modern UI modes) both embedding `VisualizationGLView` for rendering.

### What is ProjectM/MilkDrop?

- **MilkDrop** was the iconic visualization plugin for Winamp
- **ProjectM** is the open-source reimplementation
- Presets are shader-based programs creating infinite visual variety

### Presets

NullPlayer includes bundled presets. Add custom presets to:
```
~/Library/Application Support/NullPlayer/Presets/
```

Place `.milk` files in this folder and use "Reload Presets" from context menu.

### Controls

**Keyboard Shortcuts:**
- **→ / ←**: Next/Previous preset
- **Shift+→ / Shift+←**: Hard cut (no blend)
- **R**: Random preset
- **Shift+R**: Random preset (hard cut)
- **L**: Lock/unlock preset
- **C**: Cycle through modes (Off → Auto-Cycle → Auto-Random)
- **F**: Toggle fullscreen
- **Escape**: Exit fullscreen

**Context Menu:**
- Current Preset (shows name and index)
- Next/Previous/Random Preset
- Lock Preset
- Manual Only / Auto-Cycle / Auto-Random modes
- Cycle Interval (5s, 10s, 20s, 30s, 60s, 2min)
- Presets submenu (all available presets)
- Audio Sensitivity (PCM gain: Low 0.5x, Normal 1.0x, High 1.5x, Intense 2.0x, Max 3.0x)
- Beat Sensitivity (Low 0.5, Normal 1.0, High 1.5, Max 2.0)
- Fullscreen

### Modes

| Mode | Behavior |
|------|----------|
| **Manual Only** | Presets only change via user input (default) |
| **Auto-Cycle** | Advances to next preset sequentially at interval |
| **Auto-Random** | Jumps to random preset at interval |

**Note**: Auto-switching modes disabled by default for stability. Some presets may glitch during transitions.

### Technical Details

- **Rendering**: OpenGL 4.1 Core Profile via NSOpenGLView
- **Frame Rate**: 60 FPS via CVDisplayLink
- **Audio Input**: PCM waveform data from AudioEngine
- **Beat Detection**: Built-in projectM beat sensitivity (adjustable)

### Audio Sensitivity (PCM Gain)

Controls amplitude of audio samples fed to visualization engine:

| Preset | Gain | Effect |
|--------|------|--------|
| **Low** | 0.5x | Subdued visuals |
| **Normal** | 1.0x | Unity gain (default) |
| **High** | 1.5x | More reactive |
| **Intense** | 2.0x | Very reactive |
| **Max** | 3.0x | Maximum reactivity |

Persisted: `projectMPCMGain` (UserDefaults)

### Beat Sensitivity

ProjectM uses two sensitivity levels:
- **Idle**: 0.2 when audio is quiet/stopped
- **Active**: User-configurable (default 1.0)

Persisted: `projectMBeatSensitivity` (UserDefaults)

## Spectrum Analyzer Window

A dedicated Metal-based spectrum analyzer providing larger, more detailed view than the main window's 19-bar analyzer. Window has two implementations (classic/modern UI modes) both embedding `SpectrumAnalyzerView`.

### Accessing

- **Click** the spectrum analyzer display in main window
- Context Menu → Spectrum Analyzer
- Window menu → Spectrum Analyzer

### Features

- **Bar Count**: 55 bars (vs 19 in main window)
- **Rendering**: Metal GPU shaders at 60Hz
- **Window Size**: 275x116 pixels (matches main window)
- **Color Source**: Skin's `viscolor.txt` (24-color palette)

### Docking

Participates in docking system with Main, EQ, and Playlist:
- Docks and moves with window group
- Opens below current vertical stack
- State saved with "Remember State on Quit"

### Quality Modes

| Mode | Description |
|------|-------------|
| **Winamp** | Discrete color bands from skin palette with floating peaks, 3D bar shading, LED gaps (default) |
| **vis_classic** | Exact-port vis_classic analyzer core with profile-compatible INI behavior |
| **Enhanced** | Rainbow LED matrix (55x16) with gravity-bouncing peaks, amber fade trails, rounded corners |
| **Ultra** | Maximum fidelity seamless gradient with smooth decay, physics-based bouncing peaks, reflection effect |
| **Fire** | GPU fire simulation with audio-reactive flame tongues (4 color styles) |
| **JWST** | Deep space flythrough with 3D star field, JWST diffraction flares |
| **Lightning** | GPU lightning storm with fractal bolts mapped to spectrum peaks (8 color schemes) |
| **Matrix** | Falling digital rain with procedural glyphs (5 color schemes, 2 intensity presets) |
| **Snow** | Layered procedural snowfall with spectrum-shaped density, gusting drift, and soft atmospheric haze |

### Switching Modes

- **Double-click** the spectrum window to cycle through modes
- **Right-click** → Mode to select specific mode
- **Left/Right arrows**: Cycle flame/lightning/matrix styles (or prev/next profile in `vis_classic`)
- **[ / ]**: Previous/next profile in `vis_classic`

### `vis_classic` Exact Mode and Waveform Demand

`vis_classic` exact mode consumes the shared 576-sample waveform notification stream (`.audioWaveform576DataUpdated`), not just generic spectrum data.

- `SpectrumAnalyzerView` registers a waveform consumer only while `qualityMode == .visClassicExact`
- The registration is tied to active rendering, so hidden/occluded analyzers do not keep the waveform side path alive
- This is separate from `spectrumConsumers`; do not merge the two demand signals when refactoring

### vis_classic Mode Details

Profile controls are available from both main window and spectrum window context menus when `vis_classic` is active.

- **Profiles submenu**: Load profile directly
- **Fit to Width**: Toggle bar mapping across full width
- **Transparent Background**: Toggle analyzer background alpha (window-scoped)
- **Next/Previous Profile**: Cycle through profile catalog
- **Import/Export INI**: Read and write profile files

Main window `vis_classic` keyboard controls:
- **,** previous profile
- **.** next profile

Spectrum window `vis_classic` keyboard controls:
- **Left/Right** previous/next profile
- **[ / ]** previous/next profile

Persistence is window-scoped (independent between main window and spectrum window):
- Profile keys: `visClassicLastProfileName.mainWindow`, `visClassicLastProfileName.spectrumWindow`
- Fit keys: `visClassicFitToWidth.mainWindow`, `visClassicFitToWidth.spectrumWindow`
- Transparent keys: `visClassicTransparentBg.mainWindow`, `visClassicTransparentBg.spectrumWindow`

### Flame Mode Details

**Flame Style Presets:**
- **Inferno**: Classic orange/red fire
- **Aurora**: Green/cyan/purple northern lights
- **Electric**: Blue/white/purple plasma
- **Ocean**: Deep blue/teal/white

**Fire Intensity:**
- **Mellow**: Gentle ambient flame, smooth transitions
- **Intense**: Punchy beat-reactive flame, sharp spikes

**Audio Reactivity:**
- Bass (bands 0-15): Controls heat injection intensity
- Mids (bands 16-49): Increases flame sway and motion
- Treble (bands 50-74): Adds ember sparks

**Technical**: 128x96 simulation grid with per-column propagation. Two-pass separable Gaussian blur (11H + 11V = 22 samples/pixel vs 121 for a single-pass 11×11). Three Metal passes: compute (propagation), render (horizontal blur → r16Float intermediate), render (vertical blur + color mapping → drawable). 60 FPS.

### JWST Mode Details

Deep space flythrough inspired by James Webb Space Telescope.

**Visual Elements:**
- **3D perspective star field**: 5 depth layers with radial streaking
- **JWST 6-axis diffraction flares**: Authentic spike pattern with chromatic fringing
- **Vivid celestial bodies**: Rare, richly colored galaxies/nebula patches
- **Giant flare events**: On major peaks, screen-filling diffraction flare (5.5s decay)
- **JWST color palette**: 10-stop gradient (navy → indigo → violet → cream → white)
- **Gossamer nebula wisps**: Transparent gas layers with vertical stretch

**Audio Reactivity:**
- Music intensity drives flight speed
- Flare frequency tied to overall dB level
- Flare position aligned to frequency peaks
- Giant flare on strong bass peaks (6s cooldown)
- Stars twinkle with treble energy

**Technical**: Single render pass with procedural FBM noise, parametric JWST flare function, filmic tone mapping. 60 FPS.

### Matrix Mode Details

Iconic falling digital rain from The Matrix.

**Matrix Color Schemes:**
- **Classic**: White head, bright green trail, dark green fade
- **Amber**: Warm white head, amber/orange trail, dark brown fade
- **Blue Pill**: White head, cyan/electric blue trail, navy fade
- **Bloodshot**: Pink-white head, crimson trail, dark maroon fade
- **Neon**: Magenta-white head, hot magenta trail, purple fade

**Matrix Intensity:**
- **Subtle**: Sparse rain, gentle glow, zen-like ambient
- **Intense**: Dense rain, strong glow, punchy beat reactions

**Visual Elements:**
- 75 columns mapping to spectrum bands
- Procedural glyph patterns (katakana-inspired)
- Spectrum-driven column speed, brightness, trail length
- Phosphor glow and CRT scanlines
- Reflection pool at bottom 18%
- Beat pulse (bass hits flash white)
- Dramatic awakening (sweep-down on major peaks)

**Technical**: Single render pass with hash-based segment patterns, multi-stream rain simulation. Phosphor glow samples 8 neighbors (glowRange capped to 1 for both Subtle and Intense). 60 FPS.

### Responsiveness Modes

Controls how quickly bars fall:

| Mode | Retention | Feel |
|------|-----------|------|
| Instant | 0% | No smoothing |
| Snappy | 25% | Fast and punchy (default) |
| Balanced | 40% | Middle ground |
| Smooth | 55% | Original Winamp feel |

## Comparison

| Feature | Album Art | ProjectM/MilkDrop | Spectrum Analyzer |
|---------|-----------|-------------------|-------------------|
| **Visual Style** | Transformed artwork | Procedural graphics | Frequency bars/vis_classic/Fire/JWST/Lightning/Matrix/Snow |
| **Effect Count** | 30 built-in | 100s of presets | 9 modes |
| **Customization** | Intensity adjustment | Full preset ecosystem | Mode + decay + style presets |
| **GPU Tech** | Core Image (Metal) | OpenGL shaders | Metal shaders + compute |
| **Audio Response** | Spectrum bands | PCM waveform + beats | 75-band spectrum / energy-driven |

### When to Use Each

**Album Art Visualizer:**
- When you want to see the album artwork
- More subtle, integrated experience
- When browsing your music library

**ProjectM/MilkDrop:**
- Full-screen immersive visualizations
- Classic Winamp nostalgia
- Parties and ambient displays
- Maximum visual variety

**Main Window Visualization:**
- Quick access to all GPU modes without separate window
- Double-click to cycle through modes
- Independent settings from Spectrum window

**Spectrum Analyzer Window:**
- Detailed frequency visualization (55 bars)
- Monitoring audio levels
- Classic Winamp spectrum aesthetic
- Larger display complements main window
- Fire/JWST/Lightning/Matrix modes for ambient visuals

## Key Files

### Album Art Visualizer
- `Visualization/AudioReactiveUniforms.swift` - Audio data struct for shaders
- `Visualization/ShaderManager.swift` - Metal pipeline management
- `Visualization/ArtworkVisualizerView.swift` - MTKView rendering
- `Windows/ArtVisualizer/ArtVisualizerWindowController.swift` - Window controller
- `Windows/ArtVisualizer/ArtVisualizerContainerView.swift` - Window chrome

### ProjectM/MilkDrop
- `Windows/ProjectM/ProjectMWindowController.swift` - Window controller (classic)
- `Windows/ProjectM/ProjectMView.swift` - Container with classic chrome
- `Windows/ModernProjectM/ModernProjectMWindowController.swift` - Window controller (modern)
- `Windows/ModernProjectM/ModernProjectMView.swift` - Container with modern chrome
- `Visualization/VisualizationGLView.swift` - OpenGL rendering (shared)
- `Visualization/ProjectMWrapper.swift` - ProjectM library wrapper
- `App/ProjectMWindowProviding.swift` - Protocol abstracting classic/modern

### Spectrum Analyzer
- `Windows/Spectrum/SpectrumWindowController.swift` - Window controller (classic)
- `Windows/Spectrum/SpectrumView.swift` - Container with classic chrome
- `Windows/ModernSpectrum/ModernSpectrumWindowController.swift` - Window controller (modern)
- `Windows/ModernSpectrum/ModernSpectrumView.swift` - Container with modern chrome
- `Visualization/SpectrumAnalyzerView.swift` - Metal rendering and vis_classic frame upload path (shared)
- `Visualization/VisClassicBridge.swift` - Swift bridge to C vis_classic core, scoped prefs/profile I/O
- `Visualization/SpectrumShaders.metal` - Enhanced/Ultra mode shaders
- `Visualization/FlameShaders.metal` - Fire mode compute + render shaders
- `Visualization/CosmicShaders.metal` - JWST mode fragment shaders
- `Visualization/ElectricityShaders.metal` - Lightning mode fragment shaders
- `Visualization/MatrixShaders.metal` - Matrix mode fragment shaders
- `Sources/CVisClassicCore/` - Portable C/C++ vis_classic core implementation and C API
- `App/SpectrumWindowProviding.swift` - Protocol abstracting classic/modern

### Main Window GPU Modes
- `Windows/MainWindow/MainWindowView.swift` - Mode switching, overlay (classic UI)
- `Windows/ModernMainWindow/ModernMainWindowView.swift` - Mode switching, overlay (modern UI)
- `Visualization/SpectrumAnalyzerView.swift` - Shared Metal rendering

## Troubleshooting

### Album Art Visualizer

**Effects not showing:**
- Ensure you're in ART mode in Library Browser
- Check that music is playing
- Try clicking to cycle to next effect

**Performance issues:**
- Lower the intensity setting
- Some effects (like Feedback) are more demanding

### ProjectM/MilkDrop

**Black screen:**
- ProjectM requires OpenGL 4.1 support
- Check Console.app for projectM initialization errors
- Try reloading presets from context menu

**No presets loading:**
- Verify preset files exist in bundle or custom folder
- Check file permissions on custom preset folder

**Choppy animation:**
- Close other GPU-intensive applications
- Try a different preset

**Crashes during preset switching:**
- Fixed by disabling soft cuts (blended transitions)
- Check Console.app for "projectM" errors

**Null texture pointer crash:**
- Fixed by removing direct OpenGL calls from `reshape()` method
- Render thread now handles all viewport updates safely

## Metal Gotchas

### Metal Command Encoders

Never use `if let enc = cb.makeRenderCommandEncoder(...), let pl = pipeline { ... }` — if `pipeline` is nil, the encoder is created but never ended, leaving the command buffer in an invalid state and causing a Metal API violation crash on `commit()`. Always guard the pipeline BEFORE creating the encoder:

```swift
// WRONG - encoder created but never ended if pipeline is nil:
if let enc = cb.makeRenderCommandEncoder(descriptor: rpd), let pl = pipeline {
    enc.setRenderPipelineState(pl)
    enc.endEncoding()
}
cb.commit()  // Crashes!

// CORRECT - guard pipeline first, then create encoder:
guard let pl = pipeline else { inFlightSemaphore.signal(); return }
if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
    enc.setRenderPipelineState(pl)
    enc.endEncoding()
}
cb.commit()
```

### Metal Render-to-Texture UV Y-Flip

When doing multi-pass rendering (render pass A writes to an intermediate texture, render pass B samples that texture), the intermediate texture is stored with y=0 at the TOP (Metal render-target convention). But the fullscreen-quad vertex shader maps `in.uv.y=0` to the BOTTOM of the screen (NDC y=-1). So pass B must flip y when sampling: `float2(in.uv.x, 1.0 - in.uv.y)`. Failing to flip produces an upside-down result. Example: `FlameShaders.metal` `flame_blur_v` uses `baseUV = float2(in.uv.x, 1.0 - in.uv.y)` to read the horizontal-blur intermediate texture correctly.

### Fire Mode — 3 Metal Passes

Fire mode uses 3 Metal passes: (1) compute `propagate_fire` (128×96 grid), (2) render `flame_blur_h` (horizontal blur, fire grid → r16Float intermediate texture at drawable size), (3) render `flame_blur_v` (vertical blur + color mapping → drawable). The `flameBlurTexture` intermediate is lazily created/resized when drawable size changes (`flameBlurLastDrawableSize`). `isPipelineAvailable(.flame)` requires all three pipelines.

### Spectrum Shader Availability

Use `SpectrumAnalyzerView.isShaderAvailable(for:)` to check if a mode's shader file exists before switching to it. This static method works without a view instance and should be used when restoring modes from UserDefaults and when building menus. The instance method `isPipelineAvailable(for:)` checks the actual compiled pipeline and is used after `setupMetal()`.
