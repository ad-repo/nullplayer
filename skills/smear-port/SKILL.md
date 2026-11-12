---
name: smear-port
description: Implementation reference for NullPlayer's Smear visualization engine — Smear 1.2 by mykel and xplo (Sonique), its Stutter script interpreter vendored in C behind a small shim and rendered as a CPU RGBA frame blitted into the Visualizations window. Covers the CSmearCore layout and ABI, the upstream edits, the scripts and their bundling, move scripts as held presets, audio, threading, licensing and gotchas. Use when modifying anything under Sources/CSmearCore/, SmearEngine.swift, Resources/Smear/, or the Smear case of the engine factory, preset seam or skin effects catalogue.
---

# Smear Port Guide

Smear is a visualization engine in the Visualizations window, picked from the right-click
**Visualization Engine** submenu. It is a G-Force-style feedback visualizer: each frame the last
one is pulled through a *move map* (a per-pixel displacement, bilinear, slightly faded), then a
waveform and up to three particle systems are drawn into it, and the 8-bit result goes through a
*colour map*. All four are scripts in "Stutter", a small Lisp (`upstream/stutter.txt`).

Source: Smear 1.2 for Sonique by mykel and xplo (Michael Landers, Samuel Graenacher),
`https://support.xmplay.com/files/11/smear.source.zip?v=791201`. The zip also holds Windows
binaries; they were never run.

It runs in every skin family's slot: a `.wal` skin's visualization box (which follows the shared
engine preference) and the `.wmz` / Sonique effects list (`SkinEffectSelection.catalogue`, entry
`smear`), where it renders offscreen like the other engines.

## File layout

| Path | Role |
|------|------|
| `Sources/CSmearCore/upstream/` | `parser.{c,h}`, `eruntime.h`, `fnlist.{c,h}`, `functions.c`, `array.c`, `runtime.c` (the interpreter and script runtimes), `file.c` (loading and picking scripts), `smear.{c,h}` (the renderer), `LICENSE.TXT`, `stutter.txt` (the language reference; not compiled). |
| `Sources/CSmearCore/include/SmearCore.h` | The C ABI Swift imports: create/destroy, `scriptCount`, `holdMove` (by file name), `render` (waveform + spectrum in, RGBA out). |
| `Sources/CSmearCore/SmearCore.c` | The shim: replaces the Sonique entry points and `smearapi`, owns the frame buffer, the clock (`smearNow`). |
| `Sources/NullPlayer/Resources/Smear/` | The 111 bundled scripts: `Moves/*.sms` (60), `Color/*.scs` (20), `Waveform/*.sws` (19), `Particle/*.sps` (12), and `LICENSE.TXT`. |
| `Sources/NullPlayer/Visualization/SmearEngine.swift` | `VisualizationEngine` conformance, GL upload + flipped blit, the held move. |
| `Tests/NullPlayerAppTests/SmearCoreSmokeTests.swift` | Every bundled script compiles; every move can be held; a loud signal lights the frame. |

`Package.swift` builds `CSmearCore` as C with `-O2` in debug too (a software renderer, like
`CGoomCore`). Files not vendored: `smearapi`, `ssm` (shared memory), `thread`, `wfstuff` (GDI
text), `songname.cpp`, `pixel.*`, `vis.h`, the test tools and `unused/`.

### Upstream edits

Each edited file carries a dated "Modified for NullPlayer" note at its top; extend it with any
further edit. `fnlist.{c,h}` and `eruntime.h`'s layout are otherwise upstream's.

1. **No globals.** Everything `smear.c`, `file.c`, `runtime.c` and `functions.c` kept in globals or
   function statics (maps, screen buffers, colour maps, the timers, the 3D matrix, the audio) is a
   field of `SmearState`; every `Environment` (a compiled script) points at its Smear (`eState`).
   Each core parses its own copies of the scripts, since a script's variables are its runtime
   state. The random generator is the core's too (`smearRand`, `rand_r` on `randSeed`, seeded
   from `arc4random`), and an out-of-range array access uses the array's own `asErrorReturn`
   where upstream had a function static. Only the tokenizer's statics remain, made
   `_Thread_local`.
2. `smear.c` is cut down to the renderer: the x86 assembly of `sbApplyMove` is replaced by
   upstream's own C twin (`OLDsbApplyMove`); the plugin entry points, VIS.INI settings, map thread,
   "constant merge"/"total mayhem", title screen, song titles and click overlay are gone. Settings
   are upstream's defaults, with the title screen off (its quick first map is used instead).
