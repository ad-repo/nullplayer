## Pokemon DS (`PokemonDS.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `PokemonDS.wal` · 380,314 B · SHA-256 `b88220b7950d566d…` · author "SpaceKitty", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- nothing outstanding that a headless pass can see


**Measured status:**

```
shape        separateWindows, 3 containers (main, nullplayer.playlist, nullplayer.library), 8 layouts, 192 scene nodes total
main window  360x510
embedded     none
own window   playlist, library
classic      equalizer, video, visualization — the skin declares no equalizer, video, or visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    0 total; layouts with zero: main/normal1, main/normal2, main/normal3, main/normal4, main/normal5, main/normal6, nullplayer.playlist/normal, nullplayer.library/normal
scripts      20 programs loaded, 0 reported a failed handler
unsupported  none
artwork      128 resolved, 1 unresolved id (wasabi.frame.basetexture)
findings     0 error, 22 warning, 0 info
```

**Worth a look:** looks wrong: 19 duplicate group identifiers (studio.button.* and player.* redefined across player-mode files 1–6, lines 56–74) plus 3 missing optional window/stdframe_listbg.png resources (lines 53–55)

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: a structural log records redefinitions and missing assets but does not show which redefined group actually renders or whether the visual hierarchy is correct
