## Love is War Miku (`Love is War Miku.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

**Fixture note:** the archive ships `Love is War Miku/screenshot.png`, the author's own reference
render at the skin's exact canvas size (456×419). Every text metric in Phase 23 was measured against
it by pixel. Compare against it before concluding anything looks wrong.

**Shape of the skin:** separate-window arrangement. `main` (456×419) plus declared `Pledit`,
`MLibrary`, `video`, `avs`, `notifier` and `notifier.preferences` containers; the equalizer is
embedded (a second panel over the same box, swapped by `maineq.maki`). Compatibility level
**`degraded`** — the remaining findings are duplicate-id warnings in its own
`components-elements.xml`, nothing functional.

### Working

- **Opening animation.** `opening.maki` fades the panel and character in on a 300 ms timer and slides
  them to their final positions (`setTargetX/Y` + `gotoTarget`): display panel to `y=84`, character to
  `x=129`. The XML positions are only where the animation *starts* — a dump without
  `WINAMP_MODERN_RENDER_SETTLE` shows a window the user never sees.
- **Display text** — song ticker (scrolling, "Artist - Title") and the large time readout, in Arial
  Bold at the sizes the skin asked for, centred in their boxes, with fixed-pitch digit cells and the
  narrow colon cell (`forcefixed`, `timecolonwidth`). Phase 23.
- **Seek bar** — the `<ProgressGrid>` fill tracks playback. Its slider thumb is a **1×1 pixel**, so
  the fill is the only position indicator the skin draws. Dragging the slider seeks. Phase 23.
- **Volume** — the `+`/`−` arrows left of the display, driven entirely by
  `autorepeatvolumebuttons.maki`: click-and-hold repeats and accelerates, and the song ticker flashes
  `Volume: NN%` from `onVolumeChanged` and clears itself. Phase 23.
- **The skin's own right-click menu** on the strip left of the display: No Visualization, Spectrum
  Analyzer → Thick/Thin Bands, Oscilloscope → Solid/Dots/Lines, Show Peaks, Peak Falloff Speed,
  Analyzer Falloff Speed, Analyzer Coloring — with the current choice ticked, and each selection
  persisted through `setPrivateInt`. Phase 23.
- **Visualization** — comes up as the spectrum analyzer, which is the skin's own default
  (`getPrivateInt("Visualizer Mode", 1)`), with the skin's black band colours at `alpha="80"` over its
  artwork. `bandwidth`, `peaks`, `peakfalloff`, `falloff` and `coloring` all arrive from its script.
- **Transport, PL/EQ/ML/VD buttons, shuffle, repeat, minimize, close**, the EQ panel swap, and the
  `notifier` windows.
- **The visualization and video windows' toolbars** (Phase 39): `VIS_FS`/`_PREV`/`_NEXT`/`_MENU` at
  the bottom of the `avs` container and `VID_FS`/`VID_MISC` in the `video` one. The VIS arrows step
  the visualization window's presets when it is up and this skin's own `<vis>` mode otherwise; the
  video Options button opens the video window's own menu. Twelve of this skin's buttons; five of them
  were the whole toolbar of a window.

### Not implemented / knowingly wrong

- **`fliph` on `<vis>`** — a left-click on the same invisible trigger toggles it in the skin's script,
  and the renderer ignores the attribute, so the left-click has no visible effect.
- **The oscilloscope is a mirrored spectrum**, not real PCM: the host publishes band levels, so it is
  the shape of the signal rather than the waveform. Engine-wide, see `compatibility.md`.
- **`volbtn` ("Show Volume Bar") does nothing** — `action="TOGGLE"` with an empty `param`. It does
  nothing in Winamp either; not a defect.
- **Time readout is ~2px narrower than the reference** (48px against 50px for `1:12`). The fixed-pitch
  cell is the widest digit's advance; Winamp appears to add a little trailing cell padding. Cosmetic.
- **`stringToFloat` demand in `notifier-preferences-group.xml`** is implemented, but the notifier
  preferences window itself has never been driven in a GUI session.
- The `avs` container maps to the visualization component and shows a bounded neutral backing, not an
  AVS engine — there is no AVS.
- **`VID_1X` / `VID_2X` / `VID_TV`** are accepted and inert, each recording its reason once (Phase
  39): our video window has no native-size sizing to scale from, and there is no internet-TV source.

### Traps this skin sets

- **The song title belongs *above* the white seek bar.** The reference screenshot shows it there. The
  white strip is the seek bar, not a text field.
- **`<vis ghost="1">`** — the visualization box takes no clicks at all; the menu hangs off a separate
  invisible `<layer rectrgn="1">` (`visual.trigger`) whose rect is nowhere near the vis.
- **The volume buttons carry no `action`.** They do nothing on their own; the script's `leftClick()`
  is what moves the level, and its `onLeftClick` body is guarded so a *user* click alone does not
  double-apply.
