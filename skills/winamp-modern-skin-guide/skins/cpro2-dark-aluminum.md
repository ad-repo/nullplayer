## cPro2 Dark Aluminum (`cpro2_dark_aluminum_final_by_victhor_d6necra.wal` + ClassicPro 2.01, engine **two**)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

**This is the corpus's only engine-"two" skin**, and the reason it is worth its own file. Its
`ClassicPro.xml` declares `<ClassicPro version="2.01" engine="two">` and its `skin.xml` includes
`load-two_alpha.xml` — the shadow variant — which pulls an include graph **disjoint** from the `one`
family every other cPro skin uses: `two/xml/player{,-elements,-shade,-shade-elements}.xml`,
`xui/CentroSUI/_v2`, `PlaylistPro/_v2`, `widgets/Load/v2/*` and `two/xml/player-shadow.xml`. Nothing
measured against cPro-Bento transfers automatically. See
[reference/classicpro.md](../reference/classicpro.md) → *Engine "two"*.

**Fixture note:** the archive ships `screenshot.png` — 178×75, the author's own reference render, and
a **crop** of the info + transport band rather than the whole window (40 + 30 = 70 of its 75 rows).
Too small to adjudicate glyph-level questions, but it settles the two that cost the most time here:
the bands are contiguous under the titlebar, and there is a **clear gap** between the elapsed time and
the `/` separator. Extract it to a scratchpad; nothing third-party is committed.

The ClassicPro engine is user-supplied and imported separately (`ClassicProEngineStore`); the skin is
inert without it. `sha256 33d1c9f52cbaca9b63ae3aeed33174fe862519885683d5fc9ea5a235d2dde30c`, 885,580 bytes.

**Measured status** — `WINAMP_MODERN_RENDER_DUMP`, 2026-09-01, engine ClassicPro 2.01 (`one` + `two`):

```
arrangement=singleWindowSUI  catalog: playlist=embedded equalizer=embedded library=embedded
                             video=embedded visualization=classic (skin declares no vis surface)
containers: main (player) · notifier · browserpro · searchresults · widgets.manager
            main.aerosnap · main.tooltip · main.shadow
main/normal        800×600   147 nodes   min 240×115   declared 240×106   max 1920×1080
main/shade         800×22     72 nodes   min 240×22    declared 240×22    max 16384×22
widgets.manager    321×400    36 nodes   min 321×400   declared 100×400
notifier           128×80     13 nodes  (normal + desktopalpha layouts)
searchresults      200×200     6 nodes  ·  browserpro 200×200 4 nodes
main.aerosnap      275×116     2 nodes  ·  main.tooltip 275×116 2 nodes
main.shadow        830×630     2 nodes  (declared by load-two_alpha.xml; nothing instantiates it)
bitmaps            main/normal: 80 resolved, 1 unresolved (beatvis.overlay)
                   main/shade:  42 resolved, 1 unresolved (s.button.mute.over.0)
compatibility      unsupported — 4 error findings, all one class: unimplemented MAKI methods
                   enumObject ×12 · getNumObjects ×2 · enumItem ×1 · onLeaveArea ×1
VIS box            main/normal two.playback.visobject(14,74,71,17) mode=1 Spectrum Analyzer
                   main/shade  shade.vis(351,4,39,14)             mode=1
PLAYLIST holder    PlaylistPro.wdh(596,116,196,457) text=12.5px row=14px scale=auto(114%)
```

**`min 240×115` / `declared 240×106` are runtime values, not the XML's.** The XML says
`minimum_h="200"`; `layout.m`'s `fullScreen(false)` lowers it to `i_titlebar+i_info+i_playback+8` =
106 once it runs. A dump taken before that ran reads 200, and that difference is the quickest check
that the cold-start chain below is alive.

**Shape of the skin:** single-window SUI — one `main` container, everything embedded, nothing
synthesized and nothing left to the classic fallback. Six SUI tabs: Media Library, Playlist, Video,
Visualization, Web Reader, Now Playing.

### Working

- **The whole player lays out from `System.onShowLayout`.** Engine two places `two.screen` — the
  entire info + transport band — only from `layout.m`'s `fullScreen()`, whose sole cold-start caller
  is that event (the engine comments it *"On cold start"*, and the one line in `buildSkin()` that
  would otherwise set it is commented out). See the trap below.
- **The info panel *is* the seek control.** `two.info.seeker` spans the full band with the title,
  artist, time and bitrate drawn on top of it; the played portion is revealed by widening a `w="0"`
  group over a 550px lit layer. Clicking anywhere in the band seeks, and the fill follows playback.
