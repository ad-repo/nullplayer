---
name: fractal-vis
description: NullPlayer-Fractal, the app's own GPU fractal engine — raymarched 3D and 2D escape-time scenes in GLSL, beat-synced through FractalDirector, an adaptive render scale, the shared camera-shot system, and the headless render harness. Use when changing a Fractal scene, its camera, its timing, or its performance.
---

# NullPlayer-Fractal

NullPlayer's own visualization engine, not a port: eleven fractal scenes written as GLSL 330
fragment shaders, driven by the beat. `VisualizationType.fractal` ("NullPlayer-Fractal"); it
answers the preset seam like every engine (see `visualizations`), so it plays in the
Visualizations window, a `.wal` visualization box and the `.wmz` / Sonique effects area with no
host code of its own.

## Files

| File | Owns |
|---|---|
| `Visualization/Fractal/FractalEngine.swift` | The `VisualizationEngine`: GL targets, the three passes, scene programs (compiled lazily, 0 = failed), audio intake, the preset seam, the Render Scale menu, `FRACTAL_TRACE` |
| `Visualization/Fractal/FractalDirector.swift` | Pure Swift, no GL: the beat clock, beat pulse, per-band AGC, parameter springs, palettes. Tests drive it by hand |
| `Visualization/Fractal/FractalScaler.swift` | The render scale: auto from GPU time, or a fixed menu choice |
| `Visualization/Fractal/FractalShaders.swift` | The GLSL shared by every scene (`common`, `raymarch`), and the feedback and present passes |
| `Visualization/Fractal/FractalScenes.swift` | `FractalScene` and the eleven scene bodies (`FractalScenes.all`, in preset order) |
| `Visualization/GLProgram.swift` | Shader compile and link, shared with Geiss |
| `Visualization/BeatFeed.swift` | aubio beats paced onto the render thread, shared with AVS |

## The frame

1. **Scene** pass into an RGBA16F target at the render scale. Alpha is how much of it replaces
   the trails.
