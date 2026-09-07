## Wiimote (`Wiimote.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Wiimote.wal` · 249,510 B · SHA-256 `af8ce82cb2f39498…` · author "SpaceKitty", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- nothing outstanding that a headless pass can see


**Measured status:**

```
shape        separateWindows, 3 containers (main, nullplayer.playlist, nullplayer.library), 6 layouts, 133 scene nodes total
main window  110x461
embedded     equalizer
own window   none
classic      video, visualization — the skin declares no video or visualization surface
hosted       0 wear the skin frame, 0 fall back to classic
clickable    0 objects across all layouts; layouts with zero: all 6 layouts
scripts      8 programs loaded, 0 reported a failed handler
unsupported  none
artwork      94 resolved, 1 unresolved id (wasabi.frame.basetexture)
findings     0 errors, 15 warnings, 0 info
```

**Worth a look:** looks wrong: all layouts report zero clickables per lines 49, 53, 57, 61, 65, 71

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: headless log cannot determine whether zero-clickable across 4 player-mode layouts reflects intentional radio-button toggling (no per-mode input) or unfinished routing
