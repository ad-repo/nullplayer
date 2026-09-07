## cPro - Bento (`cpro_interface_by_jinghis_d301whe.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `cpro_interface_by_jinghis_d301whe.wal` · 495,190 B · SHA-256 `f0c6ceeca17696d7…`, version 2.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: medium)** — from a headless pass; nobody has used this skin. Calls 1 unimplemented maki method(s) ×4 (`enumitem`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `unsupported` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 4 bitmap id(s) it references do not resolve, leaving a visible gap: `custom.repeat.0`, `custom.shuffle.0`, `custom.winamp`, `size.khzkbps`
- unimplemented MAKI: `enumitem` ×4
- 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 1 error-severity load finding(s)


**Measured status:**

```
shape        singleWindowSUI, 8 containers (searchresults, browserpro, notifier, main, widgets.manager, nullplayer.about, searchresults#2, searchresults#3), 8 layouts with content, 299 scene nodes total
main window  500x500
embedded     equalizer, library, playlist, video
own window   none
classic      visualization — skin declares no visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    11 total (3 in main/normal: centro.mainframe, centro.plframe, pl.search.go; 8 button objects in widgets.manager/normal); layouts with zero: 6 layouts (searchresults/normal, browserpro/normal, notifier/normal, notifier/desktopalpha, main/shade, nullplayer.about/normal)
scripts      51 programs loaded, 1 reported a failed handler (onaction in widgets-manager.xml)
unsupported  enumitem×2
artwork      85 resolved, 6 unresolved ids (beatvis.overlay, custom.repeat.0, custom.shuffle.0, custom.winamp, size.khzkbps, studio.BaseTexture)
findings     1 error, 62 warning, 0 info
```

**Worth a look:** looks wrong: enumitem method not implemented per line 222, causing handler failure; additionally unresolved font cpro.menu.font per line 283

The archive ships the author's own `screenshot.png`; the 2026-09-06 comparison pass found our render recognisably the same skin at rest.

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: headless log cannot show whether enumitem failure breaks widgets manager core functionality or only affects edge cases; cannot verify visual rendering or user interaction with complex SUI layout
