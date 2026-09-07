## ZDL-AMP SIX-TRACK REEL-TO-REEL WA-3 (`ZDL_Reel-To-Reel_Analog_Tape_Machine.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `ZDL_Reel-To-Reel_Analog_Tape_Machine.wal` · 526,715 B · SHA-256 `b67c392efb1c07ff…` · author "Mike Zee", version 1
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `unknown` · compatibility level `-` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 4 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
shape        separateWindows, 5 containers (EQ, Main, thinger, nullplayer.playlist, nullplayer.library), 9 layouts, 310 scene nodes total
main window  275x348 (Main/normal layout)
embedded     none
own window   equalizer only
classic      visualization only — the skin declares no visualization surface
hosted       not in log (header incomplete); library and playlist are synthesized by NullPlayer
clickable    4 objects across layouts (Main/normal: 2, Main/compact: 1, thinger/normal: 1); layouts with zero: EQ/normal, EQ/advanced, EQ/shade, Main/shade, nullplayer.playlist/normal, nullplayer.library/normal
scripts      8 programs loaded, 0 reported a failed handler
unsupported  none
artwork      199 resolved, 0 unresolved ids per layout totals; header incomplete
findings     0 error, 2 warning, 0 info
```

**Worth a look:** looks wrong: Synthesized library and playlist windows lack standard frame artwork resources (wasabi.standardframe.statusbar), per line 34-35, resulting in plain windows without reel-to-reel styling

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: Cannot verify whether spinning reel graphics animate, whether needle meters track audio dynamics, or whether the three layout modes (normal/compact/shade) present visually distinct experiences
