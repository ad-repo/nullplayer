## cPro_Winamp Modern (`211786-Cpro_Winamp_Modern.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `211786-Cpro_Winamp_Modern.wal` · 274,438 B · SHA-256 `1b6b350e3963e737…`, version 0.99
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: medium)** — from a headless pass; nobody has used this skin. Calls 1 unimplemented maki method(s) ×4 (`enumitem`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `unsupported` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 13 bitmap id(s) it references do not resolve, leaving a visible gap: `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`, `player.o.center`, `player.o.left`, `player.o.right`…
- unimplemented MAKI: `enumitem` ×4
- 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 1 error-severity load finding(s)


**Measured status:**

```
shape        singleWindowSUI, 8 containers (searchresults, browserpro, notifier, main, widgets.manager, nullplayer.about, searchresults#2, searchresults#3), 8 layouts, 299 scene nodes total
main window  500x500 (main/normal)
embedded     equalizer, library, playlist, video
own window   none
classic      visualization — the skin declares no visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    12 objects total across all layouts; layouts with zero: main/shade, notifier/normal, notifier/desktopalpha, nullplayer.about/normal, searchresults#2, searchresults#3
scripts      67 programs loaded, 1 reported a failed handler (enumitem)
unsupported  enumitem×2
artwork      74 resolved, 15 unresolved ids (beatvis.overlay, player.o.bottom, player.o.bottomleft, player.o.bottomright, player.o.center, player.o.left, player.o.right, player.o.top)
findings     1 error, 59 warnings, 0 info
```

**Worth a look:** looks wrong: widgets-manager.xml failed with enumitem not supported, per line 146

The archive ships the author's own `screenshot.png`; the 2026-09-06 comparison pass found our render recognisably the same skin at rest.

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: log is structural only — cannot show visual rendering quality, interactive behavior, or animation playback
