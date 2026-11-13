---
name: avs-port
description: Implementation reference for NullPlayer's AVS (Advanced Visualization Studio) engine — the BSD-3 libavs from grandchild/vis_avs vendored as CAvsCore and run as a ProjectM-peer engine in the Visualizations window, a `.wal` AVS slot and a `.wmz` effects area. Covers the upstream-vs-port split, the patches, build flags and sse2neon, the EEL2 JIT and its entitlement, threading, the stereo audio feed and beat detector, presets, the hosts, the preset editor, licensing and debugging. Use when touching Sources/CAvsCore/, AvsCore.swift, AvsEngine.swift, AvsPresets.swift, Windows/AvsEditor/ or the AVS cases in the visualization hosts.
---

# AVS Port Guide

AVS is an engine in the Visualizations window, picked from **Visualization Engine → AVS** beside
ProjectM, Geiss and Tripex. The same engine list is shared, so a `.wal` skin's AVS slot and a
`.wmz` skin's effects area run it too. It is the library half of
[grandchild/vis_avs](https://github.com/grandchild/vis_avs) at
`1cee1f3d4f783b830538c3e4d2082a2c59521dee` (BSD-3; EEL2 under zlib), vendored as the `CAvsCore`
SwiftPM target. The Winamp frontend, the Win32 editor and the APE-plugin loader are not.

AVS is exempt from CLAUDE.md's Winamp-source rule: it is a BSD-licensed visualizer, not skin code.

## File layout

| Path | Role |
|------|------|
| `Sources/CAvsCore/upstream/` | Upstream `avs/` subset, edits marked `NullPlayer:` (see *Patches*). `vis_avs/` is the library (`avs.h`, `avs_editor.h`, effects `e_*`, `instance`, `render_context`…); `3rdparty/` is md_fft, nlohmann json, stb_image, pevents and ns-eel. `LICENSE.TXT` is upstream's. |
| `Sources/CAvsCore/upstream_port/platform_darwin.cpp` | Port of upstream's `platform_linux.c`: timers (`CLOCK_UPTIME_RAW`), threads, pevents locks and events, `mem_mark_rwx`. C++ because a C translation unit with `-fmodules` sees Mach's `thread_create` and clashes with upstream's. |
| `Sources/CAvsCore/upstream_port/texer2_portable.{h,cpp}`, `convolution_portable.{h,cpp}` | C ports of Texer II's MMX loops and of the code Convolution's x86 JIT emits, for everything but i386 (see *Patches*). |
| `Sources/CAvsCore/upstream_port/e_text.{h,cpp}` | The Text effect (legacy id 28), which upstream's library does not build: config, legacy load/save and the per-frame word, beat and placement logic. It keeps the saved `CHOOSEFONTA`/`LOGFONTA` blobs and patches only the changed font fields on save. `$(regNN[:fmt])` reads the EEL global registers; `$(title)` is empty and `$(playpos)`/`$(playlen)` read 0:00, as Winamp with no song. |
| `Sources/CAvsCore/upstream_port/text_coretext.{h,cpp}` | Text's font measuring and drawing on CoreText (a `CGBitmapContext` in the framebuffer's BGRX layout, Windows-1252 strings). A separate translation unit with a libavs-free header, because CoreText's Mach headers clash with `platform.h`'s typedefs. |
| `Sources/CAvsCore/upstream_port/audio_in_darwin.cpp` | Stubs for upstream's audio-input API. NullPlayer feeds audio with `avs_audio_set` (AVS_AUDIO_EXTERNAL). |
| `Sources/CAvsCore/upstream_port/simd/` | `immintrin.h`, `emmintrin.h`… shims searched before clang's. On arm64 they include sse2neon (v1.8.0, MIT); on x86_64 they `#include_next` the real header. `mmintrin.h` adds the two MMX helpers sse2neon lacks. |
| `Sources/CAvsCore/include/CAvsCore.h` | The module header: `avs.h` and `avs_editor.h`. |
| `Sources/NullPlayer/Visualization/AvsCore.swift` | One libavs instance behind a lock (`withHandle`), the audio slot, `AvsBeatDetector` and the paced `AvsBeatFeed`s. |
| `Sources/NullPlayer/Visualization/AvsEngine.swift` | The `VisualizationEngine`: render, GL blit, stereo feed, presets. |
| `Sources/NullPlayer/Visualization/AvsEngine+Menu.swift` | The engine's section of the shared visualization menu and its actions. |
| `Sources/NullPlayer/Visualization/AvsPresets.swift` | Preset list (bundled, then the user folder, recursive) and the UserDefaults keys. |
| `Sources/NullPlayer/Windows/AvsEditor/AvsEditorWindowController.swift` | **Edit Preset…**: the component tree, add / duplicate / delete / drag-move, the file buttons. |
| `Sources/NullPlayer/Windows/AvsEditor/AvsParameterInspector.swift` | One component's parameters as controls built from `avs_parameter_info`. |
| `Sources/NullPlayer/Resources/AVSPresets/` | Upstream's 35 bundled `.avs` presets. |
| `Tests/NullPlayerAppTests/AvsCoreSmokeTests.swift` | Every preset loads, saves legacy idempotently and moves; only effects with no implementation load as Unknown Effect; the SuperScope JIT; lock serialisation; the beat detector and the feed's pacing; the inspector builds for every component of every preset. |
| `Tests/NullPlayerAppTests/AvsEffectPortTests.swift` | The C ports of the x86 code and Text, by pixels: Convolution blurs a dot, Texer II draws in all ten blend modes, Text draws and cycles, and a Win32-layout Text record round-trips byte for byte. `AvsPresetBuilder` builds a preset through `avs_editor.h` by effect and parameter name. |

