## EPS (Egor Petrov Systems) (`EPS_High-End_System_v1_test.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `EPS_High-End_System_v1_test.wal` · 1,219,330 B · SHA-256 `072568c903fc074b…` · author "Egor Petrov", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: C (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Calls 1 unimplemented maki method(s) ×2 (`setchecked`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `player-skinned` · compatibility level `unsupported` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 9 bitmap id(s) it references do not resolve, leaving a visible gap: `meterback`, `pausetip`, `peak`, `playtip`, `shade.bg.met`, `speaker3`…
- unimplemented MAKI: `setchecked` ×2
- 8 NullPlayer-owned window(s) open in the plain frame — no reusable standard frame (B110/B140)
- 13 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 1 error-severity load finding(s)


**Measured status:**

```
shape        separateWindows, 11 containers (opensource_notifier, opensource_notifier_prefs, Main, leftspeaker, rightspeaker, eq, PLEdit, ML, Video, meter, visualizator), 20 layouts, 464 scene nodes total
main window  752x160 (Main/normal layout)
embedded     none
own window   equalizer, library, playlist, video
classic      visualization only — the skin declares no visualization surface
hosted       0 wear the skin frame, 8 fall back to classic
clickable    13 objects across all layouts; layouts with zero: opensource_notifier_prefs/normal, Main/shade_metallic, leftspeaker/normal, leftspeaker/metallic, leftspeaker/glassy, rightspeaker/normal, rightspeaker/metallic, rightspeaker/glassy, PLEdit/normal, ML/normal, Video/normal, meter/normal, meter/metallic
scripts      17 programs loaded, 0 reported a failed handler
unsupported  setchecked ×1
artwork      310 resolved, 10 unresolved ids (component.basetexture, meterback, pausetip, peak, playtip, shade.bg.met, speaker3, stoptip, and others)
findings     1 error, 34 warning, 0 info
```

**Worth a look:** looks wrong: notifier onscriptloaded failed with 'setchecked' not implemented, per line 15, which could disable the checkbox in the notifier preferences

Ships no reusable standard frame, so all eight NullPlayer-owned windows open in the plain frame rather than this skin's chrome (B110/B140).

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: Cannot determine if cassette tape mechanics, analog meters, speaker box graphics, and glass overlay effects render with intended 3D depth and smooth animations
