---
name: visualizations
description: Index of NullPlayer's visualization systems. Use this to discover which sub-skill covers the specific visualizer you're working on (main window vis, spectrum window, album art, ProjectM/MilkDrop, Geiss, Tripex, AVS, Goom, Corona, Smear, NullPlayer-Fractal, vis_classic, Metal mode internals).
---

# NullPlayer Visualization Systems — Index

NullPlayer has several visualization stacks. Each has its own skill; this file is a router. Open the relevant sub-skill for details.

The standalone waveform window is **not** a Metal visualization mode. It reuses audio waveform notifications and the cache service. Do not treat it as part of this stack.

## The engine suite is global: no per-family permission

The visualization engines and their shared seams (`Visualization/`: the engines, the preset seam, the
shared menu, the cycler) are one app-wide feature that every skin family's host runs. A change there
is a global change, **exempt** from CLAUDE.md's rule that a change affecting more than one skin family
needs the user's permission first (the user's ruling, 2026-11-12). Verify it in each host anyway.

## Engine presets: one seam

Each engine answers `VisualizationEngine`'s preset requirements (`presetCount`, `presetIndex`,
`presetName(at:)`, `selectPreset`, `stepPreset(forward:)`, `randomPreset`, and `addMenuItems` for its own menu
items), and `VisualizationGLView+Presets.swift` forwards to the running engine. Every host (the
Visualizations window's keys, the `.wal` slot, the `.wmz` and Sonique effects areas) calls the seam
and never switches on the engine. A new engine adds nothing outside its own files and
`VisualizationGLView.createEngine`; the `.wmz` / Sonique catalogue lists it as `.engine(type)`.
An engine that persists its choice does it in its own preset methods (Tripex's `lastEffectIndex`).
Every host shares one saved choice per engine (AVS's `avs.presetPath` included), as they share the
cycle settings: the last preset chosen anywhere is what each restores.
An engine's own menu items target the engine itself, so no host carries engine-specific actions.
`VisualizationGLView`'s `projectMPreset*` / `selectProjectMPreset` members are ProjectM-only (its
ratings, a UI-switch restore, the main menu's preset list); anything meant for every engine goes
through the seam.

## Context menu and auto-cycle: one menu, one timer

`VisualizationContextMenu.build` gives every engine in every host the same menu: `Preset: name
(i/n)`, Next / Previous / Random (R) and the Presets list (built from the seam above), then Manual
Only / Auto-Cycle (C) / Auto-Random / Cycle Interval, then **that engine's own items**, then
Visualization Engine, Audio Sensitivity, Quality, Fullscreen, Close. A host with its own engine
picker leaves Visualization Engine out (`Options.showsEnginePicker`): the `.wmz` / Sonique slot,
whose Effect menu lists the engines among its own effects, once showed both. An engine's own items are only
what no other engine has: ProjectM's default / rating / favorites (its preset titles carry stars),
Geiss's config and Tripex's settings (`GeissEngine+Menu.swift`, `TripexEngine+Menu.swift`), AVS's editor and
folder (`AvsEngine.addMenuItems`), Corona's Blaze (`CoronaEngine.addMenuItems`), Fractal's Render Scale (`FractalEngine.addMenuItems`), nothing for Goom or Smear. A new engine needs no menu code for the shared
block.

- **The shared block targets the `VisualizationGLView`** (`nextPresetMenuAction` etc., in
  `VisualizationGLView+Presets.swift`), so no host repeats preset or cycle actions. Every preset
  change made through the seam (keys, menu, cycler) calls `enginePresetDidChange`; the ProjectM
  windows close their rating overlay there.
- **`VisualizationPresetCycler` is the only thing that auto-advances an engine.** It is owned by the
  GL view; the mode and interval are per engine (`VisualizationCycleSettings`, keys
  `<engine>.cycleMode` / `.cycleInterval`) and shared by every host. Whoever drives the engine
  calls `start()` / `stop()` (`startRendering` / `stopRendering`); `switchEngine` and a new mode or
  interval only re-read the settings (`restart()`), so they never start a stopped cycler. The
  `.wmz` / Sonique surface never starts a display link, so it calls `presetCycler.start()` itself.
- **Every engine's own switching is held at creation** (`VisualizationGLView.createEngine`): Tripex
  `setHold(true)`, Geiss `modeLocked = true`, Goom always held on its chosen effect, Corona always
  held on its chosen palette, Smear on its chosen move script. Manual Only
  therefore means the engine stays put; there are no per-engine Hold / Mode Lock / Auto-Switch items.
- Defaults: ProjectM and AVS Manual Only, Tripex Auto-Cycle, Geiss, Goom, Corona, Smear and Fractal Auto-Random
  (they used to switch on their own); 30 s. Tests: `VisualizationCycleSettingsTests`.

## Software engines' canvas: one rule

Geiss, AVS, Corona and Smear render on the CPU in pixel units, so a small canvas shows a coarse close-up
of the scene. `SoftwareCanvas.atLeastMinimum` (`VisualizationEngine.swift`) raises a viewport
narrower than 400 px to that width at its aspect, and each engine shrinks its frame into the
viewport: a skin's effects slot (Sonique's top circle is 182×176 px) shows the whole scene small.
The scaled height stops at `maxScaledHeight` (1,600 px), so a viewport over 4:1 tall is drawn at
another aspect rather than as a 400×240,000 canvas (a 1×600 viewport).
Measured 2026-11-12 offscreen at 182 and 400 px with the same audio and preset: Geiss's waveform
ran off both edges at 182, and AVS's strokes were twice as thick. ProjectM and Tripex are
resolution-independent and Goom is not offered to the `.wmz` / Sonique effects surface (a `.wal`
visualization box hosts the user's engine, Goom included); none of them uses it.

## Standard keys: one seam

Every window that shows a visualization answers the same keys, defined once in
`Visualization/VisualizationKeys.swift` (`VisualizationKey`): **⌘↓ / ⌘↑ step the engine** (a
main window's mode, the Spectrum window's mode, the `.wmz` / Sonique effect, Art's effect group) and
**⌘→ / ⌘← step the preset inside it** (an engine's presets, a mode's style, a vis_classic profile,
Cava's colour preset or channel mode, an Art effect). ⇧ added is a hard cut where an engine blends.
Plain arrows stay each window's own: seek and volume on every main window, presets in the
Visualizations and Spectrum windows, effect and intensity in Art.

| Window | ⌘↓ / ⌘↑ | ⌘→ / ⌘← |
|---|---|---|
| Classic / Original main window | `MainWindowVisMode.advanced(by:)` | `MainWindowVisStyle.step`, vis_classic via the overlay |
| `.wal` hosted visualization | `WindowManager.switchVisualizationEngine` (the shared preference) | the engine's presets |
| `.wmz` / Sonique `<EFFECTS>` | `SkinEffectsSurfaceView.handleKeyDown` (effect) | within the effect |
| Visualizations window | `VisualizationType.advanced(by:)` | presets (its plain arrows) |
| Spectrum window | `SpectrumQualityMode.advanced(by:)` | style / profile (its plain arrows) |
| Art window | `ArtVisEffect.advancedGroup(by:)` | `ArtVisEffect.advanced(by:)` |
| Audion | no visualization: the keys do nothing | |

- **A ⌘-arrow is never seek or volume**, even in a main window with nothing to visualize:
  `MainWindowKeys.performArrow` refuses it.
- **No visualization menu item carries an arrow key equivalent.** The menu bar's Visuals →
  Visualizations copies the live Visualizations window's context menu, so an arrow equivalent on
  any item `VisualizationContextMenu` or an engine's `addMenuItems` builds becomes app-wide: key equivalent
  routing gave every ⌘→ in the app to the Visualizations window — and a stale copy kept eating it
  after that window closed — so the key window never saw it. The Next / Previous items therefore
  show no shortcut.
- **The effects surface (`.wmz`, Sonique) takes only ⌘-arrows** (`SkinEffectsSurfaceView.handleKeyDown`
  parses `VisualizationKey`), so its host offers it every key after its own plain arrows.
- Tests: `Tests/NullPlayerAppTests/VisualizationKeysTests.swift`.

## Persistence and Reset Policy

Visualization choices are durable `UserDefaults` preferences, not AppState session fields. AppState only remembers quit-session state such as window visibility/layout and playlist/audio state.

- Main-window (including embedded Cava), Spectrum-window, Visualizations-window, `vis_classic`, and browser artwork visualizer settings must remain resettable through `VisualizationPreferences`.
- Modern/metal skin `visualization` defaults are first-use defaults on app launch. They may seed missing keys, but must not overwrite user-selected mode/style/profile keys during a normal relaunch.
- Explicit skin changes and **Reset Skin to Default** still reapply the selected skin's visualization defaults.
- When adding a new visualization preference that can be hard to recover manually, add it to the appropriate `VisualizationPreferenceResetScope`.

## Sub-Skills

| Skill | Scope |
|-------|-------|
| [main-window-visualization](../main-window-visualization/SKILL.md) | The 76×16 main-window display area: 12 modes, switching, mode-specific settings |
| [spectrum-analyzer-window](../spectrum-analyzer-window/SKILL.md) | Dedicated 84-bar spectrum window: docking, geometry, mode list, the cropped analyzer curve, vis_classic waveform demand |
| [audio-analysis-window](../audio-analysis-window/SKILL.md) | Friture-style multi-pane Audio Analyzer window: Scope/Levels/Spectrogram/Octave/Pitch/Delay panes, stereo PCM + FFT-magnitudes paths, per-pane consumer gating, AudioAnalysisDSP module |
| [peppymeter](../peppymeter/SKILL.md) | Skinnable analog VU meter window (PeppyMeter port): needle/bar meters composited from meters.txt templates, driven by the stereo tap. A CoreGraphics-skinned meter, **not** a Metal visualization mode |
| [cava](../cava/SKILL.md) | cava-style bar spectrum in both the standalone window and main-window inline area (clean-room Swift/vDSP port): dual bass/treble FFT → log bands, CoreGraphics gradient bars, scoped skin-following colors + tuning. A CoreGraphics meter driven by the full-rate stereo tap, **not** a Metal mode |
| [gpu-vis-modes](../gpu-vis-modes/SKILL.md) | Per-mode internals shared by both windows: Fire, JWST, Lightning, Matrix, Snow, EKG, Classic/Enhanced/Ultra |
| [album-art-visualizer](../album-art-visualizer/SKILL.md) | The Art window: playing cover, rating, and VIS (30 Core Image effects) |
| [projectm-milkdrop](../projectm-milkdrop/SKILL.md) | ProjectM/MilkDrop preset engine in the visualization window |
| [geiss-port](../geiss-port/SKILL.md) | Geiss engine — port architecture, ABI, configuration |
| [tripex-port](../tripex-port/SKILL.md) | Tripex (ben-marsh/tripex) port — D3D9→OpenGL, C ABI |
| [avs-port](../avs-port/SKILL.md) | AVS (grandchild/vis_avs libavs) — CAvsCore, EEL2 JIT, stereo feed, presets, every host |
| [goom-port](../goom-port/SKILL.md) | Goom (j3k0/goom Goom2k26 C core) — CGoomCore shim, RGBA blit, 30/s cadence, forced effects, the port's own effects (Heart, Pentagram etc.) |
| [corona-port](../corona-port/SKILL.md) | Corona (libvisual's port of the Sonique visualizer) — CCoronaCore shim, host spectrum, RGBA blit, palettes as presets, Blaze |
| [smear-port](../smear-port/SKILL.md) | Smear (mykel and xplo's Sonique visualizer) — CSmearCore Stutter interpreter and renderer, bundled scripts, move scripts as held presets |
| [fractal-vis](../fractal-vis/SKILL.md) | NullPlayer-Fractal, the app's own engine — GLSL raymarched and 2D fractal scenes, beat-synced director, adaptive render scale, camera shots, headless render harness |
| [vis-classic-guide](../vis-classic-guide/SKILL.md) | vis_classic exact-port analyzer core |
| [metal-gotchas](../metal-gotchas/SKILL.md) | Metal command-encoder pitfalls, render-to-texture y-flip, spectrum jitter |
| [visualization-cast](../visualization-cast/SKILL.md) | **Cast Visualization ▸** — the Visualizations window's picture and the app's audio live to a Chromecast or DLNA TV; the GL readback seam, encoder, playlist, quality limits |

## Comparison

| Feature | Album Art | ProjectM | Geiss | Tripex | Fractal | Spectrum Window |
|---------|-----------|----------|-------|--------|---------|-----------------|
| **Visual Style** | Transformed artwork | Procedural shaders | Indexed framebuffer + palette | 3D Winamp-era effects | Raymarched 3D and 2D fractals | Bars / vis_classic / Fire / JWST / Lightning / Matrix / Snow / EKG |
| **Effect Count** | 30 built-in | 100s of presets | 25 modes | Upstream effect set | 11 scenes | 10 modes |
| **Customization** | Intensity | Full preset ecosystem | Effect selection | Effect / cycle / intensity | Scene / cycle / render scale | Mode + decay + style presets |
| **GPU Tech** | Core Image (Metal) | OpenGL shaders | OpenGL palette LUT | OpenGL geometry | GLSL 330 + HDR feedback | Metal shaders + compute |
| **Audio Response** | Spectrum bands | PCM + beats | PCM + 256-bin host spectrum | PCM-driven internal FFT | Beats + BPM + 256-bin host spectrum | 75-band spectrum / energy |

### When to use each

- **Album Art** — subtle, integrated, browsing the library
- **ProjectM** — immersive full-screen, classic Winamp nostalgia
- **Geiss** — classic Geiss look, low-level palette effects
- **Tripex** — Winamp-era 3D, no preset files needed
- **AVS** — Winamp's Advanced Visualization Studio presets (`.avs`), scripted effects included
- **Goom** — the XMMS-era zoom/tentacle/star-field effect that picks its own look from the music
- **Corona** — Sonique-era particle flames swirling over a rippling reflection, in 31 palettes
- **Smear** — Sonique-era G-Force-style feedback: 60 scripted move maps, with scripted colours, waveforms and particles
- **NullPlayer-Fractal** — slow, beat-locked flights through 3D fractals (Mandelbulb, Menger, Apollonian, an alien planet) and 2D zooms
- **Main Window Vis** — quick access without a separate window
- **Spectrum Window** — detailed 84-bar frequency view + ambient modes (Fire/JWST/etc.)
- **Cava** — responsive bar spectrum with gravity/autosens and skin-matched gradient colors; use mono inline in the main window or mono/stereo in the dockable standalone window
