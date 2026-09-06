## Styx (`Styx.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Styx.wal` · 996,993 B · SHA-256 `755f7bad46deb96c…`, version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Calls 2 unimplemented maki method(s) ×14 (`getmode`, `setchecked`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Compatibility level:** `unsupported` (a diagnostic count, not a quality signal)

**Measured status:**

```
main container   Main  (100.0% of its canvas painted)
layouts          9, 504 scene nodes total
surface fallback none — every surface has a home
hosted windows   8 wear the skin frame, 0 fall back to plain
scripts          42 programs, 0 with a failing handler
unsupported MAKI getmode x2, setchecked x12
artwork          392 resolved; unresolved: 0 base, 0 hover/pressed, 0 deliberate draw-nothing
findings         7 error, 28 warning, 0 info
```

**Known outstanding:**

- unimplemented MAKI: `getmode` ×2, `setchecked` ×12
- 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 7 error-severity load finding(s)

### Not measured

No live pass, no driven click, no motion ladder, no menu walk, no coverage figure. Every number above is from one headless render at rest: it says a thing exists, never that it is drawn right or that it responds.
