## Rika (`Rika.wal`)

**Name clash:** this archive's `skininfo` calls itself **T-800** by Quadhelix, and so does the separate, smaller `T800.wal` ([t800.md](t800.md)). Different SHA-256, different sizes, both installed. Go by the hash, not the name.

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Rika.wal` · 703,189 B · SHA-256 `25ac7fb836e7430b…` · author "Quadhelix", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
shape        separateWindows, 10 containers (main, eq, spider1, spider2, spider3, spider4, Message, Warp Browser, nullplayer.playlist, nullplayer.library), 10 layouts, 144 scene nodes total
main window  450x450 (main/normal)
embedded     none
own window   equalizer, playlist, library
classic      video, visualization — the skin declares no video or visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    1 object total (animatedlayer#progress.ani); layouts with zero: eq/normal, spider1/normal, spider2/normal, spider3/normal, spider4/normal, Message/normal, Warp Browser/normal, nullplayer.playlist/normal, nullplayer.library/normal
scripts      8 programs loaded, 0 reported a failed handler
unsupported  none
artwork      87 resolved, 0 unresolved ids
findings     0 errors, 112 warnings, 0 info
```

**Worth a look:** looks wrong: 112 warnings for missing optional bitmaps spanning player, eq, system, and menu resources, per lines 33-144

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: log is structural only — cannot show visual rendering of missing UI elements or animation quality
