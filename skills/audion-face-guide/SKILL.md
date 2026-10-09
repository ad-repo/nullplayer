---
name: audion-face-guide
description: Panic Audion face (folder of index.json + PNGs) skin engine — the FaceKit-derived format, bounded loading and AUD#### codes, the scene/renderer shared by harness and screen, the FaceKit oracle, and Audion-mode app integration. Use before changing Sources/NullPlayer/AudionFace/ or Sources/NullPlayer/Windows/AudionFace/, or when a face draws or behaves wrong.
---

# Audion Faces skin engine

Read this skill before changing `Sources/NullPlayer/AudionFace/` or
`Sources/NullPlayer/Windows/AudionFace/`. The locked decisions — format, provenance, limits, button
mapping, window policy — are `docs/audion-face/phase-0-decision-record.md`. The backlog is
`AUDION_TASKS.md`.

**Status:** Phase 6. The model, bounded loader, scene and renderer exist in
`Sources/NullPlayer/AudionFace/`, with the harness, census, render sweep, load ratchet and FaceKit
oracle; all 856 corpus faces are geometry-identical to FaceKit (`reference/harness.md` § *Measured*).
Audion Faces is a DEBUG-only mode: the face window, transport, drag and docking, install/select/
remove, persistence, NullPlayer's windows in a face-derived gloss frame, every button, the volume
and position sliders, the marquee and animation clock, keys and accessibility (`reference/windows.md`).
NullPlayer's windows beside a face wear a palette sampled from the drawn face, checked for
legibility across the corpus (`reference/windows.md`). The window follows UI Size, redraws only what
changed (`AudionFaceCanvas`), and the loader survives a seeded fuzz (`reference/loading.md`). Phase 7
is public exposure.

## The rule that outranks everything

**Audion work must never change Classic, Original, `.wal` or `.wmz` behaviour.** A change in shared
code (`App/WindowManager.swift` above all) is gated on `controllerFamily == .audion`, never justified
by reasoning that it "should be a no-op". Each phase that touches `App/` ends with Classic, Original,
`.wal` and `.wmz` sweeps byte-identical to the capture before it. A Classic or Original diff is a
regression by definition. `skin-subsystem-blueprint` § *The rule that outranks everything* is the
worked version.

## This engine is a port, and it has an oracle

- **FaceKit is the authority.** Panic's viewer library (GPL-3.0-or-later, pinned at `5b7c847`)
  defines what a face means. The format spec is `reference/format.md`.
- **A diff against the FaceKit oracle is evidence.** Unlike `.wal` and `.wmz`, where a sweep compares
  the engine against its own last guess, the Phase 2 oracle renders what Panic's own code draws.
  A geometry diff there is a defect unless it is a listed departure.
- **A diff against the engine's previous capture is still unclassified.** Classify it against the
  oracle first, then the face's artwork.
- **Departures from FaceKit are listed, never silent.** The table is in the decision record
  § *Deliberate departures from FaceKit*; add a row in the change that adds one.

## Isolation boundary

| Rule | Where |
|---|---|
| Engine and model: pure, no AppKit windows | `Sources/NullPlayer/AudionFace/` |
| AppKit: controller, window, view, host, sliders | `Sources/NullPlayer/Windows/AudionFace/` |
| Tests | `Tests/NullPlayerAppTests/AudionFace*Tests.swift`; fixture faces are synthesized in-test, and `Tests/NullPlayerAppTests/Fixtures/AudionFace/` holds only the corpus load baseline |
| Shared files | only through a gated seam, recorded in `reference/windows.md` |

- Never teach another family's types about faces, and never share code with `WMPArchive` or the
  `.wal` loader; families stay isolated.
- Never use another family's controller, preference or artwork as a default or fallback. The
  fallback is the app-authored `AudionFaceUnskinnedView`.
- Folder walk, zip inflation, JSON decode and image decode run off the main thread. `MainActor`
  receives only a completed immutable `AudionFace`. Never `DispatchQueue.main.sync`.
- **No Panic artwork in the repo** — not `Smoothface 2`, not a fixture. Fixtures are synthesized in
  the test that uses them.
- An adapted FaceKit file keeps Panic's header verbatim; see the decision record § *Provenance and
  attribution*.

## Where everything lives

| Symptom or change | Read |
|---|---|
| a key in `index.json`, a rect, a sprite name, a PICT range, a text colour or font | [reference/format.md](reference/format.md) |
| a face that will not load, an `AUD####` code, a limit, zip import, installing a face | [reference/loading.md](reference/loading.md) |
| wrong pixels: order, nearest-neighbour, mask shape, digits, indicators, marquee, scale | [reference/rendering.md](reference/rendering.md) |
| the face window: hit testing, drag, docking, the sliders, NullPlayer's windows beside a face, placement | [reference/windows.md](reference/windows.md) |
| any measurement — every `AUDION_*` flag, the census, the sweep, the oracle | [reference/harness.md](reference/harness.md) |
| what to work on next | `AUDION_TASKS.md` |
| why a decision was made | `docs/audion-face/phase-0-decision-record.md` |

`reference/harness.md` is the **only** place a probe flag or corpus command is documented. Add a
flag there in the change that adds it.

## Debugging a live defect

Read **`skills/live-ui-testing`** before diagnosing anything that only reproduces on screen, and the
process section it points at — `winamp-modern-skin-guide/reference/harness.md`
§ *Debugging a live defect* — which is the reference implementation of that workflow. Launching,
driving a control and capturing a window are `app-control`'s; do not restate them here.

What is specific to this engine:

1. **Render the same state through the oracle first.** If FaceKit draws it the same way, the engine
   is faithful and the report is about FaceKit semantics or a listed departure. If it differs, the
   defect is in the scene or renderer.
2. **Then compare the renderer's own image with a capture of the window.** Agreement puts the defect
   in the scene; disagreement puts it in the AppKit layer (mask, backing scale, compositing). The
   harness and the screen share one draw path, so they must agree.
3. **Confirm the face before diagnosing.** A launch that failed to select the face shows the
   unskinned view, which looks like a face that does nothing.
4. **A sweep proves the default state only.** Hover, press, a ticking marquee, an animation and
   playback need the state probes (Phase 2, `reference/harness.md`) or the live app. A byte-identical sweep across a change to any of those is unmeasured, not unchanged.

The probe flags and the launch command are in `reference/harness.md`.

## Verification

- `swift test --build-system native` in the worktree (the toolchain's default build system cannot
  find VLCKit; see `scripts/lib/swiftpm.sh`).
- From Phase 2: the census, the render sweep and the oracle comparison, per `reference/harness.md`.
- From Phase 3: the Classic, Original, `.wal` and `.wmz` sweeps byte-identical, and
  `skin-mode-switch-test.sh`.
- Do not commit faces, oracle output or rendered PNGs.
