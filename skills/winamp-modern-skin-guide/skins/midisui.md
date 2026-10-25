## MIDISUI (`MIDISUI_1_1.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md).*

- **File:** `MIDISUI_1_1.wal` · SHA-256 `6778daa51be3e2a316bab0eff96ed5e6…` · intake #2, silver
- **Measured:** 2026-10-23 — `skin-triage` pass, headless plus live (reported live: "odd display
  problems, not all buttons work", then "the library browser takes over the main window blank and
  cannot be exited")
- **Shape:** one 750×450 single-window SUI (`normal`, `normalthanks`, `Media Library`) plus two
  companion windows declared `default_visible="1"` beside it: **Skin Info** (`info` credits page,
  `beatvis` mini player) and **Color Themes**. No screenshot ships in the archive and its
  winampheritage page is gone, so the skin's own artwork was the reference.

**Fixed (four engine rules):**

- The vis drawer (`DrawerGroup`, no `w`/`h`) opens from `drawer.maki` with `setTargetX(-118)`; it
  slid over the COMPONENT column and the playlist, burying the playlist / vis studio / video
  buttons. A group with no declared box now clips to its children's declared union while a target
  move is under way ([rendering.md](../reference/rendering.md)).
- `ledAnimation` groups are instanced `image="led.animation"` (the 280×14 sheet); the engine drew
  the group's `image=` as art — 20 dots over the TIMER / SONG INFO / TRACK labels, 120px past the
  right edge. A group no longer takes `image=`.
- The library holder is `hold="guid:{6B0EDF80-…} (Media library)"`; the label's hex letters joined
  the GUID, so it held nothing. A braced GUID now ends at its brace ([components.md](../reference/components.md)).
- The Media Library layout has no `CLOSE`; the view's fallback close corner sat on the skin's
  `SWITCH normal` button and quit the app. The corner now yields to a skin control.

**By the skin's design, not defects:**

- The ✕ on the main window (`ExitMain`, `exitmain.maki`) and on Skin Info (`Exit1`/`Exit2`,
  `exit.maki`) print a goodbye, fade, then call `System.Shutdown()` — they quit, as in Winamp. The
  user chose to keep that (2026-10-23). Skin Info is dismissed with the main window's `info.toggle`.
- Crossfade ‹ › are `ghost="1"` until crossfade is on (`crossfade.maki` un-ghosts them).
- The 21 station buttons (`SOMA.maki`) call `playFile` on 2008-era SomaFM / di.fm URLs; the
  request reaches `StreamingAudioPlayer` and the server answers with something that is not audio.

**Ruled out:**

- *The drawer button is dead* — the interaction sweep reads it `silent` only because the startup
  open animation is still playing inside its 2 s window; `RENDER_SETTLE=3` drives it both ways.
- *Crossfade + is stuck at 2* — headless only: the stub host swallows `crossfadeSeconds`; live it
  steps 1 → 4.
- *`playbuttons.drawer` covers the playlist* — a transient wipe that returns to `alpha=0`.
- *Color Themes' red panel is mis-drawn* — it is the window's own background art.

**Known outstanding:**

- The mini view's `info.toggle` is `TOGGLE main` (hide the player, keep the mini player); the host
  toggles auxiliary containers only, so it does nothing.
- Right-click menus not checked.
