## cPro2 Dark Aluminum (`cpro2_dark_aluminum_final_by_victhor_d6necra.wal` + ClassicPro 2.01, engine **two**)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **Grade: C (provisional · confidence: medium)** — from a headless pass; nobody has driven this skin. Calls 3 unimplemented maki method(s) ×32 (`enumitem`, `enumobject`, `getnumobjects`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.

**Known outstanding:**

- 3 bitmap id(s) it references do not resolve, leaving a visible gap: `cpro2.eq.auto.overlay.0`, `cpro2.eq.on.overlay.0`, `cpro2.xfade.overlay.0`
- 1 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `s.button.mute.over.0`
- unimplemented MAKI: `enumitem` ×2, `enumobject` ×26, `getnumobjects` ×4
- 8 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 3 error-severity load finding(s)


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
main/normal        two.screen(0,28,800,70) · cpro.sui(8,98,784,494) — contiguous (B124, 2026-09-04)
containers: main (player) · notifier · browserpro · searchresults · widgets.manager
            main.aerosnap · main.tooltip · main.shadow
main/normal        800×600   147 nodes   min 240×106   declared 240×106   max 1920×1080
                             (min read 240×352 until B127, 2026-09-05)
main/shade         800×22     72 nodes   min 240×22    declared 240×22    max 16384×22
widgets.manager    321×400    36 nodes   min 321×400   declared 100×400
notifier           128×80     13 nodes  (normal + desktopalpha layouts)
searchresults      200×200     6 nodes  ·  browserpro 200×200 4 nodes
main.aerosnap      275×116     2 nodes  ·  main.tooltip 275×116 2 nodes
main.shadow        830×630     2 nodes  (declared by load-two_alpha.xml; shadow.m instantiates it,
                                        and B101 keeps it off screen)
bitmaps            main/normal: 80 resolved, 1 unresolved (beatvis.overlay)
                   main/shade:  42 resolved, 1 unresolved (s.button.mute.over.0)
compatibility      unsupported — 4 error findings, all one class: unimplemented MAKI methods
                   enumObject ×12 · getNumObjects ×2 · enumItem ×1 · onLeaveArea ×1
                   (onLeaveArea answered since B100, 2026-09-04)
VIS box            main/normal two.playback.visobject(14,74,71,17) mode=1 Spectrum Analyzer
                   main/shade  shade.vis(351,4,39,14)             mode=1
