---
name: visualizations
description: Album art visualizer, ProjectM/MilkDrop integration, spectrum analyzer window modes, and main window visualization modes. Use when working on visualization features, ProjectM integration, Metal shaders, or audio-reactive effects.
---

# NullPlayer Visualization Systems

NullPlayer features multiple visualization systems for audio-reactive visual effects.

Related but separate from the visualization stack is the standalone waveform window. It reuses the audio system's waveform notifications and cache service, but it is not a Metal visualization mode and should not be documented or implemented as one.

## Main Window Visualization

The main window's built-in visualization area (76x16 pixels in Winamp coordinates) supports eleven display modes.

### Modes

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
| **EKG** | Realistic high-resolution ECG monitor trace synchronized to detected BPM and waveform amplitude, with selectable monitor palettes |
| **vis_classic** | Exact-port vis_classic analyzer core with profile-compatible rendering |

### Switching Modes

- **Double-click** the visualization area to cycle through modes
- **Right-click** → Spectrum Analyzer → Main Window → Mode to select a specific mode, including **Off**
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
- **CPU Efficiency**: Display link pauses when window is minimized/occluded, in Spectrum mode, or in Off mode

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

Renders classic MilkDrop presets using OpenGL. Window has two implementations (classic/modern UI modes) both embedding `VisualizationGLView` for rendering. The same window hosts the ProjectM, Geiss, Tripex, and Met Museum engines, switchable from the right-click **Visualization Engine** submenu.

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
- **Drag suspend**: ProjectM rendering is suspended for the duration of any window drag (`.windowDragDidBegin` / `.windowDragDidEnd` notifications from `WindowManager`). This prevents WindowServer stalls on Apple Silicon caused by simultaneous OpenGL compositing and window repositioning. If adding new window-movement code that runs outside a drag, do not rely on ProjectM being suspended — the suspend is drag-scoped only.

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

## Geiss Visualizer

Geiss is a ProjectM-peer engine in the visualization window. It is selected from the same right-click **Visualization Engine** submenu and uses the same fullscreen, frame-rate, window docking, and engine-switch lifecycle as ProjectM.

### Controls

**Keyboard Shortcuts:**
- **→ / ←**: Next/previous effect
- **R**: Random effect
- **F**: Toggle fullscreen
- **Escape**: Exit fullscreen

**Context Menu:**
- Current Effect
- Next / Previous / Random Effect
- Effects submenu
- **Beat Detection** toggle
- **Sync Color to Sound** toggle
- **Slide Shift** toggle
- **Mode Lock** toggle (when on, suppresses auto mode-switching at chunk boundaries)
- **Palette Lock** toggle
- **Geiss Sensitivity** submenu — internal `volscale`, discrete steps `0.25 / 0.5 / 1.0 / 2.0 / 3.0 / 4.0`. Stacks on top of the host-side `projectMPCMGain`; labelled "Geiss Sensitivity" to distinguish from the existing Audio Sensitivity control.
- **Gamma** submenu — discrete steps `0 / 25 / 50 / 100 / 150 / 200`, labelled with the resulting factor (`1.00× / 1.25× / 1.50× / 2.00× / 2.50× / 3.00×`)
- **Auto-Switch** submenu — `5s / 15s / 30s / 60s / 120s` (no "Off" entry — Mode Lock is the single source of truth for stopping auto-switch)
- **visMode** submenu — Wave / Spectrum
- **Randomize Palette** action (one-shot palette shuffle)
- Audio Sensitivity (host-side PCM gain — same control as ProjectM)
- Visualization Engine
- Fullscreen

All lever state is persisted to UserDefaults under the `geiss.*` namespace (`geiss.sensitivity`, `geiss.gamma`, `geiss.beatDetection`, `geiss.syncColorToSound`, `geiss.slideShift`, `geiss.modeLocked`, `geiss.paletteLocked`, `geiss.autoSwitchSeconds`, `geiss.visMode`) and re-applied on engine activation. The same shared `GeissMenuBuilder` populates the menu in both classic (`ProjectMView`) and modern (`ModernProjectMView`) UI.

### Technical Details

