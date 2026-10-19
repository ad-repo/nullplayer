# Audion Faces — open backlog

The only live backlog for the Audion face subsystem, and a list of open rows — nothing else. Read
`skills/audion-face-guide/SKILL.md` before picking anything up.

- The locked decisions are [`docs/audion-face/phase-0-decision-record.md`](../docs/audion-face/phase-0-decision-record.md).
  The phased plan the rows below were seeded from is `~/.claude/plans/in-a-worktree-only-rippling-kay.md`.
- Closed rows move to [`docs/audion-face/backlog-archive.md`](../docs/audion-face/backlog-archive.md) in
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
| A11 | The Library Browser opens off-screen and 52 pt tall | The Library Browser under every Audion face | Measured on 2026-10-13 under `audion:Black Bar`, on `main` (`5a844a95`) and on `library-browser-model`: Windows ▸ Library Browser opens the classic browser at x = 2340, y ≈ 294, 550×52, with the display 1800 pt wide, so it is out of sight and too short to show its list. Captures: `~/.claude/plans/library-browser-phase0/captures/audion-local-*.png`. Every other family opens it on screen at 550×580 (`.wal`: 680×440). Find where Audion sizes and places the hosted library (its frame restore or the face's window placement) before changing anything shared, since `.wmz` and `.wal` use the same browser. **Done when** under Audion it opens on screen at the classic default size, a resized and moved browser restores where it was left, and the Classic, `.wal` and `.wmz` library windows open exactly as before. |
