# Tripex port — current state and rendering-issue handoff

Branch: `tripex-port-chunk-1`. Build is green. UI surface (menu, hotkeys,
cycle controls, persistence) is complete. **Rendering is broken**: most
effects display as solid black; a handful of grid-based effects display
but several visual issues remain. This document is the handoff for the
agent continuing the rendering debug.

## What works

- Vendoring, win_compat shims, mixed C++/Swift target builds clean.
- `swift build` → green; `./scripts/build_dmg.sh` produces a working DMG.
- Engine selection (right-click → Visualization Engine → Tripex)
  switches to TripexEngine; viewport resizing, PCM push, frame render
  all wire up.
- Embedded JPEG texture blobs decode via CoreGraphics / ImageIO in an
  isolated TU (`upstream_port/ImageDecode.cpp`) — Tripex::Startup no
  longer fails.
- On-screen hotkey help overlay is suppressed by default
  (`h->tripex->ToggleHelp()` in `TripexCore_create`).
- Right-click menu mirrors ProjectM's structure for uniform UX across
  the three visualization engines (Geiss has its own slightly different
  Auto-Switch submenu — unifying all three is a follow-up).
- Bare-key shortcuts ←/→/R work in both classic and modern
  `ProjectMView.keyDown` for `.tripex`, matching ProjectM/Geiss.
- Cycle controls: Manual Only / Auto-Cycle / Auto-Random + Cycle
  Interval (5/10/20/30/60s, 2min). Swift drives the timer; Tripex is
  held via `PortSetHold(true)` so its internal cycle doesn't fight.
- State persisted in UserDefaults
  (`tripex.lastEffectIndex`, `tripex.cycleMode`, `tripex.cycleInterval`).
- "Blank" effect (internal fade helper, `enabled_effects[0]`) hidden
  from the user-facing API; next/previous wrap.

## What is broken

User-reported observations (in order, most recent last):

1. "Mostly black, occasional fade-bys" → tracked to runaway frames
   accumulator. **Fixed** in `56c80a8`.
2. "Most effects don't work; only Distortion1, Distortion2 and DotStar
   display but DotStar doesn't react to audio."
3. After my attempted CW→CCW front-face change (`2b10308`):
   "Now nothing works."
4. After reverting and disabling culling unconditionally (`687aa3f`):
   **awaiting user re-test as of handoff**.

The user has not yet tested commit `687aa3f`. The hypothesis is:
- Grid-based effects (Distortion*, DotStar) end up CW in NDC after the
  vertex shader's Y-flip → previously worked with `glFrontFace(GL_CW)`,
  broke with `GL_CCW`.
- Actor-based 3D effects (Tunnel, Sun, Light*, MorphingSphere,
  BezierCube, Spectrum, Rings, MotionBlur*) ended up with the opposite
  winding because of L-handed→R-handed coord asymmetry in Actor's CPU
  projection → broken with either `glFrontFace` value.
- Disabling cull entirely should make both categories visible, even if
  some triangles draw back-to-front; that's the current state.

**If `687aa3f` doesn't restore the previously-working effects**, my
hypothesis is wrong; revisit the `glFrontFace` / shader Y-flip story
from scratch. See "Coordinate-system pitfalls" below.

## Fix attempts so far (chronological)

| Commit | What it changed | Result |
|---|---|---|
| `849bcfa` | JPEG decode via ImageIO (was: stub returning Error) | `Tripex::Startup` succeeds, but visualizer still black |
| `4a0616e` | Always bind a 1×1 white texture to unit 0 when no stage set | Silences macOS GL3 "GLD_TEXTURE_INDEX_2D unloadable" warning |
| `fffb935` | (diagnostic only) Disable depth/cull globally + dark-blue clear + draw logging | Revealed Tripex was issuing draw calls (~240/frame); confirmed effects were *drawing* something but it was rendering invisibly |
| `5aa2fd0` | Remove the diagnostic stderr draw-counter | — |
| `ece9844` | `TripexCore_create` calls `ToggleHelp()` to suppress the hotkey overlay | Overlay gone |
| `8e64cb1` | Restored RenderState-driven depth/cull/blend (removed diagnostic disable); wired Tripex menu into classic `ProjectMView` (it was only in Modern) | Classic-mode menu items appear; rendering still problematic |
| `9a819eb` | **Implement `OpenGLTexture::SetDirty`** — store CPU buffer / stride / palette on Dynamic textures, expand P8→BGRA via palette on bind, upload via `glTexSubImage2D` | Canvas-based effects can now actually animate (their per-frame mutated pixel buffer reaches the GPU) |
| `c745932` | Bare-key ←/→/R hotkeys + strip Cmd-modifier menu key equivalents | UX parity with ProjectM/Geiss |
| `56c80a8` | **Fix `frames +=` → `frames =`** in `upstream/Tripex.cpp` Render | Eliminated runaway auto-cycle (~1–5 s) and runaway `CanRender(frames > 3.8)` short-circuit. Many more effects *should* render correctly than before this fix |
| `6e8abc3` | Cycle controls (Manual/Cycle/Random + Interval) | Standard ProjectM-style controls added |
| `23239d6` | Hide internal "Blank" effect (index 0); wrap navigation; `PortJumpToEffect` for direct seek | Effects submenu starts with first real effect; arrows wrap |
| `2b10308` | (BAD) `glFrontFace(GL_CW)` → `GL_CCW` thinking the shader Y-flip inverted winding | Broke the previously-working grid effects → "now nothing works" |
| `687aa3f` | Removed `glFrontFace` setting entirely; force-disabled `GL_CULL_FACE` regardless of `RenderState.enable_culling` | Current state — awaiting user re-test |

