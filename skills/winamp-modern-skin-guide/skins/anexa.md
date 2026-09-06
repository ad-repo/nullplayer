## Anexa (`Anexa.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Anexa.wal` · 337,401 B · SHA-256 `d2a1ad8db2fc2550…` · author "nynako / skin-zone", version 1.1
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has driven this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Compatibility level:** `degraded` (a diagnostic count, not a quality signal)

**Measured status:**

```
main container   main  (67.1% of its canvas painted)
layouts          10, 273 scene nodes total
surface fallback none — every surface has a home
hosted windows   8 wear the skin frame, 0 fall back to plain
scripts          16 programs, 0 with a failing handler
unsupported MAKI none
artwork          207 resolved; unresolved: 0 base, 0 hover/pressed, 0 deliberate draw-nothing
findings         0 error, 3 warning, 0 info
```

**Known outstanding:**

- nothing outstanding that a headless pass can see

### Not measured

No live pass, no driven click, no motion ladder, no menu walk, no coverage figure. Every number above is from one headless render at rest: it says a thing exists, never that it is drawn right or that it responds.
