---
name: visualizations
description: Index of NullPlayer's visualization systems. Use this to discover which sub-skill covers the specific visualizer you're working on (main window vis, spectrum window, album art, ProjectM/MilkDrop, Geiss, Tripex, Met Museum, vis_classic, Metal mode internals).
---

# NullPlayer Visualization Systems — Index

NullPlayer has several visualization stacks. Each has its own skill; this file is a router. Open the relevant sub-skill for details.

The standalone waveform window is **not** a Metal visualization mode. It reuses audio waveform notifications and the cache service. Do not treat it as part of this stack.

## Persistence and Reset Policy

Visualization choices are durable `UserDefaults` preferences, not AppState session fields. AppState only remembers quit-session state such as window visibility/layout and playlist/audio state.

- Main-window, Spectrum-window, Visualizations-window, `vis_classic`, and browser artwork visualizer settings must remain resettable through `VisualizationPreferences`.
- Modern/metal skin `visualization` defaults are first-use defaults on app launch. They may seed missing keys, but must not overwrite user-selected mode/style/profile keys during a normal relaunch.
- Explicit skin changes and **Reset Skin to Default** still reapply the selected skin's visualization defaults.
- When adding a new visualization preference that can be hard to recover manually, add it to the appropriate `VisualizationPreferenceResetScope`.

## Sub-Skills

| Skill | Scope |
|-------|-------|
| [main-window-visualization](../main-window-visualization/SKILL.md) | The 76×16 main-window display area: 11 modes, switching, mode-specific settings |
| [spectrum-analyzer-window](../spectrum-analyzer-window/SKILL.md) | Dedicated 84-bar spectrum window: docking, geometry, mode list, the cropped analyzer curve, vis_classic waveform demand |
| [audio-analysis-window](../audio-analysis-window/SKILL.md) | Friture-style multi-pane Audio Analyzer window: Scope/Levels/Spectrogram/Octave/Pitch/Delay panes, stereo PCM + FFT-magnitudes paths, per-pane consumer gating, AudioAnalysisDSP module |
| [peppymeter](../peppymeter/SKILL.md) | Skinnable analog VU meter window (PeppyMeter port): needle/bar meters composited from meters.txt templates, driven by the stereo tap. A CoreGraphics-skinned meter, **not** a Metal visualization mode |
| [gpu-vis-modes](../gpu-vis-modes/SKILL.md) | Per-mode internals shared by both windows: Fire, JWST, Lightning, Matrix, Snow, EKG, Classic/Enhanced/Ultra |
| [album-art-visualizer](../album-art-visualizer/SKILL.md) | Library Browser ART-mode effects (30 Core Image filters) |
| [projectm-milkdrop](../projectm-milkdrop/SKILL.md) | ProjectM/MilkDrop preset engine in the visualization window |
| [met-museum-visualizer](../met-museum-visualizer/SKILL.md) | Met Museum public-domain artwork slideshow engine |
| [geiss-port](../geiss-port/SKILL.md) | Geiss engine — port architecture, ABI, configuration |
| [tripex-port](../tripex-port/SKILL.md) | Tripex (ben-marsh/tripex) port — D3D9→OpenGL, C ABI |
| [vis-classic-guide](../vis-classic-guide/SKILL.md) | vis_classic exact-port analyzer core |
| [metal-gotchas](../metal-gotchas/SKILL.md) | Metal command-encoder pitfalls, render-to-texture y-flip, spectrum jitter |

## Comparison

| Feature | Album Art | ProjectM | Geiss | Tripex | Met Museum | Spectrum Window |
|---------|-----------|----------|-------|--------|------------|-----------------|
| **Visual Style** | Transformed artwork | Procedural shaders | Indexed framebuffer + palette | 3D Winamp-era effects | Public-domain artwork slideshow | Bars / vis_classic / Fire / JWST / Lightning / Matrix / Snow / EKG |
| **Effect Count** | 30 built-in | 100s of presets | 25 modes | Upstream effect set | N/A | 10 modes |
| **Customization** | Intensity | Full preset ecosystem | Effect selection | Effect / cycle / intensity | Department / interval / transition / aspect | Mode + decay + style presets |
| **GPU Tech** | Core Image (Metal) | OpenGL shaders | OpenGL palette LUT | OpenGL geometry | OpenGL textured quad | Metal shaders + compute |
| **Audio Response** | Spectrum bands | PCM + beats | PCM + 256-bin host spectrum | PCM-driven internal FFT | Optional zoom/pan + beat advance | 75-band spectrum / energy |

### When to use each

- **Album Art** — subtle, integrated, browsing the library
- **ProjectM** — immersive full-screen, classic Winamp nostalgia
- **Geiss** — classic Geiss look, low-level palette effects
- **Tripex** — Winamp-era 3D, no preset files needed
- **Met Museum** — calm gallery slideshow with optional audio reactivity
- **Main Window Vis** — quick access without a separate window
- **Spectrum Window** — detailed 84-bar frequency view + ambient modes (Fire/JWST/etc.)
