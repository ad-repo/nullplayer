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
| A12 | Lookalikes for the fonts that cannot ship | The `unresolved` and `substitute` cohorts of `scripts/audion_font_sheet.py` (51 and 254 faces) | Names with no original NullPlayer may ship and no lookalike, or one judged only by name: Charcoal (Chicago Kare stands in), New York and Osaka bitmaps, Espy Sans, Century Gothic, VT100, Sand, Textile, and the commercial or "redistribution prohibited" families `audion_face_fonts.py` lists in `fonts.tsv` (Facet, Institution, braille, SF Digital Readout, Junior Pro, Eurostile, Bell Centennial, Machine ITC, …). Each candidate is an OFL or freeware font with its licence in the notices. **Done when** each name has a lookalike the user accepts on the cohort's contact sheet, or is recorded in `format.md` as staying on Helvetica. |
| A13 | Vintage Totem draws Monaco 9, not Geneva 9 | Vintage Totem; possibly other 1999 faces with no `Txtr` | Its archive has no `Txtr` 200/201, so it takes Audion's default, Geneva 9 (`format.md` § *`Txtr`*), but Panic's screenshot shows Monaco 9. Find whether Audion's default changed between versions (a face's `vers` or creation date against the screenshots of the other 66 `no-txtr` faces) before changing the default. **Done when** the `no-txtr` sheet matches Panic's screenshots, or the exceptions are explained. |
| A14 | aPop's text mode 4 is inverse video | aPop 1–4 (`Txtr` mode 4) | QuickDraw mode 4 (`notSrcCopy`) draws the text's complement; NullPlayer draws it black on the base. `…TextMode` is parsed only for its `& 2` (XOR) bit. **Done when** aPop's lines match its screenshot on the contact sheet and no other face's text changes. |
| A15 | Car Stereo's text sits lower than NullPlayer draws it | Car Stereo (Geneva 9, centred) | Panic's screenshot puts the baseline below where the `bdat` path places it (FaceKit's outline baseline). Compare the `bitmap-strike` sheet for a pattern before moving the baseline for every Geneva line. **Done when** Car Stereo matches its screenshot and the `bitmap-strike` cohort does not regress. |
| A16 | The time colon flickers during radio, and the Library Browser shows black corners | Plasmat (#640); check the other faces whose colon is an indicator | Reported on GitHub #640: on internet radio the `:` dots flash up and down; local files are steady. In the media browser its corners draw black pixels where they should be transparent; other subwindows are fine. **Done when** under Plasmat a station plays with a steady colon and the browser's corners are transparent, with Classic, `.wal` and `.wmz` unchanged. |
| A17 | "<<< STREAMING" draws stretched vertically | iPod 1.2 (#641) | Reported on GitHub #641: playing internet radio shows a "<<< STREAMING" sprite stretched vertically, breaking the layout — likely the streaming animation drawn into a rect of another height. **Done when** iPod 1.2 streams with the animation at its authored size, and the render sweep's `streaming` state changes only on faces whose frames differ from their rect. |

## App integration

| ID | Item | Reach | Notes |
|---|---|---|---|
| A11 | The Library Browser opens off-screen and 52 pt tall | The Library Browser under every Audion face | Measured on 2026-10-13 under `audion:Black Bar`, on `main` (`5a844a95`) and on `library-browser-model`: Windows ▸ Library Browser opens the classic browser at x = 2340, y ≈ 294, 550×52, with the display 1800 pt wide, so it is out of sight and too short to show its list. Captures: `~/.claude/plans/library-browser-phase0/captures/audion-local-*.png`. Every other family opens it on screen at 550×580 (`.wal`: 680×440). Find where Audion sizes and places the hosted library (its frame restore or the face's window placement) before changing anything shared, since `.wmz` and `.wal` use the same browser. **Done when** under Audion it opens on screen at the classic default size, a resized and moved browser restores where it was left, and the Classic, `.wal` and `.wmz` library windows open exactly as before. |
