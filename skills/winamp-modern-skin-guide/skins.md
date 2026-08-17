# Per-skin status

What each measured `.wal` fixture actually does in NullPlayer today, and what is still missing **for
that skin**. The engine-wide surface is [compatibility.md](compatibility.md); this file is the
skin-by-skin view, because a `.wal` skin exercises an arbitrary slice of Wasabi and two skins can fail
in completely different ways while the compatibility report says the same thing about both.

Nothing third-party is committed — every skin here is user-supplied. See
[manual-qa-checklist.md](manual-qa-checklist.md) for how to run one.

**Keep this current.** When a phase closes on a skin, update its section: the phase it was fixed in,
what came alive, and what is knowingly left. A skin's own `screenshot.png`, when the archive ships one,
is the reference to compare against.

| Skin | Last worked | State | Biggest gap |
|---|---|---|---|
| Love is War Miku | Phase 23 | renders and drives correctly | `fliph`; oscilloscope is a mirrored spectrum |
| mmd3 | Phase 17 | text, knobs, drawers, own display all live | `wasabi.*`-backed widgets draw empty |
| cPro-Bento (+ ClassicPro engine) | Phase 24 | SUI body drawn and framed, live tabs, beat vis, playlist, embedded library | script-built menus (`popAtXY`), Guilist widgets |
| Winamp Modern (stock) | Phase 13 | frame, script-built body, playlist + library | — |
| CornerAmp Redux | Phase 13 | frame, titles, playlist + EQ | synthesized library window |
| T800 | Phase 20–22 | per-layout groups, region-clipped volume, drag | — |
| ZDL Reel-To-Reel | Phase 18 | sized from its background art | — |
| Rika | Phase 22 | loads without its missing TTF; vis colours honoured | — |

---

## cPro-Bento (`2222-cPro__Bento.wal` + ClassicPro 2.01)

**Fixture note:** the archive ships `screenshot.png` — 178×75, the author's own reference render.
Small, but it settles the questions that cost the most time here: the tab pills are **framed** and sit
*inset* inside the strip, the SUI sheet and playlist box have drawn borders, and the tab labels are the
long names at that window's width. The ClassicPro engine is user-supplied and imported separately
(`ClassicProEngineStore`); the skin is inert without it.

**Measured status** — `WINAMP_MODERN_RENDER_DUMP`, 2026-08-17 (Phase 24), engine ClassicPro 2.01:

```
arrangement=singleWindowSUI  catalog: playlist=embedded equalizer=embedded library=embedded
containers: main (player) · notifier · browserpro · widgets.manager
main/normal    500×500   158 nodes   min 446×201   declared 317×168   max 1920×1080
main/shade     500×23     24 nodes   min 317×23    declared 317×23    max 16384×23
notifier       128×80     13 nodes  (normal + desktopalpha layouts)
browserpro     200×200     4 nodes
compatibility  degraded — 46 findings, all warnings: 0 errors, 0 unsupported methods at startup
               resources 12 · groups 34
bitmaps        main/normal: 57 resolved, 3 unresolved
               (beatvis.overlay, custom.repeat., custom.shuffle. — declared, never shipped)
```

The 46 warnings are duplicate ids (the skin's own `custom-element-overide.xml` and `colors.xml`
deliberately override engine art, plus the engine overriding itself) and optional missing bitmaps
(`mainframe_lr/tb/title.png`, `vis_overlay.png`, `volume_ani.png`, `window/scrollgrips.png`, two
Reader icons). None is functional — Winamp tolerates all of them the same way.

**Shape of the skin:** single-window SUI — one `main` container, everything embedded, nothing
synthesized and nothing left to the classic fallback.

### Working

- **The framed surfaces** — `<grid>` nine-slice (Phase 24). The tab pills, the SUI sheet, the playlist
  box, the mini-view strip and the seek track are all grids; before this they drew *nothing* and read
  as flat black holes. 49 of them in this skin's include graph.
- **The tab strip is live** — clicking Media Library / Playlist / Video / Visualization / Browser
  activates the tab and switches the sheet, through the skin's own message chain: the tab button's
  script → `CproTabs` → `CentroSUI.onAction("show_tab")`. It re-lays itself out on resize and drops to
  short labels (`LIB`/`PLE`/…) when the sheet is narrower than 50px per tab, which is its own
  behaviour, not a defect. Phase 24; see the trap below about §15.6.
- **The beat visualization** in the middle of the display, centred on the window and surviving play /
  pause / resume, with its VU timer started and stopped by the transitions. Double-clicking it cycles
  the animations (and **re-centres** them — `beat.m` centres only inside `onResize`, and showing or
  hiding a group is a geometry change, so this depends on the settle); right-clicking it offers the
  animation list.
- **Closing and reopening the playlist column** from the side-view arrows. The close button collapses
  the pane and the skin swaps in its *open* button, which ships `visible="0"` — so this only works
  because `onResize` is dispatched when a script moves something, and because hidden objects are still
  laid out. Without either, closing the playlist was a one-way door.
- **The playlist column and its splitters** — both dividers drag (`centro.mainframe` vertical,
  `centro.plframe` horizontal), and the mini view opens and closes.
- Transport, volume, mute, the kbps/kHz/stereo readouts, the clock, the menu bar, the drawer, the
  embedded library browser, the embedded EQ, and the colour themes.

