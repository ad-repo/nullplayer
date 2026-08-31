## Nullsoft Winamp 2000 SP4 Lite (`Nullsoft.Winamp.2000.SP4.Lite.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Nullsoft.Winamp.2000.SP4.Lite.wal` · 639133 B · SHA-256 `147838d6a8e36090…`
- **Measured:** 2026-08-31 (B77) — **structural first pass only**, see *Not measured*
- **Grade: not graded (confidence: low)**

**Measured status:**

```
arrangement=separateWindows
catalog: EVERY surface declared — playlist=PLEdit  equalizer=equalizer  library=MLibrary
         video=Video  visualization=AVS      (nothing synthesized, nothing on classic fallback)
main/normal            550x242   112 nodes   min 550x242   max 10000x16384
winamp.albumart/normal 212x242    78 nodes
equalizer/normaleq     550x242   117 nodes
PLEdit/normalpl        276x242    90 nodes
MLibrary/normal        275x484    81 nodes
scripts: 50 programs, 0 failing at load
bitmaps: 13 layouts with misses — a `none` id throughout, plus
         `window.shade.region.*` and `window.plvis.display.bg`
```

**The only skin of the six that declares every surface**, including a visualization window — so
nothing falls back to a NullPlayer-owned window. That makes it the best control in this batch for
surface routing.

It ships a dedicated **`winamp.albumart` window**, and it declares a `<Menu>` bar (1 declaration).

**A literal `none` is being resolved as a bitmap id** on 13 layouts. Almost certainly an attribute
whose value is the string `none` meaning "no artwork", which the resource lookup should treat as
absent rather than as a missing resource. Cheap to confirm and probably a one-line engine fix; not
chased.

### Not measured

No `RENDER_CLICK`, no motion ladder, no live pass, no screenshot comparison, no coverage figure.
Its `<Menu>` bar was not exercised and may be subject to **B79** (a group whose `autowidthsource`
names a bitmap sizes to nothing).
