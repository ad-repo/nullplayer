---
name: goom-port
description: Implementation reference for NullPlayer's Goom visualization engine — the LGPL-2.1 Goom2k26 C core (j3k0/goom) vendored behind a small C shim, plus the port's own Spiral/Vortex/Flower/Heart/Pentagram/Ooh-Ugh effects and heart/star scopes, and rendered as a CPU RGBA frame blitted into the Visualizations window. Covers the CGoomCore layout and ABI, the upstream edits, the 30-per-second update cadence, the audio feed, threading, the effect menu, licensing and gotchas. Use when modifying anything under Sources/CGoomCore/, GoomEngine.swift, or the Goom case of the engine factory, preset seam or context menu.
---

# Goom Port Guide

Goom is a visualization engine in the Visualizations window, picked from the right-click
**Visualization Engine** submenu beside ProjectM, Geiss, Tripex and AVS. It is the pure-C effect
core of **Goom2k26** (`https://github.com/j3k0/goom`, pinned at
`e4fc3550457cf5a5b194fa9ec8219d3f1e78acc7`), the 2026 revival of Jean-Christophe Hoelt's
XMMS-era Goom. Only `Goom/` is vendored; upstream's SDL front-end, Fovea engine (`gametools/`,
`iosfc/`) and `libs/` are not.

It is also an effect in the `.wmz` and Sonique effects areas (`SkinEffectSelection.catalogue`),
rendered offscreen there like the other GL engines.

## File layout

