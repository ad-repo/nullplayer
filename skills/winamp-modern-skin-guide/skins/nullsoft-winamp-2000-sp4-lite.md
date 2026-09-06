## Nullsoft Winamp 2000 SP4 Lite (`Nullsoft.Winamp.2000.SP4.Lite.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Nullsoft.Winamp.2000.SP4.Lite.wal` · 639133 B · SHA-256 `147838d6a8e36090…`
- **Measured:** 2026-08-31 (B77) structural pass; **2026-09-05 (B135/B136/B137)** live QA on the
  running app
- **Grade: B (provisional · confidence: medium)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.

**Known outstanding:**

- 7 bitmap id(s) it references do not resolve, leaving a visible gap: `window.normal.left2`, `window.normal.middle2`, `window.plvis.display.bg`, `window.shade.region.bottom.left`, `window.shade.region.bottom.right`, `window.shade.region.top.left`…
- 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
arrangement=separateWindows
catalog: EVERY surface declared — playlist=PLEdit  equalizer=equalizer  library=MLibrary
         video=Video  visualization=AVS      (nothing synthesized, nothing on classic fallback)
main/normal            550x242   112 nodes   min 550x242   max 10000x16384
winamp.albumart/normal 212x242    78 nodes
equalizer/normaleq     550x242   117 nodes
PLEdit/normalpl        550x242    93 nodes   (276x242 before B136)
MLibrary/normal        550x484    84 nodes   (275x484 before B136)
AVS/normal             354x278    80 nodes   (96x30 before B136)
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

No `RENDER_CLICK`, no motion ladder, no coverage figure. The 2026-09-05 live pass covered the
titlebars and the window sizes and nothing else.
Its `<Menu>` bar was not exercised and may be subject to **B79** (a group whose `autowidthsource`
names a bitmap sizes to nothing).


### Three engine defects it was the first skin to reach (2026-09-05)

Reported as "the titlebars have a colour artifact that makes them unreadable" and "the built-in
visualization window opens collapsed and you have to drag it open". Neither is about this skin; each
is a gap in the engine that no earlier corpus skin exercised. Full write-ups in the references — the
router rows in [SKILL.md](../SKILL.md) point at them.

- **B135 — `activealpha`/`inactivealpha` were never read.** This skin keeps an active and an inactive
  copy of every title *in the same slot* and shows one at a time purely by that pair
  (`xml/titlebar.xml`, and the same idiom in `main-player.xml` and `playlist-editor.xml`). Both drew,
  in two gammagrouped colours a glyph apart. See
  [reference/rendering/colour.md](../reference/rendering/colour.md).
- **B137 — a `<gradient>` naming no direction flat-filled its last stop.** The Windows 2000 titlebar
  is `Active Title Bar Color 1` (navy, opaque) with `Color 2` (light blue) over it at
  `points="0.0=…,0;1.0=…,255"`. Flat-filled, the light blue covered the navy: every title strip was a
  uniform `rgb(167,203,242)`. Same file.
- **B136 — container `default_w`/`default_h`, and the component-room fit.** This skin sizes *every*
  auxiliary window on the `<container>` rather than the `<layout>`, which nothing read, so its
  playlist, library and visualizer all opened at their `minimum_*` floors. Its `AVS/normal` states no
  height at all, which needed a second, narrower rule. See
  [reference/loading.md](../reference/loading.md).

**The trap this skin set, worth more than the fixes:** the size fix was verified in a clean corpus
render sweep and was *still* wrong on screen, because the dump asks for a window's size after
`runtime.start()` and the app's tiler asks before it. `WINAMP_MODERN_PLACE_TRACE=1` in the running
app is what found it.