## Build

`Package.swift` builds `CAvsCore` from shared lists at the top of the file:

- **Header search paths:** `upstream_port/simd` first, so the SIMD shims win, then `upstream`.
- **Defines:**
  - `SIMD_MODE_X86_SSE` on both architectures. On arm64, sse2neon turns the SSE code into NEON.
  - `NO_MMX`, which selects upstream's C fallbacks for the inline MMX asm in Blur, Blitter Feedback, Dynamic Movement and Movement.
  - `_USE_MATH_DEFINES`, `NO_FFMPEG`, `WFMO`, `FORCE_CPP_FILESYSTEM_API`.
- **Renames:** `FFT=AvsFFT` and `Effect=AvsEffect`. CVisClassicCore and CTripexCore export the same class names, and without the renames the link fails on duplicate symbols.
- **Links** CoreText and CoreGraphics, for Text.
- **Flags:** `-O2 -fno-strict-aliasing -fwrapv -w`.
  - `-O2` applies in debug too. At `-O0`, a 524×550 frame took 55 ms (13 fps); optimised it takes about 1 ms.
  - `-w` hides upstream's warnings, so check a new patch with `-Wint-to-pointer-cast` by hand.
- **Excluded from compilation:**
  - The `asm-nseel-*` files (`#include`d by `nseel-cfunc.c`), `y.tab.c` (`#include`d by `nseel-yylex.c`), and the standalone EEL tools `eel_pp.cpp` and `loose_eel.cpp`.
  - The `.patch` files and licences.
- **Not vendored:** `e_example_effect` and the ffmpeg video reader (`video_libav`, hence `NO_FFMPEG`). Upstream's library comments Text out of `effect_library.cpp`; NullPlayer builds its own (`upstream_port/e_text.cpp`).

**x86_64** uses EEL2's portable bytecode interpreter (`EEL_TARGET_PORTABLE`, set in `ns-eel.h`), because EEL2's x64 JIT needs a NASM object. The whole app does not build for x86_64 on `origin/main` (M82). The port was verified there with a standalone clang harness under Rosetta, and every preset loaded except Spacefolding (since fixed by the APE aliases). The x86-only code paths that now have C ports (Texer II, Convolution) still compile there and keep their asm on i386 only.