| Path | Role |
|------|------|
| `Sources/CGoomCore/upstream/` | Upstream `Goom/*.c` and `*.h` with the port edits below, plus `LICENSE` and `COPYING.README` (excluded from the build). `goom_core.c`, `sound_tester.c` and `goom_filters.h` are ISO-8859-1, not UTF-8 — grep them with `LC_ALL=C grep -a`, or matches are silently missed. |
| `Sources/CGoomCore/include/GoomCore.h` | The C ABI Swift imports. Upstream's headers stay private: `goom_config.h` `#define`s `guint32` and friends, which would leak into Swift. |
| `Sources/CGoomCore/GoomCore.c` | The shim: owns a `PluginInfo *` and a pending forced mode (create returns NULL when `goom_init` fails); the effect-name table. |
| `Sources/NullPlayer/Visualization/GoomEngine.swift` | `VisualizationEngine` conformance, GL upload + blit, effect selection, its context-menu section. |
| `Tests/NullPlayerAppTests/GoomCoreSmokeTests.swift` | Lit frames, a forced effect landing (an upstream one and the last of the port's), Ooh/Ugh staying red, black and white, a second core after the first, and a held effect surviving 1,500 cycles of loud beats, against a control run in which the same input must change effect. |

`Package.swift` builds `CGoomCore` as C with `-O2` (debug too — it is a software renderer, like
libavs; a 1024-wide frame takes about 1.5 ms) and silences only the two warning kinds upstream
raises, `-Wno-gnu-designator` and `-Wno-absolute-value` (`abs()` on a float in `tentacle3d.c`,
which upstream's look depends on), so a warning in the port's own code still shows. `zoom_filter_neon.c` is `#if defined(__aarch64__)` upstream, and
`plugin_info.c` selects it on arm64 and the C `zoom_filter_c` elsewhere.

### Upstream edits

Nine upstream files are edited (plus the port's own `ooh_ugh.{h,c}` beside them): `filters.c`, `gfontlib.c`, `goom_core.c`, `goom_filters.h`,
`goom_plugin_info.h`, `goom.h`, `lines.c`, `lines.h`, `plugin_info.c`. Each opens with a dated
"Modified for NullPlayer" notice summarising its change, as LGPL-2.1 §2(a) requires; a further
edit to any upstream file adds or extends that notice. `diff -r` against a checkout of the pinned
commit's `Goom/` shows exactly what changed.

1. `gfontlib.c` `gfont_load` returns early once the font is built. Upstream calls it from every
   `goom_init` and allocates fresh process-wide arrays each time, leaking the previous ones; the
   port recreates the core on every resize and engine switch.
2. **Five effects of the port's own** — Spiral, Vortex, Flower, Heart, Pentagram (modes 10–14,
   every edit marked `NullPlayer port`). They are original work, not upstream's:
   - `goom_filters.h` defines them and `NB_ZOOM_MODES`; `goom.h` raises `NB_FX` (15 then, 16 with Ooh/Ugh); the
     "Zoom Mode" feedback param's max follows. The shim's name table is indexed by the `*_MODE`
     constants, and a `_Static_assert` ties its size, `NB_FX` and `NB_ZOOM_MODES` together.
   - `filters.c` `zoomVector`: each bends the radial zoom. Spiral and Vortex add a `spin` (a
     rotation, constant for Spiral, strongest at the eye for Vortex); Flower modulates the speed
     with `sin(5θ)`; Heart ripples it with `sin(12h)`, where `h = sqrt(x² + (-y - |x|)²)` has
     heart-shaped level sets (screen Y grows downwards, hence `-y`); Pentagram ripples it with
     `sin(14h)`, where `h` scales a point-up pentagram through the point — the angle is folded
     into half a point and `h` is the point's projection on that sector's edge normal, divided by
     the tip's, so the level sets are stars with sharp tips.
   - `goom_core.c`: the random mode roll goes from 34 to 44 outcomes (46 with Ooh/Ugh), two each for the new modes,
     so upstream's own modes come up a little less often. `settle_port_mode`, run whenever the
     zoom changes (random or forced), centres the new modes and clears the plane, noise, wave and
     hypercos add-ons, which smear them.
3. **Heart and star scopes**, `GML_HEART` and `GML_PENTAGRAM` (`lines.{h,c}`). The heart is the
   classic heart curve, point *i* put where the circle's point *i* is, so the waveform morphs
   between circle and heart. The star is drawn in one stroke, corner to every second corner, and
   the waveform pushes each edge along its normal. Goom's random shape roll (`choose_a_goom_line`)
   includes both; in Heart or Pentagram mode it always picks that mode's shape. Entering Heart
   switches both scope lines to hearts (new `GML_ROSE` and `GML_RED`); entering Pentagram makes
   a pentacle — a star (new `GML_CRIMSON`) and a circle through its points (`GML_ORANGE_V`).
   Both turn the scope on. Goom still drops the scope when its state has none (`drawScope`), as
   for every shape.
4. **Hold**: `update.holdMode` (`goom_plugin_info.h`, zeroed in `plugin_info_init`) skips the
   random mode roll in `goom_update` — the only place Goom changes the mode itself. Speed, centre,
   scope, colours and the kaleidoscope add-on keep following the music; a forced mode still lands.

5. **Ooh/Ugh** (`OOH_UGH_MODE`, 15), the port's own heavy-metal effect. Unlike the other port
   modes it draws: `Sources/CGoomCore/ooh_ugh.{h,c}` (outside `upstream/`, so `goom_core.c`
   includes `"../ooh_ugh.h"`) holds its emitters and state (`update.oohUgh`, freed in
   `goom_close`). `NB_FX` and `NB_ZOOM_MODES` are 16, and the random mode roll has 46 outcomes.
   - **Scenes**: five (`OOH_SCENES`): throat, maelstrom, pyre, rift and vortex. Each one is a flow field in
     `filters.c` (switching on `ZoomFilterData.oohScene`, which the wrapper copies) and a row in
     `ooh_ugh.c`'s `scenes` table, by the same index. A row sets the abyss (the zoom's middle) and the
     mix of emitters. `filters.c` gained a `lift` term, an upward drift in `vy`.
     `ooh_ugh_scene` runs every cycle before Goom's forced-effect check. It restates the scene's
     config, because Goom moves the middle and delivers unsettled configs on its own beats. On a
     scene change it returns 1, so `goom_update` delivers the zoom and Goom morphs the flow. The
     emitters then cross-fade over `MORPH_CYCLES`. The vortex is a tunnel: it sets its own
     outward rush (`coefVitesse`, growing with distance) instead of adding to Goom's, which was
     too slow to carry anything past Goom's fade, and its eye throws sparks at random angles (fixed
     spokes read as a pinwheel). A descent scene (ash sinking, no fire) was dropped as too sparse.
   - **Sparse**: in this mode `goom_core.c` skips the IFS, the point loops, the tentacles and the
     scope lines. `ooh_ugh_settle` also clears the kaleidoscope add-on: folded around an off-centre
     abyss, it floods the screen red.
   - **Burn line**: the undrawn line the fire burns from (`burn_at`). It is turned about the
     screen's middle (`ang`) at a distance (`reach`), and both pick new targets on a scene change,
     every ~300 cycles, and on some big hits. It is never turned past the sides: hung from the top,
     the fire lifts off screen and leaves it black; held near the bottom, it reads as a fixed horizon,
     which the user rejected twice. `ooh_ugh_finish` darkens what lies behind it.
   - **Drawing**: `ooh_ugh_draw` draws fire and smoke along the burn line, plus wraiths,
     ash and a rare, broken sigil (an inverted pentacle, a goat, a sword or an inverted cross). It
     draws into `p2` before the zoom. `ooh_ugh_finish` maps the output frame after convolve:
     the brightest channel goes through a red LUT, the dimmest through a white LUT, and a vignette
     is applied. So the frame is red, black and white only: `g == b <= r`, which a smoke test checks.
     No kick rings and no glow round the abyss: the user rejected both the concentric circles and
     the round, pulsing orb. Instead, kicks multiply the whole red ramp and add a faint wash that
     only the vignette shapes, and a big hit flashes the hottest fire white.
   - **Low end**: `ooh_ugh_draw` low-passes the PCM (about 120 Hz) into `bass`, measured against its
     recent peak but never below an absolute floor (6000 RMS), so thin rock bass doesn't read as a
     doom drone and flatten the kicks. `bass` heaves the burn line, grows and heats the flames and
     swells the flare. The **souls** are up to six faint, wavering skulls and goat heads rising out of the
     fire, more on kicks, big hits and heavy bass. They use their own shapes (`SOUL_SKULL`,
     `SOUL_GOAT`): the sigil goat's spread horns and ears read as a bird, so the soul goat's horns
     climb straight up. The hottest white (g > 120) cools
     each cycle, so a held drone can't pile it into a white sky; kick flashes stay below that line.