- **The transport strip centres itself** and picks a normal/mini/micro band from the window width
  (`playback-layout.m`'s `g.onResize`, `g_buttons.x = w/2 − 112`), with the visualization box at the
  left and the volume slider at the right.
- **The SUI tab strip is live** — the six tabs switch the sheet, the embedded playlist fills, and the
  media library renders, as on every other cPro skin.
- **The bolt multi-button** works, including its right-click command menu (Change Color Theme,
  Explore Folder, Open About Winamp, Show Quick Playlist, Show Send to Menu) — the menu records which
  command the *left* click will run, so drive two clicks to measure it (`WINAMP_MODERN_RENDER_CLICK_PICK`).
- **F9–F12 preset positions** — `two/scripts/presetpos.m` calls `getCurAppLeft/Top/Width/Height()`;
  all four now answer, in Winamp's screen space.

### Not implemented

- **`enumObject` / `getNumObjects`** (×14 combined) — `CentroSUI/_v2/InfoViewer` walks its own object
  list with them. Highest measured demand this skin has.
- **`enumItem`** — `xml/widgets-manager-cpro2.xml`.
- **`onLeaveArea`** — `CentroSUI/_v2/CentroSUI.xml`.
- **Aero-snap is inert by design.** `snapAdjust` is accepted and returns `.null`; the
  `main.aerosnap` container is declared and drawn as a 2-node stub. Snapping a window to a screen
  edge is a Windows shell behaviour with no macOS counterpart worth emulating.
- **The drop shadow is inert by design.** `load-two_alpha.xml` declares `main.shadow` (830×630) and
  nothing instantiates it. macOS draws its own window shadow.
- **`beatvis.overlay`** is unresolved, as on every cPro skin — the skin ships no such bitmap.

### Working (continued)

- **The built-in spectrum analyzer** draws its sixteen-step ramp. This skin keeps eight of those
  sixteen colours in swatch rows whose **alpha is 0** (`cpro2.color.read`, a 3x18 slice of
  `playback_area.png` at 282,62), so a `Map` that samples composited rather than stored pixels reads
  `0,0,0` for every other band — the analyzer came out with black scanlines through it. No
  `one`-family cPro skin has a transparent swatch row, so this half of the defect was cPro2's alone.
  See [reference/rendering/vis.md](../reference/rendering/vis.md).

### Traps this skin sets

- **Nothing lays out until `System.onShowLayout` fires.** This was never dispatched anywhere in the
  codebase, and the failure is silent and total: `two.screen` keeps its declared `y=0`, so the title
  and transport draw **over** the titlebar and a 28px dead strip opens above the SUI — which is
  `cpro.sui`'s hard-coded `y="98"` (titlebar 28 + info 40 + playback 30) with nothing beneath it. The
  band is contiguous in the author's screenshot; that is the check.
- **The cold start is gated on `!shade.isVisible()`.** A container shows exactly one layout at a
  time, so `normal` and `shade` must never both report visible. Answering `isVisible` for the whole
  window made them both true and the branch never ran — a second, independent blocker behind the
  first.
- **`two.playback` declares no `h`, only `autoheightsource`.** A group that resolves 0 tall is not a
  resize target, so `playback-layout.maki`'s `g.onResize` never runs and the transport strip stays
  hard left at its declared `x=8` with the visualization sitting on top of it at the same x and no
  volume slider. The children still *draw*, because a group does not clip to its own box — so this
  reads as a layout bug rather than a missing group.
- **A `w="0"` group is a reveal window, not an empty one.** `two.info.seeker.active` and
  `.finder` each hold a 550px lit layer that must be clipped to the group's zero width. Falling back
  to the parent's clip painted both across the entire band, which reads as *"clicking the top area
  recolours the UI"* — the seam jumps to wherever the pointer went — and makes the bar unable to
  reflect the track position, because the width it is drawn from means nothing. `action="SEEK"` on
  the slider over it works throughout, so clicking still moves playback while the paint does not
  follow.
- **The seek fill is driven by `onPostedPosition` on `two.info.seeker.slider.0`**, not on anything
  called `HiddenSeek`. A clock that posts only to the stock skin's id leaves this bar frozen while
  dragging it still works — a drag is the user's own value change.
- **`display="4"` on the time readout is a right-margin number, not a display binding.** ClassicPro's
  `<TextSettings>` uses `display` as *"move the text this many pixels away from the right side"*, and
  the scripts read it back with `getXmlParam("display")`. It is not `display="time"`, so the readout
  does **not** take the clock-run path.
- **The `<Style>` blocks depend on attribute *document* order.** `read-classicpro.m` reads each style
  as two parallel lists and keys its apply loop on reaching `id` — everything written before `id` is
  skipped by construction. The skin writes `id` first. Handing the callback an alphabetised list put
  `id` at index 4 of 10 and silently dropped `display`, `fontsize`, `forcefixed` and `h` from every
  style in the file. See [reference/scripting.md](../reference/scripting.md).
- **`forcefixed` reserves a width; it does not monospace.** `info-text.m` places the total time at
  `trackTime.getTextWidth() − 4 + 21` — a deliberate 4px tuck into the elapsed time's reserved box —
  so the two boxes overlap by 4px whatever the measurement returns. Drawing each glyph centred in a
  widest-digit cell runs the final digit's ink to the box edge and lands the `/` on top of it for
  *every* value and *every* cell width. Only a proportionally drawn string inside a fixed reservation
  produces the author's gap. See [reference/rendering/text.md](../reference/rendering/text.md).
- **A saved window frame from before B93 is poison.** This skin graded *did not load* until
  2026-09-01, so every frame it ever persisted is the unskinned 275×116 default. Restore trusted it
  because it was saved under the same *skin name*, and restoring it is what the next save recorded —
  the player reopened in a 275×200 box on every launch, over the skin's own 800×600.
