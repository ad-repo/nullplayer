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
| cPro-Bento (+ ClassicPro engine) | Phase 24 | SUI body drawn and framed, live tabs, beat vis, playlist, embedded library, **script-built menus** | Guilist widgets |
| Winamp Modern (stock) | Phase 24 | frame, script-built body, playlist + library, **EQ drawer**, **centred title + streaks** | the 1px title overlay keeps its declared slot |
| CornerAmp Redux | Phase 13 | frame, titles, playlist + EQ | synthesized library window |
| T800 | Phase 20–22 | per-layout groups, region-clipped volume, drag | — |
| ZDL Reel-To-Reel | Phase 18 | sized from its background art | — |
| Rika | Phase 22 | loads without its missing TTF; vis colours honoured | — |
| Defix Hi-End 200 | Phase 26 | wood panel + framed windows, cassette display, **live SUI tabs + embedded library**, clipped reels | its `<Browser>` explorer; layer FX; `newDynamicContainer` |

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
- **The script-built menus placed at a computed point** (`popAtXY`, 6 call sites, with
  `clientToScreenX/Y` behind it). Right-clicking a tab opens its `Show Status Bar` / `Auto Close Tab`
  menu under the tab — measured with `RENDER_CLICK`, which prints the point the menu is placed at
  (`CLICK menu at 10,130` for the first tab, whose own frame is `(10, 104, 35, 29)`). Phase 24.

### Not implemented or knowingly wrong

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

## Winamp Modern (`winampmodern566.wal`) — the stock 5.x skin

**Shape of the skin:** separate windows — `main` (354×280) plus declared `Pledit`, `MLibrary`,
`Video`, `AVS`, `winamp.albumart` and `notifier` containers. The main window is **hollow XML**: the
whole client area is built at runtime by `standardframe.maki` from its `content=` XUI param.

### Working

- The frame, the script-built body, the playlist and library windows (Phase 13).
- **The config drawer** — the `CONFIG` button at the bottom right slides it open, revealing the
  equalizer (preamp + 10 bands with the dB scale, ON / AUTO / PRESETS), the crossfade controls, and the
  EQ / Options / Color Themes tab strip. Phase 24; it had never opened in any version.
- **The titlebar** — title centred on the window with a decorative streak flanking it either side, at
  every width. Phase 24, and the last of this skin's error-severity findings: the skin now loads at
  `degraded`, not `unsupported`.

### The titlebar streaks: laid out by the script, not by the markup

Worth knowing because it looked for two phases like a *rendering* problem. `titlebar.maki` lays out
all three pieces in one routine — called from `onResize`, `onTextChanged` and `onSetXuiParam` — and
every position is derived from the centred title:

```
titleX  = layout.clientToScreenX((layoutW − title.getAutoWidth()) / 2)   // → window-client space
titleX  = titlebargroup.screenToClientX(titleX) − titlebargroup.getLeft() // → group-local
title.x = titleX                       streakLeft.x  = padTitleLeft
streakLeft.w  = titleX − padTitleLeft  streakRight.x = titleX + titleW + 1
streakRight.w = −(titleX + titleW + padTitleRight + 2), relatw="1"
```

The markup's `x="0" w="95"` / `x="155" relatw="1"` values are only what the streaks wear until that
routine first runs. Two things had to be true before it could:

- **`clientToScreenX`/`screenToClientX` must exist** — they abort the handler otherwise — **and must
  convert relative to the receiver's parent**. Here both objects hang off the layout, so the round trip
  returns the input and the script's own `− getLeft()` is the group correction. See
  `compatibility.md`; the reading is pinned by ClassicPro's call sites, not by this one.
- **`instanceid` must name the instance.** Both streaks are instantiations of one `wasabi.titlebar.streak`
  groupdef and are told apart *only* by `instanceid`. While that was ignored, the script's
  `findObject("wasabi.titlebar.streak.left")` returned null for both, so the streaks kept their declared
  slot while the title centred itself — landing underneath them, reading "WI…". That was the whole of
  the symptom this skin was documented with, and it was never about the streak *geometry*.

