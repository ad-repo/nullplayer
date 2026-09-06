## MMD3 (`mmd3.wal` and `MMD3-4-5.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

Two **different** archives that both declare themselves `MMD3`, version 2.2, in `skininfo` — they are not duplicates (different SHA-256, different sizes) and both are installed. One file covers them because the name does not distinguish them; the hashes below do.

- **`mmd3.wal`** · 1,019,741 B · SHA-256 `c6c96a9232a2449a…`
- **`MMD3-4-5.wal`** · 1,256,458 B · SHA-256 `9b4eec002df5be2b…`

- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **`mmd3.wal` grade: B (provisional · confidence: medium)** — Everything it declares routes, draws and resolves, and it calls no unimplemented script method.
- **`MMD3-4-5.wal` grade: B (provisional · confidence: medium)** — Everything it declares routes, draws and resolves, and it calls no unimplemented script method.

A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.

**Measured status:**

```
--- mmd3.wal  (level degraded)
  main container   main  (100.0% of its canvas painted)
  layouts          8, 459 scene nodes total
  surface fallback none — every surface has a home
  hosted windows   8 wear the skin frame, 0 fall back to plain
  scripts          6 programs, 0 with a failing handler
  unsupported MAKI none
  artwork          350 resolved; unresolved: 0 base, 0 hover/pressed, 0 deliberate draw-nothing
  findings         0 error, 5 warning
--- MMD3-4-5.wal  (level degraded)
  main container   main  (100.0% of its canvas painted)
  layouts          8, 459 scene nodes total
  surface fallback none — every surface has a home
  hosted windows   8 wear the skin frame, 0 fall back to plain
  scripts          5 programs, 0 with a failing handler
  unsupported MAKI none
  artwork          333 resolved; unresolved: 5 base, 0 hover/pressed, 0 deliberate draw-nothing
  findings         0 error, 4 warning
```

**Known outstanding:**

- *mmd3.wal* — 23 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- *MMD3-4-5.wal* — 5 bitmap id(s) it references do not resolve, leaving a visible gap: `pledit.buttonbg.add`, `pledit.buttonbg.misc`, `pledit.buttonbg.options`, `pledit.buttonbg.rem`, `pledit.buttonbg.sel`; 22 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click

### Not measured

No live pass, no driven click, no motion ladder, no menu walk, no coverage figure for either archive. Every number above is from one headless render at rest.
