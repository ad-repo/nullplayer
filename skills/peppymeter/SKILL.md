---
name: peppymeter
description: The PeppyMeter analog VU meter window — a skinnable needle/bar meter (port of project-owner/PeppyMeter) in classic + modern UI. Covers the meters.txt geometry, the CoreGraphics compositor (needle rotation + linear masks), the stereo-tap level model, meter selection/random, bundled GPL assets, and WindowManager integration. Use when modifying the PeppyMeter window, its renderer, meter templates, or level plumbing.
---

# PeppyMeter Window

A skinnable **analog VU meter** window — a native Swift port of
[project-owner/PeppyMeter](https://github.com/project-owner/PeppyMeter). It renders left/right audio
levels on classic analog **needle (circular)** and **bar (linear)** meters composited from bundled
image templates. Two implementations (classic/modern UI) share one mode-neutral engine, following
the same standalone-window pattern as the [spectrum-analyzer-window](../spectrum-analyzer-window/SKILL.md)
and Audio Analyzer windows.

## Accessing

- Main-window right-click context menu → **PeppyMeter**
- Window menu → **PeppyMeter**
- Available in classic and modern UI modes.

## What it shows

- **Circular meters** — one rotating needle per channel (stereo) or a single needle (mono), swinging
  between per-meter start/stop angles.
- **Linear meters** — a bar (or single moving indicator) per channel that grows with level.
- Right-click the window to pick any bundled meter or toggle **Random** (auto-switches on an interval).

The default catalog is the PeppyMeter **480×320** templates (25 meters: `bar`, `vintage`, `blue`,
`compass`, `chillout`, `big-bang`, …). Higher-resolution sibling sets (`800x480`, plus the partial
wide `1280x400` set) are bundled for sharper large-window/fullscreen rendering. Mixed `.png`/`.jpg`
backgrounds are supported.

## Audio path (levels)

PeppyMeter reuses the **existing stereo tap** — it does **not** add a new audio tap.

- `PeppyMeterLevelModel` registers a `stereo` consumer via
  `WindowManager.shared.audioEngine.addStereoConsumer("peppyMeter")` while the window is shown, so the
  tap stays idle when no meter is open (removed on hide/close/teardown).
- It observes `.audioStereoPCMDataUpdated` (userInfo `left`/`right` = 512 samples, `sampleRate`),
  computes per-channel level with `AudioAnalysisDSP.rmsDBFS`, and maps dBFS → PeppyMeter's 0…100
  volume via `PeppyMeterLevels.volume(fromDBFS:floor:)` (default floor −42 dB).
- A **60 Hz timer** applies VU ballistics (fast attack / slow release) and drives redraws, so the
  needle keeps falling toward zero on silence (when no notifications arrive). Redraws are skipped once
  the needles settle, so an idle meter costs nothing.

This is the same stereo path the Audio Analyzer's Levels/Delay panes use — see
[audio-analysis-window](../audio-analysis-window/SKILL.md). Any change to the stereo tap must still be
emitted by **both** `AudioEngine` and the `StreamingAudioPlayer` delegate route.

## Rendering (CoreGraphics compositor)

`PeppyMeterRenderer.draw(template:leftVolume:rightVolume:in:context:)` composites
**background → needle(s)/indicator(s) → optional foreground**, scaled-to-fit (aspect preserved,
centered) into the window's content rect. Ported faithfully from PeppyMeter's `circular.py`,
`linear.py`, `needlefactory.py`, and `maskfactory.py`.

- **Coordinate space.** `meters.txt` uses a **top-left, y-down** pixel space; CoreGraphics is
  **bottom-left, y-up**. Top-left points are converted with `y_bl = H − y_topLeft` (`H` = the
  meter's native background-image height).
- **Circular needle.** The needle image points up at angle 0; its pivot, in image-local coords, is
  `(w/2, h/2 + distance)` and is placed at the channel origin `(origin_x, origin_y)`.
  `angle = start + (volume/100)·(stop − start)` degrees, **CCW-positive** (`ctx.rotate(by:)`). Stereo
  uses `left/right.origin.*` + `left/right.start/stop.angle`; mono uses `mono.origin.*` (angles fall
  back to the shared `start.angle`/`stop.angle`). Origins may sit off-canvas (e.g. `vertical-circular`).
- **Linear bar.** `linearMasks` is a cumulative pixel-width table
  (`masks[n] = n·step.width.regular`, then the overload zone adds `step.width.overload` steps). Volume
  picks a step index → reveal width `w`. A **growing** bar crops the indicator to `w` per `direction`
  (`left-right`, `right-left`, `bottom-top`, `top-bottom`; `center-edges`/`edges-center` are resolved
  per channel). A `single` indicator (`indicator.type = single`, e.g. `chillout`) instead **moves** the
  whole sprite by `w`. `flip.left.x`/`flip.right.x` mirror the indicator image (cached).

Rendering matches `SkinRenderer`'s CoreGraphics approach; there is no Metal here.

### Window compositing

Classic and modern PeppyMeter windows draw the animated meter content separately from the window
chrome:

- `PeppyMeterPresenter.onNeedsDisplay` must call the view's `requestMeterRedraw()` method, not
  `needsDisplay = true`, for normal VU ticks. This invalidates only the meter content rect, so the
  static window border is not repainted at 60 Hz.
- Both views clip `PeppyMeterDrawing.draw(...)` to the chrome content rect. Keep this clip in place; some
  templates have artwork near their own edges and must never paint over the app window border.
  Modern skins do not add an extra PeppyMeter-specific gutter beyond the shared auxiliary chrome inset.
  In every render style the modern meter content rect expands through adjacent joined chrome strips (via
  `NSRect.expandingThroughJoinedEdges`) so no ~1px seam shows on a docked edge — this is not metal-only
  (issue #364). The helper is bounded to small edge-adjacent gaps so content cannot jump across a
  visible title bar/chrome gap.
- Do not add a PeppyMeter-specific outer padding around the modern meter content. That recreates the
  old heavy-border look. If a template needs spacing, handle it inside the meter compositor or template
  layout, not by shrinking the whole window content rect.
- Classic PeppyMeter draws the skin chrome after the meter content by using
  `SkinRenderer.drawSpectrumAnalyzerWindowChromeOverlay(...)`. The normal spectrum chrome method fills
  the whole window and is not suitable as a border-only overlay.

## meters.txt & bundled assets

- Templates live in `Sources/NullPlayer/Resources/PeppyMeter/<resolution>/` (currently `480x320/`,
  `800x480/`, and `1280x400/`), auto-included by the existing `.copy("Resources")` in `Package.swift`
  — no `Package.swift` change to add a resolution folder. `PeppyMeterLibrary` discovers configured
  folders via `BundleHelper.url(forResource:withExtension:subdirectory:)` and chooses the best
  same-name template for the current draw size, falling back to the full `480x320` catalog.
- `PeppyMeterConfig.parse` reads the INI-style `meters.txt`; each section keeps a template only if it
  has a valid `meter.type` **and** its background image loads.
- **Licensing.** The bundled meter images + `meters.txt` are **GPL-3.0** (from PeppyMeter). They live in
  their own folder with `Resources/ThirdPartyLicenses/PeppyMeter_NOTICE.txt`. The NullPlayer rendering
  engine (`Sources/NullPlayer/PeppyMeter/`) is an independent implementation.

## Selection, random, persistence

`PeppyMeterPresenter` (mode-neutral) owns the level model, the random-switch timer, the current
template, and the right-click menu. Settings persist to `UserDefaults` (independent of Remember State),
via `PeppyMeterSettings`:

- `peppyMeterCurrentMeter` — selected meter name
- `peppyMeterRandomEnabled` — Random toggle
- `peppyMeterRandomIntervalSeconds` — switch interval (default 20 s)

Window visibility + frame are saved in `AppStateManager` session state (`isPeppyMeterVisible` /
`peppyMeterWindowFrame`), mode-gated like the other center-stack windows.

## WindowManager integration

Registered as `CenterStackWindowKind.peppyMeter`. `showPeppyMeter` / `togglePeppyMeter` /
`isPeppyMeterVisible` / `peppyMeterWindowFrame` mirror the Audio Analyzer / Network Monitor methods
exactly, and the controller is threaded through every window collection (docking, snapshots,
always-on-top, UI Size, Hide Title Bars, compact-mode snapshots, mode teardown/rebuild) and the
classic frame-repair path (`repairClassicCenterStackFrames`). It docks/snaps flush in the vertical
stack, opens at main-window width, and is vertically stretchable like the spectrum/analyzer windows.
Its default/minimum height is `1.75×` the normal center-stack height, rounded to whole pixels, because
the bundled meter templates are landscape-oriented. Saved legacy double-height PeppyMeter frames are
normalized down to this landscape height on restore/repair.

## Architecture / key files

Engine (mode-neutral — **must not** import `Skin/` or `ModernSkin/`):
- `PeppyMeter/PeppyMeterConfig.swift` — `meters.txt` parser → `[PeppyMeterTemplate]`
- `PeppyMeter/PeppyMeterLibrary.swift` — template + image loading/caching; `PeppyMeterSettings`
- `PeppyMeter/PeppyMeterRenderer.swift` — CoreGraphics compositor (needle + linear geometry)
- `PeppyMeter/PeppyMeterLevelModel.swift` — stereo consumer + dBFS→volume + ballistics; `PeppyMeterLevels`
- `PeppyMeter/PeppyMeterPresenter.swift` — shared runtime + `PeppyMeterDrawing` + menu

Windows + protocol:
- `App/PeppyMeterWindowProviding.swift` — `: ModeDependentWindow`
- `Windows/PeppyMeter/PeppyMeterWindowController.swift` + `PeppyMeterView.swift` (classic chrome, `SkinRenderer`)
- `Windows/ModernPeppyMeter/ModernPeppyMeterWindowController.swift` + `ModernPeppyMeterView.swift` (modern chrome, `ModernSkinRenderer`)

Assets: `Resources/PeppyMeter/{480x320,800x480,1280x400}/` (+ `ThirdPartyLicenses/PeppyMeter_NOTICE.txt`).
Tests: `Tests/NullPlayerAppTests/PeppyMeterConfigTests.swift` (parser + mask table + dBFS→volume math
and window geometry restore coverage).

## Gotchas

- **Mode independence.** `Windows/ModernPeppyMeter/` must never import from `Skin/` or
  `Windows/MainWindow/`; the shared engine under `Sources/NullPlayer/PeppyMeter/` stays mode-neutral
  (no skin imports). Only the classic shell may use `Skin/`.
- **No new audio tap.** PeppyMeter consumes the existing `.audioStereoPCMDataUpdated` stream. Don't add
  a dedicated tap; register/deregister the `stereo` consumer with show/hide so it's idle when closed.
- **Don't invalidate chrome on VU ticks.** Use `requestMeterRedraw()` for level animation updates. Full
  `needsDisplay = true` is reserved for skin changes, fullscreen transitions, resize, titlebar state,
  and other events where chrome really changed.
- **GPL assets.** The bundled meters are GPL-3.0 and isolated in `Resources/PeppyMeter/`. For a build
  that can't ship GPL assets, drop that folder — the renderer shows a "No meters bundled" placeholder.
- **Coordinate flip.** Get the top-left→bottom-left conversion right (needle pivot Y, linear anchor Y,
  rotation sign) — see [ui-guide](../ui-guide/SKILL.md) for the skin top-left vs macOS bottom-left rule.
- **Native size varies.** Some backgrounds are `.jpg`; the meter's canvas size comes from the
  background image, not a hardcoded 480×320.

See [audio-analysis-window](../audio-analysis-window/SKILL.md) for the shared stereo path and
[visualizations](../visualizations/SKILL.md) for the visualization/meter index.
