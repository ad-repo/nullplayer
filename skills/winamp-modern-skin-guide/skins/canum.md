## Canum (`canum_winamp_by_burnsplayguitar_d2xhizu.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `canum_winamp_by_burnsplayguitar_d2xhizu.wal` · 439,776 B · SHA-256 `4afef48777717d68…` · author "burnsplayguitar", version 1
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Declares no library, playlist window, so a standard NullPlayer window stands in. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `partly-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 1 bitmap id(s) it references do not resolve, leaving a visible gap: `displayscreen`
- no library, playlist window of its own
- 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140)


**Measured status:**

```
shape        separateWindows, 1 container (main), 1 layout, 34 scene nodes total
main window  340x220 (main/normal)
embedded     equalizer
own window   none
classic      library, playlist — frame scripts missing per FINDING line 26
hosted       0 wear the skin frame, 8 fall back to classic
clickable    0 objects total; layouts with zero: main/normal
scripts      4 programs loaded, 0 reported a failed handler
unsupported  none
artwork      11 resolved, 2 unresolved ids (displayscreen, player.VolumeKnob.blank)
findings     0 error, 4 warning, 0 info
```

**Worth a look:** looks wrong: critical include files missing (@DEFAULTSKINPATH@xml/eq.xml, @DEFAULTSKINPATH@xml/thinger.xml, @DEFAULTSKINPATH@xml/pledit.xml) per FINDING lines 20-22; all 8 hosted NullPlayer windows fall back to classic rendering

Declares no `library,playlist` window of its own, so NullPlayer's standard one stands in. That is usually the skin's age rather than a defect.

Ships no reusable standard frame, so all eight NullPlayer-owned windows open in the plain frame rather than this skin's chrome (B110/B140).

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: cannot show whether the single main window renders functionally without the missing includes; cannot assess the impact of missing volume knob artwork
