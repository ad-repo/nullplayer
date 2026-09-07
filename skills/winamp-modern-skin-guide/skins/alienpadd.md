## AlienPADD (`PaddPreview.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `PaddPreview.wal` · 675,762 B · SHA-256 `ef398cd4a8f92a6f…`, version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 2 bitmap id(s) it references do not resolve, leaving a visible gap: `player.normal.button.menu.btn`, `player.shade.shade`
- 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
shape        separateWindows, 4 containers (main, Pledit, MLib, Settings), 5 layouts, 193 scene nodes total
main window  226x486 (main/normal)
embedded     equalizer
own window   playlist (Pledit), library (MLib)
classic      none — not in log
hosted       8 wear the skin frame, 0 fall back to classic
clickable    1 object total; layouts with zero: main/shade, Pledit/normal, MLib/normal, Settings/normal
scripts      9 programs loaded, 0 reported a failed handler
unsupported  none
artwork      137 resolved, 3 unresolved ids (component.basetexture, player.normal.button.menu.btn, player.shade.shade)
findings     0 error, 21 warning, 0 info
```

**Worth a look:** looks wrong: missing include file "pledit-elements.xml" skipped per FINDING line 31; missing close button and hover state bitmaps per FINDING lines 49-51

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: cannot show whether the tall narrow main window (226x486) renders with adequate spacing or whether missing menu assets break functionality
