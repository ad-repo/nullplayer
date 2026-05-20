# Tripex Port Status

Branch: `tripex-port-chunk-1`.

Current state: build is green, Tripex is usable from the NullPlayer visualizer
window, menu/key navigation works, fullscreen rendering has been fixed, and
the previously blocking/stalling effects reported during this session have
targeted fixes. Remaining work is visual QA and further profiling, especially
for Tube and WaterGlobe on lower-power machines.

## Verification

- `swift build` passes after the latest Tube/WaterGlobe optimization pass.
- The user manually tests by running `./scripts/kill_build_run.sh`; do not rely
  on launching a separate app instance unless explicitly requested.

## Current User-Confirmed Fixes

- Actor-based effects no longer render black after fixing
  `RendererOpenGL::GetClipRect()` to return viewport pixel coordinates.
- Fullscreen no longer stalls after window transition / occlusion handling
  fixes in `VisualizationGLView` and both ProjectM window controllers.
- Flowmap no longer stalls on selection.
- MotionBlur1 and Phased no longer stall on selection.
- WaterGlobe and Tube look better after removing the transparent z pre-pass
  and feeding PCM during skipped 30fps draw ticks.

## Menu / Control Surface

- Right-click Tripex menu has ProjectM-style parity:
  - Next / Previous / Random / Randomize Effect Settings.
  - Hold Current Effect.
  - Auto-Cycle / Auto-Random + Cycle Interval.
  - Intensity submenu from `0.25x` to `4.0x`.
  - Show Audio Info / Show Help.
  - Effects submenu with checked current effect.
- There is no "Manual Only" item. Clicking a checked Auto-Cycle or Auto-Random
  item unchecks it and disables cycling.
- Tripex's transient effect-name overlay is disabled; state is surfaced through
  native menus instead.

## Persistence

UserDefaults keys currently used:

- `tripex.lastEffectIndex`
- `tripex.cycleMode`
- `tripex.cycleInterval`
- `tripex.intensityScale`

## Rendering / Timing Fixes

- `Tripex::Render` uses per-frame `frames = ...`, not the old accumulating
  `frames += ...`, to avoid runaway cycling and bad effect timing.
- Effects whose `CanRenderImpl` assumed accumulated skipped-frame timing now
  opt into every-frame rendering:
  - Flowmap
  - MotionBlur1
  - Phased
- Flowmap fixes:
  - Initializes `nCalcX`, `nCalcY`, `dFrames`, and `dOscFade`.
  - Uses a fixed millisecond work budget instead of `CLOCKS_PER_SEC`, which is
    1,000,000 on macOS and caused long stalls.
- Low-power / 30fps mode still feeds PCM on skipped draw ticks, so Tripex's
  elapsed-time audio reader is not starved when drawing is throttled.

## OpenGL Port State

- `RendererOpenGL::GetClipRect()` returns the D3D-style viewport-space clip
  rectangle used by `Actor.cpp`; returning NDC clips away most Actor effects.
- Culling is still force-disabled in `RendererOpenGL` because 2D/grid effects
  and Actor-projected effects have conflicting winding after the shader Y flip.
- Overlay blend modes use inverse source color, matching the D3D9 behavior.
- Normal depth uses `GL_LESS`, matching D3D9 `D3DCMP_LESS`.
- Specular is gated by the render state's `enable_specular` flag.
- `OpenGLTexture::GetPixelData` is implemented with `glGetTexImage`.
- Dynamic P8 texture uploads reuse an upload scratch buffer.
- Canvas tile rendering uses stack vertices/faces instead of per-tile vectors.
- Streaming VBO/IBO capacity is retained and orphaned before sub-data uploads.

## Tube / WaterGlobe Notes

These two effects are the current performance-sensitive area.

- Tube:
  - Transparent z pre-pass disabled for the port because culling is globally
    disabled and the pre-pass could write interior/back-face depth.
- WaterGlobe:
  - Transparent z pre-pass disabled for the same culling/depth reason.
- An attempted analytic/radial normal optimization for both effects improved
  CPU cost but degraded the look, so it was reverted. Keep the original normal
  rebuilds unless a visual-equivalent replacement is found.
- If either still struggles, the next pragmatic knob is mesh LOD:
  - WaterGlobe currently uses `CreateTetrahedronGeosphere(200, 5)`.
  - Dropping to 4 iterations should be a large CPU/GPU reduction, but it is a
    visible fidelity tradeoff and should be tested deliberately.

## Files Most Relevant To Current Work

- `Sources/CTripexCore/upstream_port/RendererOpenGL.{h,cpp}`
- `Sources/CTripexCore/upstream/Tripex.{h,cpp}`
- `Sources/CTripexCore/upstream/EffectFlowmap.cpp`
- `Sources/CTripexCore/upstream/EffectMotionBlur1.cpp`
- `Sources/CTripexCore/upstream/EffectPhased.cpp`
- `Sources/CTripexCore/upstream/EffectTube.cpp`
- `Sources/CTripexCore/upstream/EffectWaterGlobe.cpp`
- `Sources/NullPlayer/Visualization/VisualizationGLView.swift`
- `Sources/NullPlayer/Visualization/TripexEngine.swift`
- `Sources/NullPlayer/Visualization/TripexMenuBuilder.swift`

## Reproduce

```bash
./scripts/kill_build_run.sh
```

Then right-click the visualizer, choose **Visualization Engine -> Tripex**,
and use the effects submenu or bare arrow keys to move through effects.
