## BLAKK (`BLAKK.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `BLAKK.wal` · 774,043 B · SHA-256 `3ac9f24cbe024a9b…` · author "Dwight Robinson aka Vica.", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 1 bitmap id(s) it references do not resolve, leaving a visible gap: `player.remote-toggles-ml-text-off`
- 5 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
shape        separateWindows, 9 containers (main, browser.quicklink.edit.dialog, browser.submenu.edit, eq, pledit, VideoWindow, configure, BLAKK.color-themes, nullplayer.library), 12 layouts, 420 scene nodes total
main window  436x160 (main/boombox)
embedded     none
own window   equalizer (eq), playlist (pledit), video (VideoWindow)
classic      none — not in log
hosted       8 wear the skin frame, 0 fall back to classic
clickable    5 objects total; layouts with zero: browser.quicklink.edit.dialog/normal, browser.submenu.edit/normal, eq/normal, pledit/normal, VideoWindow/normal, configure/normal, configure/about, BLAKK.color-themes/about, nullplayer.library/normal
scripts      22 programs loaded, 0 reported a failed handler
unsupported  none
artwork      308 resolved, 2 unresolved ids (component.basetexture, player.remote-toggles-ml-text-off)
findings     0 error, 38 warning, 0 info
```

**Worth a look:** looks wrong: synthesized library window will be plain due to missing wasabi.standardframe.statusbar artwork, per FINDING line 58

The archive ships the author's own `screenshot.png`; the 2026-09-06 comparison pass found our render recognisably the same skin at rest.

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: headless log cannot show whether text overlaps, whether menu graphics render, or whether the UI looks correct; only that structure exists
