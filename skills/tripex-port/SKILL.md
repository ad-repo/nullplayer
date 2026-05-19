---
name: tripex-port
description: Implementation reference for NullPlayer's Tripex visualization engine — the MIT-licensed port of ben-marsh/tripex (Winamp-era D3D9 3D visualizer, ~25 effects) onto macOS as a ProjectM-peer engine. Covers the CTripexCore C ABI, upstream-vs-port file split, OpenGL 3.2 renderer subclass, audio ring buffer, threading model, persistence, and the architectural deviations from upstream. Use when modifying anything under Sources/CTripexCore/, TripexEngine.swift, TripexMenuBuilder.swift, the Tripex factory branch in VisualizationGLView, or the engine-conditional Tripex menu in ModernProjectMView.
---

# Tripex Port Guide

Tripex is a third visualization engine in NullPlayer's modern visualizer window, switchable from the right-click **Visualization Engine** submenu alongside ProjectM and Geiss. It is a port of the MIT-licensed upstream at `https://github.com/ben-marsh/tripex` (vendored verbatim into `Sources/CTripexCore/upstream/`).

Architecturally simpler than the Geiss port: Tripex already has a clean `Renderer` abstract base in upstream, so the port substitutes one concrete subclass (`RendererOpenGL`) for the Direct3D 9 implementation that ships upstream. There is no asm to translate (Geiss had 30+ blocks), no Winamp 2 SDK stub, and no DirectDraw indexed-framebuffer plumbing — the renderer pushes geometry through a small GLSL 150 shader pair.

The port inherits the visualizer window's CVDisplayLink-driven render cadence, fullscreen toggle, and engine-switch lifecycle. It is **not** available in CLI/headless mode — `VisualizationType` is not exposed there.

## File Layout

### `Sources/CTripexCore/`

| Path | Role |
|------|------|
| `include/TripexCore.h` | C ABI consumed by Swift. 19 entry points: lifecycle (`_create`/`_destroy`/`_resize`), audio (`_pushPCM`), render (`_renderFrame`), effect navigation (`_prev`/`_next`/`_change`/`_reconfigure`/`_toggleHoldingEffect`/`_toggleAudioInfo`/`_toggleHelp`), inventory (`_effectCount`/`_effectName`/`_currentEffectIndex`/`_selectEffect`), generic int options (`_setOption`/`_getOption`), and `_lastError`. |
| `include/win_compat.h` | Typedefs (DWORD/HRESULT/WORD/LONG/POINT/RECT/etc.), inline shims (GetTickCount64/timeGetTime/fopen_s/_stricmp/_copysign), macros (FAILED/SUCCEEDED/ZeroMemory/__assume/WAVE_FORMAT_PCM). `<chrono>` is guarded by `#ifdef __cplusplus` so the Swift clang-module importer doesn't choke. |
| `include/Windows.h`, `wtypes.h`, `mmeapi.h`, `conio.h`, `d3d9.h` | Empty stubs (or thin typedef wrappers) so upstream `#include <X>` lines resolve without forcing edits to upstream sources. Anything D3D-specific stays unresolved because the only TUs that use those types are excluded from compilation. |
| `TripexCore.cpp` | C++ glue. Owns `TripexCoreHandle` (renderer + Tripex + HostAudioSource + options map + last_error + mutex), serializes every public ABI entry. |
| `upstream/` | Verbatim MIT source from ben-marsh/tripex `src/Tripex/*`. `LICENSE` and `README.md` retained. **One inline edit** to `Platform.h` replaces `#error Unsupported compiler.` with `#include "win_compat.h"` under the `_MSC_VER` `#else` branch — the absolute minimum upstream patch. Three small accessors (`PortGetEffectCount` / `PortGetEffectName` / `PortGetCurrentEffectIndex`) added to `Tripex.{h,cpp}` because `enabled_effects` and `effect_idx` are otherwise private. |
| `upstream_port/RendererOpenGL.{cpp,h}` | Concrete subclass of upstream's `Renderer`. GL 3.2 core profile: shared VAO/VBO/IBO, single shader pair (vertex maps `VertexTL` screen-space coords to NDC; fragment modulates diffuse by texture and adds specular). `RenderState` (BlendMode/DepthMode/cull/wrap) translated per draw to `glBlendFunc`/`glDepthFunc`/`glCullFace`/`glTexParameteri`. Buffers refilled per draw via `glBufferData(..., GL_STREAM_DRAW)`. |
| `upstream_port/HostAudioSource.{cpp,h}` | Concrete subclass of upstream's `AudioSource`. Mutex-guarded ring buffer (~2s @ 44.1 kHz stereo). `Push` from Swift, `Read` consumed per-frame by Tripex; underrun pads with silence. |
| `upstream_port/tripex_compat.cpp` | Out-of-class definitions required under clang/C++17 ODR rules. Currently just `const uint16 Actor::WORD_INVALID_INDEX;` (used by-reference in `vector::push_back`). |
| `PORT_NOTES.md` | Developer-only port log (reconnaissance findings, chunk status, gotchas register). **Not shipped in the .app.** |

