## DewyTears v2.5 (Black Glass / Pink Glass / Transparent)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

Three variants of one skin, in one file for the reason [big-bento-modern.md](big-bento-modern.md) is: they share a name in `skininfo` and differ only in colourway. Black Glass and Pink Glass each ship under a second filename as well — `dewytears_v2_5_by_dewytear_d2yn025_BlackGlass.wal` and `…_PinkGlass.wal` are byte-identical duplicates, not separate skins.

- **`DewyTears_BlackGlassV2.5.wal`** · 237,648 B · SHA-256 `e4695a84001871b1…`, version 1.0
- **`DewyTears_PinkGlassV2.5.wal`** · 237,650 B · SHA-256 `4d6425dcd3034486…`, version 1.0
- **`DewyTears_TransparentV2.5.wal`** · 237,648 B · SHA-256 `9318217a6b24c280…`, version 1.0

- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.

**Known outstanding:**

- nothing outstanding that a headless pass can see


**Measured status:**

```
--- DewyTears_BlackGlassV2.5.wal  (fully-skinned · level full)
  shape        separateWindows, 4 containers (main, Visualiser, nullplayer.playlist, nullplayer.library), 6 layouts, 117 scene nodes total
  main window  299x113
  embedded     equalizer
  own window   playlist, library
  classic      video, visualization — the skin declares no video or visualization surface
  hosted       8 wear the skin frame, 0 fall back to classic
  clickable    0 total; layouts with zero: main/Home, main/Settings, main/Artwork, Visualiser/Vis Back, nullplayer.playlist/normal, nullplayer.library/normal
  scripts      9 programs loaded, 0 reported a failed handler
  unsupported  none
  artwork      56 resolved, 2 unresolved ids (component.basetexture, wasabi.frame.basetexture)
  findings     0 error, 0 warning, 0 info
--- DewyTears_PinkGlassV2.5.wal  (fully-skinned · level full)
  shape        separateWindows, 4 containers (main, Visualiser, nullplayer.playlist, nullplayer.library), 6 layouts, 117 scene nodes total
  main window  299x113
  embedded     equalizer
  own window   library, playlist
  classic      video, visualization — skin declares neither
  hosted       8 wear the skin frame, 0 fall back to classic
  clickable    0 total; layouts with zero: all layouts
  scripts      8 programs loaded, 0 reported a failed handler
  unsupported  none
  artwork      56 resolved, 2 unresolved ids (component.basetexture, wasabi.frame.basetexture)
  findings     0 error, 0 warning, 0 info
--- DewyTears_TransparentV2.5.wal  (fully-skinned · level full)
  shape        separateWindows, 4 containers (main, Visualiser, nullplayer.playlist, nullplayer.library), 6 layouts, 117 scene nodes total
  main window  299x113 (main/Home)
  embedded     equalizer
  own window   playlist, library
  classic      video, visualization — the skin declares no video or visualization surface
  hosted       8 wear the skin frame, 0 fall back to classic
  clickable    0 objects total; layouts with zero: main/Home, main/Settings, main/Artwork, Visualiser/Vis Back, nullplayer.playlist/normal, nullplayer.library/normal
  scripts      8 programs loaded, 0 reported a failed handler
  unsupported  none
  artwork      56 resolved, 2 unresolved ids (component.basetexture, wasabi.frame.basetexture)
  findings     0 errors, 0 warnings, 0 info
```

**Worth a look (DewyTears_BlackGlassV2.5.wal):** looks wrong: missing bitmaps component.basetexture and wasabi.frame.basetexture, per line 5

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, no coverage figure. Every number above is a declaration count from one headless render at rest — it says a thing exists, never that it is drawn right or that it responds. The Transparent variant in particular is a skin whose whole point is alpha, and a headless render at rest cannot tell you whether that reads correctly on screen.