2. **Feedback**: a ping-pong RGBA16F pair with mips. Warps the previous frame (zoom, rotation,
   the scene's `swirl`, a hue drift), decays it by the scene's `trail`, and blends the scene in.
   `push` adds forward zoom to the warp (Kaleido IFS presses forward with it).
3. **Present** into the host's framebuffer: bloom from the mips, slight chromatic aberration,
   ACES tonemap, vignette.

Host rules every engine keeps: the draw and read framebuffer bindings are saved and restored, and
blend, depth, scissor and cull state are set every frame. A full-screen triangle comes from
`gl_VertexID` with an empty VAO. A scene change fades the new scene in over the trails for one
bar; a hard cut (⇧, or a host's hard cut) skips the fade.

## Audio and timing (`FractalDirector`)

- **Beats** come from aubio (`addBeatConsumer` and `.audioBeatsUpdated`, through `BeatFeed`), the
  tempo from `.bpmUpdated`. Bass, mid and treble come from the host spectrum
  (`consumesHostSpectrum`: 256 linear bins, about 86 Hz each), bins 1–3, 4–23 and 24–127.
- **The beat clock** (`u_beatTime`) runs at the tempo and is pulled onto each detected beat. It
  never runs backwards; a late beat slows it. Scenes measure motion in beats, so the tempo sets
  the pace. It wraps at 4096 beats in the shader to keep float precision.
- **`u_p`**: four scene parameters on critically damped springs, retargeted every 2 bars from a
  seeded `SplitMix64`, settling over those 2 bars. A parameter that would visibly reshape the
  world under the camera (Fractal Planet's terrain, its towers) must not be one: towers once came
  and went with an eased density.
- **Palettes**: seven IQ cosine palettes, a new one every 4 bars, crossfading over 2.
- **Pace**: the user found the first cut queasy. Orbits run 0.02–0.05 rad/beat, palettes and
  parameters change over bars, and 2D zooms take tens of beats per factor of e. Keep new motion
  calm, but not static: Fractal Planet was "boring" until its speed swung between a crawl and a
  rush within each shot.

## Cameras (the `raymarch` header)

- **Shots**: every 64 beats a new seed (`shotSeed(salt)`), with `shotTime()` the beats into the
  shot. A cut lands under the feedback trails, so it reads as a dissolve.
- `orbitShot(near, far, spread)`: a slow orbit whose radius swings once per shot.
  `flightShot(extent, speed)`: a wander through a box. `keepClear(ro, clearance)` pushes a camera
  out of the surface. `wander(t, seed)` gives a smooth look-around; `explore2D(uv, minZoom)` the
  2D scenes' zoom and pan.
- **Mandelbox Flight stays outside.** Inside, the box is dense foam and every interior camera
  tried was a whirling blur.
- **Menger Dive** zooms ×3 about the edge midpoint (1, 1, 0) every 16 beats with the eye at
  (0, −0.75, 0): a line searched (in Python) to stay at least 0.125 of the current scale from
  any wall. No dive line exists toward a corner.
- **Fractal Planet** flies its own drone camera: it integrates the position along a per-shot path
  (a steady turn plus an S-curve) in 32 legs, so it travels the way it faces; speed is distance
  per beat, swinging every 16–30 beats; height is held over the land's broad shape up to 25 units
  ahead. It is the heaviest scene (170 steps of 7-octave noise).

## Render scale (`FractalScaler`)

Auto times the scene and feedback passes with a 3-slot ring of `GL_TIME_ELAPSED` queries, each read
when its slot comes round again so nothing stalls. Every 0.5 s it shrinks ×0.85 when the passes
take over 0.7 of the frame interval and grows ×1.08 under 0.45, quantised to 5% within 0.35–1.0.
It starts near 1280 px across. Trails are blitted into the resized targets so a change does not
flash. Render Scale ▸ 50% / 75% / 100% fixes it (`fractal.renderScale`; 0 is Auto).
On a 120 Hz display the frame interval is 8.3 ms, so Fractal Planet settles near 40% at about
1050×1100 (measured 2026-11-13).

## Persistence

`fractal.scene` (the preset index) and `fractal.renderScale`, both cleared by Reset All
Visualization Preferences. The cycle default is Auto-Random (`VisualizationCycleSettings`).

## Adding a scene

Append a `FractalScene` to `FractalScenes.swift` and to `FractalScenes.all` (the end, so saved
indices stay put). A `.raymarched` body defines `float de(vec3 p, out vec4 trap)` and
`vec4 scene(vec2 frag)`; a `.flat` body only `scene`. Then render it headless (below) for a full
shot or two and look at the frames.

## Tests and the headless harness

- `FractalRenderTests` runs every scene in an offscreen GL 3.2 core context at 640×360 with
  simulated 120 BPM music, and fails a scene that errors or draws nothing. With
  `FRACTAL_RENDER_DIR=<dir>` it writes a PNG every 20 frames; `FRACTAL_SCENES="Menger Dive,..."`
  limits the scenes and `FRACTAL_SECONDS` sets each run (default 4 with a render dir; a shot is
  64 beats, 32 s). Contact sheet: list the PNGs in a file and `magick montage @list.txt -tile 4x4
  -geometry 400x225+2+2 out.png` (zsh does not split an unquoted command substitution).
- `FractalDirectorTests`: the beat clock, parameter ranges and retarget cadence, seeding; `FractalScalerTests`: the render scale.

## Debugging a live defect

Read [`live-ui-testing`](../live-ui-testing/SKILL.md) and `winamp-modern-skin-guide/reference/harness.md`
§ *Debugging a live defect* first. To open straight on a scene:

```bash
defaults write NullPlayer visualizationEngineType "NullPlayer-Fractal"
defaults write NullPlayer fractal.scene -int 10   # index into FractalScenes.all
FRACTAL_TRACE=1 skills/app-control/scripts/launch.sh aquamp -- -winampModernShowVisualization 1
```

`-winampModernShowVisualization 1` opens the Visualizations window on any skin. `FRACTAL_TRACE`
(DEBUG) logs once a second: `FRACTAL scene=… render=WxH scale=… gpu=…ms bpm=… beats=… bar=…
phase=… bands=b/m/t`. A shader that fails to compile logs under `GLProgram`'s label and the scene
draws nothing; the headless test catches that first.