Tuning the new effects is by eye: render them with a scratch C harness that forces the mode every
20 updates and writes PPMs, rather than relaunching the app.

## ABI

```c
GoomCore *GoomCore_create(int width, int height);
void GoomCore_destroy(GoomCore *core);                       // NULL-safe
const uint32_t *GoomCore_update(GoomCore *core, const int16_t *pcm);  // pcm: 512 L then 512 R
void GoomCore_forceEffect(GoomCore *core, int index);        // 0..GOOM_CORE_EFFECT_COUNT-1
void GoomCore_setHold(GoomCore *core, int hold);             // Goom stops changing effect itself
int GoomCore_currentEffect(const GoomCore *core);
const char *GoomCore_effectName(int index);
```

`GoomCore_update` calls `goom_update(info, pcm, forceMode, fps: 0, songTitle: NULL, message:
NULL)`, so Goom draws no text (no fps counter, no title). The returned buffer is the core's
(`outputBuf`), valid until the next update.

## Render pipeline

- **Canvas**: half the viewport width, at most 1024, height in proportion — upstream
  `GoomWidget.cpp`'s desktop rule. The frame is blitted scaled to fill with `GL_LINEAR`, flipped
  (Goom row 0 is the top), into whatever framebuffer the host has bound — the same blit as
  `AvsEngine`.
- **Cadence**: one `GoomCore_update` per 1/30 s; display-link frames in between re-blit the last
  texture. Goom's motion is per cycle and upstream ticks it at 30 per second, so updating every
  60 Hz frame would run it at double speed.
