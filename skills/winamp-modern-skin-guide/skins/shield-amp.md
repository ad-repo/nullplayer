## Shield_AMP (`Shield_Amp.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Shield_Amp.wal` · 896,917 B · SHA-256 `e52d89a66811b113…` · author "team skinconsortium [graphic by Mike a.k.a WistonGFX coding by Faris Wijaya a.k.a Faris18787 and SLoB]", version beta
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Calls 2 unimplemented maki method(s) ×4 (`setchecked`, `setxmlparam`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Compatibility level:** `unsupported` (a diagnostic count, not a quality signal)

**Measured status:**

```
main container   main  (90.6% of its canvas painted)
layouts          11, 530 scene nodes total
surface fallback none — every surface has a home
hosted windows   8 wear the skin frame, 0 fall back to plain
scripts          47 programs, 0 with a failing handler
unsupported MAKI setchecked x2, setxmlparam x2
artwork          351 resolved; unresolved: 0 base, 0 hover/pressed, 0 deliberate draw-nothing
findings         3 error, 40 warning, 0 info
```

**Known outstanding:**

- unimplemented MAKI: `setchecked` ×2, `setxmlparam` ×2
- 6 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 3 error-severity load finding(s)

### Not measured

No live pass, no driven click, no motion ladder, no menu walk, no coverage figure. Every number above is from one headless render at rest: it says a thing exists, never that it is drawn right or that it responds.
