## Sony (`Sony_Walkman.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Sony_Walkman.wal` · 453,078 B · SHA-256 `697f8969983fccf2…` · author "Petrol Designs", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Declares no library, playlist window, so a standard NullPlayer window stands in. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `partly-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- no library, playlist window of its own
- 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140)
- 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
shape        separateWindows, 3 containers (Component, eq, main), 6 layouts (main/shade partially corrupted), 138 scene nodes total
main window  335x106 (normal layout)
embedded     none
own window   equalizer only
classic      library, playlist — statusbar frame has no instantiating script to create content, per line 19
hosted       0 wear the skin frame, 8 fall back to classic
clickable    2 objects across layouts; layouts with zero: Component/resizable_status, Component/resizable_nostatus, Component/modal, Component/static, eq/normal
scripts      1 program loaded, 0 reported a failed handler
unsupported  none
artwork      117 resolved, 0 unresolved ids in header; however FINDINGs report frame/menu.png missing ×3, discrepancy noted
findings     0 error, 3 warning, 0 info
```

**Worth a look:** looks wrong: Surfaces playlist and library fall back to classic because wasabi.standardframe.statusbar/nostatusbar/static have no frame scripts, per line 19, which could severely break a Walkman-themed interface

Declares no `library,playlist` window of its own, so NullPlayer's standard one stands in. That is usually the skin's age rather than a defect.

Ships no reusable standard frame, so all eight NullPlayer-owned windows open in the plain frame rather than this skin's chrome (B110/B140).

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: Cannot ascertain whether the compact Sony Walkman aesthetic renders authentically, if small display area shows text legibly, or if minimal UI feels appropriate for the intended device metaphor
