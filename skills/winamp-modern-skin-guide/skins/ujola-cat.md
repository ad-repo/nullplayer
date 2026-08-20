## Ujola Cat (`Ujola Cat.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

By sambaneko. First measured in **Phase 34** (2026-08-20), from three user-reported defects: two dead
buttons in the console's right drawer, "the visualizer does not look correct", and the library and
playlist windows showing "layered full backgrounds in different colors" and "multiple top menubars".
All three are fixed; two of the fixes were engine-wide.

**Fixture note:** the archive ships `screenshot.png` — the author's own reference render. Compare
against it before concluding anything looks wrong.

**Shape of the skin:** separate-window arrangement, `main` 764×370. Declared `PLEdit` (430×200) and
`Video` containers plus the skin's own `ujolaCat` (192×222) and `colorthemes` (335×480) windows; the
equalizer is **embedded** (the left drawer) and the library window is **synthesized**. Compatibility
level `degraded` — the findings are duplicate-id warnings in its own `elements-system.xml`, nothing
functional. The player is a console with a drawer sliding out of each side: the left tab opens the EQ,
the right tab opens volume/balance and four window buttons.

### Working

- **Both drawers.** The tabs at the console's far left and far right slide their drawer out
  (`setTargetX` + `gotoTarget`, and the harness settles them, so a `RENDER_CLICK` on the tab moves the
  contents to their open coordinates before the next point is driven).
- **Left drawer (EQ)** — 10 bands + preamp, an EQ On / Auto pair, a presets menu, a live `eqvis`
  curve, and three quick-set buttons that slam all ten bands to max / flat / min
  (`scripts/equalizer.m`).
- **Right drawer** — volume and balance sliders; dragging either **hijacks the song ticker** to read
  `Volume: 72%` / `Balance: 30% Left` for 750 ms (`scripts/playerConsoleRight.m`) — plus the Color
  Themes, cat, playlist and library buttons. Both halves of that arrived in Phase 37: `PAN` drives
  the engine's balance, and a drag dispatches `onSetPosition`, which is the event the ticker takeover
  hangs off.
- **The Color Themes and cat buttons** (Phase 34). They carry no `action` at all: their entire
  behaviour is `getContainer("colorthemes").toggle()` / `getContainer("ujolaCat").toggle()`, and
  `Container.toggle()` was unimplemented, so a fail-closed dispatch abandoned the one-statement
  handler and the click did nothing. Both buttons also **light up** while their window is open, from
  that window's layout `onSetVisible` — which now also fires when the user closes the window from its
  own titlebar.
- **The cat window** — prev / play-pause / next / stop on the cat's face; the face art changes
  (`snooze` when paused, `joy` on the pause button).
- **19 colour themes**, one per Genshin region/character, each retinting 12 gamma groups
  (`xml/gammasets.xml`: 19 gammasets × 12 groups = 228). The skin ships a full picker — its
  `colorthemes` window carries a `<ColorThemes:List>` with all 19 rows and a working *Switch Color
  Theme* button.
- **The `<vis>` analyzer** (Phase 34) — 120×37, `gammagroup="Energy"`, all 22 colours declared inline.
  It now follows the colour themes (lime green under `:: Default`, red under *Liyue - Hu Tao*), draws
  Winamp's bands on a decibel scale, and paints its `colorbandpeak` caps.
- **The framed windows** (Phase 34) — playlist, video and the synthesized library no longer paint
  `window-regions.png`, the magenta-and-white silhouette five `sysregion="-2"` layers in
  `xml/standardframe.xml` carry. The green and orange title strips and the bottom transport bar are
  the real artwork and are unchanged.
- Double-clicking the song ticker is `trackinfo`; the scrubber seeks; shuffle / repeat / crossfade are
  the three round buttons under it.

### Not implemented / knowingly wrong

- **`<eqvis>` ignores `gammagroup`** — deliberately. `xml/player-console-left.xml` carries the
  author's own comment, *"note: eqvis doesn't support gammagroup; known bug"*, and works around it
  with white. That is Winamp's behaviour, so matching it is correct.
- **The window region is not applied**, only no longer painted: `.wal` windows are rectangular here,
  so the rounded/notched silhouette those mask layers describe is not cut out of the window.
- The oscilloscope mode is a mirrored spectrum rather than real PCM — engine-wide, see
  `compatibility.md`.

### Traps this skin sets

- **The far-left round button under the seek bar looks inert and is not.** `id="Shuffle"` works; its
  artwork is a bar-graph icon rather than crossing arrows, which is what makes it read as dead.
- **`sysregion` is a signed mode, and this skin uses both signs.** Its console art is
  `sysregion="1"` over real bitmaps (`bg.main`, `bg.console.face`, …) and **must** paint; only the
  negative ones are masks. Skipping by the attribute's presence rather than by its sign would strip
  the console.
- **The two drawer buttons are hit-testable while the drawer is closed but unreachable**: the console
  artwork is declared after the drawer groups, so it wins the reverse hit test. A probe must click the
  drawer tab first — `RENDER_CLICK` takes a `;`-separated point list for exactly this. Measured
  points, drawer closed then open: tab `554,236`; then `btnColorThemes` `602,265`, `btnCat` `664,206`.
- **`colorThemes.m`'s `onScriptLoaded` sets the console button to its `.active` artwork** before
  anything knows whether the window is open. The launch seed
  (`auxiliaryContainers.forEach { $0.view.setSceneVisible($0.window.isVisible) }`) is what corrects
  it; a probe that never opens a window sees both buttons stuck lit, which is expected there.
