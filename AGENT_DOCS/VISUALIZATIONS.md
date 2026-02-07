# NullPlayer Visualization Systems

NullPlayer features multiple visualization systems for audio-reactive visual effects.

## Table of Contents

1. [Main Window Visualization](#main-window-visualization)
2. [Album Art Visualizer](#album-art-visualizer)
3. [ProjectM/ProjectM Visualizer](#projectmprojectM-visualizer)
4. [Spectrum Analyzer Window](#spectrum-analyzer-window)
5. [Comparison](#comparison)

---

## Main Window Visualization

The main window's built-in visualization area (76x16 pixels in classic coordinates) supports seven rendering modes — the same GPU modes available in the Spectrum Analyzer window (except Classic, which is replaced by Spectrum).

### Modes

| Mode | Description |
|------|-------------|
| **Spectrum** | Classic 19-bar spectrum analyzer drawn with skin colors via CGContext (default) |
| **Fire** | GPU flame simulation using Metal compute shaders |
| **Enhanced** | LED matrix with rainbow gradient, gravity-bouncing peaks, and amber fade trails |
| **Ultra** | Maximum fidelity seamless gradient with smooth decay, physics-based peaks, and reflections |
| **JWST** | Deep space flythrough with 3D star field and JWST diffraction flares |
| **Lightning** | GPU lightning storm with fractal bolts mapped to spectrum peaks |
| **Matrix** | Falling digital rain with procedural glyphs mapped to spectrum bands |

### Switching Modes

- **Double-click** the visualization area in the main window to cycle through all modes (single-click toggles the Spectrum Analyzer window)
- **Right-click** → Spectrum Analyzer → Main Window → Mode to select a specific mode
- Setting is persisted across app restarts (UserDefaults key: `mainWindowVisMode`)

### Settings

All GPU modes share:
- **Responsiveness**: Controls bar decay speed (Instant, Snappy, Balanced, Smooth) — UserDefaults key: `mainWindowDecayMode`
- **Normalization**: Controls level scaling (Accurate, Adaptive, Dynamic) — UserDefaults key: `mainWindowNormalizationMode` (hidden for Fire mode)

Mode-specific settings:
- **Fire**: Flame Style (Inferno, Aurora, Electric, Ocean) and Fire Intensity (Mellow, Intense) — keys: `mainWindowFlameStyle`, `mainWindowFlameIntensity`
- **Lightning**: Lightning Style (Classic, Plasma, Matrix, Ember, Arctic, Rainbow, Neon, Aurora) — key: `mainWindowLightningStyle`
- **Matrix**: Matrix Color (Classic, Amber, Blue Pill, Bloodshot, Neon) and Matrix Intensity (Subtle, Intense) — keys: `mainWindowMatrixColorScheme`, `mainWindowMatrixIntensity`

All main window settings are independent from the Spectrum Analyzer window (separate UserDefaults keys with `mainWindow` prefix).

### Technical Details

- **Implementation**: Metal overlay (`SpectrumAnalyzerView` with `isEmbedded = true`) added as subview of `MainWindowView`
- **Positioning**: Converted from classic coordinates (top-left origin) to macOS view coordinates (bottom-left origin), accounting for window scaling
- **Lifecycle**: Overlay is created lazily on first GPU mode activation, display link starts/stops with mode changes and window visibility
- **CPU Efficiency**: Display link pauses when window is minimized, occluded, or in Spectrum mode
- **Isolation**: Embedded overlay uses its own `normalizationUserDefaultsKey` and does not write to spectrum window UserDefaults keys

### Key Files

| File | Purpose |
|------|---------|
| `Windows/MainWindow/MainWindowView.swift` | Mode switching, overlay management, click cycling |
| `Visualization/SpectrumAnalyzerView.swift` | Metal rendering for all GPU modes (shared with Spectrum window) |
| `Visualization/FlameShaders.metal` | Fire mode GPU compute + render shaders |
| `Visualization/CosmicShaders.metal` | JWST mode fragment shaders |
| `Visualization/ElectricityShaders.metal` | Lightning mode fragment shaders |
| `Visualization/MatrixShaders.metal` | Matrix mode fragment shaders |
| `Visualization/SpectrumShaders.metal` | Enhanced/Ultra mode shaders |

---

## Album Art Visualizer

The Album Art Visualizer applies GPU-accelerated effects to album artwork, creating audio-reactive visuals that transform the current track's cover art.

### Accessing the Visualizer

1. Open the **Library Browser** window (click the Plex icon or use the context menu)
2. Switch to **ART** mode (click the ART tab)
3. The visualizer activates automatically when music plays
4. Right-click for the visualizer context menu

### Effects (30 Total)

All effects use Core Image filters for GPU acceleration and respond to audio levels (bass, mid, treble).

#### Rotation & Scaling
| Effect | Description |
|--------|-------------|
| **Psychedelic** | Twirl distortion + hue rotation + bloom glow |
| **Kaleidoscope** | Multi-segment kaleidoscope with rotating pattern |
| **Vortex** | Swirling vortex distortion centered on image |
| **Spin** | Continuous rotation with zoom blur trails |
| **Fractal** | Zooming scale effect with rotation and bloom |
| **Tunnel** | Hole distortion creating tunnel/portal effect |

#### Distortion
| Effect | Description |
|--------|-------------|
| **Melt** | Glass distortion simulating melting/liquid effect |
| **Wave** | Bump distortion moving across the image |
| **Glitch** | RGB offset + posterization on bass hits |
| **RGB Split** | Chromatic aberration - separates color channels |
| **Twist** | Strong twirl distortion that follows the beat |
| **Fisheye** | Bump distortion creating fisheye lens effect |
| **Shatter** | Triangular tile creating shattered glass look |
| **Stretch** | Pinch distortion creating rubber band effect |

#### Motion
| Effect | Description |
|--------|-------------|
| **Zoom** | Zoom blur pulsing with the bass |
| **Shake** | Earthquake shake with motion blur |
| **Bounce** | Squash and stretch bouncing animation |
| **Feedback** | Multiple scaled/rotated copies with bloom |
| **Strobe** | Exposure flashing synchronized to beat |
| **Jitter** | Random position/scale jitter on beats |

#### Copies & Mirrors
| Effect | Description |
|--------|-------------|
| **Mirror** | Four-fold reflected tile pattern |
| **Tile** | Op-art style tiling with rotation |
| **Prism** | Triangle kaleidoscope with decay |
| **Double Vision** | Offset duplicate images blended together |
| **Flipbook** | Rapid flipping between orientations |
| **Mosaic** | Hexagonal pixelation pattern |

#### Pixel Effects
| Effect | Description |
|--------|-------------|
| **Pixelate** | Square pixelation that responds to audio level |
| **Scanlines** | CRT-style scanlines with bloom |
| **Datamosh** | Edge detection + color shift effect |
| **Blocky** | Large pixelation with vibrance boost |

### Controls

#### Keyboard Shortcuts
| Key | Action |
|-----|--------|
| **Click** | Next effect |
| **← →** | Previous/Next effect |
| **↑ ↓** | Decrease/Increase intensity |
| **R** | Toggle Random mode |
| **C** | Toggle Cycle mode |
| **F** | Toggle Fullscreen |
| **Escape** | Exit fullscreen / Turn off visualizer |

#### Context Menu (Right-Click)
- **Current Effect** - Shows active effect name
- **Next/Previous Effect** - Navigate effects
- **Random Mode** - Changes effect randomly on beat hits
- **Auto-Cycle Mode** - Automatically advances through effects
- **Cycle Interval** - Set timing: 5s, 10s, 20s, 30s
- **All Effects** - Submenu to select specific effect
- **Intensity** - Low, Medium, Normal, High, Extreme
- **Fullscreen** - Enter/exit fullscreen mode
- **Turn Off** - Disable visualization

### Modes

| Mode | Behavior |
|------|----------|
| **Single** | Manual effect selection, stays on chosen effect |
| **Random** | Changes to random effect on strong bass hits (~30% chance) |
| **Cycle** | Automatically advances to next effect at set interval |

### Technical Details

- **Rendering**: Core Image filters with Metal GPU acceleration
- **Frame Rate**: 60 FPS animation timer
- **Audio Reactivity**: Reads spectrum data from AudioEngine (bass/mid/treble bands)
- **Auto-Stop**: Effects pause after ~0.5s of silence (no music)
- **Intensity Range**: 0.5x to 2.0x effect strength

---

## ProjectM/ProjectM Visualizer

The ProjectM visualizer renders classic ProjectM presets - the legendary visualization system from classic. It uses OpenGL for real-time procedural graphics synchronized to music.

### Accessing the Visualizer

1. **Context Menu** → Visualizations → ProjectM Window
2. Or use the main menu: Window → ProjectM

### What is ProjectM/ProjectM?

- **ProjectM** was the iconic visualization plugin for classic, created by Ryan Geiss
- **ProjectM** is the open-source reimplementation that runs ProjectM presets
- Presets are shader-based programs that create infinite visual variety
- Each preset defines equations for motion, color, and waveform rendering

### Presets

NullPlayer includes bundled ProjectM presets. You can also add custom presets:

**Custom Preset Location:**
```
~/Library/Application Support/NullPlayer/Presets/
```

Place `.milk` preset files in this folder and use "Reload Presets" from the context menu.

### Controls

#### Keyboard Shortcuts
| Key | Action |
|-----|--------|
| **→** | Next preset |
| **←** | Previous preset |
| **Shift+→** | Next preset (hard cut, no blend) |
| **Shift+←** | Previous preset (hard cut, no blend) |
| **R** | Random preset |
| **Shift+R** | Random preset (hard cut) |
| **L** | Lock/unlock current preset |
| **C** | Cycle through modes: Off → Auto-Cycle → Auto-Random |
| **F** | Toggle fullscreen |
| **Escape** | Exit fullscreen |

#### Context Menu (Right-Click)
- **Current Preset** - Shows preset name and index (e.g., "Preset: Aurora (5/150)")
- **Next/Previous/Random Preset** - Navigate presets
- **Lock Preset** - Prevents automatic switching
- **Manual Only** - No automatic preset changes
- **Auto-Cycle** - Sequential preset advancement
- **Auto-Random** - Random preset on timer
- **Cycle Interval** - 5s, 10s, 20s, 30s, 60s, 2min
- **Presets** - Submenu listing all available presets
- **Audio Sensitivity** - PCM gain multiplier: Low (0.5x), Normal (1.0x), High (1.5x), Intense (2.0x), Max (3.0x)
- **Beat Sensitivity** - ProjectM beat detection: Low (0.5), Normal (1.0), High (1.5), Max (2.0)
- **Fullscreen** - Enter/exit fullscreen mode

### Modes

| Mode | Behavior |
|------|----------|
| **Manual Only** | Presets only change via user input (default) |
| **Auto-Cycle** | Advances to next preset sequentially at interval |
| **Auto-Random** | Jumps to random preset at interval |

**Note**: Auto-switching modes are disabled by default for stability. Some presets may cause visual glitches during transitions. If you experience issues, stick with Manual Only mode.

### Preset Transitions

- **Hard Cut**: Instant switch with no transition (always used for stability)

**Note**: Soft cuts (blended transitions) are disabled to prevent potential crashes caused by race conditions in libprojectM when accessing resources from multiple presets simultaneously.

### Technical Details

- **Rendering**: OpenGL 4.1 Core Profile via NSOpenGLView
- **Frame Rate**: 60 FPS via CVDisplayLink
- **Audio Input**: PCM waveform data from AudioEngine
- **Beat Detection**: Built-in projectM beat sensitivity (adjustable)
- **Resolution**: Renders at window/screen resolution

### Audio Sensitivity (PCM Gain)

Controls the amplitude of audio samples fed to the visualization engine. Higher values make visuals more reactive to audio; lower values produce calmer visuals. The gain is applied as a multiplier on PCM samples before they reach projectM, clamped to the [-1.0, 1.0] range to prevent distortion.

| Preset | Gain | Effect |
|--------|------|--------|
| **Low** | 0.5x | Subdued visuals, good for loud/busy tracks |
| **Normal** | 1.0x | Unity gain, original signal strength (default) |
| **High** | 1.5x | More reactive, good for quieter tracks |
| **Intense** | 2.0x | Very reactive, strong waveform motion |
| **Max** | 3.0x | Maximum reactivity, dramatic visual response |

Setting is persisted across app restarts (UserDefaults key: `projectMPCMGain`).

### Beat Sensitivity

ProjectM adjusts its visuals based on detected beats. NullPlayer uses two sensitivity levels:
- **Idle**: Lower sensitivity (0.2) when audio is quiet/stopped
- **Active**: User-configurable sensitivity during playback (default 1.0)

The active beat sensitivity is configurable via the context menu:

| Preset | Value | Effect |
|--------|-------|--------|
| **Low** | 0.5 | Fewer beat-triggered effects |
| **Normal** | 1.0 | Default projectM behavior |
| **High** | 1.5 | More frequent beat-triggered effects |
| **Max** | 2.0 | Maximum beat reactivity |

Setting is persisted across app restarts (UserDefaults key: `projectMBeatSensitivity`).

---

## Spectrum Analyzer Window

A dedicated Metal-based spectrum analyzer visualization that provides a larger, more detailed view of the audio spectrum than the main window's built-in 19-bar analyzer.

### Accessing the Visualizer

1. **Click** the spectrum analyzer display in the main window
2. **Context Menu** → Spectrum Analyzer
3. Or via the Window menu

### Window Behavior

The Spectrum Analyzer window participates in the docking system:
- Docks with Main, EQ, and Playlist windows (moves together when dragged)
- Opens below the current vertical stack
- Position and visibility saved with "Remember State on Quit"

### Features

| Feature | Value |
|---------|-------|
| **Bar Count** | 55 bars (vs 19 in main window) |
| **Rendering** | Metal GPU shaders at 60Hz |
| **Window Size** | 275x116 pixels (matches main window) |
| **Color Source** | Skin's `viscolor.txt` (24-color palette) |

### Switching Modes

- **Double-click** the spectrum analyzer window to cycle through modes (classic → Enhanced → Ultra → Fire → JWST → Lightning → Matrix)
- **Right-click** → Mode to select a specific mode
- **Left/Right arrow keys** cycle flame styles (Fire), lightning styles (Lightning), or matrix color schemes (Matrix)

### Quality Modes

| Mode | Description |
|------|-------------|
| **classic** | Discrete color bands from skin's 24-color palette with floating peak indicators, 3D bar shading, and band gaps for an authentic segmented LED look (default) |
| **Enhanced** | Rainbow LED matrix with gravity-bouncing peaks, warm amber fade trails, 3D inner glow cells, and anti-aliased rounded corners |
| **Ultra** | Maximum fidelity seamless gradient with smooth exponential decay, perceptual gamma, warm color trails, physics-based bouncing peaks, and reflection effect |
| **Fire** | GPU fire simulation with audio-reactive flame tongues (see below) |
| **JWST** | Deep space flythrough with 3D perspective star field, JWST diffraction flares as intensity indicators, and vivid celestial bodies (see below) |
| **Lightning** | GPU lightning storm with fractal bolts mapped to spectrum peaks, multiple color schemes (see below) |
| **Matrix** | Falling digital rain with procedural glyphs mapped to spectrum bands, multiple color schemes and intensity presets (see below) |

### classic Mode Details

The classic mode aims to recreate the iconic classic 2.x spectrum analyzer aesthetic with modern enhancements:

- **Discrete Color Bands**: Bars are divided into 16 horizontal segments with subtle 1-pixel gaps between them, creating the classic LED matrix look without a screen door effect
- **Floating Peak Indicators**: Bright lines hold at peak heights, then fall with gravity-based physics including subtle bouncing for satisfying visual feedback
- **3D Cylindrical Shading**: Each bar has a specular highlight down the center for depth
- **Skin Palette Colors**: All colors come from the loaded skin's `viscolor.txt` (24-color palette)

### Flame Quality Mode

Flame mode replaces spectrum bars with a GPU-driven fire simulation. Narrow flame tongues rise from the bottom, dance independently, thin to points, and react to music in real-time.

**Flame Style Presets** (right-click > Flame Style, or left/right arrow keys):

| Style | Description |
|-------|-------------|
| **Inferno** | Classic orange/red fire |
| **Aurora** | Green/cyan/purple northern lights |
| **Electric** | Blue/white/purple plasma |
| **Ocean** | Deep blue/teal/white |

**Fire Intensity Presets** (right-click > Fire Intensity):

| Intensity | Description |
|-----------|-------------|
| **Mellow** | Gentle ambient flame with smooth transitions. Lower burst threshold (0.15), moderate multiplier (6x), slow attack/release smoothing |
| **Intense** | Punchy beat-reactive flame with sharp spikes. Lower burst threshold (0.1), high multiplier (10x), fast attack (0.5) and quicker release (0.12) |

**Audio Reactivity:**
- Bass (bands 0-15): Controls heat injection intensity. Strong bass = taller tongues
- Mids (bands 16-49): Increases flame sway and lateral motion
- Treble (bands 50-74): Adds ember sparks in the flame zone
- Intensity preset controls how aggressively the flame tracks the beat

**Playback State:**
- **Stop**: Immediately clears flame textures and renders a black frame
- **Pause**: Freezes the flame display in place (last frame stays visible)
- **Play**: Resumes flame rendering

**Technical:** 128x96 simulation grid with per-column propagation and edge erosion. Rendered with an 11x11 Gaussian blur at 2-texel steps for silky smooth output. Single compute pass + render pass per frame at 60 FPS.

**Key files:** `Visualization/FlameShaders.metal` (compute + render shaders), `Visualization/SpectrumAnalyzerView.swift` (pipeline integration)

### JWST Mode

JWST mode is a 3D deep space flythrough inspired by the James Webb Space Telescope's Pillars of Creation image. You drift through space while vivid JWST-style diffraction flares visualize the music. Everything is generated in a single GPU fragment shader pass.

**Visual Elements:**
- **3D perspective star field**: 5 depth layers of stars emanating outward from a central vanishing point, creating a forward-flight effect. Stars subtly streak radially when music is intense
- **JWST 6-axis diffraction flares**: Authentic spike pattern (strong vertical, 4 diagonal at ±60°, short horizontal strut) with chromatic color fringing — blue extends further than red along each spike, like real JWST optics
- **Vivid celestial bodies**: Rare, richly colored objects (galaxies, nebula patches) with saturated JWST palette colors and prominent diffraction spikes
- **Giant flare events**: On major peaks, a massive screen-filling diffraction flare fires and slowly decays over ~5.5 seconds while suppressing all other flares — the giant owns the screen until it dissipates, position locked at trigger
- **JWST color palette**: 10-stop gradient cycling through deep navy, indigo, violet, mauve, dusty rose, chocolate, amber, gold, cream, and warm white
- **Bold star colors**: Electric blue, vivid red, pure gold, neon pink, hot crimson, cyan, royal blue — at full saturation with chromatic fringing
- **Gossamer nebula wisps**: Very sparse, transparent gas layers with vertical stretch for abstract pillar-like forms
- **Floating cosmic dust**: Tiny particles drifting through space

**Audio Reactivity (not a spectrum analyzer — pure atmospheric):**
- Music intensity drives flight speed (scroll accumulation: gentle drift when quiet, faster when loud)
- Flare frequency tied to overall dB: dynamic threshold `max(0.12, 0.40 - energy * 0.9)` — quiet = very sparse flares, loud = more frequent
- Flare horizontal position aligned to frequency peaks (bass on left, treble on right), vertical position random
- Uses normalized `displaySpectrum` (AudioEngine's per-region normalization) so highs compete fairly with lows
- Giant flare on strong bass peaks (>0.25 above smoothed average), 6-second cooldown, 5.5-second slow decay
- Stars twinkle with treble energy, overall saturation lifts with energy
- Beat detection creates gentle zoom nudges and brightness pulses

**Technical:** Single render pass with procedural FBM noise, 5-layer perspective star field, parametric JWST flare function with rotation and chromatic aberration, filmic tone mapping. 60 FPS. CosmicParams struct (48 bytes) passes time, scroll offset, energy bands, beat/flare intensity, and frozen flare scroll snapshot.

**Key files:** `Visualization/CosmicShaders.metal` (vertex + fragment shaders), `Visualization/SpectrumAnalyzerView.swift` (pipeline integration, flare state management)

### Matrix Mode

Matrix mode recreates the iconic falling digital rain from The Matrix, driven by the audio spectrum. Each column of falling characters maps to a frequency band, with brightness, speed, and trail length scaling with the audio energy.

**Visual Elements:**
- **Digital rain columns**: 75 columns of procedural glyph-like shapes (katakana-inspired geometric patterns), each mapped to a spectrum band
- **Spectrum-driven intensity**: Column speed, trail length, and brightness scale with the corresponding frequency band's energy
- **Glyph mutation**: Characters scramble periodically — brighter cells mutate faster for an "active" look
- **Multiple rain streams**: 2-4 overlapping rain streams per column for density
- **Phosphor glow**: Bright characters bleed a colored glow into neighboring cells
- **CRT scanlines**: Subtle horizontal line overlay for an authentic monitor feel
- **Reflection pool**: Bottom 18% of the screen shows a mirrored, ripple-distorted reflection of the rain above
- **Beat pulse**: Bass hits flash columns brighter with a white wash
- **Dramatic awakening**: On major peaks, a horizontal scan line sweeps down the screen while all glyphs momentarily reveal (JWST-style LPF detection, ~7s cooldown)
- **Background code grid**: Faint, slowly-scrolling layer of dim characters for depth
- **CRT vignette**: Dark edges for a cinematic monitor feel

**Matrix Color Schemes** (right-click > Matrix Color, or left/right arrow keys):

| Color | Description |
|-------|-------------|
| **Classic** | Iconic green: white-hot head, bright green trail, dark green fade |
| **Amber** | Retro terminal: warm white head, amber/orange trail, dark brown fade |
| **Blue Pill** | Cool blue: white head, cyan/electric blue trail, deep navy fade |
| **Bloodshot** | Red alert: pink-white head, crimson trail, dark maroon fade |
| **Neon** | Cyberpunk: magenta-white head, hot magenta trail, deep purple fade |

**Matrix Intensity Presets** (right-click > Matrix Intensity):

| Intensity | Description |
|-----------|-------------|
| **Subtle** | Sparse rain, gentle glow, smooth transitions, zen-like ambient feel |
| **Intense** | Dense rain, strong glow, punchy beat reactions, high density |

**Audio Reactivity:**
- Each of the 75 spectrum bands drives its corresponding rain column
- Bass bands produce thicker glow effects
- Scroll speed integrates total energy (quiet = gentle drift, loud = fast cascade)
- Beat intensity (fast attack/slow release) modulates overall brightness
- Dramatic awakening fires on energy spikes above a slow-moving baseline, with ~7s cooldown

**Technical:** Single render pass with procedural glyph grid (75 columns x ~40 rows), hash-based segment patterns for character shapes, multi-stream rain simulation, and per-scheme color palette functions. 60 FPS. MatrixParams struct passes time, scroll offset, energy bands, beat/dramatic intensity, color scheme, and intensity preset value. Reuses `flameSpectrumBuffer` for spectrum data.

**Key files:** `Visualization/MatrixShaders.metal` (vertex + fragment shaders), `Visualization/SpectrumAnalyzerView.swift` (pipeline integration, state management)

### Responsiveness Modes

Controls how quickly spectrum bars fall after peaks:

| Mode | Behavior |
|------|----------|
| **Instant** | No smoothing - bars respond immediately |
| **Snappy** | Fast response with 25% retention (default) |
| **Balanced** | Middle ground with 40% retention |
| **Smooth** | Classic classic feel with 55% retention |

### Context Menu

Right-click on the window for:
- **Mode** - Switch between classic/Enhanced/Ultra/Fire/JWST/Lightning/Matrix rendering
- **Responsiveness** - Adjust decay behavior (bar modes)
- **Flame Style** - Choose flame color preset (Flame mode only)
- **Fire Intensity** - Choose Mellow or Intense reactivity (Flame mode only)
- **Lightning Style** - Choose lightning color preset (Lightning mode only)
- **Matrix Color** - Choose color scheme (Matrix mode only)
- **Matrix Intensity** - Choose Subtle or Intense reactivity (Matrix mode only)
- **Close** - Close the window

### Technical Details

- **Rendering**: Metal shaders via CAMetalLayer with runtime shader compilation
- **Shader Modes**: Separate pipeline states for classic (bar), Enhanced (LED matrix), Ultra (seamless gradient), Fire (compute simulation), JWST (procedural space), Lightning (procedural storm), and Matrix (digital rain) modes
- **Frame Rate**: 60 FPS via CVDisplayLink (auto-stops when window closes or occluded)
- **Audio Input**: 75-band spectrum data from AudioEngine
- **Thread Safety**: OSAllocatedUnfairLock for spectrum data updates
- **LED Matrix**: 55 columns × 16 rows = 880 cells in Enhanced mode
- **Peak Hold**: Floating peak indicators with slow decay in Enhanced mode
- **Memory Management**: 
  - Drawable pool limited to 3 (prevents unbounded CAMetalDrawable accumulation)
  - Rendering pauses when window is minimized or occluded (saves CPU/GPU)
  - Display sync disabled to allow frame dropping under load

---

## Comparison

| Feature | Album Art Visualizer | ProjectM/ProjectM | Spectrum Analyzer |
|---------|---------------------|-------------------|-------------------|
| **Visual Style** | Transformed album artwork | Procedural graphics | Frequency bars / Fire / Deep space / Lightning / Matrix |
| **Effect Count** | 30 built-in effects | 100s of presets available | 7 modes (classic, Enhanced, Ultra, Fire, JWST, Lightning, Matrix) |
| **Customization** | Intensity adjustment | Full preset ecosystem | Mode + decay + flame/lightning/matrix styles |
| **GPU Tech** | Core Image (Metal) | OpenGL shaders | Metal shaders + Metal compute shaders |
| **Audio Response** | Spectrum bands (bass/mid/treble) | PCM waveform + beat detection | 75-band spectrum / energy-driven |
| **Best For** | Album art appreciation | Immersive light shows | Frequency analysis / Ambient visuals / Deep space / Lightning / Matrix rain |

### When to Use Each

**Album Art Visualizer**
- When you want to see the album artwork
- For a more subtle, integrated experience
- When browsing your music library

**ProjectM/ProjectM**
- For full-screen immersive visualizations
- Classic classic nostalgia
- Parties and ambient displays
- When you want maximum visual variety

**Main Window Visualization Modes**
- Quick access to all GPU visualization modes without opening a separate window
- Double-click the vis area to cycle through all modes (Spectrum, Fire, Enhanced, Ultra, JWST, Lightning, Matrix)
- Each mode has its own settings independent from the Spectrum Analyzer window

**Spectrum Analyzer Window**
- When you want detailed frequency visualization (Classic/Enhanced/Ultra modes)
- For monitoring audio levels
- Classic classic spectrum aesthetic
- Larger display area (275x116 pixels, 55 bars) complements the main window's smaller analyzer
- Fire mode for ambient flame visuals
- JWST mode for a chill deep space drift with music-reactive diffraction flares
- Lightning mode for dramatic storm visuals mapped to spectrum peaks
- Matrix mode for iconic falling digital rain synced to frequency bands

---

## Troubleshooting

### Album Art Visualizer

**Effects not showing:**
- Ensure you're in ART mode in the Library Browser
- Check that music is playing (effects pause during silence)
- Try clicking to cycle to next effect

**Performance issues:**
- Lower the intensity setting
- Some effects (like Feedback) are more demanding
- Ensure your Mac supports Metal

### ProjectM/ProjectM

**Black screen:**
- ProjectM requires OpenGL 4.1 support
- Check Console.app for projectM initialization errors
- Try reloading presets from context menu

**No presets loading:**
- Verify preset files exist in the bundle or custom folder
- Check file permissions on custom preset folder

**Choppy animation:**
- Close other GPU-intensive applications
- Some presets are more demanding than others
- Try a different preset

**Crashes during preset switching:**
- This was fixed by disabling soft cuts (blended transitions)
- Some presets reference textures that may cause issues
- If crashes persist, try different presets or stick to Manual Only mode
- Check Console.app for "projectM" errors to identify problematic presets

**Null texture pointer crash (Texture::Empty):**
- This was caused by an OpenGL context race condition between the main thread (reshape/resize) and the CVDisplayLink render thread
- Fixed by removing direct OpenGL calls from the `reshape()` method - the render thread now handles all viewport updates safely
- The render thread already updates viewport dimensions every frame via `setViewportSize()` with proper locking
