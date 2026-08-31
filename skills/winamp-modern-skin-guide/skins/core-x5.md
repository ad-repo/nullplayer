## Core-X5 (`Core-X5.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Core-X5.wal` · 336165 B · SHA-256 `e111688d2a1b3d91…`
- **Measured:** 2026-08-31 (B77) — **structural first pass only**, see *Not measured*
- **Grade: not graded (confidence: low)**

**Measured status:**

```
arrangement=separateWindows
catalog: playlist=declared:Pledit  equalizer=embedded  library=synthesized:nullplayer.library
         video=classic (none declared)  visualization=classic (none declared)
Main/normal        277x145   52 nodes   min 277x135   declared 1x1
Main/shade         277x18    47 nodes
Pledit/normal      277x145   26 nodes
CoverArt/normal    155x145   24 nodes
About.window       600x500   22 nodes   min 542x452
Message/normal     350x235   28 nodes
scripts: 109 programs, 0 failing at load
bitmaps: one miss — `component.basetexture` on the `Skin Consortium ` container
```

A small player (277x145) with a large script surface (109 programs), plus its own **CoverArt**,
**About** and **Message** windows.

**A container id with a trailing space** — `"Skin Consortium "`. Worth remembering if an id lookup for
this skin ever fails for no visible reason.

Its playlist holder is one of the corpus's smaller ones, so it is a candidate for **B78**.

### Not measured

No `RENDER_CLICK`, no motion ladder, no live pass, no screenshot comparison, no coverage figure.