### Compiled vs excluded

`Package.swift` excludes the following from the `CTripexCore` C++ target:

- `upstream/main.cpp` — Win32 message-loop shell. Beat detection, effect switching, fade timing all already live inside `Tripex::Render` — nothing to re-home.
- `upstream/RendererDirect3d.{cpp,h}` — D3D9 backend, replaced by `RendererOpenGL`.
- `upstream/AudioDevice.{cpp,h}` — WaveOut output, replaced by NullPlayer's audio pump → `HostAudioSource`.
- Build-system files (`*.vcxproj*`, `*.sln`, `packages.config`, `LICENSE`, `README.md`).

Everything else under `upstream/` plus all of `upstream_port/` is compiled.

`cxxSettings`: `headerSearchPath(".")`, `headerSearchPath("include")`, `headerSearchPath("upstream")`, `headerSearchPath("upstream_port")`, `define("__APPLE__")`, `unsafeFlags(["-fno-strict-aliasing", "-fwrapv"])`.

Package-level `cxxLanguageStandard` is **C++17** (Tripex uses `std::shared_ptr<uint8[]>`). C++17 is backwards compatible with CGeissCore and CVisClassicCore.

Exceptions are present in upstream (`Error.cpp` throws); clang's default `-fexceptions` covers this — no extra flag needed.

## Threading model

