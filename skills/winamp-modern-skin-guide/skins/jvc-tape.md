## JVC Tape (`jvc.tape.v0.5.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `jvc.tape.v0.5.wal` · 1,943,429 B · SHA-256 `0e79514d557e7713…`, version 1.1
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Declares no library window, so a standard NullPlayer window stands in. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Compatibility level:** `degraded` (a diagnostic count, not a quality signal)

**Measured status:**

```
main container   main  (96.2% of its canvas painted)
layouts          6, 312 scene nodes total
surface fallback library
hosted windows   0 wear the skin frame, 8 fall back to plain
scripts          11 programs, 0 with a failing handler
unsupported MAKI none
artwork          64 resolved; unresolved: 2 base, 0 hover/pressed, 0 deliberate draw-nothing
findings         0 error, 18 warning, 0 info
```

**Known outstanding:**

- 2 bitmap id(s) it references do not resolve, leaving a visible gap: `pl.button.bg`, `pl.button.small`
- no library window of its own
- 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140)
- 3 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click

### Not measured

No live pass, no driven click, no motion ladder, no menu walk, no coverage figure. Every number above is from one headless render at rest: it says a thing exists, never that it is drawn right or that it responds.
