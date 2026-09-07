## K-jr (`K-jr.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `K-jr.wal` · 239,458 B · SHA-256 `4cd619470e5b15fb…` · author "Marisa85", version 1.0.1
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has driven this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.

**Known outstanding:**

- 2 bitmap id(s) it references do not resolve, leaving a visible gap: `img/bt_crf.png`, `img/bt_none.png`
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Measured status:**

```
shape        separateWindows, 10 containers (main, cont.clear.dl, cont.clear.pl, cont.clear.vd, cont.clear.ml, PLEdit, Video, MLibrary, DLibrary, cont.clear.vd#2), 11 layouts, 144 scene nodes total
main window  153x233
embedded     equalizer
own window   library (MLibrary), playlist (PLEdit), video (Video)
classic      visualization — skin declares no visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    1 total; layouts with zero: 10 layouts (all except main/Control)
scripts      8 programs loaded, 0 reported a failed handler
unsupported  none
artwork      54 resolved, 2 unresolved ids (img/bt_crf.png, img/bt_none.png)
findings     0 error, 50 warning, 0 info
```

**Worth a look:** looks wrong: 50 warnings for missing img/elements.png, repeated references to same file from elements.xml suggest resource path issues, per line 42+

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: headless log cannot determine which UI controls are actually functional or show what should render when files are missing
