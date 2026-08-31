## meridian (`meridian.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `meridian.wal` · 3553988 B · SHA-256 `082121ac2e279d90…`
- **Measured:** 2026-08-31 (B77) — **structural first pass only**, see *Not measured*
- **Grade: not graded (confidence: low)**

**Measured status:**

```
arrangement=separateWindows
catalog: playlist=declared:Pledit  equalizer=embedded  library=synthesized:nullplayer.library
         video=classic (none declared)  visualization=classic (none declared)
main/normal       829x366   109 nodes   min 597x366   declared 1x1
main/shade        891x32     30 nodes   min 891x32
remote/normal     326x173    36 nodes
notifier2/normal  275x135     0 nodes   min 1x135     <-- draws nothing
ThemeWindow       381x500    32 nodes
Pledit/normal     333x270    33 nodes   min 294x140
UCheck/normal     251x360    23 nodes   (fixed)
scripts: 123 programs, 0 failing at load
bitmaps: nothing missing on any layout
```

The largest script surface of the six new installs (123 programs) and the second-largest archive.

**`notifier2/normal` resolves to 0 nodes.** A declared container that draws nothing is either a
host-driven surface with no content of its own or a real defect; which was not established. It is
`main=false` and does not open by default, so it is not on screen — but it is the first thing to look
at if this skin is picked up.

Ships its own **ThemeWindow** and a **UCheck** (update-check) window; neither was opened.

### Not measured

No `RENDER_CLICK`, no motion ladder, no live pass, no screenshot comparison, no coverage figure. The
`failed=-` is load-time only.
