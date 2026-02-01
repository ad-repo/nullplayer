# AdAmp Visualization Systems

AdAmp features two distinct visualization systems for audio-reactive visual effects.

## Table of Contents

1. [Album Art Visualizer](#album-art-visualizer)
2. [ProjectM/Milkdrop Visualizer](#projectmmilkdrop-visualizer)
3. [Comparison](#comparison)

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

## ProjectM/Milkdrop Visualizer

The ProjectM visualizer renders classic Milkdrop presets - the legendary visualization system from Winamp. It uses OpenGL for real-time procedural graphics synchronized to music.

### Accessing the Visualizer

1. **Context Menu** → Visualizations → Milkdrop Window
2. Or use the main menu: Window → Milkdrop

### What is Milkdrop/ProjectM?

- **Milkdrop** was the iconic visualization plugin for Winamp, created by Ryan Geiss
- **ProjectM** is the open-source reimplementation that runs Milkdrop presets
- Presets are shader-based programs that create infinite visual variety
- Each preset defines equations for motion, color, and waveform rendering

### Presets

AdAmp includes bundled Milkdrop presets. You can also add custom presets:

**Custom Preset Location:**
```
~/Library/Application Support/AdAmp/Presets/
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

### Beat Sensitivity

ProjectM adjusts its visuals based on detected beats. AdAmp uses two sensitivity levels:
- **Idle**: Lower sensitivity when audio is quiet/stopped
- **Active**: Higher sensitivity during playback

---

## Comparison

| Feature | Album Art Visualizer | ProjectM/Milkdrop |
|---------|---------------------|-------------------|
| **Visual Style** | Transformed album artwork | Procedural graphics |
| **Effect Count** | 30 built-in effects | 100s of presets available |
| **Customization** | Intensity adjustment | Full preset ecosystem |
| **GPU Tech** | Core Image (Metal) | OpenGL shaders |
| **Audio Response** | Spectrum bands (bass/mid/treble) | PCM waveform + beat detection |
| **Best For** | Album art appreciation | Immersive light shows |

### When to Use Each

**Album Art Visualizer**
- When you want to see the album artwork
- For a more subtle, integrated experience
- When browsing your music library

**ProjectM/Milkdrop**
- For full-screen immersive visualizations
- Classic Winamp nostalgia
- Parties and ambient displays
- When you want maximum visual variety

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

### ProjectM/Milkdrop

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
