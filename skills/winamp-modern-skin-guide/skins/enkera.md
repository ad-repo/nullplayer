## Enkera (`Enkera.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Enkera.wal` · 428306 B · SHA-256 `61912f06fbab81d7…`
- **Measured:** 2026-08-31 (B77) — **structural first pass only**, see *Not measured*
- **Grade: not graded (confidence: low)** — nothing here was driven under the mouse or seen live.

**Measured status** — `WINAMP_MODERN_RENDER_DUMP` + `RENDER_BITMAPS` + `RENDER_SCRIPTS`:

```
arrangement=separateWindows
catalog: playlist=declared:playlist  equalizer=declared:eq  video=declared:video
         library=synthesized:nullplayer.library  visualization=classic (none declared)
main/normal      653x217   56 nodes   min 653x217   declared 1x1
main/shade       461x27    14 nodes   min 461x27    declared 461x1
playlist/normal  275x300   32 nodes   min 275x116
video/normal     354x300   30 nodes   min 354x164
eq/normal        270x139   56 nodes   min 270x139   (fixed: max == min)
scripts: 28 programs, 0 failing at load
bitmaps: nothing missing on any layout
```

**Clean loader.** No missing bitmaps anywhere and no script failed at load — unusual, and worth
knowing when this skin is used as a control against a noisier one.

Its equalizer is a **declared window** (`eq`), fixed at 270x139 — `max == min`, so it is not
resizable and must not be given a resize affordance.

### Not measured

Everything behaviour-level: no `RENDER_CLICK` pass, no motion ladder, no live pass, no comparison
against an author screenshot. Coverage (declared vs ever-visible objects) was not computed. The
`failed=-` above is **load-time only** — an unsupported method records nothing until something drives
the event that reaches it.
