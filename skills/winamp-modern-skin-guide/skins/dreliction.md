## 4-dreliction (`4-drelictionreleasepic.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `4-drelictionreleasepic.wal` · 1049380 B · SHA-256 `9b481e7535b9460e…`
- **Measured:** 2026-08-31 (B77) — **structural first pass only**, see *Not measured*
- **Grade: not graded (confidence: low)**

**Measured status:**

```
arrangement=separateWindows
catalog: playlist=declared:Pledit  equalizer=embedded  video=declared:Video
         library=synthesized:nullplayer.library
Main/Normal   433x225   107 nodes   min 433x225   declared 1x1
Main/Baby     246x140    59 nodes   min 246x129
Main/Stick    433x46     51 nodes   min 246x46
Pledit/normal 246x140    58 nodes
scripts: 88 programs, **3 failing at load**
bitmaps: 10 layouts with a miss — `player.Beat Layer` on Main/Normal,
         `wasabi.frame.basetexture` on the four bare standard-frame containers
```

**The only one of the six with load-time script failures (3).** They were not identified; that is the
first thing to do here, with `RENDER_SCRIPTS=bindings`.

It declares the four Wasabi **standard-frame shells** as containers of their own
(`resizable_status`, `resizable_nostatus`, `modal`, `static`), each 246x140 and each missing
`wasabi.frame.basetexture`. Those are template containers, not windows a user opens.

`player.Beat Layer` — note the space in the identifier — is missing on the main window.

Three layouts (`Normal` / `Baby` / `Stick`), so it has a compact and a stick mode worth exercising.

### Not measured

No `RENDER_CLICK`, no motion ladder, no live pass, no screenshot comparison, no coverage figure. The
three failures are load-time; the runtime set will be larger.