Measured after the fix: at 354px the left streak is 20–152, the title 152–202, the right streak
203–309; at 500px they follow the title to 20–225 / 225–275 / 276–455.

### Not implemented or knowingly wrong

- The 1px `window.titlebar.title.overlay` layer keeps its declared slot instead of being stretched over
  the title. The script resolves it with `title.findObject("window.titlebar.title.overlay")` — a lookup
  *inside* the title object it just resolved, which finds nothing. Matching Winamp here would mean
  inventing lookup semantics for a 1px decorative sliver; measured and left alone.
- Its EQ drawer's crossfade and EQ buttons shift 14px once `onResize` runs — the layout its own script
  computes, and invisible until the drawer is opened.

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

---

## Defix Hi-End 200 (`Defix Hi-END 200.WAL`)

**Fixture note:** the archive ships `screenshot.png`, but it is a 275×116 skin-browser thumbnail of the
whole three-window arrangement, not a reference render — good enough to settle *what the skin looks
like* (wood-panelled player flanked by two speaker cabinets), not to measure against.

**Shape of the skin:** separate windows — `main` (406×355) plus `pledit`, `SUI` (its media
library/browser/visualization window, 800×600), two `SPEAKER` cabinets, `Config` (an About page),
`browserpro`, `searchresults` and `notifier`. The equalizer is synthesized. Almost everything the skin
draws is script-driven: a global `<scripts>` block in `skin.xml` (`CORE_SCRIPT.maki`, 47 KB) plus a
55 KB main-layout script.

**Measured status** — `WINAMP_MODERN_RENDER_DUMP`, 2026-08-17 (Phase 25): `degraded`, **0 errors and
0 unsupported methods at startup**; the remaining findings are duplicate ids and optional missing
bitmaps. `main/normal` 406×355, 69 nodes.

### Working

- **The wood panel and the framed windows** — see the trap below; this is the skin's whole look.
- **The SUI body** — the tab strip switches between Media Library, Visualization and Explorer, and
  the Media Library tab hosts NullPlayer's embedded library through the holder it declares. This was
  read as a "guilist gap" for two phases on the strength of a blank dump; the body is a
  `<windowholder>` on the media-library GUID, and the render harness cannot draw AppKit content, so
  the dump is blank for a surface that works. Three separate defects kept the strip inert — see the
  traps below.
- **The display** — the audio-cassette visualizer (its shipped default, one of nine styles), the song
  ticker on the cassette label, the time readout, and the Shuffle / Repeat / Kbps / Extension
  readouts, one variant at a time.
- **The SUI tab strip** — Media Library / Visualization / Explorer, each sized to its own label.
- Transport, seek and volume with their scales, the playlist window with its own titlebar buttons,
  both speaker cabinets, the About page.

### Not implemented or knowingly wrong

- **Its songticker never scrolls, and no UI here can change that.** The skin registers
  `Disable`/`Modern`/`Classic Songticker Scrolling` with `newAttribute` for **Winamp's** preferences
  dialog — they appear nowhere in its own Skin Settings window — and ships `Disable = 1`, which its
  `onDataChanged` applies as `ticker="off"`. The engine handles all three values; there is simply no
  way to reach the setting. Do not "fix" the ticker code for this.
- **Its `<Browser>` explorer tab** — the Explorer tab's content is a `<Browser>` control (Winamp
  embeds Internet Explorer and points it at a file path). The tab switches and its chrome draws; the
  browser pane itself is empty, and hosting a real web view for untrusted skin content is outside the
  sandbox this engine is built on.
- **Layer FX** — the analog VU meter styles configure a per-pixel warp we accept and ignore, so those
  display styles draw undistorted artwork.
- **`newDynamicContainer` returns the existing container**, so the skin's detachable visualizer and
  second mini-browser share one window rather than opening a copy.

### Traps this skin sets

