# CTripexCore Port Notes

Port of [ben-marsh/tripex](https://github.com/ben-marsh/tripex) (Winamp-era
D3D9 3D visualizer, ~25 effects) into NullPlayer as a third Visualization
Engine alongside ProjectM and Geiss. Executed per the 8-chunk plan in
`/Users/ad/.claude/plans/review-this-plan-prancy-sonnet.md`.

## Status

- **Chunk 1:** upstream vendored, reconnaissance complete, C ABI skeleton +
  win_compat shim, target compiles with only `TripexCore.cpp` in the compile
  set.
- **Chunk 2 (this commit):** all non-D3D/non-Win32 upstream TUs compile on
  clang/macOS. Excludes: `main.cpp`, `RendererDirect3d.{cpp,h}`,
  `AudioDevice.{cpp,h}`, plus build-system files. `Platform.h` patched
  in-place (one-line change: `#error` replaced with `#include "win_compat.h"`
  under the `_MSC_VER` guard). Header stubs in `include/`: `Windows.h`,
  `wtypes.h`, `d3d9.h`, `conio.h`, `mmeapi.h` (all empty/typedefs-only).
  `cxxLanguageStandard` bumped to C++17 (Tripex's `std::shared_ptr<T[]>`).
- **Chunk 3:** `RendererOpenGL` skeleton — clears framebuffer, allocates
  textures via `glGenTextures`/`glTexImage2D`. `OpenGLTexture` subclass of
  `Texture`. `DrawIndexedPrimitive` is a no-op.
- **Chunk 4 (this commit):** `HostAudioSource` (lock-free-ish ring buffer
  of int16 stereo @ 44.1 kHz; `Push` from Swift, `Read` consumed by Tripex),
  full `DrawIndexedPrimitive` impl (GL 3.2 core VAO/VBO/IBO streaming,
  shader pair that maps `VertexTL` screen-space coords to NDC, RenderState
  → `glBlendFunc`/`glDepthFunc`/`glCullFace`/wrap-mode translation).
  `TripexCore_create` now constructs the whole graph (renderer + audio +
  Tripex) and calls `Tripex::Startup`; failure surfaces as NULL handle.
- **Chunk 5:** full C ABI (19 entry points) + mutex serialization +
  upstream Tripex.{h,cpp} accessors (PortGet…) for effect inventory.
- **Chunk 6 (this commit):** `TripexEngine.swift` conforming to
  `VisualizationEngine`, `.tripex` added to `VisualizationType`, factory
  branch in `VisualizationGLView.createEngine`, `CTripexCore` linked into
  the `NullPlayer` target. Restores `tripex.lastEffectIndex` UserDefault
  on engine creation.
- **Chunk 7:** TripexMenuBuilder + per-engine submenu (effect list, nav,
  hold/audio-info/help toggles). No sliders — Tripex effects own their
  randomization internally.
- **Chunk 8 (this commit):** skills/tripex-port/SKILL.md documentation,
  CLAUDE.md updated to reference the new skill.

### Chunk 6 gotchas

- Module-import shock: `win_compat.h` originally `#include <chrono>` at
  top level. Swift compiles CTripexCore as a C clang module, which fails
  on `<chrono>`. Fix: guard `<chrono>` + GetTickCount64/timeGetTime
  behind `#ifdef __cplusplus`. Effects only run from C++ TUs anyway.
- Linker ODR: `Actor::WORD_INVALID_INDEX` is a class-scope
  `static const uint16` with an in-class initializer. MSVC treats this
  as a definition; clang requires an out-of-class definition when the
  member is ODR-used (e.g. `vector::push_back(WORD_INVALID_INDEX)`).
  Added `upstream_port/tripex_compat.cpp` with the required definition.

### Known Chunk-4 deferrals

- `CreateTextureFromImage` is still unimplemented. If any effect's startup
  loads a PNG/JPG, `Tripex::Startup` will return an error and
  `TripexCore_create` will return NULL — surfaces in Chunk 6 QA.
- `OpenGLTexture::GetPixelData` and `SetDirty` need real impls for any
  effect that does GPU→CPU readback or dynamic upload. Stubbed for now.
- Renderer's base destructor is non-virtual upstream — `~RendererOpenGL`
  is intentionally not marked `override` to satisfy clang.

## Reconnaissance findings

Sourced from upstream commit pulled `--depth 1` from `main` on 2026-05-18.

### License — OK to vendor

Upstream is **MIT** (Copyright (c) 2025 Ben Marsh). Compatible with
NullPlayer's distribution model; `LICENSE` and `README.md` are vendored
verbatim into `upstream/` and excluded from compilation.

### Inline asm — **none**

`grep -rniE '__asm|\b_asm\b' upstream/` returns zero hits. This removes the
single largest risk that bit the Geiss port (24 asm blocks in
`proc_map.cpp`, 6 MMX blocks in `video.h`). No asm porting needed.

### `Renderer` ABI — clean abstraction

`upstream/Renderer.h` (78 lines) defines the abstract base class with **no
D3D types in its public interface**:

- `Error* BeginFrame()` / `Error* EndFrame()` — return values only.
- `Rect<int> GetViewportRect()`, `Rect<float> GetClipRect()`.
- `CreateTexture(width, height, TextureFormat, data, size, stride, palette, flags, out)`.
- `CreateTextureFromImage(data, size, out)`.
- `DrawIndexedPrimitive(RenderState, num_vertices, VertexTL*, num_faces, Face*)`.

`RenderState` is a plain value type — `bool enable_culling`, `bool enable_shading`,
`bool enable_specular`, `BlendMode`, `DepthMode`, `TextureStage[1]`. The blend
modes are pre-baked (Replace / Add / Tint / OverlayBackground /
OverlayForeground / NoOp) — translatable to fixed `glBlendFunc` calls without
needing the full D3D blend-state matrix.

**Implication:** `RendererOpenGL` (Chunk 3) is a faithful subclass exercise.
Concrete D3D code lives in `RendererDirect3d.{cpp,h}` which we exclude
entirely. The plan's `RendererOpenGL` strategy is sound.

### FFT — Tripex computes its own

`upstream/Fourier.cpp` (95 lines) is a complete radix-2 FFT (bit-reversal
table + butterfly loop + Hann-ish apodization window). It consumes raw
`int16_t*` PCM samples directly via `Fourier::Update(const short int*)`.

`AudioSource::Read(void* read_data, size_t read_size)` is the pull-style
interface Tripex uses: every frame, the active effect asks for N bytes of
16-bit stereo @ 44100 Hz.

**Implication:** Chunk 4's `HostAudioSource` only needs a lock-free ring
buffer of `int16_t` stereo samples — **no vDSP / Accelerate work needed**.
This is materially simpler than Geiss's `updateGeissSpectrumFromPCM` (66
lines of Hann + radix-2 + dB-normalize). PCM is pushed from Swift via
`TripexCore_pushPCM(int16_t*, count)` in Chunk 5.