- **Core**: `CGeissCore` ports the platform-neutral Geiss effect pipeline from the BSD-3-Clause upstream source. `upstream/main.cpp` remains as source reference but is excluded from the build; the compiled orchestration lives in `upstream_port/geiss_port.cpp`.
- **Rendering**: Geiss writes an 8-bit indexed framebuffer. `GeissEngine` uploads that buffer to a `GL_R8` texture, uploads the 256-entry RGBA palette to a `256x1 GL_RGBA8` texture, and resolves final color in a fullscreen OpenGL fragment shader.
- **Audio Input**: `VisualizationGLView.updatePCM` feeds mono waveform samples through `GeissCore_addPCM`, where they are converted to Winamp-style signed 8-bit biased samples (`128 == silence`).
- **Spectrum Input**: `VisualizationGLView` computes a 256-bin magnitude spectrum from the 512-sample PCM buffer with `Accelerate.framework` (`vDSP_fft_zrip`) and pushes it through `GeissCore_setSpectrum`. FFT setup and scratch buffers are cached per view.
- **Idle Behavior**: The Geiss port classifies incoming PCM as active or silent. Silent PCM fades the indexed framebuffer toward black instead of running the autonomous effect loop; playback-idle notifications clear the Swift PCM/spectrum snapshots so stale audio does not keep driving the core.
- **Threading**: The audio callback uses `engineLock.try()` before pushing spectrum so it does not block behind rendering or engine swaps. `GeissEngine` serializes all C-core calls with its own `coreLock`.
- **Persistence**: The active engine is stored in UserDefaults as `visualizationEngineType` and in AppState v2 as the optional raw string field `visualizationEngineType`. Missing or unknown values default to ProjectM.
- **Licensing**: Geiss is credited in the About window and its BSD-3-Clause license is bundled as `ThirdPartyLicenses/GEISS_LICENSE.txt`.

## Tripex Visualizer

Tripex is a ProjectM-peer engine in the visualization window. It ports Ben Marsh's MIT-licensed Direct3D9 visualizer to NullPlayer's OpenGL visualization host, selected from the same right-click **Visualization Engine** submenu as ProjectM/Geiss/Met Museum.

### Controls

**Keyboard Shortcuts** (wired in both `ProjectMView` and `ModernProjectMView`):
- **→ / ←**: Next/previous effect
- **R**: Random effect
- **F**: Toggle fullscreen
- **Escape**: Exit fullscreen

**Context Menu** (built by `TripexMenuBuilder`, shared between classic and modern UI):
- Current effect label
- Next / Previous / Random / Randomize Effect Settings
- **Hold Current Effect** toggle
- **Auto-Cycle** / **Auto-Random** toggles plus **Cycle Interval** submenu
- **Intensity** submenu (`0.25x` through `4.0x`)
- **Show Audio Info** and **Show Help Overlay** actions
- **Effects** submenu
- Visualization Engine
- Audio Sensitivity
- Fullscreen

### Technical Details

- **Core**: `CTripexCore` vendors the upstream Tripex source and replaces the Direct3D9 renderer with `RendererOpenGL`.
- **Audio Input**: `TripexEngine.addPCMMono` converts NullPlayer's float mono PCM to interleaved int16 stereo for the upstream audio reader.
- **Persistence**: Tripex state uses the `tripex.*` UserDefaults namespace for last effect, cycle mode, cycle interval, and intensity.
- **Licensing**: Tripex is MIT-licensed; the upstream license is retained under `Sources/CTripexCore/upstream/LICENSE` and bundled in `ThirdPartyLicenses/TRIPEX_LICENSE.txt`.

## Met Museum Art Visualization

A ProjectM-peer engine that displays a slideshow of public-domain artwork from the Metropolitan Museum of Art's Open Access collection (api.collection.metmuseum.org). Selected from the same right-click **Visualization Engine** submenu as ProjectM/Geiss/Tripex, and reuses the same fullscreen, frame-rate, window docking, and engine-switch lifecycle.

### Controls

**Keyboard Shortcuts** (wired in both `ProjectMView` and `ModernProjectMView`):
- **→ / ←**: Advance to another artwork
- **R**: Advance to another random artwork
- **F**: Toggle fullscreen
- **Escape**: Exit fullscreen