PLAYLIST holder    PlaylistPro.wdh(596,116,196,457) text=12.5px row=14px scale=auto(114%)
```

**`min` / `declared 240×106` are runtime values, not the XML's.** The XML says
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
- **The Now Playing selector** — the button over the album-art area, opening Album Art / File Info /
  Stored Playlists / Video / Visualization / the widgets. Fixed 2026-09-04 (B100); see the trap below.
- **The bolt multi-button** works, including its right-click command menu (Change Color Theme,
  Explore Folder, Open About Winamp, Show Quick Playlist, Show Send to Menu) — the menu records which
  command the *left* click will run, so drive two clicks to measure it (`WINAMP_MODERN_RENDER_CLICK_PICK`).
- **F9–F12 preset positions** — `two/scripts/presetpos.m` calls `getCurAppLeft/Top/Width/Height()`;
  all four now answer, in Winamp's screen space.

- **The Web Reader tab.** The reader loads its twenty search providers, fills the drop-down, and
  navigates its `<browser>` to the selected provider's URL for the playing track. Fixed 2026-09-05
  (B128); see the trap below.

- **The small player.** Dragged to its floor the window is titlebar + info band + transport and
  nothing else — the SUI collapses to zero height and its tabs go with it, as in the author's own
  render. Fixed 2026-09-05 (B127); see the trap below.

- **The seek bar and the volume bar light under the pointer**, in the same colour the play controls
  glow. Fixed 2026-09-05 (B129); see the trap below.

### Not implemented

- **`enumObject` / `getNumObjects`** (×14 combined) — `CentroSUI/_v2/InfoViewer` walks its own object
  list with them. Highest measured demand this skin has.
- **`enumItem`** — `xml/widgets-manager-cpro2.xml`.
- **Aero-snap is inert by design.** `snapAdjust` is accepted and returns `.null`. Snapping a window
  to a screen edge is a Windows shell behaviour with no macOS counterpart worth emulating.
- **The drop shadow is inert by design.** macOS draws its own window shadow.
- **Neither window is allowed on screen** (B101, 2026-09-04). Both containers are real and their
  scripts run; `setAuxiliaryWindow` refuses to show a container
  `WinampModernContainerTopology.isHostProvidedDesktopEffect` matches. Before that they opened —
  see the trap below.
- **`beatvis.overlay`** is unresolved, as on every cPro skin — the skin ships no such bitmap.

### Working (continued)

- **The built-in spectrum analyzer** draws its sixteen-step ramp. This skin keeps eight of those
  sixteen colours in swatch rows whose **alpha is 0** (`cpro2.color.read`, a 3x18 slice of
  `playback_area.png` at 282,62), so a `Map` that samples composited rather than stored pixels reads
  `0,0,0` for every other band — the analyzer came out with black scanlines through it. No
  `one`-family cPro skin has a transparent swatch row, so this half of the defect was cPro2's alone.
  See [reference/rendering/vis.md](../reference/rendering/vis.md).

### Traps this skin sets

- **A script calls the pointer's own handlers, and `openMini` is on the far side of one.**
  `CentroSUI2.m` uses `wasabiCover.onEnterArea()` / `onLeaveArea()` as its only way to raise and drop
  the album-art overlay, from five places. Neither had a dispatchable arity, and a missing *signature*
  fails closed **before** the trace, so `but_miniGoto.onLeftClick` stopped one statement after its two
  `isMouseOverRect` tests with no `UNSUPPORTED` line to say why. Album Art is command id `0`, so it
  dies on the `result <= 0` branch before `openMini`; File Info and Visualization die *inside*
  `openMini`, after it has hidden every pane. Fixed by B100 — and the shape generalises: when a trace
  stops with no failure line, look for a method with no signature, not a method with no implementation.
- **The two glue windows open the moment dynamic containers work.** `shadow.m` builds `main.shadow`
  from `mainLayout.onSetVisible(1)` and `layout.m` builds `main.aerosnap` from `normal.onMove()`, and
  both were dead only because `newDynamicContainer` could not make a window. B110 made one, and the
  skin came up with a **830×630** outline (the player plus `shadow.maki`'s `-15,-15,+30,+30`, unplaced
  in a screen corner) and a **950×1060** one (the LEFT SNAP rect, `viewportWidth/2 − 10` by
  `viewportHeight − 20`) beside it — each a bare rectangle of lines, because a nine-slice with no
  centre and a 4px border grid are all either window draws. The sizes are the identification: no
  probe names these windows, and the accessibility API's frame list does. Suppressed by B101.
- **The floor of the window is set by a search bar the skin would have hidden.** `min 240x352`
  against the `declared 240x106` two lines above it in the dump is the defect, and the two numbers
  sitting side by side is the check. The protective minimum resolves a *hypothetical* canvas without
  dispatching `onResize`, so ClassicPro's 19px playlist search bar
  (`xui/PlaylistPro/_v2/PlaylistPro.xml`, `visible="0"` and shown by its own script) was still
  standing at every size the probe tried; below a 19px pane it overhung its parent by **one pixel**,
  and that one pixel pinned the whole player three times taller than its author's floor — the small
  player stopped with the tab strip and the library still on screen. `PlaylistPro.m`'s own
  `frameGroup.onResize` opens `if (h < 102 || …) topbar.hide()`, so in the app it is never there.
  Fixed by letting a script-written `minimum_h` stand the probe down (B127); the general rule is in
  [reference/loading.md](../reference/loading.md) → *The protective window minimum*.
  `WINAMP_MODERN_RENDER_MINIMUM=1` names the culprit and prints its frame beside its parent's.

- **The Web Reader hides itself, and the reason is two faults deep.** `Reader/main.m`'s
  `myGroup.onSetVisible(1)` is `initLoadFiles(); if(continueLoad) surfSelected(); else { myGroup.hide(); }`
  — a reader that cannot read its provider list takes the whole tab down with it, so the symptom is
  *"the browser tab does not load the browser"* with nothing on screen to say why. Both faults were
  in shared engine surface, not in this skin:

  1. **`Application.GetApplicationPath()` answered a host path.** The file is addressed *only* as
     `getApplicationPath() + "\Plugins\ClassicPro\engine\xui\CentroSUI\_v2\Reader\source\_<lang>.xml"`,
     and `XmlDoc.load` resolves inside the WAL VFS, where the engine is mounted at
     `/Plugins/classicPro/engine` and a `/Applications/…` path can never exist. `exists()` came back
     false and `initLoadFiles` returned with `continueLoad` still false. Now the VFS root — see
     [compatibility/maki-surface.md](../compatibility/maki-surface.md).
  2. **Behind it, `Color.getRedWithGamma()` was unimplemented.** With the providers loaded,
     `surfSelected()` builds the URL through `convert_address.mi`, whose `%COLOR:LBG%` token calls
     `getColorHex()` — and that aborted one statement before `myBrowser.navigateUrl(…)`. The default
     provider (AlbumArtExchange) carries the token, so the tab still came up dead.

  Note `getLanguageId()` answers `en` here against Winamp's `en-us`, so the *first* load always
  misses; the script's own `_en-us.xml` fallback covers it, and `exists() -> 0` followed by
  `exists() -> 1` is the healthy trace, not the defect. The whole chain is readable headlessly with
  `WINAMP_MODERN_RENDER_EVENTS=onsetvisible WINAMP_MODERN_CALL_TRACE=1` — that driver reaches a group
  inside the player's own tab strip, which `RENDER_SHOW` cannot. The end of a working run is one
  line: `navigateurl(http://www.albumartexchange.com/covers.php?bgc=121826&q=…)`.

- **A theme carries two hover tints, and the two bars declare the muted one.** Reported as "the
  volume bar and progress bar are missing the glowing highlight the play controls have", and the last
  of *four* faults behind it — the other three are in
  [compatibility/maki-surface.md](../compatibility/maki-surface.md) (`getPosition()` on a host-bound
  slider, `onSetFinalPosition`) and
  [compatibility/wasabi-surface.md](../compatibility/wasabi-surface.md) (`hoverthumb`). This one is
  the skin's own colour data: `n.playback.button.hoverdown` is the glowing group — in
  `*Default (Purple)` a `gray="2"` desaturate plus a heavy blue bias, which is the saturated purple
  the buttons light up with — while `n.infoseek.seek.hover` and `n.playback.volume.active` are muted,
  and in most of the sixty gammasets the author leaves them a plain darkening with no tint at all.
  Both bars are themed through the buttons' group now (`WasabiSkinQuirks.gammaGroup`), so they answer
  the theme picker and match the controls beside them without inventing a colour.
  **The trap for the next reader is the measurement, not the fix:** every colour number taken on the
  default theme is void against a screenshot taken on another, and this skin ships **61** gammasets.
  `WINAMP_MODERN_RENDER_THEME=<name>` renders one; `RENDER_THEMES=1` lists them.
- **The seek bar's hover overlay is the one fade layer whose markup omits `alpha="0"`.**
  `two.info.seeker.hover.layer` rests *lit* while `play.fade`, `bolt.fade`, `mute.fade`,
  `two.playback.volslider.bar.2` and its own shade twin `shade.seeker.hover.layer` all rest hidden —
  so until the pointer first entered and left the bar, the elapsed portion sat in the hover artwork
  and hovering it did nothing, and the first mouse-leave then took it muted for the rest of the
  session. Seeded to 0 at load (`WasabiSkinQuirks.restingAlpha`), and seeded **onto the object**
  rather than supplied at paint time: `gotoTarget()` eases *from* whatever `alpha` says, so a value
  only the renderer knew about leaves the script animating 255 → 255 and the fade dead in both
  directions. That is the whole difference between the two attempts, and the check is one line —
  `CLICK changed group#two.info.seeker.hover.layer … alpha=0 -> alpha=255`.
- **The snap preview fires with the pointer nowhere near a screen edge.** `layout.m` tests
  `System.getMousePosX() < 1` — the *screen's* left edge in Winamp — and ours answers in the window's
  canvas space, so it is true whenever the pointer is left of the player. B123.

- **Nothing lays out until `System.onShowLayout` fires.** This was never dispatched anywhere in the
  codebase, and the failure is silent and total: `two.screen` keeps its declared `y=0`, so the title
  and transport draw **over** the titlebar and a 28px dead strip opens above the SUI — which is
  `cpro.sui`'s hard-coded `y="98"` (titlebar 28 + info 40 + playback 30) with nothing beneath it. The
  band is contiguous in the author's screenshot; that is the check.
- **The cold start is gated on `!shade.isVisible()`.** A container shows exactly one layout at a
  time, so `normal` and `shade` must never both report visible. Answering `isVisible` for the whole
  window made them both true and the branch never ran — a second, independent blocker behind the
  first.
- **And a *third*, which is why the symptom outlived both fixes: `_layout==shade` was true for the
  normal layout.** `layout.m` reads `if(shade == NULL) shade = player.getLayout("shade")`, and on a
  cold start that answers NULL correctly — but an object compared equal to NULL, so the handler took
  the `saveSkinPos()` branch and never reached the `fullScreen()` one. Reported 2026-09-04 with the
  author's reference render alongside; the engine-wide cause and its `!= NULL` mirror are B124, in
  [reference/scripting.md](../reference/scripting.md) → *An object is never equal to NULL*. **The
  three stacked**, so each correct fix in turn changed nothing on screen — the shape the skill's
  "look for the next fault before reverting it" rule exists for. `two.screen frame=(0,28,800,70)` and
  `declared=240x106` are the check; `y=0` and `240x200` are the defect.
- **Neither `onShowLayout` nor `onHideLayout` fires on a shade round trip**, so `saveSkinPos()` and
  the `normal.resize(cPro2.x, …)` restore never run when you shade the window and come back — the
  band survives, the saved geometry does not. Engine-wide cause and status in
  [reference/scripting.md](../reference/scripting.md) → *`System.onShowLayout` / `onHideLayout`*.
- **The album-art pane has come up dead twice, and a relaunch cleared it both times.** Reported
  2026-09-04 live: no local cover, no File Info, and the selector menu doing nothing — while
  *streaming* cover art arrived in the same session, so the pane and its holder are alive when it
  happens. **Not reproduced and not diagnosed**, and deliberately not filed as backlog work: it is a
  one-off until it reproduces. What would settle it is a
  `WINAMP_MODERN_CALL_TRACE=1 WINAMP_MODERN_TRACE_MAKI=1` capture of a launch that *fails* — both
  captures so far are of launches that worked, which is the wrong half. Cheap discriminator first:
  does the classic skin show that same track's local cover at that moment? Then two candidates, in
  order — `tagviewer.m`'s `loadFileInfo()` opens `if(!scriptGroup.isVisible()) return;`, so a group
  reading invisible while on screen kills File Info for *every* source; and
  `WinampModernHost.albumArtwork` drops any cover whose `NowPlayingManager.currentTrackId` does not
  match `engine.currentTrack?.id`, which a load-order race would do to local art alone. Not
  attributable to B124: this skin's cold-start script execution is byte-identical either side of it
  (identical 265-program `RENDER_SCRIPTS` report, identical node list, only `fullScreen()` in the
  call-trace diff).
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