## Architecture quick reference

- **C++ core**: `Sources/CTripexCore/upstream/` (vendored, three patch
  files: `Platform.h` `#error` → win_compat include; `Tripex.h`/`Tripex.cpp`
  Port accessors; one-char fix in `Tripex::Render`).
- **OpenGL backend**: `Sources/CTripexCore/upstream_port/RendererOpenGL.{h,cpp}`,
  `HostAudioSource.{h,cpp}`, `ImageDecode.cpp`, `tripex_compat.cpp`.
- **C ABI bridge**: `Sources/CTripexCore/TripexCore.cpp` +
  `Sources/CTripexCore/include/TripexCore.h`.
- **Swift engine**: `Sources/NullPlayer/Visualization/TripexEngine.swift`.
- **Menu builder**: `Sources/NullPlayer/Visualization/TripexMenuBuilder.swift`.
- **View integration**:
  `Sources/NullPlayer/Windows/ProjectM/ProjectMView.swift` (classic),
  `Sources/NullPlayer/Windows/ModernProjectM/ModernProjectMView.swift` (modern)
  — `TripexMenuTarget` conformance, `addTripexEffectsMenuItems`,
  `tripexCycleMode/Interval/Timer`, `applyTripexCycleMode`, 8 @objc
  forwarders, `keyDown` `.tripex` branches.

## Coordinate-system pitfalls (the part that's tripping us up)

Tripex's `Renderer` interface is built around `VertexTL` — pre-transformed
2D screen-space vertices (D3D9 `D3DFVF_XYZRHW` analog), with:
- `position.x, position.y` in screen pixels, **top-down origin** (D3D
  convention: y grows downward)
- `position.z` typically in `[0, 1]` after Actor projection (`v.z * mult_z`,
  `mult_z = 1/clip_max_z`)
- `rhw` ≈ 1/clip_space_w (used for sprite-size scaling etc.)

My vertex shader maps these to NDC:
```glsl
float x = (in_position.x / u_viewport.x) * 2.0 - 1.0;
float y = 1.0 - (in_position.y / u_viewport.y) * 2.0;   // flips Y
float z = in_position.z;
gl_Position = vec4(x, y, z, 1.0);
```

The Y-flip is necessary so the image isn't upside-down, but it inverts
triangle winding sign relative to screen coords.

### Two categories of triangle source

1. **2D-screen-space effects** (Distortion1/2, DotStar, Spectrum
   overlays, Canvas tile quads, GeometryBuffer overlays): Tripex emits
   triangles wound CW in top-down screen coords. After Y-flip those are
   CW in NDC → require `glFrontFace(GL_CW)` to render with culling on.

2. **Actor-projected 3D effects** (Tunnel, Sun, all Light*, all
   MotionBlur*, MorphingSphere, BezierCube, Rings, Phased): Tripex's
   `Actor::Render` does a CPU-side camera transform that was authored
   for D3D9's left-handed convention. After projection to screen
   coords, the resulting winding empirically appears to be the
   *opposite* of category 1.

There is no single `glFrontFace` value that satisfies both.

### Options the next agent should consider

- **Keep cull disabled (current state).** Pragmatic; no effect's
  *correctness* depends on backface culling. Downsides: a tiny perf
  loss; transparent shells (e.g. Tunnel) may draw back faces in front
  of front faces, which combined with depth could produce visual
  artifacts.
- **Y-flip in the framebuffer instead of the vertex shader.** Render
  upside-down to an FBO and blit-flip at the end. Eliminates the
  winding inversion entirely — winding then matches whatever Tripex
  emits, and `glFrontFace(GL_CW)` is correct for everything. Largest
  change but cleanest semantics.
