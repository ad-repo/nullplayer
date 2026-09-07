## Firefox (`Firefox.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Firefox.wal` · 908,585 B · SHA-256 `96a28ac0a145e923…` · author "Quadhelix", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
shape        separateWindows, 4 containers (main, eq, nullplayer.playlist, nullplayer.library), 5 layouts, 100 scene nodes total
main window  500x240 (main/normal)
embedded     none
own window   equalizer (eq)
classic      none — not in log
hosted       8 wear the skin frame, 0 fall back to classic
clickable    1 object total; layouts with zero: main/normal2, eq/normal, nullplayer.playlist/normal, nullplayer.library/normal
scripts      17 programs loaded, 0 reported a failed handler
unsupported  none
artwork      67 resolved, 0 unresolved ids
findings     0 error, 112 warning, 0 info
```

**Worth a look:** looks wrong: missing include file "xml/xuiobjects.xml" skipped per FINDING line 47; 112 warnings mostly for missing player bitmaps (buttons, animations, visualizer sprites)

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: cannot assess whether missing player graphics break any UI flow or whether the 500x240 layout renders legibly with all text and buttons
