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

## App integration

| ID | Item | Reach | Notes |
|---|---|---|---|
| A6 | **Phase 4 — full face behaviour**: the button mapping (decision record § *Button mapping*), the volume and position sliders, labels and marquee, the inactive mask, right-click and keyboard, accessibility, and the `HOVER`/`CLICK`/`STATE`/`CLOCK` probes | every face | *UI.* First, re-run `skin-mode-switch-test.sh "Spectrum Analyzer"`: its Audion rows were corrected after its last run and have not run since (A5). **Exit:** live QA with local, stream and radio playback on the user's screen, and a passing oracle comparison for the playing state. |
| A7 | **Phase 5 — NullPlayer's windows beside a face**: the palette, `audionSurfaceStyle`, the gloss frame, the shared controllers, the tiler and `AUDION_PLACE_TRACE` landed in A5 (`reference/windows.md`); left: every NullPlayer window checked beside a few faces, legibility across the corpus, and the route to a track | every face | *UI.* **Exit:** the user confirms on screen; palette goldens for a handful of faces in `Goldens/AudionFace/`. |
| A8 | **Phase 6 — scale, retina and hardening**: integer scale 1×–3× through `applyDoubleSize`; dirty-rect redraw and a timer that stops when nothing animates; `index.json` fuzzing and hostile zip/folder fixtures; every family's regression sweep once more | every face | *UI* for scale, *autonomous* for hardening. Profile the release build before optimising past algorithmic defects. |
| A9 | **Phase 7 — public exposure**: remove the DEBUG gate; `docs/audion-face/user-guide.md`; the FaceKit credit in `LICENSE`; a `CHANGELOG.md` entry under the current version; finalise the skill and `skin-screenshots` support | release | Only when the user asks. Never bump the version. |
