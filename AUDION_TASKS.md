# Audion Faces — open backlog

The only live backlog for the Audion face subsystem, and a list of open rows — nothing else. Read
`skills/audion-face-guide/SKILL.md` before picking anything up.

- The locked decisions are [`docs/audion-face/phase-0-decision-record.md`](docs/audion-face/phase-0-decision-record.md).
  The phased plan the rows below were seeded from is `~/.claude/plans/in-a-worktree-only-rippling-kay.md`.
- Closed rows move to [`docs/audion-face/backlog-archive.md`](docs/audion-face/backlog-archive.md) in
  the change that closes them. That file's § *Issuing a number* holds the next free number.
- `.wmz` work goes in [`WMP_TASKS.md`](WMP_TASKS.md), `.wal` work in [`WINAMP5_TASKS.md`](WINAMP5_TASKS.md).

**Agent-verifiable rows** (marked *autonomous*) are closed by the agent against their exit criteria.
**UI rows** stop for an on-screen check by the user before tests, docs or changelog entries are added.
Every row that touches `App/` ends with Classic, Original, `.wal` and `.wmz` sweeps byte-identical
to the capture before it.

## Engine

| ID | Item | Reach | Notes |
|---|---|---|---|
| A2 | **Phase 1 — model and loader**, pure and off the main thread: `AudionFaceDocument`, `AudionFaceGeometry`, `AudionFacePolicy`, `AudionFaceDiagnostics`, `AudionFace` (adapted from FaceKit, Panic header kept), `AudionFaceLoader`, `AudionFaceZipImport` | whole corpus; gates every later row | *Autonomous.* Tests synthesize fixture faces in-test: every `AUD####` code, zero rects, missing pause/hover sprites, the 10- vs 11-frame digit rule, missing animation frames, mask mismatch, whitespace in names. Add the `facekit` row to `scripts/third_party_components.tsv` with the first adapted file (decision record § *Provenance and attribution*). The loader does not read the five files FaceKit ignores. Set `AUD0010`'s zip bounds with the fixtures that prove them. **Exit:** `swift test --build-system native` green. |
| A3 | **Phase 2 — scene, renderer, harness and FaceKit oracle**, before any window: `AudionFaceHostState`, `AudionFaceInteractionState`, `AudionFaceScene`, `AudionFaceRenderer`; `AudionFaceRenderDumpTests.testSweepsFaceOrCorpus` with the `AUDION_*` flags; census, render sweep and load ratchet; `scripts/audion_facekit_reference.sh` + `scripts/audion_oracle_compare.py` | whole corpus | *Autonomous.* One draw path for harness and screen. Output through a locked `write(2)` emitter copied from `WMPHarnessOutput`. Oracle output never committed. The census confirms or refutes the meaning of the five files FaceKit ignores. The oracle comparison renders with no track index (decision record § *Deliberate departures from FaceKit*). **Exit:** census prints the measured count with failures classified by code; ≥ 95% of the corpus geometry-identical to the oracle, each remaining face an `A` row or a dossier; two identical captures prove determinism. |

## App integration

| ID | Item | Reach | Notes |
|---|---|---|---|
| A4 | **Phase 3 prerequisite — derive `isRunningModernUI` / `isRunningWMPUI` from `runningControllerFamily`** (`WindowManager.swift`) | every family's mode switch | Its own scoped commit, before A5. Behaviour changes only in the transient mode-switch window; say so in the commit. Drive the app across mode switches afterwards. `skin-subsystem-blueprint` § *Prefer an enum the compiler checks*. |
| A5 | **Phase 3 — app integration behind a DEBUG gate**: the `.audion` `PlayerUIMode` case and family first, then every compiler-listed seam gated on `.audion`; `Windows/AudionFace/` controller, window, view, host, unskinned view; importer, menu, persistence, `-audionFacePath`; `launch.sh audion:<name>` and the family lists in the app-control and screenshot scripts; `AudionFacePhase3Tests` | the user-visible mode | *UI.* Record every shared seam in `reference/windows.md`. **Exit:** the debug build switches to face mode on AppleClassic, Agitator, a tiny face and Black Bar, plays local audio, runs transport and drag-and-dock; the user confirms on screen; `skin-mode-switch-test.sh` passes; the other families' sweeps are byte-identical. |
| A6 | **Phase 4 — full face behaviour**: the button mapping (decision record § *Button mapping*), the volume and position sliders, labels and marquee, the inactive mask, right-click and keyboard, accessibility, and the `HOVER`/`CLICK`/`STATE`/`CLOCK` probes | every face | *UI.* **Exit:** live QA with local, stream and radio playback on the user's screen, and a passing oracle comparison for the playing state. |
| A7 | **Phase 5 — NullPlayer's windows beside a face**: `AudionFacePalette` → `SkinnedSurfaceStyle` through `legible`; `WindowManager.audionSurfaceStyle`; shared controllers and the tiler; `AUDION_PLACE_TRACE`; a route to a track from day one | every face | *UI.* **Exit:** the user confirms on screen; palette goldens for a handful of faces in `Goldens/AudionFace/`. |
| A8 | **Phase 6 — scale, retina and hardening**: integer scale 1×–3× through `applyDoubleSize`; dirty-rect redraw and a timer that stops when nothing animates; `index.json` fuzzing and hostile zip/folder fixtures; every family's regression sweep once more | every face | *UI* for scale, *autonomous* for hardening. Profile the release build before optimising past algorithmic defects. |
| A9 | **Phase 7 — public exposure**: remove the DEBUG gate; `docs/audion-face/user-guide.md`; the FaceKit credit in `LICENSE`; a `CHANGELOG.md` entry under the current version; finalise the skill and `skin-screenshots` support | release | Only when the user asks. Never bump the version. |