## Patches to upstream

Every edit is marked `NullPlayer:` in the source. The list:

- `ns-eel2/nseel-compiler.c`, the arm64 JIT:
  - `MAP_JIT` RWX pages.
  - `eel_set_blocks_allow_execute` only calls `sys_icache_invalidate`.
  - `NSEEL_code_compile_ex` is wrapped in `pthread_jit_write_protect_np(0/1)`; the original is renamed `nseel_code_compile_ex_unbracketed` by a `#define`.
- `ns-eel.h`: `EEL_TARGET_PORTABLE` on x86_64 Apple.
- `platform.h`, `uuid.cpp` (both places): `__APPLE__` alongside `__linux__`.
  - Without it, `uuid4` hit a SIGTRAP.
- `files.cpp`: includes `constants.h`, for `MAX_PATH`.
- Pointer arithmetic moved from `uint32_t` to `uintptr_t`:
  - `e_videodelay.cpp` and `e_multidelay.cpp`, including the `l` and `d` locals.
  - `e_effectlist.cpp`: `(int)(intptr_t)parm`.
- **Texer II** (`e_texer2.cpp`): `DrawParticle`'s clipping and texture mapping are shared; where its 32-bit MMX asm starts, anything but i386 calls `texer2_draw_scaled` / `texer2_draw_unscaled` (`upstream_port/texer2_portable.cpp`), byte-exact C ports of the two loop families. They keep the asm's quirks: the min/max select compares RGB unsigned and the fourth byte signed, the two loops order min/max operands and weight the adjustable blend differently, and masked multiply filters the product. One deliberate difference: the asm's scaling loop read one texel past the image at the last column and row; the port clamps to the last texel. `EMMS` is i386 only. `e_texer2_macros.h` uses `lrint` in place of its GCC asm `RoundToInt`.
- **Convolution Filter** (`e_convolution.cpp`): the 32-bit x86 JIT stays on i386; elsewhere `render` plans a `Convolution_Portable` (`upstream_port/convolution_portable.cpp`) when `need_draw_update` is set, as the JIT is rebuilt, and applies it per frame. It does what the generated code does: 16-bit lanes, wrapping sums when a side's weights sum under 256 and saturating otherwise, edge rows and columns clamped as the JIT's loads were, the second pass's rotated taps, in-place filtering when no weight precedes the centre. A diff from Winamp here is a port defect.
- **Legacy APE aliases** (`effect_library.cpp`): `Winamp Starfield v1` and `Winamp Mosaic v1` load as the built-in Starfield and Mosaic, whose config records they match byte for byte (36 and 28 bytes). `FunkyFX FyrewurX v1` has no implementation and stays Unknown Effect (M91).
- **`E_Root::swap`** (`e_root.h`): `Effect::swap` moved the children but not the config, so a loaded preset kept the previous preset's Clear flag and metadata. `E_Root` swaps its config too.
- **Text** is added to the library (`MAKE_EFFECT_LIB_ENTRY(Text)`), from `upstream_port/`.
- `e_blitterfeedback.cpp`: the stale `BLEND4` is renamed to `blend_bilinear_2x2`.
- **All 54 `PUT_INT` macros:** `((y) >> N)`. Without the parentheses, Roto Blitter's legacy save wrote the wrong bytes, and a save then load was not idempotent.
- `instance.h` `EelState`: `global_ram`, `visdata`, `log_errors` and the hooks are initialised. Freeing an uninitialised `global_ram` aborted.
- Debug output removed:
  - `audio.cpp`: a printf per audio buffer.
  - `instance.cpp`: `print_tree()` on a legacy load.
  - `3rdparty/md_fft.cpp`: the `normalize_table.txt` writes into the working directory.