**Context Menu** (built by `MetMuseumMenuBuilder`, shared between classic and modern UI):
- **Department** submenu — filters by Met department (departments with no public-domain images are auto-excluded after exhaustion)
- **Slideshow Interval** submenu
- **Transition** submenu — Crossfade / Ken Burns / Beat Cut / Slide
- **Transition Duration** submenu
- **Aspect Ratio** submenu — Fit / Fill / Stretch
- **Audio-Modulated Effects** toggle (subtle zoom/pan reacting to PCM levels)
- **Beat-Triggered Changes** toggle (advance on detected beats instead of fixed interval)
- **Show Artist & Title** toggle
- **Clear Image Cache** action
- Visualization Engine
- Audio Sensitivity
- Fullscreen

### Persistence

All preferences live in UserDefaults under the `metMuseum*` namespace via `MetMuseumEngine.DefaultsKey`:
`metMuseumDepartmentID`, `metMuseumIntervalSeconds`, `metMuseumTransitionMode`, `metMuseumTransitionDuration`, `metMuseumAspectMode`, `metMuseumAudioReactive`, `metMuseumBeatTriggered`, `metMuseumShowAttribution`.

When restoring config from UserDefaults in `VisualizationGLView`, Bool keys must be guarded with `object(forKey:) != nil` before calling `bool(forKey:)` — an unconditional `bool(forKey:)` returns `false` for missing keys and would clobber the engine's defaults on fresh installs.

### Technical Details

- **Files**: `Visualization/MetMuseum/MetMuseumEngine.swift` (slideshow + OpenGL rendering), `MetMuseumClient.swift` (Met API client), `MetMuseumImageCache.swift` (on-disk image cache).
- **API Client**: `MetMuseumClient` uses a semaphore + minimum request spacing (`withPermit`) to stay under the API's throttle and avoid 429s under load. `withPermit` is `throws` (not `rethrows`) so `CancellationError` from `Task.sleep` propagates and the network request is skipped when the slideshow task is cancelled mid-throttle.
- **Image URL Validation**: `URL(string: objectInfo.primaryImage)` must be optional-bound; throw `MetMuseumError.noImageURL` on nil rather than force-unwrapping — the Met occasionally returns malformed URL strings.
- **Caching**: Downloaded images are persisted to a disk cache keyed by object ID, so re-visits and history walks are free.
- **Empty-Department Handling**: When a department exhausts its public-domain pool without a match, it's added to an exclusion set, the menu hides it, and the slideshow auto-picks a different department.
- **Audio Hook**: Engine is `setAudioActive`-driven; the slideshow pauses when playback stops. Beat-triggered mode listens to `bpmUpdated` notifications; audio-reactive mode samples PCM levels each frame for zoom/pan modulation.
- **Per-Engine Scoped Prefs**: Visualization preferences are scoped per engine — Met Museum's preferences do not collide with ProjectM/Geiss/Tripex (see commit 40c8a5c).
- **Licensing**: Met Museum Open Access content is CC0; attribution is shown via the in-engine overlay when **Show Artist & Title** is on.

## Spectrum Analyzer Window

A dedicated Metal-based spectrum analyzer providing larger, more detailed view than the main window's 19-bar analyzer. Window has two implementations (classic/modern UI modes) both embedding `SpectrumAnalyzerView`.

### Accessing

- **Click** the spectrum analyzer display in main window
- Context Menu → Spectrum Analyzer
- Window menu → Spectrum Analyzer

### Features

- **Bar Count**: 84 bars (vs 19 in main window)
- **Rendering**: Metal GPU shaders at 60Hz
- **Window Geometry**: default 275x116 at 1x; supports horizontal + vertical stretching with skin minimum size constraints
- **Color Source**: Skin's `viscolor.txt` (24-color palette)

### Docking

Participates in docking system with Main, EQ, and Playlist:
- Docks and moves with window group
- Opens below current vertical stack
- State saved with "Remember State on Quit"

### Quality Modes