### Not implemented or knowingly wrong

- **`popAtXY` (6 call sites)** — a script-built menu positioned at a computed point, with
  `clientToScreenX`/`clientToScreenY` (7 each) behind it. So the tab strip's own right-click menu and
  the drawer's "goto" menu do not open. `popAtMouse` menus do.
- **Guilist-backed widgets** — `getItemLabel`, `getItemFocused`, `setSubItem`, `getAttributeName`: the
  skin lists (skin switcher, tag viewer fields) draw empty.
- **`XmlDoc` callback parsing** (`parser_addCallback`/`parser_start`/`parser_destroy`, 4–5 sites) —
  ClassicPro's optional `classicpro.xml` extras (custom beat-vis names, songticker antialiasing) are
  never read; every caller is behind `if (myDoc.exists())` and takes its skip path.
- **`enqueueFile` / `playTrack` / `clear`** — the playlist surface is NullPlayer's, driven by the app,
  not by the skin's script.
- The full unimplemented-method tally is in [compatibility.md](compatibility.md).

### Traps this skin sets

- **The top-right damage came from the *playlist* column, not the volume slider.** `centro.plframe`'s
  collapsed top pane (`centro.playlist.directory`, the closed mini view) is **correctly** 6px tall, but
  its children are anchored for the 27px strip it has when open, so they resolved 21px *above* it —
  over `Volume`, `mute` and the `fileinfo` readouts, with `comp.goto` left floating as a stray `▭≡` on
  the display. A `Wasabi:Frame` pane is a window and always clips; that is the whole fix (Phase 24.2).
  The escaped children still *have* frames at y=79 — check their **clip**, not their frame.
- **`WINAMP_MODERN_RENDER_XUI`'s `onscriptloaded=false` is not evidence a script did not run.** It
  reports per-object *bindings*, and it says `false` for every object in this skin including
  `layout id=normal`, whose scripts demonstrably run. TASKS §15.6 concluded the tab strip's script
  never initialized from exactly that reading; the real cause was `Group.init(parent)` being a no-op
  (see below). Use `WINAMP_MODERN_RENDER_SCRIPTS`, which observes execution.
- **`newGroup` is only half of Wasabi's two-step.** `newGroup(id)` creates a group, `init(parent)` puts
  it where the script wants it — and the new subtree's own scripts must start **after** the second, or
  they look around from the wrong parent. Both tab defects (dead clicks, pills 4px out of place) were
  this one gap.
- **`getWidth()` must answer the *resolved* width.** The tab strip is `w="-4" relatw="1"`; answered
  from the attribute it is −4, and `CproTabs.m` compares that against the space its tabs need and
  squeezes every one of them to its 20px floor. Nearly all of this skin's geometry is relative.
- **A colour resource may be declared as a `<bitmap file="$solid" color="…">`.** This skin declares
  `wasabi.list.background` as both a `<color>` and a `$solid` bitmap, and the bitmap wins the registry
  — so a lookup insisting on `kind == "color"` fell through to the literal parser and became **white**,
  painting a white slab across the tab strip of a near-black skin.
- **The promo art double-centres itself — corrected by the engine's one skin quirk.** `beat.m` shows
  either the beat visualization or a ClassicPro logo in the same slot, swapped by a double-click. The
  beat visualization is centred at every width; the logo was out by exactly its own offset *inside* its
  300-wide box, because the box is placed at `centre − artWidth/2` (already centring the picture) and
  the picture is then offset inside the box as well. Measured against the display centre
  `143 + (w−317)/2`:

  | canvas | centre | beat vis | promo (before) | promo (after) |
  |---|---|---|---|---|
  | 700 | 334.5 | 334 | 334 ✓ | 334 ✓ |
  | 560 | 264.5 | 264 | 314 ✗ | 264 ✓ |
  | 500 | 234.5 | 234 | 384.5 ✗ | 234.5 ✓ |

  `WasabiSkinQuirks.correctedFrame` shifts the box back by the picture's in-box offset. Exact at all
  three branches and a **no-op** at offset 0 — the branch that was already correct, and the evidence
  that our `resize()`/`getWidth()` semantics are right and the skin's arithmetic is what is off. Read
  that file before adding a second entry; the bar is deliberately high.

- **The beat visualization is only ever enabled inside `frameGroup.onResize`.** `beat.m` assigns
  `showBeat`/`showPromo` nowhere else, and `System.onPlay()` → `refreshView()` → `showGroup(0)` hides
  both display groups first. Without an `onResize` having fired, pressing play made the visualization
  disappear for good. Any new window/scene must seed a resize after `scripts.start()`.

---

## Love is War Miku (`Love is War Miku.wal`)

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

### Traps this skin sets

- **The song title belongs *above* the white seek bar.** The reference screenshot shows it there. The
  white strip is the seek bar, not a text field.
- **`<vis ghost="1">`** — the visualization box takes no clicks at all; the menu hangs off a separate
  invisible `<layer rectrgn="1">` (`visual.trigger`) whose rect is nowhere near the vis.
- **The volume buttons carry no `action`.** They do nothing on their own; the script's `leftClick()`
  is what moves the level, and its `onLeftClick` body is guarded so a *user* click alone does not
  double-apply.