## JIT and signing

On arm64, EEL code (SuperScope, Dynamic Movement, Custom BPM…) is JIT-compiled into `MAP_JIT` pages. Under the hardened runtime that needs `com.apple.security.cs.allow-jit`; without it the process dies with SIGTRAP (exit 133) on the first compile.

The entitlement is in `scripts/DeveloperID.entitlements`, which `build_dmg.sh` signs with, and in `Resources/NullPlayer.entitlements` (the Mac App Store build). Debug builds are not hardened, so a missing entitlement only shows in a signed build.

## Threading

libavs is not thread-safe. `AvsCore` serialises the render and every `avs_editor.h` call through `withHandle`, under one lock.

- **Render thread** (the host's GL render thread): `AvsEngine.renderFrame` renders under the lock, uploads to a texture, and blits.
- **Audio tap thread:** the `.audioStereoPCMFullDataUpdated` observer only stores into `AvsAudioSlot`, a lock, an assignment and an unlock. It never takes the core lock.
- **Main thread:** preset state (`presets`, `currentIndex`) and the menu actions. A preset load takes the core lock and blocks one frame.
  - `init` (render thread) scans the preset list and loads the saved preset before the engine is shared, so a `.wmz` host can apply a preset number at once. It posts nothing and saves nothing.
  - `reloadPresets` (folder change, editor save) scans on a background queue and publishes the list on main. `selectPreset` and `reloadPresets` assert main with `dispatchPrecondition`.
  - GL objects are freed only in `cleanup()`, which every host calls with its context current. `deinit` removes the audio observer and never touches GL.
  - Auto-cycle is the shared `VisualizationPresetCycler` on main (`visualizations` skill § *Context menu and auto-cycle*), not the engine's.

More than one `AvsEngine` can exist at once (the Visualizations window and a skin slot); each owns its own instance.

## Audio and beats

`avs_audio_set` takes the stereo buffer with an end sample time that must increase. `AvsCore` passes the running count of frames it has fed.

AVS's FFT reads the newest 576 samples whatever the rate, so at 96 kHz the spectrum is compressed (576 samples is 6 ms).

The engine takes its audio itself, registering as `"avsEngine"` on main and releasing on `cleanup`:
- the full-rate stereo feed (`addFullStereoConsumer`), for `avs_audio_set`;
- the 576-sample waveform feed (`addWaveformConsumer`), for the standard beat detector;
- aubio's beats (`addBeatConsumer`, `.audioBeatsUpdated`), for advanced detection.

Its `addPCMMono` is empty, because the host only hands engines mono audio.

The full-rate stereo feed is the newest 2048 frames of each tap buffer, and the tap delivers about 4410 frames ten times a second. A detector reading the newest 576 samples per frame heard one 13 ms slice in every 100 ms and missed most beats, so beats come from feeds that carry every sample.

**Beat detection:** libavs's `AVS_BEAT_INTERNAL` is a stub, because upstream left beat detection in the Winamp frontend.
- The instance runs with `AVS_BEAT_EXTERNAL`.
- **Pacing:** each source fills an `AvsBeatFeed` with one verdict per slot of the music, about 100 ms of slots per tap buffer. `renderFrame` takes the slots whose time has come by its clock (`nowMs`, injectable for tests), so a beat lands within a slot of its place in the music, about one tap buffer late. Both feeds drain every frame, so switching never releases a backlog.
- **Standard:** `AvsBeatDetector`, a port of the frontend's standard detector, runs on every 576-sample chunk: a summed 8-bit amplitude, a beat at 34/32 above a decaying peak and above a silence floor. On real music it fires on snares and hi-hats as readily as kicks.
- **Advanced** (right-click ▸ Beat Detection, `avs.advancedBeatDetection`, off by default): aubio's beat tracker, from the app's `BPMDetector` (`audio-system`), one verdict per 512-sample hop. This replaces Winamp's "advanced" `bpm.cpp` refiner: ported, it was fed the standard detector's beats and never settled on a tempo on real music (measured 2026-11-12: 165 → 87 → 136 BPM over 29 s).
- Many presets only change colour or move on a beat, so a test signal without beats renders black.

## Rendering

- **Frame size:** the viewport, first raised to `SoftwareCanvas.minWidth` (400 px) wide at its aspect when narrower, then divided by the smallest whole number that brings it to 800 px wide or less, rounded down to libavs's 4×2 grain. AVS presets were written for a few hundred pixels, so a skin's small effects slot (Sonique's top circle is 182×176 px) gets the 400 px frame shrunk instead of strokes and glows twice as thick.
- **Upload:** `AVS_PIXEL_RGB0_8` (0x00RRGGBB, little-endian) goes up as `GL_BGRA` into `GL_RGB8` storage. The zero alpha is dropped there; otherwise it would make the surface transparent.
- **Blit:** `glBlitFramebuffer` from a read framebuffer into whatever draw framebuffer the host has bound, flipped, because AVS row 0 is the top.
  - That is the window's own framebuffer, or the `.wal` and `.wmz` offscreen one.
  - There is no shader and no quad.

`base_path` is `~/Library/Application Support/NullPlayer/AVS`. AVSTrans writes `eeltrans.ini` there on teardown, and effects look up image files (Picture, Texer) there.

## Presets and persistence

| Key | Meaning |
|-----|---------|
| `avs.presetPath` | The preset showing, by path; the first preset when it is missing. |
| `avs.customPresetsFolder` | The user folder from **Choose AVS Preset Folder…**, a plain path (M84: security-scoped bookmarks). |
| `avs.advancedBeatDetection` | Beat Detection ▸ Advanced (aubio's beats); one setting for every engine instance, read each frame. |
| `avs.cycleMode` / `avs.cycleInterval` | Manual Only / Auto-Cycle / Auto-Random and its interval, through `VisualizationCycleSettings` like every engine's. One setting for every host. |

The first three are in `VisualizationPreferences`' `.all` reset (`AvsPresets.preferenceKeys`); the cycle keys are in the Visualizations window's reset with every engine's. The engine choice itself is the shared `visualizationEngineType`.

## Hosts

- **Engine list:** the `.avs` case of `VisualizationType` puts AVS in every engine list. That is `VisualizationContextMenu` (all hosts) and **Visuals → Visualizations → Visualization Engine**.
- **Factory:** `VisualizationGLView.createEngine` builds `AvsEngine`.
- **Menu section:** the presets and cycle are the shared block every engine gets; `VisualizationContextMenu` then calls `AvsEngine.addMenuItems` for AVS's own Edit Preset…, Beat Detection and folder items. They target the engine, so a host needs no AVS actions of its own.
- **Preset stepping:** no host names AVS. Keys (→ / ← / R in `ProjectMView` and `ModernProjectMView`), the `.wal` `stepPreset` and the `.wmz`/Sonique `applyPreset` all call `VisualizationGLView+Presets.swift`, which maps count, name, select, step and random onto `AvsEngine.presets` / `selectPreset` / `step` / `selectRandomPreset`.
- **`.wmz`:**
  - `SkinEffectSelection` has an `avs` style and catalogue entry.
  - `SkinEffectsSurfaceView` treats it as an offscreen engine.
  - `applyPreset` maps the skin's preset number onto the running engine's list (see *Preset stepping*).

## Preset editor

**Edit Preset…** (in the engine's menu section) opens `AvsEditorWindowController` on the engine whose menu was used. It is a plain, unskinned AppKit window, and only one is open at a time.

**Generic by design.** Nothing in the editor knows an effect: the tree comes from `avs_component_*` and every control from `avs_parameter_info`. A newly vendored effect is editable with no editor change.

**Tree** (`NSOutlineView`; items are `Node`s, a snapshot of the component tree read under one lock per reload, so the data source never calls libavs between reloads):
- Root is the single top-level item.
- **Add Effect** lists `avs_effect_library` effects that are `is_user_creatable`, grouped by `group`. A new effect goes into Root, or into an expanded Effect List, and otherwise after the selection.
- Rows drag-move with `avs_component_move`: before the row dropped on, or at the end of a list.
- Each row's checkbox is `AVS_Component_Properties.enabled`. It is a bare checkbox beside a label, so a click on the name selects the row instead of toggling it.

**Inspector controls**, by parameter type:

| Type | Control |
|---|---|
| bool | checkbox |
| int, float | slider and field; field only when the range is unbounded. The value written is read back, since libavs clamps. |
| color | colour well; values are the framebuffer's `0x00RRGGBB` despite the header's "RGBA16" |
| string | monospaced text view, written on end-editing because EEL strings recompile. There is no flag marking code, so every string gets one. |
| select, resource | popup; select by index, resource by string |
| list | one box per element, with ↑ / ↓ / Remove and **Add *name***. List paths are libavs's (depth, indices). |
| action | button; the pane rebuilds after it runs |

The read-only arrays are effect output and are not shown.

**Threading:** every call goes through `AvsCore.withHandle` on main, so an EEL recompile stalls at most one frame.

**Engine coordination:**
- While the editor is open, `AvsEngine.isBeingEdited` holds auto-cycle (`VisualizationPresetCycler` skips its tick), which would throw the edit away.
- The engine posts `presetDidLoad` when a preset change replaces the tree, and the editor reloads.
- The engine posts `didStop`, with its `ObjectIdentifier`, when it stops; the editor closes.

**Files:** libavs sniffs the format from the content.
- **Save…** writes legacy `.avs` (`avs_preset_save_legacy`), which is what the preset list reads and Winamp opens. It then reloads the engine's preset list.
- **Export JSON…** writes `avs_preset_save`.
- **Open…** takes either.
- **New** deletes the root, and libavs makes a fresh empty one.

## Gaps (tasks/MISC_TASKS.md)

- M91: FyrewurX (`justin - fireworks kaliadascope mk 2`, `justin - steve likes it`) has no implementation.
- M82: no x86_64 app build.
- M84: preset folders are plain paths.

## Licensing

These files are listed in `scripts/third_party_components.tsv` and gathered into `ThirdPartyNotices.txt` by `scripts/generate_third_party_notices.sh`:
- `ThirdPartyLicenses/AVS_LICENSE.txt` (with the donated-effects note)
- `EEL2_LICENSE.txt` (with the Bison exception note)
- `nlohmann_json_LICENSE.txt`, `stb_image_LICENSE.txt`, `pevents_LICENSE.txt`, `sse2neon_LICENSE.txt`

Regenerate the notices after touching the manifest.

## Debugging a live defect

For anything that only shows on screen (a preset drawing wrong, stutter, a host not following), read `live-ui-testing` first. The reference implementation of that workflow is `winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect*.

- **Drive the debug build:** `skills/app-control/scripts/launch.sh <skin>`, then **Windows → Visualizations**, then **Visuals → Visualizations → Visualization Engine → AVS**.
- **Pick a preset:** set it by path with `defaults write NullPlayer avs.presetPath <path>` before launching.
- **Isolate the library:** the smoke tests run libavs headless, so a defect that reproduces there is libavs or the port, not the host.
- **Uninitialised reads:** run the tests with `MallocPreScribble=1 MallocScribble=1`.
- **Beats:** `AVS_BEAT_TRACE=1` (DEBUG) logs `AVS-BEAT t=<ms> standard=<0|1> tracked=<0|1>` for every frame with a beat from either feed; the intervals show whether a source is regular.
- **Stutter:** time `core.renderFrame` before anything else. A debug build that lost `-O2` renders at about 13 fps.
