## micro (`micro.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `micro.wal` · 1,265,732 B · SHA-256 `5d5641926bf2c0da…`, version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Compatibility level:** `degraded` (a diagnostic count, not a quality signal)

**Measured status:**

```
main container   main  (58.4% of its canvas painted)
layouts          3, 116 scene nodes total
surface fallback none — every surface has a home
hosted windows   8 wear the skin frame, 0 fall back to plain
scripts          9 programs, 0 with a failing handler
unsupported MAKI none
artwork          68 resolved; unresolved: 4 base, 0 hover/pressed, 0 deliberate draw-nothing
findings         0 error, 12 warning, 0 info
```

**Known outstanding:**

- 4 bitmap id(s) it references do not resolve, leaving a visible gap: `component.region.bottom.left`, `component.region.bottom.right`, `component.region.top.left`, `component.region.top.right`
- 4 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click

### Not measured

No live pass, no driven click, no motion ladder, no menu walk, no coverage figure. Every number above is from one headless render at rest: it says a thing exists, never that it is drawn right or that it responds.
