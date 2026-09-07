## Pure Inspired for Winamp (`Pure Inspired.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Pure Inspired.wal` · 310,504 B · SHA-256 `69dd242228c9f06e…` · author "Marisa85", version 1.1
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 1 bitmap id(s) it references do not resolve, leaving a visible gap: `img/bt_caN.png`


**Measured status:**

```
shape        separateWindows, 9 containers (main, cont.clear.dl, cont.clear.pl, cont.clear.vd, cont.clear.ml, PLEdit, Video, MLibrary, DLibrary), 11 layouts, 192 scene nodes total
main window  181x329
embedded     equalizer
own window   library (MLibrary), playlist (PLEdit), video (Video)
classic      visualization — skin declares no visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    1 total; layouts with zero: 10 layouts (all except main/Control and main/control-nocov)
scripts      8 programs loaded, 0 reported a failed handler
unsupported  none
artwork      99 resolved, 1 unresolved ids (img/bt_caN.png)
findings     0 error, 50 warning, 0 info
```

**Worth a look:** looks wrong: 50 warnings for missing img/elements.png, same pattern as K-jr with repeated resource warnings, per bash output line 46+

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: headless log cannot determine visual result of warnings or whether fallback rendering is acceptable
