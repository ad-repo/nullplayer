## Windpws Media Player 11 BlueVU (`WMP11-BlueVU.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `WMP11-BlueVU.wal` · 901,011 B · SHA-256 `554506ba9f36d420…` · author "X - Man", version 0.9.6
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: medium)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `unsupported` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 1 bitmap id(s) it references do not resolve, leaving a visible gap: `seeker.bg.vertical.right`
- 5 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 3 error-severity load finding(s)


**Measured status:**

```
shape        separateWindows, 9 containers (main, eq, about, Video, Pledit, Meter, Meter#2, nullplayer.about, nullplayer.library), 13 layouts, 629 scene nodes total
main window  354x147 (main/normal)
embedded     none
own window   equalizer, playlist, video, library
classic      visualization — the skin declares no visualization surface
hosted       8 wear the skin frame, 0 fall back to classic
clickable    4 objects total (group#Sysmenu in multiple layouts); layouts with zero: main/shade, about/normal, Video/shade, Pledit/normal, Pledit/shade, Meter/normal, Meter#2/normal, nullplayer.library/normal
scripts      99 programs loaded, 3 reported a failed handler (Script requested unknown group '')
unsupported  none
artwork      556 resolved, 1 unresolved ids (seeker.bg.vertical.right)
findings     3 errors, 25 warnings, 0 info
```

**Worth a look:** looks wrong: 3 missingGroupDefinition errors from scripts referencing empty group '', per lines 124-126

The archive ships the author's own `screenshot.png`; the 2026-09-06 comparison pass found our render recognisably the same skin at rest.

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: log is structural only — cannot verify UI rendering, synthesized library window appearance, or control functionality
