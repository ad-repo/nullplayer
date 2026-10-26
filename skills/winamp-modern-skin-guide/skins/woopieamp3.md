## WoopieAMP3 (`WoopieAMP3.wal`)

*Per-skin notes, not a graded report. Index: [skins.md](../skins.md) · a full report: `/wal-skin-report <skin.wal>`.*

- **Seen:** 2026-10-25, headless (intake #3).
- **The missing `right-up` is a stale duplicate.** `skin.xml` declares `ScrollRight` twice: line 527
  on `cb_next`/`cb_next_down` (defined, drawn), and line 528 on `right-up`/`right-down`, which no
  bitmap defines, so the second draws nothing and the Thinger's right arrow is the first.
- **The Thinger drawer is script-driven, from a bracket group.** `scripts/title.m` sits in an inline
  `<group id="songtitle">` (no `<groupdef>`, no box; its children use layout coordinates) and
  `getScriptGroup().getObject(...)`s the layout's transport, `Volume`, `Seeker`, `thinger-window`
  and `thinger-button`. Owned by the bracket, every lookup was null, `Thinger.onLeftButtonUp` bound
  nothing, and the drawer never opened (reported live, 2026-10-26). Fixed by the bracket rule in
  [scripting.md](../reference/scripting.md) § *A bracket is not a script group*; a click on the
  button at `main/normal@140,218` now runs `onleftbuttonup` and slides the drawer. The shade copy in
  `<group id="scriptcaption">` still gets null for those ids — the shade layout has none of them.
