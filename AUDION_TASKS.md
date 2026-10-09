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
| A8 | **Phase 6 — scale, retina and hardening**: integer scale 1×–3× through `applyDoubleSize`; dirty-rect redraw (the clock already stops when nothing moves, A6); `index.json` fuzzing and hostile zip/folder fixtures; every family's regression sweep once more | every face | *UI* for scale, *autonomous* for hardening. Profile the release build before optimising past algorithmic defects. |
| A9 | **Phase 7 — public exposure**: remove the DEBUG gate; `docs/audion-face/user-guide.md`; the FaceKit credit in `LICENSE`; a `CHANGELOG.md` entry under the current version; finalise the skill and `skin-screenshots` support | release | Only when the user asks. Never bump the version. |