### `main.cpp` — pure Win32 shell, no logic to re-home

269 lines. `WinMain` + `WndProc`. Frame loop is a single line:
```cpp
app->tripex->Render(*app->audio_source);
```
Beat detection, effect switching, fade timing, status messages — **all
already inside `Tripex.cpp`**, accessed through `Tripex::Render`,
`Tripex::MoveToNextEffect`, `Tripex::ChangeEffect`,
`Tripex::ToggleHoldingEffect`, etc.

`main.cpp` only handles: window creation, message pump, keyboard input
(forwarded to Tripex methods), file-open dialog for WAV playback (we ignore
— NullPlayer drives audio), test-tone generator (we ignore).

**Implication:** `main.cpp` is excluded from compilation. `TripexCore.cpp`
(Chunk 5) needs only ~15 LOC of orchestration: construct
`RendererOpenGL` + `Tripex`, then forward Swift-side calls to
`Tripex::Render` / `MoveToNextEffect` / etc. No frame-loop logic to port.

### `Tripex.h` public surface

```cpp
Tripex(std::shared_ptr<Renderer>);
Error* Startup();
Error* Render(AudioSource&);
void   Shutdown();
void   ChangeEffect();           // skip to a new random effect
void   MoveToPrevEffect();
void   MoveToNextEffect();
void   ReconfigureEffect();      // re-randomise current effect's parameters
void   ToggleHoldingEffect();    // lock / unlock auto-switching
void   ToggleAudioInfo();        // debug overlay
void   ToggleHelp();             // help overlay
```

These map 1:1 to C ABI entries planned for Chunk 5. No surprises.

### `Platform.h` — gatekeeps non-MSVC builds

`upstream/Platform.h:24` reads `#error Unsupported compiler.` for non-MSVC.
This will need either an upstream edit (preferred — minimal, scoped to
removing the `#error`) or a preprocessor wrapping shim in Chunk 2 when
upstream `.cpp` files start entering the compile set. Currently a non-issue
because Chunk 1 does not include any upstream sources.

### C++ exceptions — present, default clang handling is sufficient

`nm -u .build/.../CTripexCore.build/upstream/*.o | grep __cxa_throw`
returns hits (Error.cpp throws). Default clang C++ compilation enables
`-fexceptions`, so no additional flag is needed. If we ever switch to
`-fno-exceptions` for binary-size reasons, the upstream `throw` sites must
be rewritten — non-trivial scope, defer indefinitely.

## Exclusion plan (preview for Chunk 2)

Files known up-front to require exclusion from compilation:

- `upstream/main.cpp` — Win32 shell; logic already lives elsewhere (see above).
- `upstream/RendererDirect3d.cpp` / `RendererDirect3d.h` — D3D9 backend; replaced by `upstream_port/RendererOpenGL.{cpp,h}`.
- `upstream/AudioDevice.cpp` / `AudioDevice.h` — WaveOut output; replaced by `upstream_port/HostAudioSource.{cpp,h}`.
- `upstream/AudioData.cpp` — likely depends on AudioDevice; assess in Chunk 2.
- `upstream/packages.config`, `upstream/Tripex.vcxproj*`, `upstream/Dll.vcxproj`, `upstream/Tripex.sln`, `upstream/tripex.jpg`, `upstream/LICENSE`, `upstream/README.md` — non-source.

Upstream `.inl` files are headers and need no exclusion — SwiftPM ignores
them as source.

## Reused infrastructure (read before each later chunk)

- `Sources/CGeissCore/include/win_compat.h` — template for `win_compat.h`.
- `Sources/CGeissCore/PORT_NOTES.md` — template for this file.
- `Sources/CGeissCore/GeissCore.cpp` — mutex/ABI template for Chunk 5.
- `Sources/NullPlayer/Visualization/GeissEngine.swift` — Chunk 6 template.
- `Sources/NullPlayer/Visualization/GeissMenuBuilder.swift` — Chunk 7 template.
- `skills/geiss-port/SKILL.md` — Chunk 8 documentation template.
