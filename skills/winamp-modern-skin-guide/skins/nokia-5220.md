## Nokia_5220 (`The_Nokia_5220_XpressMusic.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `The_Nokia_5220_XpressMusic.wal` · 649,317 B · SHA-256 `0d4fad027867a04b…`, version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- nothing outstanding that a headless pass can see


**Measured status:**

```
shape        separateWindows, 3 containers (main, nullplayer.playlist, nullplayer.library), 4 layouts, 94 scene nodes total
main window  378x378
embedded     equalizer
own window   playlist, library
classic      video, visualization — the skin declares no video or visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    0 total; layouts with zero: main/normal, main/alt, nullplayer.playlist/normal, nullplayer.library/normal
scripts      10 programs loaded, 0 reported a failed handler
unsupported  none
artwork      59 resolved, 0 unresolved ids
findings     0 error, 9 warning, 0 info
```

**Worth a look:** looks wrong: 9 duplicate studio.button.* resource identifiers (lines 32–40) each replacing an earlier definition in standardframe/studio-elements.xml

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: a headless log cannot reveal whether the second definition of each button style overwrites the first visually or leaves both traces in the render
