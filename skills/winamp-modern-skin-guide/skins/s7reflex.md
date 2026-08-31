## S7Reflex (`S7Reflex.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `S7Reflex.wal` · 1305284 B · SHA-256 `ce2aa923469d50fc…`
- **Measured:** 2026-08-31 (B77) — **structural first pass only**, see *Not measured*
- **Grade: not graded (confidence: low)**

**Measured status:**

```
arrangement=separateWindows
catalog: playlist=declared:Pledit  equalizer=embedded  library=declared:MLibrary
         video=classic (none declared)  visualization=classic (none declared)
main/normal      675x280   162 nodes   min 675x280   declared 675x280   max 675x16384
Pledit/normal    436x126    58 nodes   min 354x126
MLibrary/normal  790x349    45 nodes   min 436x164
scripts: 36 programs, 0 failing at load
bitmaps: one layout with misses — `drawer.button.close.bg`, `player.button.repeat.bg`,
         `player.button.shuffle.bg`, `player.display.bg.*` on main/normal
```

Only three containers, but the densest main window of the six (162 nodes).

**Width-locked**: `max=675x16384` — it may grow vertically but never horizontally, so a horizontal
resize affordance would be wrong here.

Already referenced elsewhere in this guide for two things worth carrying over: its config tabs are
`<text default="">` filled in by a script (the case behind `autoWidth`'s zero-width guard), and it
uses the `CB_*PAGE` component-bucket actions to page its config drawer.

Its playlist holder is 424x69 — short — so it is a candidate for **B78**.

### Not measured

No `RENDER_CLICK`, no motion ladder, no live pass, no screenshot comparison, no coverage figure. The
missing `*.bg` bitmaps were not checked against `colors.xml`; on cPro-Bento a similar-looking set
turned out to be deliberate (state-0 frames the skin never declares), so they are **not** assumed to
be defects here.
