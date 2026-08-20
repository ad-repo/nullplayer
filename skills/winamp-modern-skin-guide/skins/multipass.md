## multipass 1.4 (`multipass_1_4_by_rpeterclark_d5lwjv.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

**Fixture note:** the archive ships its MAKI **sources** (`scripts/*.m`, 14 files) beside the compiled
`.maki`. Read them rather than disassembling — this skin's whole behaviour is legible in about 1,500
lines of C-like source, and the Phase 33 diagnosis came straight out of `scripts/drawers.m`.

**Shape of the skin:** separate-window arrangement. `main` (252×333, plus a shade layout) with
`pledit`, `mlibrary`, `video`, `avs_window`, `notifier` and `about` containers. Everything the player
does beyond transport lives in three **drawers** that slide out of the main window: a volume drawer to
the right, a left drawer with the toggle, and a bottom drawer with EQ / Options / Color Themes pages.
Compatibility level **`full`** since Phase 33.

### The Phase 33 defect — one method, the whole skin

`scripts/system.m`'s `System.onScriptLoaded` runs eleven initialisers in a row. The **eighth statement
of the first one** (`initDrawers`, `scripts/drawers.m:72`) is
`System.newGroupAsLayout("player.normal.group.drawer.colorthemes.list")`. The method was not in
`signature(for:)`, and under the engine's fail-closed policy a missing method **aborts the handler** —
which here was the skin's entire startup. Everything after that line never ran: the drawer toggle and
its EQ/Options/ColorThemes buttons, the six options-page buttons, `timerDrawers` (the 100 ms timer that
is the *only* thing that opens the hover drawers), and then `initSeek`, `initTime`, `initVisualizers`,
`initSliders`, `initNotifierHoldTime`, `initShadeSize`, `initBehaviors` and `initStyle` — none of them
at all. The skin was a static picture, and every symptom ("no drawers", "dead seek bar", "Style does
nothing") was that one queue-not-a-set failure.

Five more methods sit immediately downstream and would each have aborted a handler of their own:
`strUpper`, `getClassName` (the style switcher branches on the pair), `isAppActive` (drawer Focus
Mode), `setActivatedNoCallback` (the EQ-menu route to the drawer toggle), `Container.close` (the
notifier). All six landed together — see `compatibility/maki-surface.md`.

A **seventh** gap only became visible once the abort was gone: nothing in the engine dispatched
`onToggle` from a *user click*, and multipass's bottom drawer opens from
`buttonDrawerBottomToggle.onToggle` and from nothing else. Also Phase 33.

### Working

- **The three drawers.** The volume drawer slides 170→195 and the left drawer 44→0 on hover, driven by
  `timerDrawers` at 100 ms through `setTargetX/gotoTarget`; the left drawer's toggle opens the bottom
  drawer (y −178→0). Measured: the graph goes from 54 nodes to 118 when the bottom drawer opens.
- **The colour-theme picker.** 58 themes, one `<ColorThemes:List id="player.colorthemes">`, three
  `colorthemes_*` actions, all resolving to that list. It is created at runtime by
  `newGroupAsLayout` and positioned by `syncLayoutColorThemes` at **(54, 217), 164×78** — verified with
  `RENDER_CLICK_WATCH`, and exactly what the author's own commented-out `<group x="9" y="62"/>` at
  `xml/player-normal.xml:259` would have produced.
- **The seek bar** — which needed three more fixes after the startup abort, none of them in the skin
  (see *Traps*): it is an `<animatedlayer>` whose frame index is the position, with the click handlers
  on the layer itself and a full-window 252×333 greyscale `Map` converting x to a value. It draws, it
  is clickable across its whole width, and a click at x=200 reports and performs `SEEK TO: 3:56 / 4:05`.
- **Time readout, volume/balance sliders, the notifier, shade sizing, the playback LEDs** — all of
  them downstream of the aborted startup, all alive now.
- **Style switching** (Skin menu → Style → Carbon) — `initStyle` walks the skin's element list and
  swaps `image`/`downImage`/`hoverImage`/thumb ids per object kind, which is what `getClassName` is
  for.

- **The title bar's `≡` button** (`player.button.system`, `action="SYSMENU"`, *Display Main Menu*)
  opens NullPlayer's context menu. Phase 33 — it was inert, along with the `CONTROLMENU` version its
  Carbon style and its playlist window use.

- The drawer's eleven `ledfillbar` EQ bars follow **every** EQ change as of Phase 41 — a preset, the
  menu bar, the classic equalizer window, a restored session — not just the skin's own slider drags.
  They ignore the event's arguments and re-read their `parentslider`'s position, which is why the
  engine syncs every `EQ_BAND`/`EQ_PREAMP` slider's position before dispatching. 14 `ledfillbar`
  programs answer each event (`WINAMP_MODERN_RENDER_EQ=3=100,preamp=-64`).

- **`Alt+G` opens and closes the EQ drawer** (Phase 43, confirmed live 2026-08-20). `behaviors.m`'s
  `System.onKeyDown(String strKey)` lowercases the accelerator, compares it against `"alt+g"`, flips
  `configAttribute_eqVisible` and runs `complete;` — the skin's only keyboard shortcut, and the whole
  drawer animation follows from the attribute's `onDataChanged`.

### Not implemented / knowingly wrong

- **The Color Themes drawer's fourth button** (`action="TOGGLE" param="{53DE6284-…}"`, "Open Color
  Theme List in Preferences") routes to the host popup menu — there is no Winamp preferences dialog to
  open. The in-drawer list is the real route and it works.
- Its display reads at the right height as of Phase 38: 13 `valign="top"` texts on a bitmap-font
  sheet (`player.bitmapfont.display.*`) — song name, action info, time, playlist rows. That path was
  pinned to the box's top edge, so those were already right by accident and everything else on a
  sheet was half a box too high; both go through `valign` now.
- Its balance slider works as of Phase 37 (`PAN`), including the "Balance: Left +40%" readout its
  `onSetPosition` prints on the song ticker — that handler is now dispatched on a **drag**, not only
  on a script's `setPosition`. The skin stacks two sliders on the same rect (`player.slider.balance`
  and a ghosted `…balance.dummy` LED twin); both draw from the engine's balance, so they agree.
  Its song title's
  `dblclickaction="TRACKINFO"` / `rightclickaction="TRACKMENU"` and its titlebar mousetrap's
  `dblclickaction="SWITCH;shade"` were dead for the same engine-wide reason until Phase 36; all three
  work now. The mousetrap is `player.mousetrap`, 45,0 182×18 in `main/normal` — only 18px tall, which
  is worth knowing before concluding from a probe that it does not respond.

