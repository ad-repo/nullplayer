## MoonLight (`MoonLight.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `MoonLight.wal` · 356,180 B · SHA-256 `efbf44944525f3ea…` · author "Marisa85", version 1.1
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- nothing outstanding that a headless pass can see


**Measured status:**

```
shape        separateWindows, 11 containers (main, eq, cont.clear.dl, cont.clear.pl, cont.clear.vd, cont.clear.ml, PLEdit, Video, MLibrary, DLibrary, cont.clear.DL#2), 10 layouts, 140 scene nodes total
main window  450x100 (normal layout)
embedded     none
own window   equalizer, library, playlist, video
classic      visualization only — the skin declares no visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    0 objects across all layouts; layouts with zero: all 10 renderable layouts
scripts      5 programs loaded, 0 reported a failed handler
unsupported  none
artwork      69 resolved, 0 unresolved ids
findings     0 error, 7 warning, 0 info
```

**Worth a look:** looks wrong: All 10 layouts report zero clickable controls despite spanning 140 scene nodes, per CLICKABLE listings, which suggests control interaction is entirely script-driven or wiring is incomplete

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: Cannot verify whether the sleek MoonLight aesthetic renders with proper color palette, inter-window spacing, or frame appearance
