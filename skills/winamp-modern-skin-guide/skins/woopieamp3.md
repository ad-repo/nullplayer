## WoopieAMP3 (`WoopieAMP3.wal`)

*Per-skin notes, not a graded report. Index: [skins.md](../skins.md) · a full report: `/wal-skin-report <skin.wal>`.*

- **Seen:** 2026-10-25, headless (intake #3).
- **The missing `right-up` is a stale duplicate.** `skin.xml` declares `ScrollRight` twice: line 527
  on `cb_next`/`cb_next_down` (defined, drawn), and line 528 on `right-up`/`right-down`, which no
  bitmap defines, so the second draws nothing and the Thinger's right arrow is the first.
