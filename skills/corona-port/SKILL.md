---
name: corona-port
description: Implementation reference for NullPlayer's Corona visualization engine — libvisual's GPL-2.0-or-later port of the Sonique-era Corona plugin (Richard Ashburn), vendored behind a small C++ shim and rendered as a CPU RGBA frame blitted into the Visualizations window. Covers the CCoronaCore layout and ABI, the upstream edits, the host-spectrum feed, palettes as presets, Blaze, threading, licensing and gotchas. Use when modifying anything under Sources/CCoronaCore/, CoronaEngine.swift, or the Corona case of the engine factory, preset seam or context menu.
---

# Corona Port Guide

Corona is a visualization engine in the Visualizations window, picked from the right-click
**Visualization Engine** submenu. Particles rise as flames, swirl on beats and fall back, over a
warped, blurred trail and a rippling reflection along the bottom fifth. It is libvisual's
`actor_corona` (libvisual-plugins, `corona.cpp` 1.10, 2006; `https://github.com/Libvisual/libvisual`),
itself a port of Richard Ashburn's Corona for Sonique. The source came as a zip
(`Phthalo's Corona Source Code.zip`) identical to libvisual's files.

A `.wal` skin's visualization box shows it too (it follows the shared engine preference), but the
`.wmz` / Sonique effects list (`SkinEffectSelection.catalogue`) has no Corona entry, as it has no Goom.

## File layout

| Path | Role |
|------|------|
| `Sources/CCoronaCore/upstream/` | `corona.{cpp,h}`, `corona_types.h`, `palette.{cpp,h}`, `autopal.h`, with the edits below. |
| `Sources/CCoronaCore/include/CoronaCore.h` | The C ABI Swift imports: create/destroy, `update` (spectrum in, RGBA out), `setPalette`, `paletteName`, `setBlaze`. |
| `Sources/CCoronaCore/CoronaCore.cpp` | The shim, adapted from libvisual's `actor_corona.cpp`: owns a `Corona`, a `PaletteCycler`, the `TimedLevel` and the RGBA buffer; the palette table (`#include "autopal.h"`) and its names. |
| `Sources/NullPlayer/Visualization/CoronaEngine.swift` | `VisualizationEngine` conformance, GL upload + blit, the held palette, the Blaze menu item. |
| `Tests/NullPlayerAppTests/CoronaCoreSmokeTests.swift` | A loud spectrum lights the frame; a held palette (White, a grey ramp) is the only one drawn over 600 frames; every palette is named. |

`Package.swift` builds `CCoronaCore` as C++ with `-O2` in debug too (a software renderer, like
`CGoomCore`).

### Upstream edits

Each edited file carries a dated "Modified for NullPlayer" notice under its `$Id` line, as GPL-2
§2(a) requires; extend it with any further edit.

1. libvisual removed: `visual_mem_*` → `memset`/`memcpy`, `updateVisPalette` gone (the shim reads
   `getPalette()`), and the x86 MMX branch of `blurImage` dropped (its C loop is what ran on arm64).
2. `~Corona` also frees `m_particles` and `m_reflArray`, which upstream leaked; the engine recreates
   the core on every resize.
3. `Corona::setPreset`/`getPreset`: libvisual never let a host leave `PRESET_CORONA`.
4. `PaletteCycler::holdPalette(i, fade)`: fades (or switches) to palette `i` and stops the random
   palette changes in `update`. `startPaletteTransition` takes its target instead of rolling it.

## Palettes are the presets

`actor_corona.cpp` carries 23 palettes; `autopal.h` in the same source has 31 and fixes the two
"lines" rows, whose counts claimed 8 checkpoints for 6 pairs. The shim uses `autopal.h`. Names 0–22
are libvisual's comments; 23–30 had none and are named after their colours.

Corona is always held on the chosen palette (`CoronaEngine.palette`, key `corona.palette`), applied
without a fade to each new core and with Corona's own fade when the user or the cycler picks one.
The shared `VisualizationPresetCycler` changes it (default Auto-Random, 30 s). Through the preset
seam (`VisualizationGLView+Presets.swift`) the palettes are the Presets list and → / ← / R.

**Blaze** (`corona.blaze`) is Corona's own menu item (`CoronaEngine.addMenuItems`): upstream's
`PRESET_BLAZE`, which draws the particles three times a frame (before and after the warp, then
velocity-capped after the blur) and uses the heavier warp fade on canvases under 150,000 px.

Both keys are in `VisualizationPreferences`' reset list.

## Audio

Corona reads only a spectrum: Sonique's `unsigned char[2][512]`, of which it uses channel 0. The
host's 256-bin Geiss spectrum (`VisualizationGLView.updateHostSpectrumFromPCM`, sent to every engine
whose type has `consumesHostSpectrum`) is scaled 0...1 → 0...255 and each bin doubled, as libvisual's
wrapper did. libvisual multiplied its 0...1 floats by 32768 into those `unsigned char`s, which
overflows; the port feeds the range Sonique did.

Beats (`getBeatVal`): the sum of bins 50–249, divided by 3, above 1.2× its running average and at
least 1,000, and 750 ms after the last. `elapsedMs` (the time since the previous update, capped at
1 s) drives that clock.

## Rendering and threading

- One update per 1/60 s at most (`updateInterval`): upstream moves the particles one fixed step per
  call. The canvas is half the drawable, at most 1,024 wide and at least 32×32.
- The shim maps the 8-bit surface through the current palette into RGBA; Swift uploads it and blits
  it with `GL_LINEAR`. Corona's row 0 is the bottom, as GL's is, so the blit is not flipped (Goom's is).
- A new canvas size makes a new core (as `lv_corona_dimension` does), then reapplies palette and Blaze.
- `lock` guards the core, spectrum, palette and Blaze (audio thread, render thread, main's menu).
  Cores are independent instances; the only shared state is libc `rand()`, so two hosts may both run
  Corona (unlike Geiss's one-owner core).

## Licensing

GPL-2.0-or-later, used under GPL-3.0 (NullPlayer's licence). Every upstream file keeps its header;
`CoronaCore.cpp` keeps `actor_corona.cpp`'s with an adaptation note. The notices entry is the
`corona` row of `scripts/third_party_components.tsv` (regenerate with
`scripts/generate_third_party_notices.sh`). README credits it under *Native ports*.

## Gotchas

- **Index 0 is the background.** Most of the surface is 0, so a palette whose first checkpoint is
  white (Black on White, Clouds, …) draws on white. That is upstream's look, not a bug.
- **A freshly made core is dark** until particles have been drawn and a beat lands; capture a few
  times over ~10 s before calling it black.
- **`NB_PALETTES` is the row width**, not the palette count: every palette row is 23 ints, padded
  with zeros. The count is `paletteCount` in the shim, tied to `CORONA_CORE_PALETTE_COUNT` and the
  name table by `static_assert`s.

## Debugging a live defect

Read [`live-ui-testing`](../live-ui-testing/SKILL.md) and `winamp-modern-skin-guide/reference/harness.md`
§ *Debugging a live defect* first. Launch with the engine and a palette preset:
`skills/app-control/scripts/launch.sh modern:NeonWave -- -visualizationEngineType Corona -corona.palette 0 -corona.blaze YES`,
then Visuals → Visualizations → Show Visualizations Window; the log shows `Setting up Corona with
viewport WxH`.
