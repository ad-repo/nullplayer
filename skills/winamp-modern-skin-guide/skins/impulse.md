## Impulse (`impulse_by_a_t_o_m_i_c_d4wcub.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `impulse_by_a_t_o_m_i_c_d4wcub.wal` · 439,200 B · SHA-256 `33e1d79b062a8083…` · author "a-t-o-m-i-c", version 1.0
- **Measured:** 2026-09-06 · harness `a916b38a` — **headless structural pass only**, see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 1 bitmap id(s) it references do not resolve, leaving a visible gap: `window.normal.resizer`
- 13 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click


**Measured status:**

```
shape        separateWindows, 9 containers (main, Equalizer, Configuration, Tips, PLEdit, MLibrary, Video, notifier, nullplayer.about), 11 layouts, 540 scene nodes total
main window  237x212
embedded     none
own window   equalizer, library, playlist, video
classic      visualization — the skin declares no visualization surface
hosted       2 wear the skin frame (Configuration, Tips), 0 fall back to classic
clickable    13 objects across all layouts; layouts with zero: main/mini, Equalizer/normal, Tips/normal, PLEdit/normal, MLibrary/normal, Video/normal, notifier/normal, nullplayer.about/normal
scripts      15 programs loaded, 0 reported a failed handler
unsupported  none
artwork      364 resolved, 1 unresolved id (window.normal.resizer)
findings     0 errors, 1 warning, 0 info
```

**Worth a look:** looks wrong: only main/normal (2 clickables) and Configuration (9 clickables) are interactive per lines 67, 80; all feature windows have zero clickables per lines 76, 84, 88, 94, 99, 105, 109

### Not measured

No live pass, no `RENDER_CLICK`, no motion ladder, no menu walk, and no coverage figure. Every number above is a **declaration count from one headless render at rest** — it says a thing exists, never that it is drawn right or that it responds. evidence gap: headless log cannot evaluate whether Configuration and Tips are meant to be configuration dialogs (clickable-light) or whether missing window.normal.resizer bitmap (1 unresolved per line 5) hampers frame resizing affordance
