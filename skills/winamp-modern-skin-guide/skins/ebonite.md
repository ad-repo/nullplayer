## Ebonite (`Ebonite_2_1.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Ebonite_2_1.wal` · 596,336 B · SHA-256 `66487c42feffc28a…` · author "WinstonGFX and SLoB", version 2.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Calls 2 unimplemented maki method(s) ×4 (`enumgammagroup`, `setchecked`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Compatibility level:** `unsupported` (a diagnostic count, not a quality signal)

**Measured status:**

```
main container   main  (93.3% of its canvas painted)
layouts          17, 455 scene nodes total
surface fallback none — every surface has a home
hosted windows   8 wear the skin frame, 0 fall back to plain
scripts          32 programs, 0 with a failing handler
unsupported MAKI enumgammagroup x2, setchecked x2
artwork          262 resolved; unresolved: 1 base, 0 hover/pressed, 0 deliberate draw-nothing
findings         4 error, 46 warning, 0 info
```

**Known outstanding:**

- 1 bitmap id(s) it references do not resolve, leaving a visible gap: `brightness.bg1`
- unimplemented MAKI: `enumgammagroup` ×2, `setchecked` ×2
- 7 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 4 error-severity load finding(s)

### Not measured

No live pass, no driven click, no motion ladder, no menu walk, no coverage figure. Every number above is from one headless render at rest: it says a thing exists, never that it is drawn right or that it responds.
