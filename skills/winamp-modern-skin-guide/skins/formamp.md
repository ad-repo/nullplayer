## Formamp (`Formamp.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Formamp.wal` · 60,814 B · SHA-256 `f604f3df50343532…` · author "coronerss", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- nothing outstanding that a headless pass can see


**Measured status:**

```
shape        separateWindows, 3 containers (main, nullplayer.playlist, nullplayer.library), 3 layouts, 67 scene nodes total
main window  340x132
embedded     none
own window   playlist, library
classic      equalizer, video, visualization — the skin declares no equalizer, video, or visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    0 total; layouts with zero: main/normal, nullplayer.playlist/normal, nullplayer.library/normal
scripts      6 programs loaded, 0 reported a failed handler
unsupported  none
artwork      45 resolved, 0 unresolved ids
findings     0 error, 2 warning, 0 info
```

**Worth a look:** looks wrong: wasabi.standardframe.statusbar resolves no artwork twice (lines 24–25), causing synthesized playlist and library windows to render plain

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: a headless log does not show how unresolved statusbar appearance affects usability in the rendered playlist/library windows
