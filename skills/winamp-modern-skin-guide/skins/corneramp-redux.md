## CornerAmp Redux (`corneramp_redux.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `corneramp_redux.wal` · 354,604 B · SHA-256 `d5af185030e5e3f8…` · author "9 of Nine, Evil Pumpkin, RazorZero", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `full` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
shape        separateWindows, 6 containers (Main, Pledit, Video, eq, colorthemes, nullplayer.library), 6 layouts, 184 scene nodes total
main window  246x228
embedded     none
own window   equalizer (eq), playlist (Pledit), video (Video), library
classic      visualization — the skin declares no visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    2 total; layouts with zero: Pledit/normal, Video/normal, eq/normal, colorthemes/normal, nullplayer.library/normal
scripts      6 programs loaded, 0 reported a failed handler
unsupported  none
artwork      28 resolved, 19 unresolved ids (wasabi.button.close, wasabi.button.sysmenu, wasabi.frame.basetexture, wasabi.frame.bottom, wasabi.frame.left, wasabi.frame.right, wasabi.frame.top, and variants)
findings     0 error, 0 warning, 0 info
```

**Worth a look:** looks wrong: 19 missing wasabi frame and button resources (critical structural elements) in every hosted window except Main—Pledit, Video, eq, colorthemes, and nullplayer.library all report 0 or 1 resolved bitmaps against 19+ missing frame pieces, per lines 35, 41, 45, 49, 54

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: a headless render shows structural placement but cannot determine whether windows render as frameless shapes or whether missing frame resources are visually tolerable
