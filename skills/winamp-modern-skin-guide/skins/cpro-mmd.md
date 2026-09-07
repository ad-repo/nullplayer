## cPro - MMD (`221721-cPro_MMD.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `221721-cPro_MMD.wal` · 552,005 B · SHA-256 `cdffafd053ab8e1f…`, version 1.04
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: medium)** — from a headless pass; nobody has used this skin. Calls 1 unimplemented maki method(s) ×4 (`enumitem`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `unsupported` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 2 bitmap id(s) it references do not resolve, leaving a visible gap: `beat.0.right`, `player.led.off`
- unimplemented MAKI: `enumitem` ×4
- 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 1 error-severity load finding(s)


**Measured status:**

```
shape        singleWindowSUI, 8 containers (searchresults, browserpro, notifier, main, widgets.manager, nullplayer.about, searchresults#2, searchresults#3), 8 layouts, 301 scene nodes total
main window  500x500
embedded     equalizer, library, playlist, video
own window   none
classic      visualization — the skin declares no visualization surface
hosted       1 wears the skin frame (Widgets Manager), 0 fall back to classic
clickable    12 objects across all layouts; layouts with zero: searchresults/normal, browserpro/normal, notifier/normal, notifier/desktopalpha, main/shade, nullplayer.about/normal
scripts      2 programs loaded, 1 reported a failed handler (onaction)
unsupported  enumitem×2
artwork      90 resolved, 3 unresolved ids (beat.0.right, player.led.off, studio.BaseTexture)
findings     1 error, 33 warnings, 0 info
```

**Worth a look:** looks wrong: one script failed with "enumitem not implemented" per line 146, plus unsupportedScriptCapability×2 errors per line 224

The archive ships the author's own `screenshot.png`; the 2026-09-06 comparison pass found our render recognisably the same skin at rest.

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: headless log cannot show whether enumitem's no-op behavior causes visual glitches or missing features on specific UI elements