### Traps this skin sets

- **A "the skin does not ship X" verdict can be our own abort.** Phase 32 measured 58/**0**/3 and
  recorded "multipass ships no `<ColorThemes:List>` at all". The list was there the whole time, in a
  groupdef only a refused method instantiates. Check `RENDER_SCRIPTS` for a failed handler *before*
  concluding anything about what a skin contains — an object a script creates is in neither the
  document, the graph, nor the scene until the script that creates it runs.
- **The drawers are hover- and timer-driven, so a click probe measures a working control as dead.**
  `RENDER_SETTLE` is mandatory, and the coordinates move: the toggle sits at (53, 129) with the left
  drawer retracted and at (17, 137) once it has slid out, which is where it is by the time any settled
  run clicks.
- **This skin's seek bar is not a `<slider>`.** Looking for one finds nothing and the wrong
  conclusion follows. It is `<animatedlayer id="player.seek.progress">` + a `Map`, and it exercised
  three separate engine faults at once (animated-layer sizing, animated-layer hit region, and integer
  division in the VM). When a control is "not exposed", check what *kind* of object the skin built it
  from before concluding the skin does not have one.
- **The bottom drawer's page buttons are only in the graph while the drawer is open.** Drive the
  toggle first, then the page button, as two points in one `RENDER_CLICK` run.
