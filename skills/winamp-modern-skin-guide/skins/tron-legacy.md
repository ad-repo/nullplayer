## TRON___Legacy (`TRON___Legacy.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `TRON___Legacy.wal` · 181,082 B · SHA-256 `1b991ded5548dbc4…`, version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: medium)** — from a headless pass; nobody has used this skin. Declares no library window, so a standard NullPlayer window stands in. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `partly-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- no library window of its own
- 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140)
- 1 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
shape        separateWindows, 3 containers (main, eq, Pledit), 3 layouts, 60 scene nodes total
main window  275x116 (main/normal)
embedded     none
own window   equalizer (eq), playlist (Pledit)
classic      library — frame scripts missing per FINDING line 19
hosted       0 wear the skin frame, 8 fall back to classic
clickable    1 object total; layouts with zero: eq/eq, Pledit/normal
scripts      1 program loaded, 0 reported a failed handler
unsupported  none
artwork      29 resolved, 0 unresolved ids
findings     0 error, 2 warning, 0 info
```

**Worth a look:** looks wrong: all 8 hosted NullPlayer windows (library, playlist, video, visualization, configure) fall back to classic because frame scripts for wasabi.standardframe variants do not instantiate content, per FINDING line 19

Declares no `library` window of its own, so NullPlayer's standard one stands in. That is usually the skin's age rather than a defect.

Ships no reusable standard frame, so all eight NullPlayer-owned windows open in the plain frame rather than this skin's chrome (B110/B140).

The archive ships the author's own `screenshot.png`; the 2026-09-06 comparison pass found our render recognisably the same skin at rest.

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: cannot show why frame scripts are missing or whether the fallback classic rendering fits the TRON Legacy aesthetic; cannot verify if the single seeker control at line 22 is functionally correct