| Mode | Description |
|------|-------------|
| **Classic** | Low-fi stepped bars from the skin palette with chunky peak caps, hard LED bands, and the shared cropped analyzer sub curve (default) |
| **Enhanced** | Compact professional LED analyzer with cropped logarithmic frequency mapping, controlled low-bass shaping, clean peak caps, and short release trails |
| **Ultra** | Dense professional analyzer with cropped logarithmic frequency mapping, controlled low-bass shaping, fast decay, and clean peak caps |
| **Fire** | GPU fire simulation with audio-reactive flame tongues (4 color styles) |
| **JWST** | Deep space flythrough with 3D star field, JWST diffraction flares |
| **Lightning** | GPU lightning storm with fractal bolts mapped to spectrum peaks (8 color schemes) |
| **Matrix** | Falling digital rain with procedural glyphs (5 color schemes, 2 intensity presets) |
| **Snow** | Layered procedural snowfall with spectrum-shaped density, gusting drift, and soft atmospheric haze |
| **EKG** | Beat-synced ECG monitor with phosphor trace, medical grid, scan glow, BPM-driven QRS pulses, PCM amplitude-driven peak height, and selectable palettes |
| **vis_classic** | Exact-port vis_classic analyzer core with profile-compatible INI behavior |

### Switching Modes

- **Double-click** the spectrum window to cycle through modes
- **Right-click** → Mode to select specific mode
- **Left/Right arrows**: Cycle flame/lightning/matrix styles (or prev/next profile in `vis_classic`)
- **[ / ]**: Previous/next profile in `vis_classic`

### Spectrum Analyzer Curve

Classic, Enhanced, and Ultra avoid spending visible columns on the deepest sub range because these modes do not render frequency labels. `SpectrumAnalyzerView` maps the visible analyzer width over a cropped logarithmic source range starting at 48 Hz, then applies controlled low-bass tapers that begin around 42 Hz before the values reach the mode-specific renderers.

- Classic keeps its low-fi identity after the shared curve: 19/84 stepped bars, hard palette bands, quantized heights, and chunky peak caps.
- Enhanced uses the same standard cropped curve as Classic, with smoother LED release trails and clean peak caps.
- Ultra uses the same analyzer strategy at a denser bar count, with a slightly faster decay and air lift for the larger spectrum window.

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
- Opacity keys: `visClassicOpacity.mainWindow`, `visClassicOpacity.spectrumWindow`

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

### EKG Mode Details

Realistic electrocardiogram monitor visualization.

**Visual Elements:**
- Procedural P-QRS-T ECG waveform with smooth antialiasing
- Medical monitor grid with fine and major subdivisions
- Green phosphor trace, glow, scan head, scanlines, vignette, and analog monitor noise
- QRS timing pulses from the BPM clock
- R-peaks are placed on a fixed seconds-wide monitor timebase, so faster BPM produces closer peak spacing
- Peak height follows smoothed raw PCM amplitude without using frequency energy
- Persistent ping-pong trace texture preserves already-drawn history; only the scan-head region is redrawn
- Larger vertical scale and lower baseline use more of the monitor area
- Selectable styles: Clinical, Cyan, Amber, Neon, Crimson, Ice
- Subtle per-beat procedural variance keeps the trace alive without fighting amplitude response

**Audio Reactivity:**
- Detected BPM drives the cardiac clock when available, folded into a 40-100 BPM display range
- Fast tempos are halved until they fit the EKG range; unusually slow readings are doubled
- Smoothed raw PCM amplitude controls QRS/R-peak height
- No spectrum or frequency-band energy is sampled in this mode
- Defaults to 80 BPM when no confident BPM has been detected yet
- EKG Style is available in the spectrum window context menu and the main-window Visuals menu when EKG is active

**Technical**: Two-pass Metal path: an update pass scrolls/preserves the persistent trace texture and draws only the scan-head band; a composite pass renders the monitor grid, glow, and stored trace. Uses `.bpmUpdated` notifications for timing and `.audioPCMDataUpdated` for raw-amplitude scaling. 60 FPS.

### Responsiveness Modes

Controls how quickly bars fall:

| Mode | Retention | Feel |
|------|-----------|------|
| Instant | 0% | No smoothing |
| Snappy | 25% | Fast and punchy (default) |
| Balanced | 40% | Middle ground |
| Smooth | 55% | Original Winamp feel |

## Comparison