3. Maps and colour maps are `uint32_t`: they were `unsigned long`, 64-bit on macOS, and the colour
   fade walks them four bytes at a time.
4. Bugs fixed: `array.c` zeroed `sizeof(double)` bytes of a grown array instead of all of it; a
   token, the function list and the variable table could overrun (variables past 256 share
   `eOverflow`); EXECUTE/LOOP/WHILE returned uninitialised values; `TimedRunForLine` used its
   resume column before resetting it; `effectsDrawLine` shifted negative values; `/` evaluated its
   divisor twice; `WRAP` looped forever on an infinite or huge value (now `fmod`); `%=` added the
   remainder instead of storing it; a new argument slot was uninitialised and an array index could
   compile to no argument; waveforms capped at 15 paths and never reached `$Step` 1 or the last PCM
   sample; a particle's height scaled with X and its width with Y. Allocations
   are checked: a map or screen buffer that cannot be had makes `SmearCore_render` return NULL
   (that frame is skipped, the next one tries again), and an array that cannot grow reads as
   out of range.
5. The spectrum is `unsigned char` (MSVC's signed `char` made values over 127 negative), the
   waveform `signed char`.
6. `FreeEnvironment` frees a compiled script (upstream never freed them); compile errors go to
   stderr, runtime errors (e.g. a divide by zero per pixel) are dropped.

## Presets are the move scripts, held

`SmearEngine.moveFiles` is the bundle's `Moves/*.sms`, sorted; preset names drop the extension and
turn `_` into spaces. The held move is stored by file name (`smear.move`, in
`VisualizationPreferences`' reset list) and handed to `SmearCore_holdMove`, which also forces a
fast rebuild (upstream's smearapi "set move" path). `ChooseMoveScript` always returns the held
move, so Smear's own timer (15 s ±50%) only re-runs that script's `init`, re-rolling its random
parameters, and cross-fades to the new map. The shared `VisualizationPresetCycler` changes the move
(default Auto-Random, 30 s); → / ← / R and the Presets list work through the preset seam.

Colour, waveform and particle scripts still come and go by themselves with upstream's weighted
random pick and timings.

## Audio

Sonique gave 512 8-bit PCM samples and a 256-bin 8-bit spectrum per channel. The host's mono PCM
(first 512 samples, ×127) and its 256-bin spectrum (`consumesHostSpectrum`, ×255) feed both
channels. Scripts read `$left/$right/$mid` (waveform), `(lspect n)`, `(lwave n)` and the peak
variables; bass and treble are 0, as upstream never computed them.

## Rendering and threading

- At most 60 frames a second. The canvas is the drawable's size raised to `SoftwareCanvas.minWidth`
  (400 px) when narrower, at most 1,024 wide; the core follows size changes itself (maps rebuilt).
- Letterbox at 100%: the drawn height never exceeds the width, so a tall window shows a band.
- A move map is built by running the move script once per pixel, 5 ms of each frame (25 ms after a
  preset change), then cross-faded in over ~3 s. A large canvas therefore takes a few seconds to
  show a new move.
- Smear's row 0 is the top; the blit flips it.
- **The core is the render thread's alone.** `lock` guards the waveform, spectrum and held move
  handed over by the audio thread and main. Cores share nothing, so a window and a skin slot can
  each run one.
- `smearNow` is an `int` of milliseconds, as upstream's timers are, and wraps after 24.8 days,
  when the move and colour timers would stop firing. `SmearEngine` replaces a core older than
  20 days (`coreLifetime`) with a fresh one holding the same move.

## Licensing

`LICENSE.TXT` is BSD-style with two extra clauses: the authors' names may not be used to promote
the product (3), and the source of a derived work must be made available to them for personal use
(4). The user accepted clause 4 on 2026-11-12. The licence ships in the bundle and is the `smear` row
of `scripts/third_party_components.tsv` (regenerate with `scripts/generate_third_party_notices.sh`).
README credits it under *Native ports*. Do not use mykel's or xplo's names in promotion.

## Debugging a live defect

Read [`live-ui-testing`](../live-ui-testing/SKILL.md) and `winamp-modern-skin-guide/reference/harness.md`
§ *Debugging a live defect* first. In a skin slot:
`skills/app-control/scripts/launch.sh sonique:BlueEyes -- -soniqueSkinMode mid -soniqueEffect smear -smear.move Starwave.sms`.
In the window: Visuals → Visualizations → Show Visualizations Window, then Visualization Engine ▸
Smear; the log shows `Setting up Smear with viewport WxH`. A script that fails to compile prints
`Smear: <file>: <line>: <error>` to stderr.