- **Per-effect winding override.** Have `Actor::Render` (or a
  port-side wrapper) reverse face indices before passing to
  `DrawIndexedPrimitive`. Local to the 3D path; doesn't touch 2D
  effects.
- **Negate the projection's z or y in `Actor`'s CPU transform.** D3D9
  → GL handedness flip in one place. Highest semantic fidelity to "I'm
  making this OpenGL look like D3D9" but easiest to break subtly.

## Known unrelated issue: DotStar audio reactivity

`EffectDotstar.cpp` reads `params.audio_data.GetIntensity()` exclusively
for rotation/speed/spawn rate. User reported DotStar "displays but
doesn't do anything" — i.e. intensity reads as zero or near-zero. After
the frames-accumulator fix, this might already be resolved (the bug was
making per-effect time blow up, which clamped intensity-derived deltas).
If not, verify the audio path:

- `TripexEngine.addPCMMono` (Sources/NullPlayer/Visualization/TripexEngine.swift)
  converts Float mono [-1, 1] → int16 stereo × 32767 and pushes to
  `HostAudioSource`.
- `HostAudioSource::Read` (Sources/CTripexCore/upstream_port/HostAudioSource.cpp)
  pulls from a ~2-second ring buffer; pads with silence on underflow.
- `AudioData::Update` (upstream/AudioData.cpp:42) pulls 1024 int16s per
  frame at the default elapsed time (matches our per-frame push of
  512 mono samples → 1024 stereo int16s).
- `AudioData::GetIntensity` is computed from `mono_samples` mean abs;
  scale factor `(576/512) / (10 * num_samples * 256)` and a soft
  compander `i *= 1/(i+0.6)`.

If you see DotStar staying static on loud audio, instrument
`HostAudioSource::Push` and `AudioData::Update`'s `intensity` value to
narrow it down. Most likely it's fine after the frames fix.

## Other things to verify if effects still misbehave

- **Depth buffer interaction.** Default `DepthMode::Normal` →
  `glDepthFunc(GL_LEQUAL)` + depth writes on. Tripex's vertices have
  `z ∈ [0, 1]` after Actor projection (`v.z * mult_z`, `mult_z = 1/clip_max_z`).
  We clear depth to 1.0. A vertex with `z == 1.0` lands exactly at far
  plane and passes LEQUAL once, then occludes itself. Could cause
  flicker or self-occlusion for Actor effects clustered near the far
  plane.
- **Texture filter / wrap for static effects.** `CreateTexture` sets
  filter from `TextureFlags::Filter`. `CreateTextureFromImage` sets
  filter=LINEAR, wrap=REPEAT unconditionally. Some effects toggle
  `TextureAddress::Clamp` vs `::Wrap` per-frame — we honor that in
  `DrawIndexedPrimitive`.
- **Blend modes.** We translate 6 modes: NoOp/Replace/Add/Tint/
  OverlayBackground/OverlayForeground. `NoOp` uses
  `glBlendFunc(GL_ZERO, GL_ONE)` (preserves dest) — verify that's
  intended (D3D9 equivalent comment in upstream says it's a no-op
  draw, i.e. "don't write anything new").
- **Specular term.** Vertex shader passes `specular` as RGBA; fragment
  shader does `frag_color = vec4(base.rgb + v_specular.rgb, base.a);`
  unconditionally. D3D9 RenderState's `enable_specular` should gate
  this; we currently apply specular always. Could overbright some
  effects.
- **`rhw` use.** We pass `rhw` as a vertex attribute but never
  consume it in the fragment shader for perspective-correct texture
  interpolation. For pre-transformed VertexTL this is usually fine,
  but Actor's projection bakes 1/z into rhw — some effects might
  expect perspective-correct sampling.

## Reproducing locally

```
git checkout tripex-port-chunk-1
./scripts/kill_build_run.sh
# Right-click visualizer → Visualization Engine → Tripex
# Use ←/→/R to navigate effects, or Effects submenu to jump.
```

## Files most relevant to the rendering debug

- `Sources/CTripexCore/upstream_port/RendererOpenGL.cpp` — shader, draw
  call, blend/depth/cull setup, texture upload (with the SetDirty +
  P8 palette-expand path)
- `Sources/CTripexCore/upstream/Tripex.cpp` — Render loop, fade logic,
  effect cycling (contains the `frames =` patch and the new
  PortJumpToEffect / PortSetHold / PortGet* accessors)
- `Sources/CTripexCore/upstream/Actor.cpp` — Camera projection that
  produces Actor-effect VertexTL stream (likely owns the winding-flip
  issue for 3D effects; *not modified* in this port — patching here
  would mean touching upstream)
- `Sources/CTripexCore/upstream/VertexGrid.cpp` — Grid face emission
  (likely owns the working 2D effects' winding)