- **Pixels**: `COLOR_RGBA` — bytes R, G, B, A in memory (the `Pixel.channels` struct; ignore the
  `R_OFFSET 24` macros). Uploaded as `GL_RGBA` into `GL_RGB8` storage, which drops the alpha byte
  Goom leaves unset (upstream forces it to 0xFF on the CPU).
- **Resize**: a new canvas size destroys and recreates the core. Upstream's
  `goom_set_resolution` reallocates the frame buffers but not the zoom filter's own state.
- **Minimum size**: `renderFrame` skips any frame whose core would be under 16 px a side
  (`minRenderSide`). Upstream bounds-checks with unsigned `x < screen.width - 2`, so a core under
  2 px wraps that to ~4 billion and `pointFilter` writes far outside its buffer — a crash seen when
  a `.wmz` effects pane collapsed to a few points mid-layout (2026-11-18).

## Audio

`addPCMMono` receives the host's 512 mono samples (the window's Audio Sensitivity gain already
applied) and writes them as int16 into both channels. Goom does its own analysis
(`sound_tester.c`); there is no host spectrum. True stereo would mean taking the full-rate stereo
feed as `AvsEngine` does.

## Threading

One `NSLock` in `GoomEngine` guards the core, the PCM buffer and the held effect: the audio
thread writes PCM, the render thread updates (and recreates) the core, main's menu forces, holds
and reads effects. A choice computed from the running effect (step, random, hold) reads and writes
in one locked section (`select`). The render thread holds the lock through a whole frame, about
1.5 ms at the 1024-wide cap, which is all a menu action can wait. GL objects are render-thread only.

Cores are independent `PluginInfo`s, so — unlike Geiss — two hosts may each run one. The only
shared mutable state is the font (built once, then read-only, and never read since no text is
drawn) and a few animation `static`s in `ifs.c`, which are benign.

## Effects and menu

Goom chooses its own zoom-filter effect from the music. The sixteen modes (`*_MODE` in
`goom_filters.h`: upstream's Normal, Wave, Crystal Ball, Scrunch, Amulette, Water, Hypercos 1,
Hypercos 2, Y Only, Speedway, and the port's Spiral, Vortex, Flower, Heart, Pentagram, Ooh/Ugh) are the
engine's "presets" in `VisualizationGLView+Presets.swift`, so → / ← / R and the hosts' preset
steps work. **Goom is always held**: it never picks its own effect. `GoomEngine` keeps the chosen
index in `goom.heldEffect` (default 0; cleared by the Visualizations window's preference reset),
forces and holds it on every new core (a resize makes one), and `presetIndex` answers that index.
The shared `VisualizationPresetCycler` is what changes it over time (`goom.cycleMode` /
`goom.cycleInterval`, default Auto-Random, 30 s).

Goom's menu is only the shared block every engine gets (`visualizations` skill § *Context menu and
auto-cycle*); it has no items of its own.

## Licensing

LGPL-2.1-only, compatible with NullPlayer's GPL-3.0. `scripts/third_party_components.tsv` row
`goom` points at the shared `ThirdPartyLicenses/licenses/LGPL-2.1.txt`; regenerate
`ThirdPartyNotices.txt` with `scripts/generate_third_party_notices.sh` after changing it. Upstream
asks for a visible credit to Goom and its original authors — the README's credits list carries it.
`upstream/LGPL-ADDITIONAL-PERMISSION.md` is not vendored: that permission is for the copyright
holders' own apps and not extended to third parties.

## Debugging a live defect

Read [`live-ui-testing`](../live-ui-testing/SKILL.md) and
`winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect* first. Specific to Goom:

- Launch on it directly: `skills/app-control/scripts/launch.sh aquamp -- -winampModernShowVisualization 1 -visualizationEngineType Goom`;
  the log shows `Setting up Goom with viewport WxH`.
- Capture twice a few seconds apart — Goom starts dark and changes effect often, so one frame says
  little.
- A defect in the image (colour, geometry, speed) is checked against upstream's own app:
  `cd sdl && make run` in a j3k0/goom checkout (needs `brew install sdl2 freetype`), fed the same WAV
  with `--file`.
