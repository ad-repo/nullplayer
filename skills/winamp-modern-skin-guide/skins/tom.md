## Tom (`TomK.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `TomK.wal` · 2,181,051 B · SHA-256 `21a9b5b873a93d9a…` · author "Petrol Designs", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `full` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
shape        separateWindows, 5 containers (main, colorwnd, gallery, nullplayer.playlist, nullplayer.library), 6 layouts, 128 scene nodes total
main window  337x256
embedded     equalizer
own window   library, playlist
classic      video, visualization — skin declares neither
hosted       8 wear the skin frame, 0 fall back to classic
clickable    3 total (layer#vol and layer#seek in main/normal, layer#seek in main/shade); layouts with zero: 4 layouts (colorwnd/normal, gallery/normal, nullplayer.playlist/normal, nullplayer.library/normal)
scripts      8 programs loaded, 0 reported a failed handler
unsupported  none
artwork      84 resolved, 0 unresolved ids
findings     0 error, 0 warning, 0 info
```

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: headless log shows interactive controls exist but cannot verify they respond to clicks, drag operations, or value changes
