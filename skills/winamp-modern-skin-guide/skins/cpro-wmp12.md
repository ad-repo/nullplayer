## cPro - WMP12 (`221955-cPro__Winamp_Media_Player_12.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `221955-cPro__Winamp_Media_Player_12.wal` · 329,493 B · SHA-256 `2a2e2b5b9258e28d…`, version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Calls 1 unimplemented maki method(s) ×4 (`enumitem`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `unsupported` (a diagnostic count, not a quality signal)

**Known outstanding:**

- unimplemented MAKI: `enumitem` ×4
- 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 1 error-severity load finding(s)


**Measured status:**

```
shape        singleWindowSUI, 8 containers (searchresults, browserpro, notifier, main, widgets.manager, nullplayer.about, searchresults#2, searchresults#3), 8 layouts, 295 scene nodes total
main window  500x500 (normal layout)
embedded     equalizer, library, playlist, video
own window   none
classic      visualization only — the skin declares no visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    12 objects across all layouts; layouts with zero: searchresults/normal, browserpro/normal, notifier/normal, notifier/desktopalpha, main/shade, nullplayer.about/normal
scripts      32 programs loaded, 1 reported a failed handler (onaction/enumitem)
unsupported  enumitem ×2
artwork      86 resolved, 2 unresolved ids (beatvis.overlay, studio.BaseTexture)
findings     1 error, 21 warning, 0 info
```

**Worth a look:** looks wrong: onaction handler failed for widgets-manager.xml with 'enumitem' not implemented, per line 146, which could break the ClassicPro widget manager UI

The archive ships the author's own `screenshot.png`; the 2026-09-06 comparison pass found our render recognisably the same skin at rest.

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: Cannot verify whether the complex Centro UI framework renders player layout beautifully, colors/themes display correctly, or layouts respond smoothly to resizing
