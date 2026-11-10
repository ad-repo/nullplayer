# Sonique Skins — open backlog

The only live backlog for the Sonique (`.sgf`) skin family, and a list of open rows — nothing else.
Read `skills/sonique-skin-guide/SKILL.md` before picking anything up.

- The locked decisions are [`docs/sonique/phase-0-decision-record.md`](../docs/sonique/phase-0-decision-record.md).
- Closed rows move to [`docs/sonique/backlog-archive.md`](../docs/sonique/backlog-archive.md) in the
  change that closes them. That file's § *Issuing a number* holds the next free number.
- `.wmz` work goes in [`WMP_TASKS.md`](WMP_TASKS.md), `.wal` work in [`WINAMP5_TASKS.md`](WINAMP5_TASKS.md),
  Audion in [`AUDION_TASKS.md`](AUDION_TASKS.md).

**Agent-verifiable rows** (marked *autonomous*) are closed by the agent against their exit criteria.
**UI rows** stop for an on-screen check by the user before tests, docs or changelog entries are added.
Every row that touches `App/` ends with Classic, Original, `.wal`, `.wmz` and Audion sweeps
byte-identical to the capture before it.

## Phase 2 — the rest of the UI

No open rows. The family shipped with Phase 2 (decision record Amendment 5); new work is filed here
when a skin or a report reproduces it.

## Maintenance

No open rows. S18–S22, filed from the branch's two code reviews, closed 2026-10-18.

| ID | Item | Exit |
|---|---|---|
| S23 | **The oracle no longer starts** (2026-11-09). `scripts/sonique_oracle_capture.sh vertego.sgf` captured nothing: `Sonique.exe` runs, but Wine shows only three hidden 500×500 windows at 0,669 and every `-loadskin`/`-setvolume` call blocks, so the script waits forever (it worked for the 2026-10-17 corpus run). Blocks any new capture, and a playing oracle, which the mid rings, top-window vis and wrapped title (#729, #731, #732) were measured without: they rest on photos of real Sonique (`format.md` § *Mid mode's song window*). Find what changed (Wine, macOS, the prefix, a dialog off screen) | `scripts/sonique_oracle_capture.sh <dir> sonique.sgf` prints `sonique nav=1 mid=1 small=1`; ideally `-play` with a WAV in the prefix too, so the rings can be captured filling |
