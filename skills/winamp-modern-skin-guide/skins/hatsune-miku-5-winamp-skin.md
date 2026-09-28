## Hatsune Miku 5 Winamp Skin (`hatsune_miku_5_winamp_by_kaza_sou_d6izotp.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `hatsune_miku_5_winamp_by_kaza_sou_d6izotp.wal` · 889,998 B · SHA-256 `d7a69173912dd147…` · author "kazasou feat. msdzero", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. The main player window was confirmed drawing in the running app 2026-09-27 (B145 closed: the earlier "renders nothing" reading was a measurement artifact). A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- nothing outstanding that a headless pass can see


**Measured status:**

```
shape        separateWindows, 8 containers (main, Pledit, MLibrary, video, avs, notifier, notifier.preferences, nullplayer.about), 9 layouts, 267 scene nodes total
main window  514x313 (main/normal)
embedded     equalizer
own window   playlist, library, video, visualization
classic      none
hosted       7 wear the skin frame, 0 fall back to classic
clickable    0 objects total; layouts with zero: main/normal, Pledit/normal, MLibrary/normal, video/normal, avs/normal, notifier/normal, notifier/desktopalpha, notifier.preferences/normal, nullplayer.about/normal
scripts      39 programs loaded, 0 reported a failed handler
unsupported  none
artwork      153 resolved, 0 unresolved ids
findings     0 errors, 28 warnings, 0 info
```

**Its main player window draws.** The 2026-09-06 pass recorded it as empty (B145); a re-dump and a live `launch.sh` + `capture` on 2026-09-27 both show the full player, so that reading was stale.

The archive ships the author's own `screenshot.png`; the 2026-09-06 comparison pass found our render recognisably the same skin at rest.

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: log is structural only — cannot confirm visual appearance, theme colors, or animation implementation
