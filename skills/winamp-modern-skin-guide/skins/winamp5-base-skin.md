## Winamp5 Base Skin (`nullsoft_media_player_10_forked_by_hb860-d7h03zd.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `nullsoft_media_player_10_forked_by_hb860-d7h03zd.wal` · 271,693 B · SHA-256 `4e6c741c30aa7585…`, version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Calls 2 unimplemented maki method(s) ×4 (`getmode`, `onleftbuttondown`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `unsupported` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.bottom.left.corner`, `component.bottom.right.corner`, `component.bottom.stretch`, `component.top.right.corner`
- unimplemented MAKI: `getmode` ×2, `onleftbuttondown` ×2
- 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 2 error-severity load finding(s)


**Measured status:**

```
shape        singleWindowSUI, 3 containers (main, MLibrary, nullplayer.about), 5 layouts, 259 scene nodes total
main window  435x304 (main/normal layout)
embedded     equalizer, playlist, video
own window   library only
classic      visualization only — the skin declares no visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    3 objects across layouts (all in main/normal); layouts with zero: main/shade, main/fullscreens, MLibrary/normal, nullplayer.about/normal
scripts      8 programs loaded, 2 reported failed handlers (getmode, onleftbuttondown)
unsupported  getmode ×1, onleftbuttondown ×1
artwork      181 resolved, 4 unresolved ids (component.bottom.left.corner, component.bottom.right.corner, component.bottom.stretch, component.top.right.corner)
findings     2 error, 28 warning, 0 info
```

**Worth a look:** looks wrong: player-normal layout onscriptloaded failed with method 'getmode' not implemented (line 17), and about.xml onscriptloaded failed with 'onleftbuttondown' as handler (line 31), the latter being an anomalous method name that could break About window interaction

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: Cannot confirm whether Nullsoft Media Player 10 retro aesthetic renders cleanly, whether embedded video/visualizer/playlist integrate visually within the single-window frame, or whether fullscreen mode functions as intended