- **It names its background art from a preference it never seeds.** `getPrivateString(getSkinName(),
  "BG", "")` is `""` on a profile that has not opened the skin's configurator, and every background id
  is built by prefixing it — so the layout is asked for background `""` and the nine frame slices for
  `"" + "_background_material.Element.top.left"`. Winamp keeps the artwork a failed load did not
  replace; taking the writes literally left the player, both speakers, the playlist and the library as
  flat black boxes. That is the rule in `setXmlParam` now: an image-valued param only changes when the
  new id resolves.
- **It shows one readout at a time by moving alphas, not by hiding.** Kbps, KHz and Channels share one
  slot at `alpha="0"`/`145`, as do Extension and Broadcasting. Text that ignored `alpha` printed all of
  them on top of each other.
- **Its global script assumes the skin is already configured.** `CORE_SCRIPT`'s `onScriptLoaded` lays
  out the SUI tab strip as `label.getAutoWidth() + 20` per tab — run before the tab labels arrive as
  XUI params, every tab came out at that bare 20px, stacked at the left edge. A skin-level `<scripts>`
  block loads *after* the objects and their params, which is why `start()` orders it last.
- **`@HAVE_LIBRARY@` is a script param, not a path variable.** The core script reads
  `stringToInteger(getParam())` as "is there a media library?" and drops the Media Library tab when the
  answer is 0 — which the literal string is.
- **Its four round buttons are `rectrgn="1"` outline icons, and two of them were dead.** The hit test
  alpha-tested the artwork even for a declared rect region, so a click through a gap in the icon fell
  onto the `ButtonBG` panel behind. `ConfBT1`/`ConfBT4` never responded; `ConfBT2`/`ConfBT3` did,
  because their artwork is denser under the same point.
- **Those four buttons are user-configurable, and none of them is hard-wired.** Each reads its own
  `getPrivateString(getSkinName(), "MainBtnN", …)` and dispatches on the result — `"PL"` calls
  `PLSBt.leftClick()`, `"EQ"` calls `EQSwitch.leftClick()`, `"ML"`/`"Video"` send `opentab` to
  `sui.content`. `PLSBt` and `EQSwitch` are 0×0 image-less proxy buttons that exist only to carry an
  `action`/`param` pair, so `leftClick()` must run the target's *action*, not just dispatch its
  `onLeftClick`. The XML defaults are PL / EQ / ML / Video, but the script rewrites the images, so what
  a button does is not what its markup says.
- **`findObject` is the *wide* lookup.** The core script holds `sui.content` and asks it for
  `switch.ml` — a tab button in `grid.s2`, a **sibling** subtree. Answered from descendants alone all
  five tab lookups returned null, so the script bound its click handlers to nothing. `findObject`
  searches the receiver's subtree first and then the rest of the container; `getObject` stays narrow.
- **`embed_xui` says which object *is* the XUI.** `bento.tabbutton` embeds its `mousetrap` button and
  the core script hooks `onLeftClick` on the **group** (`switch.ml`), so the child's pointer events
  have to be carried up to the embedding group or the tab lights up and nothing else happens.
- **The tab switch is gated on a timer**: `if (anim.isRunning()) return; anim.start();`. The app has a
  run loop and the timer stops itself; the render harness does not, so without pumping the run loop
  between driven clicks only the *first* tab click ever appears to work. That is a harness artifact —
  do not chase it in the engine (`RENDER_CLICK` now pumps when `RENDER_SETTLE` is set).
- **A group is a window and clips.** The cassette display is a 263×79 group holding a 117×117 reel
  bitmap; unclipped, both reels spilled 53px below the cassette and painted over the song ticker,
  leaving the title readable only in the gaps between them.
- **One refused method costs the whole window.** Every early defect here was a handler aborting
  partway: `getExtension` took the main layout's display with it, `fx_setGridSize` the VU meter,
  `newDynamicContainer` → `setFontSize` → `navigateUrl` → `hasVideoSupport` the global script, each
  surfacing only once the one before it was implemented.