| Feature | Album Art | ProjectM/MilkDrop | Geiss | Tripex | Met Museum | Spectrum Analyzer |
|---------|-----------|-------------------|-------|--------|------------|-------------------|
| **Visual Style** | Transformed artwork | Procedural graphics | Indexed framebuffer + palette effects | 3D Winamp-era effects | Public-domain Met artwork slideshow | Frequency bars/vis_classic/Fire/JWST/Lightning/Matrix/Snow/EKG |
| **Effect Count** | 30 built-in | 100s of presets | 25 modes | Upstream effect set | N/A (real artwork) | 10 modes |
| **Customization** | Intensity adjustment | Full preset ecosystem | Effect selection | Effect selection / cycle / intensity | Department / interval / transition / aspect | Mode + decay + style presets |
| **GPU Tech** | Core Image (Metal) | OpenGL shaders | OpenGL palette LUT | OpenGL geometry renderer | OpenGL textured quad | Metal shaders + compute |
| **Audio Response** | Spectrum bands | PCM waveform + beats | PCM waveform + 256-bin host spectrum | PCM-driven internal FFT/effects | Optional audio-reactive zoom/pan, beat-triggered advance | 75-band spectrum / energy-driven |

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

**Geiss:**
- Classic Geiss effect look
- Lower-level indexed/palette effects
- Audio-reactive waveform and spectrum visuals without MilkDrop presets

**Tripex:**
- Winamp-era 3D visualizer effects
- Effect cycling with hold, randomize, intensity, and overlay controls
- Procedural visuals without ProjectM preset files

**Met Museum:**
- Calm, gallery-style slideshow of real artwork instead of procedural graphics
- Department-curated browsing (paintings, photography, Asian art, etc.)
- Optional audio reactivity (zoom/pan, beat-triggered advances) for a subtler music-driven feel

**Main Window Visualization:**
- Quick access to all GPU modes without separate window
- Double-click to cycle through modes
- Independent settings from Spectrum window

**Spectrum Analyzer Window:**
- Detailed frequency visualization (84 bars)
- Monitoring audio levels
- Classic Winamp spectrum aesthetic
- Larger display complements main window
- Fire/JWST/Lightning/Matrix/EKG modes for ambient visuals

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
- `Visualization/GeissEngine.swift` - Geiss OpenGL indexed-framebuffer renderer
- `Sources/CGeissCore/` - Geiss C++ port and C ABI
- `Visualization/TripexEngine.swift` - Tripex OpenGL engine wrapper
- `Visualization/TripexMenuBuilder.swift` - Tripex context menu builder
- `Sources/CTripexCore/` - Tripex C++ port and C ABI
- `Visualization/MetMuseum/MetMuseumEngine.swift` - Met Museum slideshow + OpenGL renderer
- `Visualization/MetMuseum/MetMuseumClient.swift` - Met collection API client (throttled, cancellable)
- `Visualization/MetMuseum/MetMuseumImageCache.swift` - On-disk image cache
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
- `Visualization/SnowShaders.metal` - Snow mode fragment shaders
- `Visualization/EKGShaders.metal` - EKG mode fragment shaders
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

### Spectrum Jitter / Bar Stuttering

**Symptom**: Classic and CPU Spectrum modes show jerky bar movement at startup or after cycling modes between windows.

**Root cause**: `AudioEngine` dispatched a new `DispatchQueue.main.async` block every audio tap (~60Hz). During busy main-thread periods (mode switching, window ordering, UserDefaults writes), these backed up in the queue. When the backlog cleared, multiple blocks fired in rapid succession, causing bars to jump.

**Fix**: `AudioEngine` now uses the same coalescing pattern as `StreamingAudioPlayer` — a `pendingSpectrumUpdate` flag ensures at most one dispatch is ever queued, while `latestRawSpectrum` always holds the freshest frame so data is never lost. On the main thread the pending block reads `latestRawSpectrum` and posts the notification once, then clears the flag.

**Why Classic/Spectrum are more sensitive**: The LED attack rate in Enhanced mode (`cellAttackRate = 0.5`) absorbs rapid-fire updates visually. Classic and CPU-Spectrum have no equivalent damping, so burst updates are directly visible as bar jumps.