- **Audio thread** (NullPlayer's audio pump tap) → `TripexEngine.addPCMMono(_:)` → `TripexCore_pushPCM` → `HostAudioSource::Push` → ring buffer write under `HostAudioSource::mutex_`.
- **Render thread** (CVDisplayLink) → `TripexEngine.renderFrame()` → `TripexCore_renderFrame` → `Tripex::Render(*audio)` → effect calculations + `AudioSource::Read` (ring buffer read under the same mutex).
- **Main thread** (right-click menu) → `TripexEngine.nextEffect()` / `selectEffect(at:)` / etc. → `TripexCore_nextEffect` etc.

Two mutexes are at play:
1. `TripexCoreHandle::lock` serializes every public ABI entry inside `TripexCore.cpp`. Audio push and render frame are NEVER executed concurrently — `pushPCM` holds the lock while writing to the ring buffer; `renderFrame` holds it for the full Tripex frame.
2. `HostAudioSource::mutex_` is an inner lock guarding the ring-buffer state. Redundant in practice because the outer ABI lock already serializes producer/consumer, but kept so the class is correct in isolation.

`TripexEngine.coreLock` (Swift) guards the Swift-side handle pointer + scratch buffer; the C handle itself is thread-safe under its own mutex.

## Audio path

PCM is delivered by NullPlayer as mono float in `[-1, 1]`. `TripexEngine.addPCMMono` converts to interleaved int16 stereo (left = right = sample × 32767, clamped) and pushes the entire buffer in one shot. Tripex computes its own FFT inside `upstream/Fourier.cpp` (radix-2 + Hann-style apodization on raw int16 samples) — **no Accelerate / vDSP work is done on the Swift side** for Tripex (contrast: Geiss requires ~66 lines of Hann + radix-2 + dB-normalize in `VisualizationGLView.updateGeissSpectrumFromPCM`).

`AudioSource::Read` (Tripex contract) takes a byte count. Effects typically request `<4 KB` per frame; the ring buffer holds ~2 seconds, so under any realistic display-link cadence the buffer never underruns. If audio ever pauses for >2 seconds, `Read` pads with silence and Tripex renders against silence — visually equivalent to "no sound", which is correct.

## Rendering

`Tripex::Render(audio_source)` orchestrates the per-frame work: dispatch transition-state flags (`txs`), update audio analysis (`AudioData`), pick / advance / fade the active effect, call `effect->Render(params)` which in turn calls `Renderer::DrawIndexedPrimitive`. The renderer subclass converts each `VertexTL` (screen-space pre-projected) + `Face` (3 uint16 indices) batch into a single `glDrawElements(GL_TRIANGLES, ...)` call.

`VertexTL` layout (32 bytes): `Vector3 position`, `float rhw`, `ColorRgb diffuse`, `ColorRgb specular`, `Point<float> tex_coords[1]`. The Swift-side GL context must be a 3.2 core profile (NullPlayer's `VisualizationGLView` provides this). The shader pair lives inline in `RendererOpenGL.cpp` as `kVertexShaderSrc` / `kFragmentShaderSrc`.

### Known unimplemented paths

- `RendererOpenGL::CreateTextureFromImage` — image decoding (PNG/JPG/etc.). No effect in the upstream tree currently exercises this code path during startup; if a new effect does, `Tripex::Startup` will return an error and `TripexCore_create` will return NULL. Implement with `CGImageSource` if/when needed.
- `OpenGLTexture::GetPixelData` and `SetDirty` — GPU→CPU readback and CPU→GPU dynamic upload. Stubs return an Error / no-op respectively. Implement on demand.

## C ABI surface (full)

```c
TripexCoreHandle* TripexCore_create(int width, int height);
void              TripexCore_destroy(TripexCoreHandle*);
void              TripexCore_resize(TripexCoreHandle*, int w, int h);
void              TripexCore_pushPCM(TripexCoreHandle*, const int16_t* samples, size_t count);
int               TripexCore_renderFrame(TripexCoreHandle*);
void              TripexCore_prevEffect(TripexCoreHandle*);
void              TripexCore_nextEffect(TripexCoreHandle*);
void              TripexCore_changeEffect(TripexCoreHandle*);
void              TripexCore_reconfigureEffect(TripexCoreHandle*);
void              TripexCore_toggleHoldingEffect(TripexCoreHandle*);
void              TripexCore_toggleAudioInfo(TripexCoreHandle*);
void              TripexCore_toggleHelp(TripexCoreHandle*);
int               TripexCore_effectCount(TripexCoreHandle*);
const char*       TripexCore_effectName(TripexCoreHandle*, int index);
int               TripexCore_currentEffectIndex(TripexCoreHandle*);
void              TripexCore_selectEffect(TripexCoreHandle*, int index);
void              TripexCore_setOption(TripexCoreHandle*, const char* key, int value);
int               TripexCore_getOption(TripexCoreHandle*, const char* key, int fallback);
const char*       TripexCore_lastError(TripexCoreHandle*);
```

`_selectEffect` reaches an arbitrary index by issuing internal `MoveToNext`/`MoveToPrev` deltas — Tripex's public API has no random-access selection. The effect change is queued via `txs` flags and takes effect on the next render frame.

## Persistence

UserDefaults keys, persisted via `UserDefaults.standard`:

- `tripex.lastEffectIndex` (Int) — written by `VisualizationGLView.selectTripexEffect(at:)`, read by the `.tripex` factory branch in `createEngine(type:width:height:)`. Restores last selected effect on engine creation.

The Tripex `_setOption` / `_getOption` store is currently unused by any UI surface — reserved for future effect-parameter sliders if/when individual effects expose useful tunables. The `tripex.lockedEffectIndex` constant is reserved in `TripexEngine.DefaultsKey` but not yet read or written.

## Menu surface

`TripexMenuBuilder.addTripexConfigMenuItems(to:target:visualizationView:)` produces the per-engine submenu when Tripex is the active engine. Surface:

- Current effect name (disabled label).
- Next / Previous / Random / Reconfigure effect.
- Hold Current Effect / Show Audio Info / Show Help Overlay (toggle actions).
- Effects submenu listing all enabled effects with a checkmark on `currentTripexEffectIndex`.

`TripexMenuTarget` is the @objc protocol the host view conforms to. `ModernProjectMView` implements it and forwards each action to the corresponding `VisualizationGLView.*Tripex*` helper.

There are **no sliders** — Tripex effects own their own randomization parameters internally, and the upstream API exposes none of them. `_setOption`/`_getOption` exist for future expansion.

## Mode-specific guards (per CLAUDE.md gotcha)

- `isTripexActive = currentEngineType == .tripex` is computed in `ModernProjectMView`'s menu builder. The `addTripexEffectsMenuItems` call is gated on it.
- `selectTripexEffect`, `nextTripexEffect`, etc. in `VisualizationGLView` all early-return via `withTripex` if the active engine is not `TripexEngine` — defensive against menu actions firing during an engine switch.

## Architectural deviations from upstream

1. **Renderer backend** — D3D9 replaced by OpenGL 3.2 core (NSOpenGLView). `RendererDirect3d.{cpp,h}` excluded; `RendererOpenGL.{cpp,h}` substituted.
2. **Audio backend** — WaveOut device replaced by host audio tap. `AudioDevice.{cpp,h}` excluded; `HostAudioSource.{cpp,h}` substituted. NullPlayer's audio engine is the source of truth, and Tripex consumes a synthesized in-memory stream.
3. **No window** — upstream's `WinMain` is excluded; the host `NSOpenGLView` owns the framebuffer / GL context / display-link cadence. Tripex doesn't know whether it's rendering to a real window or an offscreen FBO.
4. **No keyboard input** — upstream binds F1/F2/Left/Right/R/E/H/M/O/T inside `WndProc`. Equivalent actions are wired via the right-click menu instead. Direct keyboard handling would require routing NSEvent through the host view.
5. **Three small accessors in `Tripex.h`** — `PortGetEffectCount`/`PortGetEffectName`/`PortGetCurrentEffectIndex`. Upstream keeps `enabled_effects` and `effect_idx` private; the C ABI needs read access for the menu builder.
6. **One inline edit to `Platform.h`** — `#error Unsupported compiler.` replaced with `#include "win_compat.h"` under the `_MSC_VER` `#else` branch.

## Adding a Tripex configuration menu item

1. Add a getter/setter pair in `TripexCore.h` if the new option requires a real binding (otherwise use `_setOption`/`_getOption` with a key string).
2. Add a Swift accessor on `TripexEngine` and a forwarding wrapper on `VisualizationGLView` (mutex-guarded by `engineLock`).
3. Append the menu item in `TripexMenuBuilder.addTripexConfigMenuItems`.
4. Add the action selector to `TripexMenuTarget` and implement it on `ModernProjectMView`.
5. If the option is user-persistent, write to UserDefaults in the action handler and read it back in the `.tripex` factory branch of `VisualizationGLView.createEngine`.

## Common modifications

### Modifying the render path
- Shader source: top of `RendererOpenGL.cpp` (`kVertexShaderSrc` / `kFragmentShaderSrc`).
- VAO/VBO attribute layout: `RendererOpenGL::EnsurePipeline`.
- Blend / depth / cull translation: `ApplyBlendMode` / `ApplyDepthMode` in `RendererOpenGL.cpp`.

### Adding a new upstream effect
Effects auto-register via the `EXPORT_EFFECT(name, type)` macro at the bottom of each `EffectFoo.cpp`. To add one:
1. Drop the `.cpp` into `upstream/` (or `upstream_port/` if it's a NullPlayer-specific effect).
2. Reference its `CreateEffect_Foo` symbol from `Tripex::CreateEffects` in `upstream/Tripex.cpp`.
3. No SwiftPM change needed — the file is picked up automatically.

### Modifying the audio path
- Ring buffer capacity: `HostAudioSource::RING_CAPACITY` in `HostAudioSource.h`.
- Float→int16 conversion / mono→stereo broadcasting: `TripexEngine.addPCMMono` in Swift.

## Gotchas

- **NEVER include `<chrono>` (or any other C++-only header) at file scope in `win_compat.h`** — Swift compiles the CTripexCore clang module in C mode for the importer and the umbrella sweep pulls in `win_compat.h` via `TripexCore.h`'s transitive includes (the public-headers directory). Anything C++-only must be `#ifdef __cplusplus`.
- **Out-of-class definitions for upstream `static const` members** — MSVC accepts the in-class initializer as a definition; clang/C++17 ODR-uses (vector::push_back, function param by const&) require an out-of-class definition. Add to `upstream_port/tripex_compat.cpp`.
- **`Renderer`'s base destructor is non-virtual upstream** — `~RendererOpenGL` is intentionally NOT marked `override` to satisfy clang. Memory under `std::shared_ptr<Renderer>` still calls the correct destructor through shared_ptr's type-erased deleter, but if any future code holds `Renderer*` raw and deletes it polymorphically, behavior is undefined.
- **Effect.cpp filename case** — most upstream includes use lowercase `effect.h` and `error.h`; the files on disk are `Effect.h` / `Error.h`. macOS APFS is case-insensitive by default, so it works; clang emits `-Wnonportable-include-path` warnings (suppressible, presently kept visible as a reminder).
- **Engine switching corruption risk** — `RendererOpenGL` lazily creates its GL pipeline on first draw. After `TripexCore_destroy`, GL resources are released through `OpenGLTexture::~OpenGLTexture`, but the shared VAO/VBO/IBO are leaked (no destructor cleanup) — minor. Add cleanup in `RendererOpenGL::~RendererOpenGL` if engine-switch leaks become noticeable.

## Verification matrix

After modifying any of the touched files, run:

1. `swift build` — green, including all upstream `.cpp` files compiling without error.
2. Launch app → right-click visualizer → **Visualization Engine** → **Tripex** → confirm the window switches and a frame renders.
3. Use the per-engine submenu items (Next / Previous / Random / Reconfigure / Hold / Show Audio Info / Show Help / Effects submenu entries) → confirm each takes effect.
4. Switch back to ProjectM → confirm no GL state corruption.
5. Close + relaunch app with Tripex saved as last-engine + non-zero `tripex.lastEffectIndex` → confirm the same effect restores.
6. Run with a long-playing track (>10 min) → Activity Monitor should show steady-state memory, no growth.

## Upstream provenance

- Source: `https://github.com/ben-marsh/tripex`, MIT license (Copyright (c) 2025 Ben Marsh).
- Vendored from `src/Tripex/*` (97 files including LICENSE/README).
- `LICENSE` and `README.md` retained verbatim under `upstream/` but excluded from compilation.
- Two upstream edits (`Platform.h` `#error` replacement; `Tripex.h`/`Tripex.cpp` `PortGet*` accessors) are marked in their respective files with `NullPlayer port:` comments.
