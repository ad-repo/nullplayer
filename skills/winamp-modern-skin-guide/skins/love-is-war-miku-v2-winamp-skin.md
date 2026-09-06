## Love is War Miku v2 Winamp Skin (`Love Is War Miku V2.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Love Is War Miku V2.wal` · 810,934 B · SHA-256 `067316d2074438d2…` · author "maxim cryseria", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: F (provisional · confidence: low)** — from a headless pass; nobody has used this skin. The main player window renders nothing — 0.0% of its canvas is opaque (b145). A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player.volbg`, `player.volume`
- 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
shape        separateWindows, 7 containers (main, Pledit, MLibrary, video, avs, notifier, notifier.preferences), 8 layouts, 236 scene nodes total
main window  300x450 (main/normal)
embedded     equalizer
own window   playlist, library, video, visualization
classic      none
hosted       8 wear the skin frame, 0 fall back to classic
clickable    1 object total (layer#player.volume); layouts with zero: Pledit/normal, MLibrary/normal, video/normal, avs/normal, notifier/normal, notifier/desktopalpha, notifier.preferences/normal
scripts      21 programs loaded, 0 reported a failed handler
unsupported  none
artwork      131 resolved, 2 unresolved ids (player.volbg, player.volume)
findings     0 errors, 19 warnings, 0 info
```

**Its main player window draws nothing** — 0.0% of the canvas is opaque, while every other window this skin declares renders fully. Open as **B145**; this skin is on the live-pass shortlist.

**Worth a look:** looks wrong: missing player.volbg and player.volume bitmap resources, per lines 44-45

The archive ships the author's own `screenshot.png`; the 2026-09-06 comparison pass found our render recognisably the same skin at rest.

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: log is structural only — cannot verify volume slider appearance, visual rendering quality, or dynamic updates
