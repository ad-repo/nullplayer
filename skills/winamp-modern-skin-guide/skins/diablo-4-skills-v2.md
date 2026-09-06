## Diablo 4 Skills V2 (`Diablo IV Skills V2.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Diablo IV Skills V2.wal` · 9,259,389 B · SHA-256 `7f64f6aec67992db…` · author "sambaneko", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: medium)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 1 bitmap id(s) it references do not resolve, leaving a visible gap: `paragon.seeker.point`


**Measured status:**

```
shape        separateWindows, 7 containers (main, PLEdit, MLibrary, Video, AVS, Equalizer, SkillPicker), 12 layouts, 516 scene nodes total
main window  1080x280
embedded     none
own window   equalizer, library, playlist, video, visualization
classic      none — all declared surfaces are routed to their own containers
hosted       1 wears the skin frame (Skill Selector), 0 fall back to classic
clickable    0 objects across all layouts; layouts with zero: all 12 layouts
scripts      13 programs loaded, 0 reported a failed handler
unsupported  none
artwork      359 resolved, 1 unresolved id (paragon.seeker.point)
findings     0 errors, 11 warnings, 0 info
```

**Worth a look:** looks wrong: all layouts report zero clickable objects per lines 117, 121, 125, 129, 134, 139, 144, 150, 155, 161, 167, 171

The archive ships the author's own `screenshot.png`; the 2026-09-06 comparison pass found our render recognisably the same skin at rest.

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: headless log cannot detect whether this all-layouts-zero-clickables pattern is intentional (input not wired) or a missed routing during skin design
