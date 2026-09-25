# `.wmz` rendering: the static scene, images, and the skin's own controls

Moved verbatim from `SKILL.md` on 2026-09-24. Before an engine-wide change here, check the
counter-evidence table in `reference/skins/README.md`.

## Static scene and image contracts

- **A `<VIDEO>`'s `backgroundColor` is a surface inside the window, never part of its shape
  (W312).** The fill carries `WMPPaintCommand.confinedToPaint`, and `WMPRenderer` clips it to the
  alpha already drawn beneath it — this layer and, in the overlay, the layer below. `Navigator`'s
  `#404040` well over bare canvas under the wing is gone; `The Unit`'s, `The_Sentinel_v.1.0`'s and
  `circle`'s black wells over their own artwork are byte-identical. Suppressing the fill while
  `hasVideo` is false would have lost those three.
- **What WMP does with a `backgroundImage` whose frame is not its bitmap is unsettled — decide it
  before extending W122's natural-size rule to backgrounds.** `Ice` authors
  `<button image="Pl-xp.bmp" width="196" height="144">` over a bitmap that is really 196x**44**,
  inside `<subview id="Drawerbutton2" backgroundimage="Pl-xp.bmp" width="313" height="144">`. After
  W122 a headless dump showed a seam in the lower shell (W123); **checked live 2026-09-25 there is
  none** and the row is closed as not reproducing. The open question is the rule, not a defect:
  `Ice`'s own frame tiles all author `backgroundtiled="true"`, which suggests WMP does not stretch
  and a skin tiles deliberately — but `Vidcolorbox` is
  `horizontalAlignment="stretch" verticalAlignment="stretch"` with an untiled `Vid-bg.bmp`, and
  `LostPlanet`'s stretch tiles are 61 px of window frame that would punch through. Check
  `reference/skins/README.md`'s counter-evidence table first, and measure the class — every
  `backgroundImage` whose frame is not its bitmap — before changing the rule.

- **A `.wmz` is 1x artwork and this app draws it on a 2x display, so the upscale is done by Lanczos
  ahead of the draw — never by CoreGraphics' own filter.** This is the one rendering rule that is
  about *resolution* rather than geometry, and it is settled:
  `WMPBitmapInterpolationPolicy.decision` says whether a draw qualifies, and
  `WMPImageStore.upscaledImage` does the resample once and caches it in the same LRU as every
  decoded image. **`.low` and `.high` are byte-identical on the draw path** — measured on
  `Plus! Hard Boiled/Egg_Body_Normal.jpg` at 2x — so the interpolation *quality* is not a lever and
  changing it is a no-op; the only choices CoreGraphics offers are bilinear, which blurs, and
  `.none`, which blocks. A reporter rejected both in turn (W160).

  Three conditions must all hold before a bitmap is resampled, and each one exists because the
  version without it moved artwork nothing was wrong with:

  1. the skin draws the bitmap at its **authored size** — a stretched gradient is asking to be
     interpolated, and resampling it as artwork changes a picture nobody complained about;
  2. the device scale is a **whole multiple**;
  3. the destination lands **on the pixel grid** — a fractional origin has no whole-pixel
     destination, and snapping it is a shift, not a sharpening.

  Everything else keeps `.low`, which is what the engine has always passed. **A corpus render sweep
  cannot see any of this**: `WMPRenderer.dump` renders at 1x, where the device scale is 1 and no
  draw qualifies, so a clean sweep here proves only that nothing *else* moved. The measurement is a
  `screencapture` of the live window on a Retina display — see `reference/skins/plus-family.md`
  § *W160*.

  **The crop happens before the scale, never after.** Lanczos reads a ~3px neighbourhood, so
  resampling a filmstrip whole would bleed each sprite into the one beside it; `sourceRect` is part
  of the cache key for that reason. **Alpha is never sharpened** — the sharpen unpacks to planes and
  skips it — or a keyed silhouette grows a ringing halo.

- **A `<VIEW>` anchors background artwork that is not its declared size; it never stretches to fill
  (W164).** The image is the window's picture, and where the two disagree the author meant the
  surplus to be empty — `transparencyColor` keys it out and the window simply is not there.
  `Colorchooser` declares `width="300" height="200"` over a 246x202 bitmap, and stretched by 1.22 its
  drawn box landed at x=87…299 while the opaque panel that belongs inside it stayed at the authored
  77…241. **Scoped to a mismatch the markup states, not one a resize produced**: where the authored
  size and the artwork agree, a canvas the user or a script grew still stretches the background as
  before. 17 corpus views declare a literal size alongside a resolvable background image and exactly
  4 disagree — `Colorchooser`, `Cubist`, `Radio`, `Tomb Raider 2`, each of which authors a band or a
  plate rather than a full-window picture. `Ice` is what this deliberately does **not** settle: a
  `<BUTTON>` sized against a background image is the natural-size rule (W122), not the root's art.

- **`hueShift` rotates a node's artwork, and it is the property a skin is named after (W173).**
  One archive in 180 uses it and all ten uses are script writes: `Plus! HueShifter`'s paintbrush is
  `changeHue()`, which steps a JS global by `360.0 / 11` and assigns it to the five "candy" pieces
  ringing the player — `topCandy`, `botCandy`, `leftCandy`, `rightCandy`, `botCandyFacade` — so the
  ring cycles through the spectrum. Unimplemented, every write was inert and the candies were frozen
  at their native green, reported as *"is it supposed to be green or not because it still is"*. The
  green **is** the artwork — the skin ships a 600x600 self-portrait, `hueshifter_final.jpg`, and the
  bottom clamshell is green in it at the coordinates the markup puts `botCandy` — and the defect was
  that it could never be anything else.

  **The unit is degrees, and the skin is the authority.** `changeHue()` offers ten stops at 33°,
  65°, 98° … 327° and `savePrefs` clamps to `0…360`. Read as -1…1 every one of them would clamp to
  the same value and the button would do nothing visible, which is not what Microsoft shipped.
  `WMPImageStore.canonicalHueShift` wraps; 0 and 360 are both no shift and take the untouched decode.

  **Use the standard `hue-rotate` matrix, not the NTSC YIQ constants.** The YIQ form rotates the
  *other* way — 120° takes red to blue, `(24, 42, 255)`, where every other implementation gives
  `(0, 113, 0)` — and its blue row carries coefficients of 1.25 and -1.05, which drive a saturated
  pixel far out of gamut and then clamp it, costing the luminance the rotation exists to keep. The
  SVG/CSS matrix turns the chroma about the luma axis: measured at all ten of the skin's stops on
  in-gamut colours the worst luma drift is **0.45 of 255**, which is rounding, and a grey does not
  move at any angle — which is what keeps the candies' black wedges and white specular highlight.
  A fully saturated pixel always clips and always will; that is inherent to the operation.

  **The rotation is folded into the decode, not applied at the draw**, and the angle is part of the
  cache key — so the crop, the Lanczos upscale (W160) and every mask see the colour the skin asked
  for, and five elements at five angles are five entries rather than one shared bitmap. `hueshift`
  is in `standardNumericProperties` because it is *rendered*: stored inert it would never reach the
  scene, which is exactly what the defect was. **A corpus sweep proves nothing here** — the property
  defaults to 0, so 179 archives are byte-identical and the one that moves does so only after a
  handler runs. Drive the button with `WMP_RENDER_CLICK` and read the `changed=` line.

- **A colour has three sources and the markup is only one of them (W165).** `mirroredColor` resolves
  them in WMP's order: the value a handler assigned, then the authored attribute, then one hop
  through `wmpprop:<element>.<property>` — the named element's own override first, then its markup.
  One hop, like `mirroredVisibility`, because a mirror of a mirror is authored nowhere in the corpus.
  `Colorchooser` is the **only archive that binds a colour with `wmpprop:`** and needs all three at
  once; reading markup alone drew its caption white on a white panel, painted no fill behind its
  transport, and left its three RGB sliders with nothing to change. **A write the colour parser
  cannot read is no answer, not black** — `theme.loadPreference` answers WMP's `--` sentinel for an
  unsaved key and skins assign it without checking, so an unparseable override leaves the authored
  colour standing. The reach beyond that skin is the mechanism's, not a heuristic's: 8 further corpus
  images moved, every one a colour the skin's own script had always assigned and nothing painted.

- **At a `zIndex` tie a `<SUBVIEW>` paints above its non-subview siblings, whichever comes first
  in the markup** (`WMPSceneBuilder.paintOrder`, 2026-09-24). Otherwise ties go by document order.
  `Plus! HueShifter` authors its equaliser drawer as the band subview *then* the tray's opaque
  `<buttonGroup>`, both `zIndex="2"`; `Plus! SlimLine` authors the same drawer the other way round.
  Both skins' shipped screenshots show the bands over the tray, and a subview-wins-ties rule is the
  only simple one that fits both. Under plain document order HueShifter's eight bands drew no
  thumbs and every press landed on the tray — reported as "the EQ in plus hue shifter is non
  functional". **Reach**: across the 179-archive corpus, 14 subview/sibling ties overlap
  (a statically resolved frame, subview first). Apart from HueShifter they are hosted widgets
  (`<video>`, `<playlist>`, `<effects>`, which sit above the scene anyway), `TDK`/`portals`'
  `content_image` (hidden until the script pages to it) and `Tomb Raider 2`'s background-less EQ
  subview. An A/B render of all 11 reachable skins was byte-identical except HueShifter with its
  drawer authored open. The rule does **not** put subviews above *higher*-`zIndex` siblings: 235
  overlapping pairs across 29 archives author a button or text over a subview at a higher
  `zIndex`, and they are meant to be seen. `WMPEqualizerSliderDragTests.testASubviewWinsAZIndexTieWithItsSiblingsInEitherOrder`
  pins both drawer orders.

- **A script owns paint order as much as the markup does (W166).** `zIndex` is an ordinary writable
  property and seven archives animate it — 58 assignments across `Beck`, `Cablemusic`,
  `Charlies_Angels_Full_Throttle`, `Colorchooser`, `Plus! Professional`, `Spider-man` and
  `cyberchannel`. Reading only the markup left every one of those swaps drawing in its authored
  order, and on `Colorchooser` it reached the window itself: `checkForContent()` raises
  `viz.zIndex` from -5 to 5 to bring the visualizer forward, and with the node still sorted at -5
  the opaque panel the player sits on counted as artwork *above* a **windowed** surface and was
  punched out by `windowedEffectsRects` (W144). Below it the view's own artwork keys white to
  transparent, so the result was a click-through hole through a borderless `isOpaque = false` window
  for as long as a track played. **W144's rule is unchanged** — what belongs in a windowed rect is
  still whatever the skin painted before the effects node — and so is `cerulean`'s: the number is
  still sorted **among a node's own siblings**, never flat across the view. Only where it comes from
  moved. **No headless probe and no corpus sweep can see this class**: the sweep runs a stopped
  player, which is the one state in which the skin is correct, and `WMP_RENDER_HOST=playing` seeds
  the snapshot without raising the `playstatechange` the write lives in.

- **A `<VIEW>` that declares both `clippingColor` and `transparencyColor` has said two different
  things, and an `<EFFECTS>` rect over the second one is not a hole (W174).** The clipping colour is
  the matte outside the window's silhouette; the transparency colour is a hole *inside* it, and what
  a hole inside the window shows is the control behind it. Both were keyed straight out of the
  artwork, so `Ovoid`'s screen — 11,400 magenta pixels in the middle of a 153x200 oval whose 6,468
  red ones are its corners — was a hole through a borderless `isOpaque = false` window: *"missing its
  backing in the center, it click through to the desktop"*. Behind it is
  `<EFFECTS zIndex="-1" left="24" top="29" width="105" height="142">`, and **an `<EFFECTS>` that
  authors no backdrop of its own still has one, and in WMP it is black** — two corpus rects restate
  it as `backgroundColor="#000000"` and none names another colour. `WMPEffectsGround` is the rule.

  **The ground goes under everything in the below layer, never over it**, so a skin that paints its
  own backdrop behind the rect covers it completely and W9 is intact: 78 of the corpus's 95 effects
  rects are already fully backed and render byte-identically. **The shape it is clipped to comes
  from `clippingColor` alone** — the nearest *ancestor*'s background artwork with that colour keyed
  out, at the container's own size (the `Gorillaz` guard). This is the one place the W172 widening to
  `transparencyColor` must not reach: a container that shapes itself with the transparency key alone
  has not distinguished the outside from a hole, and `Plus! BubbleSkin` would take 44% of its rect
  black outside the silhouette. **`circle` holds down the other half — the ancestor.** Its `vMain`
  declares the `<EFFECTS>` and the vis field that keys a hole in it as *siblings*, so no shape is in
  scope and the rect takes no ground; and that is the right answer, because `visfield.bmp`'s 1,122
  magenta pixels are a one-pixel antialias fringe between the grey field and the red matte rather
  than a screen. Relaxing either half draws a black halo round that skin.

  **A parent that paints its own `backgroundColor` over keyed artwork and hangs the rect behind it
  is the third permission, and the ground is then the rect itself.** `bluegrid`'s view is
  `backgroundImage="background.bmp" backgroundColor="#000000" transparencyColor="#FF00FF"` with no
  `clippingColor`; its 19,200 magenta pixels are exactly the 160x120 screen its
  `<effects zIndex="-1">` sits in, so the screen was see-through and click-through — reported
  2026-09-24 as *"visualizer has empty background and can be clicked through"*. `Plus! BubbleSkin`
  still refuses it: it authors no `backgroundColor` anywhere. The gate is
  `behindFilledArtworkStack` — the rect's *direct* parent, and only for a negative-`zIndex` child.
  Markup scan over the 180 readable `.wms` files: 7 nodes in 6 archives match (`aoe`, `bluegrid`,
  `cerulean`, `claw`, `gadget`, `pharaoh` ×2), and every one but `bluegrid` already had a
  `clippingColor` shape (`WIDGET … shape=` in the probe), so `bluegrid` is the only render that moves.
  Accepted live 2026-09-24. `WMPEffectsGroundTests.testAFilledContainerGroundsTheRectBehindItsKeyedHole`
  pins it.

  **This class a corpus sweep can arbitrate, and the ground is drawn in the flat dump for that
  reason** — it is the *skin's* backdrop, not the hosted surface. Sweep over 184 archives: **5 images
  move and every changed pixel is a former hole becoming opaque black** — `rad` 27,090 px, `Ovoid`
  11,400, `Goo` 2,993 (through its `bigGoo` subview), `digitaldj/DigitalDJMini` 1,973, and
  `cerulean` 20 isolated pinholes along its vis hole's antialiased curve. Nothing already painted
  moved. **The reach is measured by rendering, not by the markup**: dump the corpus, then count the
  fully transparent pixels inside each `WIDGET … effects` frame — that is the whole population, and
  it is 17 rects of 95 before the clipping-colour gate takes it to 5.

- **A one-shot GIF that ends on a degenerate `restore to background` frame ends showing nothing,
  and holding its last frame buries whatever it was drawn over (W161).** A `.wmz` opens its shutter
  by assigning an animated GIF to a `<SUBVIEW>` over the player's face and never hides that subview
  again — the *closed* state is held by a separate static child the same handler toggles, which only
  makes sense if the animation leaves nothing behind. On `Windows_XP_Media_Center_Edition` the held
  frame is an opaque blue plate, so the metadata, `STATUS:`, elapsed readout, seek slider **and the
  equaliser panel the skin opens in the same rectangle** were all drawn and then covered — reported
  as *"the eq does not work"*. `WMPGIFTerminator` is the rule and only `WMPRenderer` consults it, so
  hit testing and coverage still read the sprite.

  **Disposal alone is not the test, and reading it that way erases artwork.** 379 corpus GIFs are
  one-shot with a full-size disposal-2 final frame, `ALXMorph`'s six-frame idle logo among them. The
  **degenerate final block** — 1x1, disposing to background, on a canvas larger than that — is what
  separates them: **79 files across 33 archives**. `Age_of_Mythology` settles the shape inside one
  skin: `open_shutter.gif` carries the terminator and `close_shutter.gif` does not, ending instead on
  a full-size 80%-opaque closed shutter that has to persist. `Halo 2` says the same thing the other
  way — its `m_shutter_open.gif` ends on a full-size frame that is *entirely the key colour*, so it
  was already invisible and this rule changes nothing there. **A corpus render sweep cannot see any
  of this**: it draws at clock 0, before any animation has finished, so a clean sweep here proves
  only that nothing else moved — the measurement is the live window.

- **A GIF with no global colour table has no canvas outside its frames (W201).** `pharaoh`'s
  `pyrevolver.gif` is a 140x128 logical screen whose 16 frames are 21x16 blocks at 0,0. With no
  global colour table the rest of the screen is undefined, ImageIO decodes it as opaque black, and
  the 21x16 `<BUTTON>` drew the whole canvas stretched into itself: a black box. Such a GIF is
  decoded as the rectangle at the origin that holds all its frames (`WMPGIFCanvas`, applied in
  `WMPImageStore.decode` to every frame and to the natural size). **A canvas larger than its frames
  is not the test** — 27 corpus GIFs have one and 26 mean it: `Official_Xbox_MP71` and `TripleX`
  place a frame at an offset inside an unsized button, and `Age_of_Mythology`'s shutter is a
  193x172 frame on 198x173. All 26 carry a global colour table and decode their uncovered area
  transparent, so the rule matches 1 file.

- **`player.status` is a sentence, not a token (W162).** `Playing` / `Paused` / `Stopped`, and
  `Ready` before anything is open — `WMPHostSnapshot.statusText`, read by the object-model member,
  by the `wmpprop:player.status` binding **and** by the `status_onchange` argument, which are three
  separate resolutions of one path and were not all present. It was inert and empty for eight
  phases, so the readout 69 of the 180 archives dedicate to it painted nothing. Safe to word freely
  because **not one of the corpus's 128 uses compares it against a literal**; every one prints it.
  **There is deliberately no `Buffering (n%)`** — `bufferingProgress` is 0-100 with 100 meaning full
  and nothing outside the harness writes it, so a `< 100` test would report every skin permanently
  buffering. W119's trap is unchanged and is about the *rate*: a status string must never be raised
  from a clock tick.

- **A view is sized like any other node: authored literal, then script override, then the natural
  size of its own `backgroundImage`.** WMP skins routinely author `<VIEW backgroundImage="...">` with
  no width or height — the window *is* the bitmap — and demanding a positive literal at the root was
  the largest single cause of a skin that loaded and then drew nothing (89 views across 48 skins).
  The same artwork fallback already applied to every non-root node. **A view with no size and no
  artwork of its own is then sized by the union of the subtree it can place from literals and
  artwork alone** — `iconic` hangs its whole player off one `<SUBVIEW backgroundImage="base.gif">`.
  That union descends into a container whose own size is unknown and ignores `visible`, because a
  skin authors every wrapper hidden and turns one on in `onLoad`. Anything needing script
  contributes nothing, and the builder never invents geometry.
- **A view with nothing to draw is `0x0`, not a rejection, and a literal or scripted zero is an
  authored answer.** A `.wmz` names views that are never windows: 25 corpus skins author a
  `controlView` holding only `<player>` and a hidden `<video>` so an `onLoad` can run with host
  bindings and no window, and `pharaoh` writes the same idea as `<view id="vGhost" width="0"
  height="0">` whose handler redirects. Rejecting them was the last of `WMP0032`. The builder still
  invents nothing — the honest size of empty content is empty — and **`WMPMainWindowController` is
  what refuses to make a window out of it**: initial load walks its candidate list (persisted view,
  then `vPlayer`, then document order) running each view's script and following the views it asks
  for next until one has a canvas, and `switchView` runs a windowless view's script, honours its host
  commands, and stays where it is. `WMPRenderer` still refuses a non-positive canvas; a zero-area
  scene must never reach it.
- **What a windowless view asks for next is two different requests, and collapsing them into one
  `last` picks the wrong player (W175).** `theme.currentViewID` is a redirect and the last write
  wins. `theme.openView` is not a redirect at all — WMP opens a window per call and leaves the caller
  alone — so a dispatcher that opens its playlist, its player and its equaliser is asking for three
  windows, and `WMPMainWindowController.windowlessSuccessors` is where the distinction is made.
  **The player is the earliest of the opened views in the skin's own declaration order**, the rest
  are replayed against it through `applyHostCommands` once it is on screen, and every one of them
  stays in the candidate list so a player that is windowless in its turn still falls through.
  Reading only the last command opened `XBOX Music Mixer` on the equaliser its `onLoadSkin()` opens
  *after* `mainView` — *"it opens to the playlist and there is no route to get to the main window"* —
  and it is the only one of that skin's views whose buttons reach the others. **The old rule was
  right by luck wherever the skin happened to open its player last, which is most of them** — 21 of
  the 25 windowless `onLoadSkin` dispatchers end on `openView('mainView')`, and the panels they
  opened before it had therefore never opened at launch at all. Measured live, `Halo 2` goes from
  1 window to 5 and `xsn_sports` from 1 to 5, each of the extras a panel its own preferences say was
  open. The ranking is by declaration order because **all 21 archives that declare both a `mainView`
  and a panel view declare `mainView` first**; both scans, and the four dispatchers that are the
  exception, are in `reference/skins/xbox-music-mixer.md`.
  **The persisted view is the trap when this is touched**: `wmpSkinViewID` is written on every
  present, so a wrong player is sticky across relaunches and a fix is not visible until it is
  cleared — which is also what selecting the skin again does (`WMPSkinImporter.select`).
  `WMPWindowlessSuccessorTests` holds the ranking down.
- **`theme.openView` opens an additional window beside the opener; `theme.currentViewID` replaces the calling window's view. A skin's extra views are real windows.** 90 of the 180 archives call `openView`, 579 times. For four phases this engine had exactly one WMP window and the call was reduced to "present the view here and remember the one it covered" (`openedViewStack` / `CoveredView`) — and **that reduction was itself the cause of three reported defects**, not merely a deviation: W90 ("closing an interior window closes the whole UI"), W96 ("the skin is empty and shows no player") and W127 (the macOS close control stranding the user) each existed only because a covered view had to be *simulated*. `WMPViewWindowMaterializer` builds one borderless window per open view, all against **one shared script runtime**, modelled directly on `WinampModernHostedWindowMaterializer` — the only one of the three other families whose recipe transfers, because a `.wmz` view is an arbitrary authored canvas with no stack to join (Halo 2's panels are 406x209 against a 327x294 player). The first view presented binds the app's own window and is **the player**: the `MainWindowProviding` anchor, the restore anchor, the tiler's anchor, and the only presentation that writes `wmpSkinViewID` or is sampled for `WMPSurfacePalette`. **That window is the app's, not the skin's, and ordering it out is what a *close* means and nothing else** — a skin reload and a mode teardown drop its presentation without touching the window, because the caller is about to put a new skin (or the unskinned view) into it. Sharing one `remove` between close and teardown cost exactly that: `AppStateManager.restoreWindowFrames` calls `restoreFrame`, which reloads the skin when one is already loaded, so **every launch with a persisted `.wmz` and a saved frame ordered the main window off screen** with nothing anywhere to put it back. Reported as "main windows launch minimized". An *auxiliary* window is ordered out either way — it belongs to the skin, and a skin going away must not leave its panels behind. `theme.closeView(name)` closes the named window (84 skins, and every one of them had been aborting the handler that called it) and `openViewRelative` places the new window at its authored offset from the opener's top-left (W50 closed). **The drawer exception is what this does not touch**: Corona's sliding playlist and equaliser and NVIDIA's embedded modes are `<SUBVIEW>`s of the presented view's own canvas, never reach `openView`, and behave exactly as they did. See `reference/object-model.md`.
- **A windowless view opened by `theme.openView` owns the window it was asking for, and its
  window-scoped commands must never reach the opener (W200).** `openView` opens a window beside the
  opener and leaves the opener alone; a view with no canvas has no window to leave anything in, and
  running *every* command it posts against `existing ?? opener ?? player` is correct for the
  host-level ones and destructive for the three that are about a window.
  `WMPMainWindowController.redirectedToOwnWindow` rewrites `setCurrentView` to `openView` and drops
  a valueless `closeView`/`minimizeWindow`, and it applies **only when there is no `existing`
  window** — a view that becomes windowless in its own `onLoad` (`Halo 2`'s `previewView`) is
  reached by a switch, has a window, and is unchanged. `theme.closeView('name')` is untouched:
  naming a target is not the same as meaning your own, and 84 archives call the named form.
  **`pharaoh` is the whole case and only 2 of 185 archives reach this at all** (its two ghosts, and
  `cyberchannel`'s `playView`). Its transport calls `theme.openView('vGhostAutoDetect')`, that 0x0
  view's `onLoad` writes `theme.currentViewID='vRos'`, and the redirect landed on the player — the
  400x249 sphinx *became* the 197x194 rosetta panel, whose own close button then closed the app's
  only window; two clicks left the process running with zero windows. Reported as *"you can get
  trapped in the mini windows with no way back to the main window"*, and **it survived a relaunch**,
  which is the half that matters: `OnLoad()` opens `vGhost` on every launch and its `onLoad` reads a
  preference the skin itself saves, so one branch closed the player before it was seen and the other
  replaced it. A defect that persists through a restart has no route out inside the skin.
- **The app menu must open a skin-owned auxiliary surface through `openView`, never `switchView`.** The reason has changed and the rule has not: `openView` is the call the skin's *own* button makes, so routing a menu toggle through it means the panel behaves identically however it was opened — its own window, its own close. `switchView` would instead replace the player's view with the panel, which is what it means, and it is not what a menu item asking for a playlist means. `revealSkinSurface` routes every off-screen WMP surface through the `openView` host command. `WindowManager.wmpSkinShowsInActiveView` asks about **any open WMP window**, not the one presented view, so a toggle for a playlist already up reports checked-and-inert rather than opening it twice.
- **Do not mistake an in-place mode for an auxiliary view.** NVIDIA is the counterexample: its playlist and video layouts live inside `mainView`, while its top-right control still calls `view.close()`. There is no window of its own to close, so treating that command like an EQ close hides the player and leaves its last embedded mode as the apparent main window. The guard used to read "nothing has been opened over the player" and now reads "this is the player and it is the only window open" — the same statement in the new vocabulary. NVIDIA's close route instead runs its authored audio transition, first clearing its `videoItem` preference because `audioModeToggle()` otherwise redirects back into video mode. The installed-skin key is `NVIDIA` — `WMPSkinImporter` removes `.wmz` — so a compatibility guard must compare the installed name, not the archive filename. `WMPPhase9Tests.testNVIDIAEmbeddedPlaylistCloseReturnsToAudioMode` holds the route down.
- **A skin sound effect must not abort its state transition.** NullPlayer does not play bundled WMP skin sounds, but `theme.playSound(...)` is an inert host call rather than an unrecognised member: AlienMorph opens its shutter, plays `intro.wav`, then stops its intro timer. Throwing on the sound call skipped the stop and re-toggled the shutter every second.
- **A view the skin never shows can still have to keep running, and a view it only covered has to come back as it was left.** Two different things this engine used to treat the same way — "not the presented view, therefore gone" — and each is a whole class of dead controls. **A windowless view that declares `timerInterval` + `onTimer` is a *dispatcher*** (W89): 24 of the 180 archives author `<view id="controlView" timerInterval="100" onTimer="checkRemoteViewStatus()">` and route their panel, minimize and close buttons through it — the button does not call the host at all, it writes `theme.savePreference('remoteCallPl','true')` and that handler reads it back. Real WMP keeps it open beside the player. `WMPMainWindowController.adoptDispatcher` **scans** for it after presenting; keying it off the candidate walk works only on a profile with no persisted view, because `wmpSkinViewID` is written on every present and the walk then stops at the player. **The same skip hid its `onLoad` (W299)**: the family's `onLoadSkin()` is where the panels the user left open are re-opened from `plViewer`/`eqViewer`/…, so from the second launch on they never opened while the preference still said `"true"`, and each panel button's `toggleView` took two clicks. `adoptDispatcher` now runs the dispatcher's `load` itself when the walk did not visit it (`runSkippedDispatcherLoad`) and applies its commands against the player minus the player's own `openView` — the route the walk's deferred commands take. `launch.sh` deletes `wmpSkinViewID`, so it can only reach the first-launch path; to see the second, launch with the persisted view left in place. It runs through `WMPScriptRuntime.dispatch`, which commits no overrides and does not consume the observable-property changes — a dispatcher has no window, so it has no scene — and its elements are swapped in and the presented view's swapped back, objects and all, because every view root is called `view`. **And `theme.openView` opens a *second window*: the opener is never touched** (W90). That used to be simulated — the covered view's overrides, its timer period and its animation clock were stashed and a `closeView` return was a *restore* rather than a load, because rebuilding it discarded the overrides its script had accumulated and reinstated the markup `timerInterval` the script had overridden. On `Alienware Invader` that returned to `commands=0` and let the markup's 500 ms re-fire `toggleShutter()` with `introStatus` already true, shuttering the whole player; reported as "closing an interior window closes the whole UI". **The simulation is gone and so is everything built on it** — `CoveredView`, `openedViewStack`, `switchView(to:restoring:)` and `WMPScriptRuntime.prepareForRestore` — because the opener is now genuinely still running in its own window, which is what the restore was imitating. What survives is the primitive underneath: `WMPScriptContext.restoreElements(for:)` swaps each window's live elements in for the length of its own transaction, since one `JSContext` serves them all and every view root is called `view`. A genuine view change still loads exactly like a launch (W46).
- **A view arrived at by a switch loads exactly like one arrived at by launch, and a `.wmz` compact mode is built entirely out of that.** `switchView(to:)` raises `load` on the new view, applies the host commands the handler posts — *after* `apply`, which sets the view timer from markup, so the script's `setViewTimerInterval` is the override and not the other way round — and schedules its `timerRequests`. It did none of the three for a long time (W46), and Corona's `viewTiny` is authored `timerInterval="0"` and animates itself into the mini player from `OnTinyLoad` alone: the switch happened, nothing ran, and the compact view drew **the same artwork at the same size as the player**. The only visible symptom was the playlist and equaliser drawers going away, because `viewTiny`'s markup does not have them. Two consequences bind: the initial-load `collapsed` guard applies here too, since a view can now blank itself in an `onLoad` this path finally runs; and `viewchange` is dispatched only when the markup authors a handler, because a transaction's `timerRequests` are what *that* transaction registered and an unconditional binding-only one posts an empty set that cancels what `load` just scheduled.
- **The skin's own JScript is ES3, and `JSContext` is not — `WMPJScriptDialect` is where that is reconciled (W86).** WMP9's `corona_tiny.js` chains its compact-mode animation by appending a timer event to the array its `TimerDispatch` is enumerating with `for-in`. JScript visits the appended index; JavaScriptCore snapshots and does not, so the chained event was dropped on the tick it was registered and the whole WMP9 family could neither collapse its video panel nor get back to `vPlayer`. Corona's 2002 script splices the array instead and is unaffected, which is what made `corona` the control and `9SeriesDefault` the case. The rewrite is bounded, skips strings/comments/regex literals, and leaves a program with no `for-in` byte-identical; **3 of 180 archives use `for-in` at all and one depends on the live semantic**, so the corpus sweep is the proof it changed nothing else. **Before ranking a "the script runs and nothing happens" defect, ask whether the handler depends on an ES3 semantic** — no headless probe here can see that class, and the live `INPUT script-diag` line stays silent because nothing throws. And when you add to this file's scanner: **test a CRLF fixture.** Swift folds `"\r\n"` into one `Character` that is not `"\n"`, and the first version of the rewrite silently did nothing to the entire corpus for that reason while every LF-only unit test passed.
- **A `<property>_onchange` fires in the same transaction as the write that triggered it, and the view's `JScript:` geometry expressions are *not* re-run to achieve the same thing.** A `.wmz` animates by writing geometry once per timer tick, so a pane positioned off a moving one has to move in the same frame; letting it catch up on the next transaction tore the compact view into two visible halves that closed four seconds later (W87). Only what the skin declared is raised — 16 geometry `_onchange` attributes across 6 archives — bounded and once per property per transaction, so two panes positioned off each other cannot loop. **Re-resolving the expression set after the handlers is the tempting general form and it is wrong**: those attributes are an initial layout rather than a live binding, and several read the property they write (`left="JScript:svBottomLeft.width-left"`), so re-running them moved 175 of 545 corpus images and shattered `Back to the Future Trilogy`'s `videoView` and `ALXMorph`'s frame. That is what a sweep is for; it was reverted on the measurement, not on taste.
- **A tween's endpoint is not readable by the rest of the handler that started it (W112).** WMP
  animates `moveTo`/`resizeTo`/`alphaBlendTo` over the call's duration argument, so an element's
  `left` still answers where it *is* for the remaining statements — and skins are written against
  exactly that. `Cablemusic`'s playlist tab is `onClick="PlayListMove();HidePlist();"`: the first
  slides the drawer, the second reads `subPlayList.left` to decide whether it is now open or shut.
  With the endpoint applied inside the call that read answered the destination, so closing the
  drawer never hid the playlist and it stayed over the player forever — reported as "the playlist is
  always showing". **A duration of zero is not a tween** and applies immediately, which is what
  `movePlayButton()`'s `moveTo(x, 116, 0)` toggle depends on.
- **And the tween now runs for the duration it was given, but only where something is drawing
  frames (W194).** For four phases the endpoint landed at the handler boundary and the completion
  was raised in the same transaction, so a 1,000 ms slide took one frame and nothing in the corpus
  ever animated — reported against `Compact`'s drawers as *"its not a smooth opening"*. **The
  decision is made per transaction, not per call**: `WMPScriptRuntime.transact(animatesTweens:)` is
  a caller promising a frame clock, and only a window has one. A render dump, the corpus census and
  the windowless dispatcher (W89) do not, and for them the call behaves exactly as it did before —
  endpoint at the handler boundary (W38), completion from it (W55) — so **the settled state is
  identical either way and every measurement taken against a headless probe still holds**. That is
  also why a sweep cannot see this row at all; it is drivable only live.
  With a clock, `WMPObjectModel` holds the motion as a `WMPScriptTween` (channels with `from`/`to`,
  duration, completion event), the runtime keeps it per view scope, and
  `WMPMainWindowController.startTweenLoop` steps it at 30 fps through
  `WMPScriptRuntime.tweenFrame` — a real transaction per frame, so the interpolated value is
  written through the object model, becomes a mutation and therefore a scene override, and the
  element reads where it *is* mid-slide. Three things still arrive instantly under a clock, each
  because a frame would be a guess: a duration of zero, a channel already at its destination (its
  completion is raised at once, or a sequence chained off a no-op move would stall), and a channel
  whose current value the model does not hold — which is why `alphaBlendTo` on an **unauthored**
  `alphaBlend` still arrives rather than fading, and the ALX family keeps the subtrees it depends on
  arriving. A later call on the same element and property **replaces** the one running, so a drawer
  re-toggled mid-slide reverses from wherever it is.
  **The callback is the load-bearing half.** Moving `onEndMove` from end-of-handler to end-of-tween
  changes when 36 views chain their next step: `Compact` shrinks its own window inside
  `Playlist_OnEndMove`, so the window now shrinks a beat after the drawer starts closing, which is
  what WMP does.
- **And `load` carries a clock too, which is the half W194 left out (W253).** It was enabled on the
  click and view-timer paths only, so a tween a skin authored in its `onLoad` still landed its
  endpoint in one frame — `Revert (1)`'s `onLoad="vwPlayer_OnLoad();alphaBlendTo(40,9000);"` is the
  clean case, a nine-second fade to translucent that arrived fully faded before the window was ever
  shown. **`WMPMainWindowController` has two load sites and the row named the wrong one**: ~1348 is
  `theme.openView`, the skin's *extra* windows, while the player itself opens on the skin-load walk
  at ~404. Both now pass `animatesTweens:` and call `startTweenLoop`; fixing only the first
  compiled, passed, and changed nothing on screen. `WMP_LOAD_TWEENS=0` is the A/B and
  `WMP_TWEEN_TRACE=1` the instrument — see `reference/harness.md`.
  **W194's stated risk did not materialise, and it was measured rather than reasoned about**: an
  `onLoad` sequence chained through `onEndMove` now presents its pre-tween state and completes a
  beat later, exactly as WMP does. Ten skins A/B'd at t=16 s — `9SeriesDefault`, `corona`,
  `Back to the Future Trilogy`, `Plus! Professional`, `TripleX for XP`, `US Marine Corps`, `WoW`,
  `Rave-MP`, `Revert` — settle byte-identical at identical window sizes.
  **`Alienware Invader` is the one that cannot be A/B'd this way and is the trap worth keeping**:
  it differed, and four runs of it produce four distinct hashes because its intro never settles, so
  the diff is the skin's own animation and not the change. Its ON run ran **zero** tweens, which is
  what says so. A skin that never settles needs a same-mode control before any comparison is read.
  **The corpus numbers on this row are void.** `WMP_TASKS.md` carried 108 of 184 archives and a
  static walk of `onLoad` handlers gives 67; both count markup rather than execution. `Blinx`'s only
  `moveTo` sits inside a `/* */` block, and a walk that follows every call from `onLoad` follows
  branches that never run. Only `WMP_TWEEN_TRACE` can count this, per skin, and it has not been run
  corpus-wide.
- **Compact mode is authored by 11 archives, and the button every skin has is not it — audited 2026-09-12.**
  The corpus splits three ways and conflating them wastes a session. **Real compact toggles: 11 skins**, by two
  mechanisms — a switch to a smaller view (`corona`, `9SeriesDefault` → `viewTiny`; `Main_Street` slim/mini;
  `T3-Skynet_Media_Player`; `digitaldj`; `holiday_skin`; `portals`) and an in-place `view.width`/`view.height`
  write (`Cablemusic`, `Goo`, `iconic`, `Melvin`). Every one of them was clicked in the running app with a track
  playing and **10 of the 11 change the window**: 859x468→596x468, 593x600→475x373, 324x253→163x114,
  288x255→79x70, 440x336→280x130, 516x496→214x49, 317x330→400x81. `portals` is the exception and its cause is not compact mode:
  the walk opened the wrong view (**W153**, closed 2026-09-13) and the right one turned out to drag the window
  instead of clicking (**W154**). `digitaldj` works from `DigitalDJMid` and not from `DigitalDJ`, which is W152. **The
  five *"Return to Player/Main Mode"* buttons are video-mode returns, not compact** (`Plus! Professional`,
  `QuickSilver` ×2, `TripleX` ×2, `xXx_night_vision_redx`) and all reach `setCurrentView` cleanly. **And the
  button the reporter meets in nearly every skin is `view.returnToMediaCenter()` — 162 archives, 196
  controls, 179 of them tooltipped "Return to full mode".** It toggles the Library Browser (opens when hidden, closes when visible) since W100 closed on
  2026-09-13; before that it was dead in every one of them, which is why *"the compact button does nothing"*
  was that button and not compact mode. Name the skin and check it against this list before reading such a
  report as a compact defect.
  **This button's glyph is not its meaning, and a report about it is usually about the glyph
  (W176).** Re-derived 2026-09-19 over the 185 installed archives: **204 controls in 169 archives**,
  and *every one* tooltipped some spelling of "Return To Full Mode". **139 of them are
  `<BUTTONELEMENT>` with no image at all** — a mapping colour on a shared bitmap — 61 are
  `<BUTTON>` and 4 are bare `<RETURNBUTTON>`. Of the 65 that name a file the stems are
  `full`/`fullmode`/`max`/`fullbutton`, **and 5 are `close*`**: the notice-view close boxes, which
  is why those five now close their window instead (W176). So the same call wears a maximize box, a
  full-mode arrow, an unmarked colour region and, in five skins, an X — and a reporter naming the
  icon is not naming the control. **Read the authored `id` and `upToolTip` off `WMP_RENDER_PROBE`
  before believing any report that identifies one of these by what it looks like.**

  **`WALL-E` is the worked case, and the lesson is the button order rather than this button.** Its
  `mainView` system strip is **minimize, full mode, close** left to right at `305,4` / `333,4` /
  `361,4` — Windows order, where macOS puts close leftmost. Read left to right as macOS, that gives
  *"the X to close maps to minimize and the minimize maps to library toggle"*, which is what it was
  reported as. All three are correct: `WMP_RENDER_CLICK` at each centre hits the button under it,
  the bitmaps are a dash on the left and a red X on the right as authored, and driven live the X
  leaves 0 windows with the process alive while the dash leaves `AXMinimized=true` with 1. A
  `.wmz` is a Windows skin and orders its title strip the Windows way; **check the strip's order
  before reading a report that names two of its buttons.**

  Rapid library toggles require `WMPMainView.acceptsFirstMouse` so the click after the library
  takes focus still activates the skin control, and WMP-only `animationBehavior = .none` in
  `WindowManager.showPlexBrowser` so native window animations do not race visibility. Verified
  on New Super Mario Bros with six consecutive clicks about 0.3 seconds apart, then user-confirmed.
  **A window bigger than the compact artwork is not a defect here**: `corona`'s `viewTiny` is authored 596x498 and
  draws a 346x103 mini player into it, exactly as its markup asks — WMP shapes that window with the transparency
  key and this engine leaves it transparent, which looks the same. Measure the window, not the ink.
- **A view's own size is the one expression input a handler can change out from under the pass that
  already read it, and the builder can refuse the change (W99).** `WMPScriptContext` resolves the
  `JScript:` geometry before the handlers run — a pane positioned off another must see the frame that
  pane lands at — so a handler that assigns `view.width`/`view.height` leaves every expression
  reading it a transaction stale. **And `canvas = resizeLimits.clamp(…)`, so a view declaring
  `minWidth`/`minHeight` has a floor its own script cannot write through**: `ALXMorph` is
  `<view id="videoView" height="357" minHeight="357">` and `onLoadVid()` assigns 316, which the
  canvas rejects while the script goes on answering it. The transaction now clamps the view element
  to its own limits and re-resolves the expressions against that; `WMPScriptRuntime` reports the
  clamped size as `viewSize`, so the window, the next transaction and the expressions carry one
  number. **Re-resolving against the *raw* assignment instead is the defect with more reach** — it
  walked `Back to the Future Trilogy/videoView` to `x=-94` — which the 20-archive sweep caught and
  no single-skin check would have. `EXPR`'s two columns are the instrument: `->` is the initial
  resolver against the canvas, `live=` is the runtime's, and **a disagreement between them where the
  deps are only `view.width`/`view.height` is this class and nothing else** (corpus-wide: 809 before,
  0 after). **A view with an `onTimer` hides it**, because the next tick opens a transaction at the
  corrected size — `xsn_sports` read as a drawer button drifting 20 px rather than as a broken
  window. 217 corpus views author the shape and **146 have no timer and never correct**, which is
  part of what W68's "draws a shell" has been all along.
- **A script resizing its own window is four separate claims, and `Compact.wmz`'s drawers needed all
  four (W184-W192, 2026-09-16).** They are listed here because each one *renders perfectly* in a
  capture and does nothing on screen: the builder takes its canvas from the script's overrides, so
  every headless probe agrees with the skin while the window stays where it was. **Read `viewSize=`
  on the `CLICK` line, never the picture.**
  1. **One axis is a resize.** `assignedViewSize` demanded an override for *both* `width` and
     `height`; this skin grows only the width for one drawer and only the height for the other, so
     it answered nil and the window never moved (W186).
  2. **The axis the transaction did not assign is the *window's*, not the one left in the
     overrides.** Those are cumulative, so a handler touching only the height re-asserted a width
     from ten minutes ago and undid the user's stretch (W188).
  3. **A script-assigned alignment is anchored at the canvas it was assigned at, and the canvas moves
     *within* the transaction.** `SetAlignment(false)` → `view.width += rightMove` →
     `SetAlignment(true)` is how a skin says *the body keeps its size and the space I just added is
     the drawer's*; measured from the authored size instead, the body stretched over the drawer it
     had opened (W185).
  4. **A piece pinned to an edge rides it through a resize in the same handler.** The same idiom
     with `right`/`bottom` instead — `SnapToVideoSize` — must move the piece, because this engine
     lays out once per transaction and the middle state otherwise never exists. Without it the
     drawer stays put while the window grows past it and **its tab ends up outside the window, where
     nothing can ever click it again** (W192). One archive in the corpus assigns an alignment from
     script, so 3 and 4 can move nothing else.
  Two more from the same report are about *when* the window moves, not what size it takes: a script
  transaction rebuilds at the **window's current size**, never the last scene's (a transaction in
  flight across a user resize otherwise re-presents the stale canvas and stores it, permanently —
  W187); and the frame is set in the **same main-actor turn as `present`**, because resizing ahead
  of the render leaves AppKit stretching the old picture into the new frame — reported as "a big UI
  flash when the drawer opens" (W190). See `reference/skins/compact.md`.
- **`view.size(corner)` blocks in WMP, and a skin's resize bracket is built entirely out of that
  (W225, 2026-09-18).** 235 calls in 88 of the 185 archives, every one of them `onMouseDown`, and
  the statements *after* the call are what the skin does when the drag is over. `Compact`'s
  `DoSize()` pins `playlistDrawer` to `right` and `settingsDrawer` to `bottom` so both ride the
  window's corner, calls it, and unpins them. Nothing here can block, so the pin and the unpin both
  landed before the first pixel moved: the drawers kept their absolute positions while `playerView`
  (`stretch`) grew over them, and their tabs ended up buried under the body where no click could
  reach them. Reported as *"when you stretch compact skin it breaks the drawers and the main body
  will absorb them and also not allow them to close"*. Three claims, and the report needed all three:
  1. **The mutation count is the seam.** `WMPObjectModel.resizeCallMutationIndex` records where the
     call fell; `WMPScriptRuntime` holds the tail and `resumeAfterWindowResize` replays it against
     the size the window finished at. **Gated on `animatesTweens`** for the same reason a tween is
     (W194) — that is the caller promising it is a window, and only a window runs a drag — so a
     render dump, the corpus census and the windowless dispatcher still run the handler straight
     through and every measurement taken against them holds.
  2. **The tail is the *last* word on the release, not the first.** Raised at the top of `mouseUp`,
     it fell straight through into the ordinary control path, whose `mouseup`/`click` dispatch calls
     `presentation.scriptTask?.cancel()`. The unpin lost that race and `playerView` stayed pinned
     `left`/`top` while both drawers stayed pinned to the corner — a player drawn small in the
     top-left with its drawers stranded out at the window's edges, for the rest of the session. It
     is raised from a `defer`.
  3. **Assigning an alignment freezes the element where it is *drawn*, and the extent half of that
     must stay out of the geometry overrides.** WMP re-measures the margins at the write, so the
     unpin must not teleport the drawer back to its authored `left`. But
     `WMPSceneBuilder.ownAuthoredSize` reads the geometry overrides and **is what every child's own
     alignment delta is measured from**: written there, `SetAlignment(true)` made `playerView`'s
     authored 422 read as the 754 it had been dragged to, and its whole chrome — tiles, corners,
     the transport strip — saw a zero delta and collapsed back to the authored arrangement inside a
     754-wide frame while both drawers sat correctly at the edges. Reported as *"the drawer and
     resizing is totally broken in every way"*. The origin half is an ordinary script-assigned
     coordinate; the extent half is `WMPSceneOverrides.scriptAlignmentExtent`, consulted only by the
     `stretch` case. **One archive in the corpus assigns an alignment from script**, so 3 can move
     nothing else — verify with a decoded scan for `.horizontalAlignment =` before touching it.
  **Drivable only live**, and `WMP_RESIZE_TRACE=1` is the instrument: read `release script=true`
  against the `resume` that must follow it. See `reference/skins/compact.md`.
- **The window edge is ours, and AppKit takes it before the view can (W227).** `WMPMainView` has
  carried a 6pt edge band since W193 and for a real drag it had never run: a `.wmz` window is
  `[.borderless, .resizable]`, and `.resizable` alone is enough for AppKit to claim a press near the
  frame in `NSWindow.sendEvent` and run its own resize loop — the view is sent no `mouseDown`, no
  `mouseDragged` and no `mouseUp`, and the window is resized entirely outside the skin. A *click* on
  the same pixel does reach the view, which is why the band read as live and why `edge-band press`
  only ever printed for gestures that resized nothing. `WMPSkinWindow.sendEvent` claims the press
  first, and only where the view says no control is there, so a control drawn against the window
  edge keeps every pixel it had.
  **What the bare band skipped is the skin's bracket, and the corpus is emphatic about it**: 69 of
  the 87 archives authoring `view.size` run something after the call, and in 68 it is one idiom —
  `saveVidSize()` / `onVidSetSize()` / `g_fUserHasSized = true`, persisting the size the user just
  dragged to. Pulled by the edge, the window resized and the skin forgot it the moment the view
  closed. So the band raises the view's own grip handler (`WMPResizeGrip` names the node; 233 of the
  234 corpus calls are spelled into the handler attribute and the one that is not is `Compact`'s
  `DoSize()`, so it resolves one hop through the skin's scripts), W225's machinery holds the tail,
  and the release replays it. `beginScriptResize` **adopts** a drag already under the pointer rather
  than refusing it: refusing answers `false`, which is the caller's signal that no release is
  coming, and the held tail would then run mid-drag against the size the window started at.
- **A script-assigned extent is an answer, not a baseline, and a nested one must not be re-grown.**
  W225's re-anchoring is the growth of the element's *parent* since the assignment, and only a child
  of the view root has a parent whose extent the canvas is; deeper, the fallback was the growth since
  the *markup*, added on top of a number the handler measured at the current size — the resize
  counted twice. `Compact` is the worked case: `svBanner`'s `visible_onchange` writes
  `svScreen.height = svScreenOuter.height - svScreen.top` the first time a track plays, and
  `myeffect` is `height="jscript:svScreen.height - top"` under it. Stretch the player to 620x573 and
  *then* start playing — both wrote the right number for that canvas, 435 and 410, and both were
  drawn 195 taller, 195 being 573 − 378. The visualizer spilled out of the window over the transport
  strip, and the drawers read as missing underneath it. **The order is the reproduction**: with a
  track already playing the same stretch is correct, because the write happens before the resize
  rather than after it. Nothing moves for a node the script never wrote.
  **An authored `jscript:` binding on a sibling's extent is a different mechanism and was W235** —
  `NVIDIA`'s `visEffects` off `visFrame` — measured not to be this, and closed 2026-09-19 by the
  alignment-baseline half of `c78f32f7`: `ownAuthoredSize` was reading the runtime's own geometry
  override back as authored, so every child's stretch delta was zero. A gated widget like
  `visEffects` is reachable headlessly after all — one `WMP_RENDER_CLICK` on the toggle that sets
  `mainModeVis.visible`, then `WMP_RENDER_SIZE` for the stretch. See the archive.
- **WMP's `event` object is a global, and 84 of 185 archives read it (W184).** `Compact`'s drawer
  handlers open `view.maxWidth = event.screenWidth` from a plain function call, and its view root
  reads the same thing from a `jscript:` attribute where no event exists at all — so it is bound
  like `player` and `theme`, not like a handler argument. `screenWidth`/`screenHeight` answer the
  window's display (a fixed 1920x1080 headlessly, so a sweep reads the same on every machine) and
  `shiftKey`/`ctrlKey`/`altKey` answer the dispatching event. **`keyCode` stays unrecognised on
  purpose** — 433 uses across 79 archives, and nothing here dispatches `onKeyDown`, so answering `0`
  would tell every one of those handlers that a key it never saw was pressed. A member that cannot
  be answered honestly belongs in the demand tally, not in a default.
- **`res://wmploc.dll/RT_STRING/#<id>` is a string, and drawing the URL is not a layout defect
  (W189).** 133 uses of 50 distinct ids across 6 archives. `Compact` labels its settings tab and both
  on/off switches this way, and the raw URL was 200 px of text in a box authored 110 wide for the
  word *On* — reported as *"the srs text is misaligned"*, which it was, because of the string.
  `WMPResourceStrings` holds only ids the corpus itself names and answers the empty string for the
  rest; it is wired into all three routes a skin reaches them by — a readout's `value`, a tooltip,
  and `theme.loadString`. **Add a row only when something in the corpus states the text.**
  **A `res://` id can also be localisation plumbing rather than a label, and neither `""` nor the
  raw URL is an answer for it (W236, closed 2026-09-20).** `netgen.wms` (`Revert`, `Revert (1)`) sets
  `fontFace="res://-/RT_STRING/#1888"` on all three metadata readouts and
  `scrollingDirection="jscript:theme.loadString('res://wmploc/RT_STRING/#1910');"` beside them —
  12 uses of 2 ids across 2 archives, measured 2026-09-19 by the W195 census. `wmploc.dll` holds the
  font family and the scroll direction for the shipping language, which is how one markup file
  serves an RTL locale, and declining to invent a *label* for either is right.
  **What the scene did with the unanswerable one was fall back to CoreText's default rather than to
  this engine's**: `CTFontCreateWithName` never fails, so the URL and the `""` it resolves to both
  became **Helvetica** — line height 7.00 at the 7pt those readouts author, against `Arial`'s 8.05 —
  a face nothing in the markup asked for. **An unusable face is an unstated face**, the reading W240
  gave an unreadable geometry value and W241 an empty one, so `WMPTextMetrics.face(_:)` is the one
  seam all four face reads go through (the builder's paint and intrinsic size, the object model's
  `intrinsicTextSize` and `measuredTextWidth`) and it answers `WMPTextMetrics.defaultFace`. The URL
  still goes through `WMPResourceStrings` rather than being rejected, so a family ever earned for
  `#1888` is used the moment the row lands. **Reach re-measured 2026-09-20 over the 185 installed
  archives: 953 literal `fontFace`/`fontType` uses, 6 of them `res://` (3 each in the two `Revert`
  releases) and 0 empty** — the rule moves those six and nothing else in the corpus.
  **`scrollingDirection` closed as a note, not a defect**: it is read nowhere in `Sources` — the
  builder consumes `scrolling`, `scrollingDelay` and `scrollingAmount` only — so answering it would
  move no pixel until a scroll direction is implemented. **The defect has almost no visual
  signature and no headless one at all**: those readouts are `value=""` in markup and filled by
  `vwPlayer_UpdateMetadata()`, which is gated on `player.openState == 13`, so a render dump of
  `Revert` is blank there and identical either side. Verify by playing a track under the skin —
  `harness.md` § *The probe flags* on what a clean sweep does not prove.
- **`<RETURNBUTTON>` is the command, not a button that happens to be there (W191).** 19 uses across
  15 archives and **15 author no `onClick` at all** — the element's own behaviour is the return to
  the media centre, so treating the kind as an ordinary button left the library unreachable from
  those skins. It posts `toggleLibrary` only when the markup authored nothing: `anemone` and
  `modernblue` spell `view.returnToMediaCenter()` themselves, and doing both toggles it twice.
- **A `.wmz` compact mode is a script resizing its own window, and it is the script's output rather
  than the drawing's (W113).** `SwitchSmall()` writes `view.width = 475; view.height = 373` and
  swaps one shell for another. Three separate things had to hold and none of them did:
  **the view root reads its own size overrides before its markup**, like every other node — the
  literal used to win, so a `<VIEW width="593">` could never be resized by its own script;
  **the size a script assigns is not the size alignment is measured from** — `ownAuthoredSize` stays
  the markup's, because `LostPlanet`'s `onLoadInfo` opens with `view.width = view.minWidth` and
  collapsing the delta to zero stopped its stretch tiles covering the 61 px they were covering,
  punching holes through the window frame; and **it is committed in the uncancellable half of the
  transaction**, beside the host commands, because with a track playing a `status_onchange` lands
  five times a second and cancels the click's task after its render (W88). The overrides had already
  committed, so the *next* rebuild drew the compact player at the old canvas — a 475x373 player in a
  593x600 window, which is the "large overlay" that was reported. `WMPScriptOutput.viewSize` carries
  it, keyed off the **mutations** so an expression-driven `<VIEW width="jscript:…">` — which already
  read the window's current size — is not mistaken for a resize request. A non-positive result is
  not a size: that is the store-thumbnail collapse, and ten more `mediaSwitcherView`s joined the
  documented `WMP0035` windowless class when the override finally reached the view root.
- **Three of the four alignments are margins and `center` is not, and reading it as one cost a whole
  window frame (W143).** `right`, `bottom` and `stretch` say *hold this edge's authored distance to
  the parent's edge* — the delta form, a no-op at the view's own authored size, and what W113's
  `ownAuthoredSize` and `LostPlanet` exist to protect. `center` says the element **stays centred**,
  so its coordinate is `(parent − own) / 2` computed fresh, and the authored coordinate on that axis
  is not an offset into it — which is exactly why a skin that wants a centred piece authors none at
  all. Read as a margin, every one of them collapsed to the parent's origin. **The Alienware/ALX
  frame is built out of this and nothing else**: each of their playlist, equaliser, visualisation and
  video windows hangs its two 175px side columns off `<subview id="plLeftCenter"
  verticalAlignment="center" backgroundImage="f_left_center.png"/>` with no `top`, plus a tile above
  and below at `top="wmpprop:plLeftCenter.top"`, so the columns landed on top of
  `f_top_left.png`/`f_top_right.png` and took the window's whole title bar and the top of its inner
  border with them. Reported as "the playlist and eq windows are not properly constructed … the
  window border and details are not correct and there are large gaps". **The blast radius is the
  measurement, and it is the largest of any single line in this engine: 139 of 535 corpus images
  moved, and every one sampled is a repair** — WALL-E's logo and transport row, `PowerToys`' cancel
  button, `xsn_sports`' progress panel finally sitting over its own pointer arrow, `TripleX`'s
  clipped `X3-080902` readout, the five `US …` video placeholders, `Plus! Pulsar`'s side-drawer tab,
  `Project Gotham Racing 2`'s frame stripes, and `T3-Skynet_Media_Player`, which had been drawing a
  half-width frame with its own buttons outside it. **The axes are independent** (AlienMorph's
  `plRightCenter` is centred vertically and pinned right). **Amended by W144: nothing outranks
  centring on the centred axis** — the `isComputed` guard was carried onto `center` alongside the
  other three, justified by WoW's `left="JScript:view.width-202"` beside an alignment, and WoW's
  alignment on that node is `right`. A decoded corpus scan finds **3** centred nodes authoring an
  expression on the centred axis, all in `Ice`, against 376 that author no coordinate at all — so
  the guard protected nothing it was written for, and it cost every drawer a skin slides by script.
  See the `windowed`/drawer entry below and `reference/skins/xsn-sports.md`. `mainView` is
  byte-identical across the whole family: a non-resizable player authors no
  centred pieces, so **this class lives entirely in the windows a skin opens beside its player** —
  which is why four phases of `mainView` work never saw it. `WMPAlignmentTests` pins both halves.
- **A `wmpprop:` read of another element's geometry answers where that element *is*, not what it
  authored (W212).** One hop on from the rule above, and the half of it that had no answer: the same
  family states the tiles either side of its centred column as `top="wmpprop:plLeftCenter.top"`, and
  centring computes a coordinate the markup does not carry, so `WMPInitialLayoutResolver` — which
  reads the target's authored attribute — answered **0** and both tiles painted over the corner
  pieces. `WMPSceneBuilder.parseDimension` answers such a read from the target's **resolved frame**,
  or, when the layout walk has not reached it yet, from the coordinate its centring computes: the
  walk is in *paint order*, so a tile at `zIndex=6` routinely reads a centre piece at `zIndex=10`.
  **This only ever showed on a surface built without the script runtime**, because WMP answers the
  read from the live object model and a skin's own window does the same through the runtime — so the
  corpus render sweep is byte-identical across the change (552 of 553 images, the odd one being
  `Scooby-Doo_2`'s random picture) and the one caller it moves is the borrowed frame
  (`WMPHostedFrameTemplate`), where it was three white blocks on every hosted window. The
  counter-evidence is pinned beside it: a target that states its own coordinate is read at that
  coordinate.
- **A container collapsed to zero area clips its children away too — and only that one.**
  `WMPSceneBuilder` passes children `nil` for "no clip at all", and `WMPRect.intersection` also
  answers `nil` for an empty result, so a pane collapsed to zero height handed its children *no*
  clip. `Classic` sets `view.height = 359 - 183` for audio, its `stretch` video pane goes to 0, and
  the centred `wmlogo` inside it drew across the nav bar. A zero-area frame now hands down a
  zero-area rect. **The wider rule — any frame that misses its parent's clip — was tried first and
  rejected by the corpus sweep**: it also removed `Back to the Future Trilogy`'s "previous
  visualization" button, authored at `left="-25"` wholly outside its logo strip and mirroring the
  next button. **Whether WMP draws that button is unknown** — no WMP was available to check, and
  the wider rule is the consistent one (a child 1px inside is clipped to 1px, one 0px inside draws
  whole). Narrowed was kept because a wrong guess there costs a working control. A WMP screenshot
  of that skin's visualization window settles it. Narrowed, the sweep (stopped and
  `WMP_RENDER_HOST=playing`, 184 archives) moves `Classic/view-2` and nothing else in pixels;
  `Blinx/mainView` hosts two fewer text widgets that were already `visible=none`. The cursor-rect
  pass in `WMPMainView` treats a clip that misses a control as hidden, not unconfined.
  `WMPAlignmentTests.testAChildOfACollapsedStretchPaneIsClippedAway` pins it.
- **A top-level `<SUBVIEW>` sized by its background image alone is not a box and clips nothing
  past it — a nested one is, and does.** With no `width`/`height` (authored or script-assigned) its
  frame is only the bitmap's extent. `Ursula` hangs its playlist drawer off the 388x224 `mainbg.bmp`
  subview and `moveTo`s it to `top="212"` in a 320-high view; clipped to the bitmap, the opened
  drawer showed its first 12 rows and read as "the drawer does not extend". A **direct child of the
  view** so sized hands its children the *inherited* clip, and its `clippingColor` shape keeps its
  keyed region inside the bitmap and says nothing outside it (`WMPSceneClipMask.boundedByFrame =
  false`; the renderer pads the mask with keep, and `WMPHitCoverage` treats a sample past the bitmap
  as kept). **The first cut applied it at any depth, and the corpus sweep refuted that**: `Melvin`'s
  `x` subview is a nested `clip.gif` whose eyelid is parked wholly above it until a blink slides it
  down, and unclipped it sat on the head. The top-level cases corroborate one another — `Creed`
  runs the same drawer script past `Main.bmp` (466x400 in a 550-high view), and `Asimov_Radio`'s
  default-on `splHead` is a 190-high face hung 30px inside its 288-high sign, which the old clip cut
  to a forehead. Sweep against the old rule (A/B, 184 archives): those two plus `Ursula`, the `Xbox`
  family's previous/next-visualization buttons (9px past `screen_buttons_back.png`, now drawn and
  reachable), and sub-pixel edge moves on half-pixel frames; the hit counts that *drop* are close
  and resize buttons laid out for a wider window that sat wholly off the canvas, which used to keep
  a hit only because a parent missing the canvas handed down no clip at all.
  `WMPAlignmentTests.testOnlyATopLevelArtworkSizedSubviewLetsItsChildrenPastItsBitmap` pins both
  halves. **And only a keyed one — a window body, not a patch (W278).** `Ursula`, `Creed` and
  `Asimov_Radio` each declare a `clippingColor` or `transparencyColor` on that subview; the `Xbox`
  family's `screen_buttons_back.png` declares neither, and parks its visualization arrows 9px past
  its bottom edge precisely so they are hidden until the visualizer is on. Unclipped they drew as two
  black boxes along the bottom of the screen — the "now drawn and reachable" line above was that
  defect, read as a gain. Sweep: `XBOX` and `Official_Xbox_XP` 257 px each, sub-pixel edges on six
  `videoView`s, and a `QuantumRedshift` close button laid out wholly off its canvas gets its hit back.
  `testAnUnkeyedTopLevelArtworkSizedSubviewClipsItsChildren` pins it. Reproduce Ursula's opened state headlessly by authoring `playlist_drawer` at `top="212"`
  and `plsub` visible in a copy of the archive — `WMP_RENDER_CLICK` reports the move but dumps the
  pre-click frame. Accepted live 2026-09-23.
- **A container that paints only a `backgroundColor` grounds all its children, negative `zIndex`
  included.** Behind-own-artwork ordering is for artwork with a hole (`Cerulean`); a colour with no
  image has no hole, so a child drawn behind it is simply gone. `Melvin`'s belly is
  `<subview id="look" backgroundColor="white">` holding `<effects id="viss" zindex="-2">`: the
  white slab was emitted after the effects split, landed in the overlay above the hosted surface,
  and a playing track showed a blank belly — reported as *"visualizer button not launching it"*,
  though the button, the `stepEffect` command and the surface were all working. `WMPSceneBuilder`
  now emits that fill before the negative children when the node has no background image; with an
  image the order is unchanged. Sweep (A/B, 184 archives): 10 `plView`s move, all the same shape —
  a `backgroundColor="#000000"` `plcenterBox` over a `<playlist zIndex="-10">` with its own colour,
  which now shows the playlist's authored colour instead of the container's black (live, the hosted
  playlist draws over both). **Finding it took the live app**: every headless instrument agreed
  with the broken app, because the harness spectrum is empty and a native effect with no levels
  draws nothing either way. What settled it was dumping the two rasters `WMPMainView.present`
  receives and reading the overlay's alpha over the effects rect — opaque white.
  `WMPAlignmentTests.testAPlainColourContainerGroundsItsNegativeZIndexChildren` pins it.
- **A hidden element still has a place, and the extent a binding gives it is not a baseline
  (W226).** Two more steps along the same read, both found by measuring `Compact`'s visualizer at
  two window sizes. **First: the walk returns on an invisible node before recording a geometry**, so
  `parseDimension` had nothing to answer a `wmpprop:` read from and fell through to the markup —
  which is the size the window was *born* at, not the size it has been dragged to. `Compact` sizes
  its vis pane with `<subview id="svVisual" height="wmpprop:video1.height">` and `video1` is
  `visible="false"` for the whole of audio playback, so stretching the window grew the pane's width
  and left its height at the authored 240. WMP lays hidden elements out and answers the read from
  its live object model; so does this, for a hidden node **some other node actually binds a
  coordinate off** (`geometryBindingTargets`) and no other — measured only, with no paint, no hit
  target, no widget, no children and no entry in the resolved or unresolved tallies. **Second: the
  alignment baseline must not read the resize back as if it were authored.** `ownAuthoredSize` takes
  the geometry overrides because W225's rule says a container a *handler* sized is a baseline — but
  `WMPScriptRuntime` writes an override for a script assignment *and* for its own re-evaluation of
  an authored expression or binding, and the second is only this canvas's answer echoed back. With
  the pane reading 462 on both sides of the subtraction, every child's delta was zero and the strip
  under the visualizer froze at its authored `top` while the pane grew around it.
  `WMPSceneBuilder.authoredDimension` takes an override only when `overrides.scriptAssignedGeometry`
  says a handler wrote it. `jscript:` attributes are untouched — the static resolver evaluates them
  at the current canvas, which is the number `parseDimension` already had. Corpus-wide the render
  sweep is byte-identical (706 invariant lines, 553 PNGs, the one differing being `Scooby-Doo_2`'s
  random picture again). Reported as "when you stretch the window the visualization does not follow
  the stretch"; `WMPAlignmentTests` pins all four halves, including the two counter-cases — a hidden
  node nobody binds to is still not measured, and a script-assigned extent is still a baseline.
- **A `windowed="true"` `<EFFECTS>` is a real child window: nothing the skin paints goes over it
  (W144).** This is the *other* answer to the occlusion question the entry below settles for the
  windowless case, and the two are opposite on purpose — which is why 106 corpus skins say
  `windowed="false"` and only 17 say `true` (18 nodes; absent on 52 nodes / 46 skins, and absent
  means windowless). A windowless surface is composited into the artwork at its own place in the
  paint order and the skin draws over it deliberately; a windowed one is an HWND in WMP and cannot
  be layered on at all. `WMPScene.windowedEffectsRects` is cleared out of the overlay raster after
  it is drawn. **Three near-misses are worth not repeating.** It is not z-order — `cerulean` is the
  counter-evidence and holds per-parent ordering down; it is not "drop the overlay", because the
  surface is transparent while idle *and* the artwork must still draw outside the rect; and it is
  not "make the surface opaque", because a stopped player draws no visualization and what belongs
  in the hole is whatever the skin painted **before** the effects node. `xsn_sports` retracts its
  settings drawers to a resting place 26px (`visView`) and 108px (`videoView`) inside the effects
  rect and relies on the surface to hide them; reported as the drawer's contents showing through the
  video window while shut. `WMPEffectsOcclusionTests` pins both sides.
- **An authored `JScript:` geometry expression re-applies only when its own value changes (W144).**
  It is re-evaluated every transaction — that is what makes `top="jscript:view.height-123"` follow a
  resize — and committing it unconditionally put it **ahead of the mutations**, so any transaction
  whose handlers did not touch the node snapped the node back to its authored place. **Any view with
  an `onTimer` therefore undid its own script within one tick**: `xsn_sports` slides its drawers with
  `visDrawer.moveTo(0, view.height-73, 400)` against `timerInterval="500"`, and half a second after
  every click the drawer was back where the markup put it. Reported as "it still does not open".
  Comparing against the value the expression last produced was the first form of this rule and it
  is **superseded by W159 below**: an expression never takes back an address the script has written,
  changed value or not.
  This is the same distinction `WMPScriptRuntime.assignedViewSize` already drew for the root: an
  expression that re-resolves is a layout reading the current size, not a fresh request. **A plain
  render sweep cannot see this class** — it renders one transaction per view, and base-vs-change came
  out identical either side of the fix. `WMP_RENDER_SETTLE` is the instrument.
- **A script assignment retires the authored expression for that address, and alignment is what
  carries the value forward (W159).** Two halves, and the second is not optional. `WMPScriptRuntime`
  keeps the geometry addresses a script wrote (with the **canvas each was written at**) and skips the
  authored `jscript:` expression for them — in `WMPScriptContext.resolveExpressions` too, or the
  dependants go on resolving against a value nothing draws. `WMPSceneBuilder` then treats such an
  address as a literal for `right`/`bottom`/`stretch` and re-anchors it by the growth **since the
  assignment**, never since the authored size. Reported on `NVIDIA`: `setModesMinWidth('playlist')`
  writes `mainModeMetadata.width = view.width-266` while the view is still 285 — the number is 19 —
  and resizes the view in the same handler, so `width="jscript:view.width-101"` answered 629 on the
  next transaction and took the property back; the bar drew 119 px past the window's right edge and
  the time readout on `jscript:mainModeMetadata.width-80` went off-window entirely. With the rule the
  bar is the script's 464 (19 + the 445 the view grew) and the digits sit where audio mode puts them.
  **Reach: 18 of 180 archives, 86 element/property pairs.** Both halves were found by corpus A/B, not
  by reasoning: retiring alone froze `xsn_sports`'s drawer floating in the middle of `visView`, and
  anchoring at the *authored* size instead of the assignment slid open 15 default-state panels
  (`Catwoman`'s video settings, the Alienware/ALX `videoView` family, `Scooby-Doo_2`'s info panel).
  The 13 views that legitimately change are the same defect being fixed — `Catwoman`'s `onLoadVid`
  calls `toggleVidDrawer('0')`, so its drawer is *meant* to be out. `WMPAlignmentTests` and
  `WMPScriptRuntimeTests` pin the two halves.
- **`onClose` is a view's last transaction, and it is where a `.wmz` saves its state (W144).** It had
  **no dispatch site at all**: `discardView` dropped the view's scope and its live elements and the
  handler never ran, so **373 `onClose` handlers across 133 of the 180 archives** were dead. What
  they do is persist — `xsn_sports` writes `visDrawerStatus` and its own view size through
  `theme.savePreference` and restores both in `onLoad`, branching on the `--` absent sentinel, so
  with nothing ever saved its settings drawer opened itself on every single launch and no window
  remembered its size. The transaction runs **before** `discardView`, because the handler needs the
  view's elements and the skin's globals, and it renders nothing: the window is already gone.
  **Quitting is a close too**, and `applicationWillTerminate` returns and the process exits, so the
  `Task` an ordinary close posts never runs — `flushCloseHandlersOnTermination` runs the same
  transaction for every open view and waits for it, which is safe only because nothing on the script
  path touches `MainActor`.
- **A number a script writes must reach the drawing, and `<TEXT>` is where it did not (W114).**
  `WMPSceneBuilder.literal(_:_:)` reads the attribute and nothing else — geometry has
  `parseDimension` and a slider has `sliderMetrics`, and the rest had nothing. `Cablemusic` lays its
  readouts out with `txtShowLabel.fontSize = 7` over a markup that says `fontSize="10"`, so every
  label was measured *and* drawn three points too large and "Copyright:" ran out of its 55 px box
  and off the left edge of the LCD it belongs in. `literalNumber` is the override-aware resolver;
  `fontSize`, `scrollingDelay` and `scrollingAmount` go through it, as does the intrinsic text size.
  The object-model half is the same rule: `justification`, `fontFace`, `fontStyle` and `fontSize`
  are **rendered**, so a write to one has to commit as a mutation rather than be stored inert, and
  each was only reaching the scene when the markup happened to author the same attribute.
- **A `fontSize` is points at 96 dpi, not skin pixels (2026-09-25).** GDI draws 7 pt as 9.33 px, and
  the engine used the number as a CoreText pixel size, so every `<TEXT>` in the corpus drew at three
  quarters of its size — reported as "the fonts are small in general". `WMPTextMetrics.pixelSize` is
  the one conversion, applied in `WMPTextMetrics.font` (so drawing, `textWidth` and the intrinsic
  text size agree) and wherever `fontSize` is used as a distance (the renderer's baseline, the
  line-height floor). **Checked against the Internet Archive's reference captures, not reasoned**:
  `xXx_night_vision_redx`'s Tahoma 7 metadata caps measure 7 px there, 5.5 before, 7.5 after;
  `WoW`'s Arial 11 `00:00` digits 11 px there, ~8 before. The collection's per-skin PNGs
  (`archive.org/download/windowsmediaplayerskinscollection/<skin>.png`) are real-WMP ground truth for
  any size question — read the skin's own state first, since most show a stopped player. Every
  corpus image containing text moves with this rule; that is the rule, not collateral.
- **A face the skin ships is loaded from the archive (W304).** `WMPSkinFonts.register` runs in
  `WMPSkinLoader` off the main thread and registers each `.ttf`/`.otf` entry for the process, so
  `CTFontCreateWithName` finds the family by name — `Alpine7618_v09`'s `fontFace="Quartz"` drew in
  Helvetica before, wider than the LCD it was laid out for. **A family already installed is never
  registered over**: a skin must not change what `Arial` means to another window or skin family.
  Registrations are never undone; a second load of the same PostScript name is a no-op. Reach: 1 of
  180 installed archives ships a font (2026-09-25).
- **An element's own artwork is drawn at its own size, and the box it does not fill is left to
  whatever is under it (W122).** WMP never scales a `<BUTTON>`'s `image` to the authored frame, and
  a skin that swaps that image from script is written against exactly that: **563 script `.image`
  assignments across 51 of the 180 archives**, of which **23 paint a clock out of digit strips**
  (`drawSeekDigits` / `DrawTimeNormalView`) and **6 give the digit a frame wider than the digit**.
  The ALX/Alienware readout is four `<BUTTON>`s authored the width of a *ten-digit strip* —
  `time1.png` is 250x23 — each inside a 25 px `<SUBVIEW>` that clips it to the first cell, and
  `drawSeekDigits()` then assigns a single 25x23 `time1_<n>.gif` per tick. Scaling that to the 250 px
  frame drew one tenth of one digit blown up ten times: reported as "in all the alien type skins the
  numeric display is illegible". `WMPSceneBuilder` clamps the foreground image command to the
  artwork's natural size, anchored at the frame's top-left, so the smaller bitmap lands where the
  strip's first cell did and the parent's clip is unchanged. **Only the foreground image takes the
  rule** — `backgroundImage` still fills its frame, because a `stretch`-aligned subview grows with a
  resizable window and its background is what covers the delta (`LostPlanet`, in the counter-evidence
  table). **A default-state sweep cannot see the defect and can see the collateral**, which is what
  makes it worth running: the strip *is* the frame until a script swaps it, and `drawSeekDigits()`
  returns early on an empty playlist, so the 545-image corpus capture moved **16 images, none of them
  a clock** — every one an oversized bitmap that had been upscaled and is now crisp (`portals/mode2`,
  the five `US …` `videoUSM` logos, `tubeframe`, `Ice/mainView`), one nondeterministic
  (`Scooby-Doo_2`), and `Ice/videoView`, which draws
  `Pl-xp.bmp` as a 196x44 button inside a subview that still stretches the *same* bitmap to 313x144
  (W123 read that as a seam; live on 2026-09-25 there is none).
- **A subview's background art larger than its box stops at the box (W283).** A background
  bitmap on a non-`stretch`, non-tiled axis draws at its own size (the `Ice` corner rule in
  `WMPSceneBuilder`), and overflowing art used to be trimmed only by the *parent's* clip. A subview
  is a window region: its own frame now clips its background wherever the art is larger than the
  box. `Asimov_Radio` closes its video drawer by sizing `splView` to 255 over a 436-tall
  `vid_screen.bmp` (and opens it to 470), and the closed half drew as a granite slab behind the
  whole head. **Gated on overflow**: clipping a background that exactly fills a fractional box put
  antialiased one-pixel seams in 70 images across 36 skins; gated, the sweep moved 4 images —
  Asimov plus a stray overflow line or speck leaving `Plus! SlimLine`, `Television` and `Gold`.
  `Ice`, whose corner relies on overflow, did not move.
- **A `<VIDEO>` box shrinks the picture to fit by default and never enlarges it (W102).** The two
  fit flags are independent and neither means crop or fill: `shrinkToFit` governs the picture being
  *reduced*, `stretchToFit` its being *enlarged*, and `maintainAspectRatio` (default true) decides
  whether the two axes scale together. **`shrinkToFit` defaults to true and `stretchToFit` to
  false**, which is not symmetry for its own sake — it is what the corpus is authored against.
  **77 of the 97 sized `<VIDEO>` elements declare no `shrinkToFit` at all and 73 of those are boxes
  under 640x480** (`Heart_Butterfly` is 89x130, `Creed` 131x88, `Cablemusic` 341x215), and **not one
  archive anywhere authors `shrinkToFit="false"`** while 19 author `stretchToFit="true"` and one
  `"false"`. Defaulting the shrink flag off therefore drew every unattributed box at the stream's
  native pixel size, centred and clipped to the middle sliver of a 1080p frame — reported as "the
  video opens at full resolution instead of scaled to the window". The corresponding read defaults
  in `WMPObjectModel` are the same three values, because a skin that reads back a flag it never
  authored must be told what is actually on screen. **This is not `mediacenter.videoShrinkToFit`**,
  which is a different object with its own defaults in `reference/object-model.md`.
- **The picture is lent to the skin as a *child window*, and `isVideoOutputHosted` is our flag while
  being a child is AppKit's fact — they drift apart (W102).** A child window is the isolation that
  makes hosting work at all: VLCKit installs its own output view and sizes that view's *ancestors*,
  so moving `videoPlayerView` into the skin's tree runs the skin's content view away by tens of
  thousands of pixels, while `addChildWindow` keeps a separate layout tree glued to the skin. The
  trap is that the link can go without the flag changing, and `hostOutputWindow` re-parents only when
  `!isVideoOutputHosted`, so nothing puts it back. **Three symptoms that read as three bugs are this
  one cause**: the picture goes black while the audio plays and seeking still works (it fell *behind*
  the skin — a real child window cannot); it lags out of the window frame on a drag (the 10 Hz
  reposition trailing a tick behind); and switching apps fixes it (activation re-collects children).
  `WMPVideoSurface.update` re-asserts the relationship every tick and traces `video reparented` /
  `video reordered above parent` — **if those fire continuously rather than once per incident, the
  repair is masking a call site that keeps breaking the link, and that is the thing to fix.** Suspect
  anything that orders the parked window out: on macOS that drops its parent relationship.
- **Video readiness has two consumers and they need different truths (W124).** `WMPHostSnapshot.video`
  is the live drawable state: when VLC drops `hasVideoOut` or `videoSize` during a same-media vout
  rebuild, it must become empty so `WMPVideoSurface` detaches the child window and releases mouse
  capture. `WMPHostSnapshot.videoEvent` is the last valid state for `videostart`/`videoend` edges,
  latched by media identity and cleared by a media change or `didReachEndOfMedia`. Feeding the
  latched event state back through `video` kept the child window over the skin and made buttons look
  globally dead when the track panel had pointer capture. Test the split state: output teardown
  produces no `videoend`, the surface detaches, and a genuine media end still produces exactly one.
- **A video's natural end is not a manual Next press.** `WindowManager.videoTrackDidFinish`
  routes WMP completion to `AudioEngine.wmpVideoTrackDidFinish`, which shares the audio engine's
  natural-end repeat/shuffle/queue-exhaustion rules without running audio reporters or gapless
  promotion. Manual `next()` wraps unconditionally; using it at EOF looped a one-video playlist
  forever with repeat off. Keep the new callback gated to `.wmp`. Verified live on 2026-09-10 with
  Corona and a 6.29-second local video: EOF stopped playback, and a subsequent Play click replayed
  it and stopped again.
- **A paused film reports no time, and in `.wmz` mode that was the only thing refreshing the host
  (W102).** `videoDidUpdateTime` is driven by VLC's time-changed callback, so a pause silenced the
  whole host tick and the skin went on drawing *and hit-testing* a pause button. What that costs is
  not a stale glyph: the next click's `mousedown` triggers the rebuild that finally sees `paused`,
  the button under the pointer is swapped mid-gesture, and `WMPMainView.mouseUp`'s
  `result.activated == capturedTarget.stableID` guard drops the click — **the click is destroyed by
  the state change it triggered**, reported as "play then pause then play just breaks it".
  `videoDidChangePlaybackState` closes it, gated to the WMP family. **The general rule this leaves:
  any state a skin hit-tests against must be pushed when it changes, never sampled on the next
  rebuild** — a rebuild driven by the very gesture that needs the old geometry will always eat that
  gesture.
- **A text baseline may never sit higher than the face's own ascent (W114).** The rule was
  `max(fontSize, (height + fontSize) / 2)` measured from the box's bottom — fine while every
  `<TEXT>` had a generously tall authored box, and four pixels *above* the box once a text is sized
  by its own glyphs. `CTFontGetAscent` is the floor. It moves nothing that was already inside its
  box and 142 corpus images where text was drawing over the artwork above it.
- **A call that lands its endpoint completes in the same transaction, and a skin's sequence is
  chained from that completion (W55).** *Superseded in one direction by W194 above: under a frame
  clock the completion is raised when the tween ends instead, and everything below still describes
  the headless path and the mechanism both share.* `moveTo`/`alphaBlendTo` have applied their
  endpoint immediately since W38, so the step that follows was the missing half: `onEndMove` is 247 uses
  across 113 archives, `onEndAlphaBlend` 50 / 21, and **`onEndResize` is zero, so it is deliberately
  not implemented.** `WMPScriptContext.raiseCompletionHandlers` raises them before the geometry
  cascade, bounded and once per `(element, event)`. **The template Microsoft shipped is built out of
  this**: `toggleVidDrawer()` slides the drawer and `onEndMove="checkVidDrawer()"` is the only thing
  that shows or hides its contents, so without it 36 corpus views drew a drawer's controls stranded
  outside a drawer that had already slid shut — and seven views (the `US …` military family,
  `Secura`, `Stars and Stripes`) drew a closed shell with no player in it at all. **Landing this
  removes an accidental compensation, so budget for what it uncovers**: where a drawer fails to open
  for an unrelated reason, the user now sees an empty drawer rather than usable controls in the
  wrong place. `onDragEnd` is the input-side sibling, raised from `WMPMainView.mouseUp` for a
  captured slider, and it is one of the two places a seek commits — see W156 above for the other and
  for how the engine chooses between them. See `reference/object-model.md` § *Methods*, and
  `reference/harness.md` for why an image-only sweep cannot see any of it.
- **A `<TEXT>`'s own artwork is its glyphs, and a `<BUTTONGROUP>`'s is its mapping image.** Every
  other node falls back to the natural size of its `backgroundImage`; these two have none, and both
  were the largest starvation classes in the corpus. **1,441 `<TEXT>` nodes across 127 of the 179
  archives** resolved no size — 1,058 of them missing width *and* height — because WMP sizes a text
  from the face and the string and a skin therefore never states it: `Cablemusic`'s script lays out
  ten readouts with `txtShow.top/left/width/fontSize` and no `height`, so the whole
  show/clip/author/copyright block never drew and the report was "there is no track display". A
  width measured from the *current* value is WMP's own behaviour — the box grows with the string, an
  empty value is honestly zero-wide, and it starts drawing on the transaction that gives it one.
  **31 `<BUTTONGROUP>`s across 16 skins** resolved no size for the mirror reason: the group's normal
  state is the window's own background artwork, so the skin authors no `image` and no geometry at
  all, and with no frame the group registered no hit target — every control in it dead while the
  artwork beneath still drew the buttons. `Cablemusic`'s presets, stop, close, minimize, next and
  previous effect, shrink, bandwidth and all three drawer tabs are one such group each: "most
  buttons don't work". The mapping image is definitionally the group's own pixel grid.
- **An attribute authored with an empty value is not an attribute, and for geometry it never was
  one** (W241). `<attr>=""` is authored **970 times across 135 of the 182 measured archives**, and
  the engine's every "did the skin state this dimension?" test is `attribute(named:) == nil` — so a
  present-but-empty `height` closed the intrinsic-size gate that an *absent* `height` opens, and
  the node resolved no size and was never painted. `Beck` authors `height=""` on each of its ten
  `eq1`…`eq10` bands over a real `foregroundImage`, and its equalizer tray drew ten empty slots.
  Ask the statedness question through `WMPNode.statedAttribute(named:)`, never
  `attribute(named:)`, anywhere a missing attribute has an ambient default — 0 for an origin, the
  artwork's own size for an extent.
  **Three things this rule is not.** It is not a coercion of `""` to zero: a zero-height slider is
  as invisible as an unresolved one, so that closes the row and changes no pixel. It is not for
  strings, handlers or colours — `tooltip=""` (299 uses) and `value=""` (101) are authored absences
  that already behave correctly, and widening it there makes 970 the blast radius instead of the
  denominator. And it is not the resource path, which implements the rule for itself:
  `WMPArchive.resolve` returns nil for an empty path, so `backgroundImage=""` already falls through
  to the `foregroundImage` behind it. See `reference/harness.md` § *The empty-value class*.
- **A geometry value the grammar cannot read is unstated too, and for extents only** (W240). W241's
  rule one step out: `XBOX`'s `xLogo` authors `width="jsa:centerBox.width"` where the `<video>` two
  lines above it in the same container writes `jscript:` — a typo WMP cannot parse either, so WMP
  falls back to the ambient default and draws the logo at `x_logo.jpg`'s own size, while the gate
  here saw a *stated* width and drew nothing. `WMPInitialLayoutResolver.Resolution.unresolved`
  carries `interpretable:` and the parser's own failures come back `false`; a **dependency**
  failure — unknown object, cycle, depth, a reference whose target failed — stays `true`, because a
  script may still satisfy it and stamping a bitmap over one is the `corona`/`svVideo` regression.
  **Extents only, and that boundary is the point**: an origin has no content-derived default, so an
  unreadable `left` stays a rejection and `left="JScript:danger();"` is still refused rather than
  drawn at 0. `jsa:` is **not** a dialect to implement — answering a typo the way WMP answers it is
  not the same as matching it, exactly as with `scrollingAmmount`. **The row was ranked on
  `33 of 458` unresolved nodes carrying a bitmap and was really one node**: 13 of 16 name a bitmap
  that cannot resolve, two more clear their own artwork from script, and the 33 was an empty `bg=`
  field captured by a loose pattern. See `reference/harness.md` § *The residue is a size fallback*.
- **`STATUSTEXT` and `CURRENTPOSITIONTEXT` are text controls with native WMP values, not unknown
  tags.** Model them as text for intrinsic sizing and paint; synthesize the latter's value from
  `player.controls.currentPositionString`. WMP right-aligns an otherwise-unqualified
  `CURRENTPOSITIONTEXT`, because it is normally the trailing cell beside a scrolling title.
  Cerulean exposed both requirements: omitting the tag removed its clock, and left alignment made
  the clock touch the title. `DURATIONTEXT` is the other half of the same clock and takes the same
  default. **An authored `justification="left"` must be named, not left to the default** — the
  default is `right` for these two tags, so a missing `left` case drew `pharaoh`'s
  `justification="Left"` duration flush right, 30 px clear of its `/` (W203).
- **An origin the markup never stated can still have been written by script, and asking the markup
  first meant it never was.** `left`/`top` default to 0 when unauthored — but the check was
  `attribute == nil ? 0 : resolve`, which short-circuited *before* `parseDimension` could look in
  the scene overrides. Size never had the bug, so a script-positioned element came out the right
  size in the wrong place: `Cablemusic`'s two drawers are seventeen station rows each, laid out
  entirely by `InitPrograms()` writing `pr<N>.top`/`.left`, and all thirty-four drew on top of one
  another in the corner of the drawer. Overrides first, then the markup, then the default.
- **WMP spells every transport control twice, and only one half of each pair was ever a kind.**
  `<…ELEMENT>` is a `BUTTONELEMENT` subtype — a colour region of a `BUTTONGROUP`'s mapping image —
  and `<…BUTTON>` is a `BUTTON` subtype with its own artwork and frame. `WMPElementKind` had
  `playElement` but no `playButton`, `pauseButton` but no `pauseElement`, and so on, so half the
  vocabulary fell to `.unknown`: **`PAUSEELEMENT` 80 uses / 69 skins, `PLAYBUTTON` 50 / 45,
  `PREVBUTTON` 50 / 45, `NEXTBUTTON` 49 / 44, `STOPBUTTON` 48 / 42, `MUTEBUTTON` 10 / 9,
  `REPEATBUTTON` 5 / 4.** An unknown kind still paints its `image` and is not interactive, so the
  button **drew and did nothing** and the pointer fell through to whatever overlapped it —
  `WMP_RENDER_CLICK` on `Cablemusic`'s play button answered `hit=ffw`. `MUTEELEMENT`,
  `REPEATELEMENT`, `SHUFFLEELEMENT` and `RETURNELEMENT` are zero in the corpus and are deliberately
  absent: a kind nothing authors is a phantom. The `*ELEMENT` half is `isNonLayout` — but keyed on
  **`mappingColor` under a `BUTTONGROUP`**, not on the kind and not on the attribute alone;
  `polygon` puts a `mappingColor` on a `<SUBVIEW>` with real geometry as a self-mask.
- **A `BUTTONGROUP`'s state artwork is a sheet the size of the whole group, and it is only ever
  painted through the group's mapping mask (W116).** `hoverImage`/`downImage` are the *entire*
  player redrawn with one control lit, and the mask cuts out the region the pointer is over. The
  normal `image` used to be **required** for any of that to happen, so a group that authors none —
  its normal state being the window's own background artwork — fell through to the generic
  single-image path and painted the whole sheet over the window. `Cablemusic`'s is a 593x600 bitmap
  with a dark green surround, so hovering any button in any of its six groups covered the entire
  player: reported as "when you mouse over the compact button there is a huge overlay". The normal
  artwork is now optional and only the mask is required; with no `image` there is nothing to draw
  *under* the lit region, which is correct, because what is under it is the window. **No corpus
  sweep can see this class** — a default-state capture never enters a hover or a down state (W73),
  and the 535-image sweep across this fix is byte-identical. `WMP_RENDER_HOVER` and
  `WMP_RENDER_CLICK` are what measure it.
- **A fix that makes dead code reachable is where a latent trap fires.** Sizing a `BUTTONGROUP` from
  its mapping image reached, for the first time on `Cablemusic`, a
  `Dictionary(uniqueKeysWithValues:)` over the group's `mappingColor`s — and that skin authors
  `bnpb6` and `bnpb7` both as `#00C0FF`, one preset too many for the eight regions its `map.gif`
  has. A dead control became a **crash on load**. WMP takes the first and draws it; so does this.
  **It fired twice**: the same row also made the unmasked state-sheet paint above reachable, and
  that one was invisible to every headless probe. Budget for both shapes whenever a row turns a
  whole class of nodes from unresolved into drawn.
- **A `<TEXT>` is a box, the clip is horizontal, and `scrolling` is what a skin turns on when the
  value overflows it (W94).** Drawing text unclipped let `WoW`'s 77x30 `metadata` readout paint
  "- AC/DC - Shoot to Thrill / Playing" straight across the player's buttons. Three things had to
  land together, and any one alone does nothing: the clip, a marquee driven off the render clock
  with `scrollingDelay`/`scrollingAmount`, and a **measured** `textWidth` on the object model,
  because the skin decides for itself with `metadata.scrolling = (metadata.textWidth >
  metadata.width)` and an answer of 0 says the string fits. `scrolling` is 358 uses across 114 of
  180 archives. **The vertical half of the clip is deliberately left open**: a skin routinely
  authors a row of links shorter than their own line box — `v2_underworld`'s About page is eight of
  them — and this engine's baseline comes from `fontSize` rather than the face's real metrics, so
  clipping to the authored height shaved those to a sliver. Cut the overflow that is measured;
  leave the one that is not. A scrolling text also contributes to `animationCadence`, endlessly and
  bounded to its own box — it is the only animation a skin turns on from script rather than by
  naming a GIF.
- **An unanswerable `wmpprop:` is not the answer "false", and on `visible` that distinction is a
  whole control (W95).** A path can name a *host* property (`eq.enhancedAudio`) or an *element in
  the skin's own graph* (`plMode.visible`); 1,459 of the corpus's uses resolve to neither today, and
  the registry answered every one with a falsy empty string. The builder deletes a node whose
  `visible` override is false, so `WoW`'s `<PLAYLIST visible="wmpprop:plMode.visible">` — `plMode`
  being a name WMP's own UI owns and this skin never declares — had no paint command, no hosted
  widget and no rows, however many tracks were queued. Reported as "adding to the playlist does not
  work". The rule now has three cases and they were arrived at one sweep each:
  **a host root this engine does not implement stays falsy** (`xsn_sports` hangs its whole SRS WOW
  panel off `visible="wmpprop:eq.enhancedAudio"`, and showing the badge would claim a feature that
  does nothing); **an element the skin *does* declare is mirrored** by `WMPSceneBuilder`, one hop,
  which is what keeps `WoW`'s CD-rip bar hidden behind `wmpprop:playlist2.visible` (150 corpus uses
  of `visible="wmpprop:…"`); **an element it does not declare answers nothing**, leaving the markup's
  own value. Only `visible` declines to default — on every other property the empty string is the
  honest answer, and `wmpenabled:` still disables.
- **A node the script shows is drawn inside a hidden container (W263).** Markup inherits: a
  default-visible child of a `visible="false"` subview stays hidden (2,630 corpus children rely on
  it). An explicit script write of `visible = true` is the node's own answer, though, and the walk
  passes through a hidden ancestor to reach it — the ancestor paints nothing, hits nothing, and
  every child the script did not show stays hidden (`passThroughAncestors` in `WMPSceneBuilder`).
  **Only a show that changes the node's answer counts (W308)**: the node must author a `visible`
  that is not `true` (`"false"`, or a binding). `Gorillaz` writes `vis.visible = true` on a button
  that was never hidden when its left drawer opens, then closes the drawer by hiding `left_ear11`,
  the frame around it; read as an escape, the button floated beside the shut drawer. Blocking at an
  authored-hidden *container* instead is wrong — `US Army`'s Help lives in `help`, authored hidden
  and never shown, and emptied. Every pass-through the corpus needs is an authored-hidden node.
  **And never out of a pane the skin itself closed (W309)**: an ancestor authored hidden that a
  script has shown this session (`WMPSceneOverrides.scriptShown`) and has hidden again closes its
  whole subtree (`closesSubtree`). `US Army`'s `hideinfomode()` hides `infomode` and in the same
  handler sets `infodown2.visible = true` on a scroll arrow inside it; `sflink` sits inside
  `creditsmask`, closed the same way. Both stayed on the face after Info closed. `help`/`credits`
  (never shown) and `Charlies_Angels`' `pos` (authored visible) are not toggles by this rule.
  **Nor out of a pane hidden *after* the show (W311)**: `WMPSceneOverrides.visibleWriteOrder`
  records when each node's `visible` last changed by script, and a shown node escapes only the
  hidden ancestors a script hid before it was shown (an ancestor no script hid counts as before).
  `Navigator`'s `movescren()` shows `vis` inside the authored-visible `visual`, and its
  `showconf()`/`showlist()`/`showlink()` hide `visual` afterwards; read as an escape, the
  visualizer drew over the EQ, playlist and links panes. `Charlies_Angels` is the other order —
  `pos` hidden, then `boxsmall` shown — and still escapes. Only a change of value takes a
  position, so a skin that rewrites the same `visible` on a timer does not reorder anything.
  `Charlies_Angels_Full_Throttle` nests its whole face in `pos`; Gallery hides `pos` and shows
  `boxsmall` (the cut-down face), the wings and the pictures inside it, and the window went empty
  with no way back (Speaker Mode is in a wing). `Stars and Stripes` and its five US-forces siblings
  show Help/Credits text inside `help`/`credits`, which are authored hidden and never shown.
  **A binding's `true` is not a script show (W301).** `wmpprop:`/`wmpenabled:` values land in the
  same `overrides.properties` as script writes, so `WMPSceneOverrides.boundProperties` records which
  addresses a binding wrote last, and a script write clears the mark. Without it
  `visible="wmpenabled:player.controls.pause"` (60 corpus uses) and `…stop` (10) escaped a closed
  panel the moment playback enabled them: `Alpine7618_v09`'s panel visualizer floated over its
  window's transparent top half. A before/after sweep with a playing host over the 50 archives that
  bind `visible` to the player moved 5 skins, each a stray control from a closed panel: `Alpine`,
  `Melvin` (two pause glyphs, from `lefthi` and `little`), `Secura` (the `video` panel's pause over the
  face's stop button), `Creed` (`visual`'s visualizer) and `Charlies_Angels_Full_Throttle`
  (`boxsmall`'s pause in the normal player; it still draws in Gallery, where the script shows
  `boxsmall`).
- **`visible` is not a `<VIEW>` attribute (W281).** The root's authored `visible="false"` is
  ignored; a script override still applies. `gnome` is the only corpus view that authors it, never
  shows itself from script, and loads in WMP — honouring it drew 0 nodes and an empty window.
  **This is not proven WMP behaviour and the corpus argues both ways** — `portals` and
  `modernblue` also show children inside closed containers (a pane choice in a shut tray, a play
  button on a hidden compact face) where inheritance is what the skin wants. The before/after sweep
  moved 3 of 529 images (`portals/mode1`, `modernblue/myview`, `US Army/MainPlayer`); the reporter
  reviewed all three and accepted them, the one visible cost being W264. Most of this pattern fires
  only on a click or play-state change, so a clean load-time sweep does not clear it — check a
  reported stray pane against this rule first.
- **A panel opened with `theme.openView` is not the session's view (W96).** `apply` persisted
  `wmpSkinViewID` on every present, so quitting with a playlist open recorded the playlist; the
  covered view was not persisted, so the next launch restored a panel with no player and no route
  back to one. Reported as "the skin is empty and shows no player or skin windows", and it stranded
  any skin whose panels are `openView` rather than `currentViewID`. Only **the player's own
  presentation** writes the key — a simpler statement of the same rule the `openedViewStack.isEmpty`
  test was making, and one that stops being a special case once the panel has a window of its own.
  The panels themselves are persisted separately (`WMPViewFrameStore.openViews`, plus a per-view
  origin) and restored *before* the load transaction's host commands, so a dispatcher skin that
  re-opens its own panels from `theme.loadPreference` raises the restored window rather than opening
  a second one.
- **An `<EFFECTS>` rect is never shaped by this engine. The skin's own artwork occludes it, through
  plain z-order (W139).** The earlier form of this rule forbade turning "image overlap, z-order,
  alpha, or an artwork's transparent bounds into effects geometry" and named Cerulean and
  Plus! Professional as counter-evidence. **They are the clearest evidence for it, and the rule was
  backwards** — it is why an inscribed-circle clip was invented in place of the occlusion the markup
  already declares. What is still true is the half it was built on: do not *derive a mask* from a
  sibling bitmap, and `clippingColor` applies to a `clippingImage` and not to arbitrary nearby art.
  What was wrong is that z-order is not a derivation at all; it is what the markup says.

  Cerulean, measured from the archive: `face.bmp` has a magenta (`#FF00FF`) hole of 4,264 px over
  x 133..205, y 35..107 — a 73px circle against an ideal 4,185 — and the subview that draws it keys
  that colour out. Inside it, `<effects zIndex="-1" width="103" height="75">` and
  `<button id="bEye" zIndex="-2">`. **A negative `zIndex` means behind the subview's own
  `backgroundImage`.** Back to front: the eye disc, the visualizer filling its full 103×75 rect, then
  `face.bmp` with a hole in it — which is why the brass bezel and all eight rivets survive.
  Plus! Professional is the same mechanism with a tilted oval (`vis_mask_w.png` inside
  `<subview id="visMask" clippingColor="#ff00ff">`). **32 `<EFFECTS>` across 30 skins author a
  negative zIndex**, and no per-skin code renders any of them.
  **Only artwork with a hole has a behind (W310).** A `backgroundImage` with no `transparencyColor`,
  `clippingColor` or `clippingImage` is opaque everywhere, so its negative-`zIndex` children draw
  over it in `zIndex` order (`artworkHasNoHole` in `WMPSceneBuilder`) — the same answer a plain
  `backgroundColor` already gets. `Navigator`'s `config` pane paints the unkeyed `screenback.bmp`
  over its EQ, links, playlist and video-settings panes, all `zIndex="-2"`, and none of them could
  ever be seen. Three containers in the corpus have this shape (an XML scan of every
  `<VIEW>`/`<SUBVIEW>`); `tubeframe`'s two render byte-identical either way.

  How it is hosted: **a node's negative-`zIndex` children are walked before it emits its own paints**
  — DFS order cannot express "behind the parent's background" on its own, and getting this wrong is
  what drew Cerulean's bars across the whole face on the first attempt. `WMPWidget.commandSplitIndex`
  then records the index into `WMPScene.commands` the walk had reached when the widget's node was
  visited, `WMPRenderer` rasterizes the scene as two images
  either side of it, and `WMPMainView` hosts the effects surface between them —
  `WMPEffectsSurfaceView` → the "above" overlay `NSImageView` → the interactive widgets, re-enforced
  on every `synchronizeWidgetViews` pass because a plain `addSubview` goes to absolute top. **The
  split is an index and not a zIndex threshold**: `WMPSceneBuilder.walk` sorts only siblings, so
  `commands` is DFS order and a `zIndex = -5` node in one subtree can legitimately follow a
  `zIndex = 10` node in another. `WMPImageStore.clippingMask(for:keyedOut:)` and `WMPColorKey` then
  apply to the overlay for free — no new masking code exists anywhere for this.

  **With two surfaces, each is covered only by what follows its own split (W302).** The rasters
  are `WMPScene.effectsLayers`, not a cut at one index: a command goes over when it overlaps a
  surface whose split it follows, or overlaps a command already placed over one, which keeps paint
  order among overlapping artwork; a command that touches no surface draws the same from either
  layer. The old rule cut every surface at the earliest split, so everything between two of them
  covered the later one. `Alpine7618_v09` has a 150x26 visualizer in its LCD and a 362x211 one in
  `VisPanel`, declared after it over an opaque black `vis_panel.bmp`, and the open panel showed
  black. **8 corpus views author two `<EFFECTS>`** (`Alpine7618_v09`, `Erektorset`, `Goo`,
  `Science`, `The Unit`/`TheUnit`, `holiday_skin`, `pharaoh`); under `WMP_RENDER_HOST=playing` every
  one draws only one at load, so this changes nothing until a skin opens its second panel. With one
  surface the pixels are the same as the single split (`Erektorset` and `Science` move 1 and 14
  commands that touch no surface into the lower raster).

  **The rect's own background is the one thing the split steps past.** A backdrop declared *on* the
  `<EFFECTS>` node — `backgroundColor="#000000"`, or a `backgroundImage` — is what WMP shows behind
  the visualizer while nothing plays, not artwork over it; with the split taken at the node's visit
  it landed in the overlay and was repainted over the hosted surface every frame, so the rect was a
  solid block for the whole of its skin. Reported against `New Super Mario Bros`, whose viz window
  drew its frame, its buttons and a black hole where the visualizer belongs. Decoded scan of the 178
  readable archives: **6 author an opaque `backgroundColor`** (`New Super Mario Bros`, `Gorillaz`,
  `Primitive`, `Tomb Raider 2`, `MSN`, `robbie`) and **8 a `backgroundImage`** (`XBOX`, both `Xbox`
  official releases, `Ice`, `WWC`, `The Unit`/`TheUnit`, `The_Sentinel_v.1.0`). `WMPSceneBuilder`
  patches `commandSplitIndex` forward once those two emits are done and nothing else — a foreground
  image on the node, its siblings, and the parent's keyed artwork stay in the overlay, so Cerulean,
  which authors no background on its rect at all, keeps the index it always had.

  **Nothing headless can see it.** The render dump flattens both rasters in the same order, so its
  PNG is identical either way, and `WMP_RENDER_APPKIT`'s `differing=` is 0 for *every* skin's
  `<EFFECTS>` because the surface draws nothing without live audio — `WMP_RENDER_HOST=playing` seeds
  a playing snapshot, not a signal. The instrument is the running app with `NULLPLAYER_PLAY` and a
  `screencapture -l <windowid>` of the skin's own visualization window.

  **A skin with no occluding artwork fills its authored rect exactly**: full `width × height`, a
  transparent background, no shape fitting and no aspect letterboxing. Of the 107 `<EFFECTS>` rects
  with numeric dimensions **19 are square, 83 wider than tall and 5 taller**, so a centred `min(w,h)`
  square covered a median 75% of the authored rect and as little as 17% (`Alpine7618_v09`, 150×26),
  and the inscribed circle took ~21% more again.
- **A zero geometry override is a value, not an absence.** Every skin with a store-thumbnail
  `previewView` collapses it in `onLoad` — `view.width = 0; view.height = 0; view.backgroundImage =
  ""; theme.currentViewID = "controlView"` — and Microsoft's own `auto.js` in `Official_Xbox_XP`
  does it with a comment saying so. Discarding a `0` override as "not positive" left 34 corpus
  skins showing a static splash bitmap where the skin had asked for its player.
- **A node draws the artwork a script last gave it, not the one its markup declares.** Images were
  the one property class the script-override path skipped, and `Alienware Invader` — whose whole
  player is behind a 568-frame intro of `mainBack.backgroundImage = "png24/intro_anim_f<N>.png"` —
  drew nothing at all because of it (W75). An override is an authored path string and resolves under
  the same provider rules as markup; one the skin does not contain warns and leaves the authored
  artwork in place; `""` clears the property the way an absent attribute does. The rules and the
  traps are in `reference/object-model.md` § *What a property read answers, and who wins*.
- `WMPSceneBuilder` resolves literal geometry plus the bounded static initial-layout grammar in
  `WMPInitialLayoutExpression`: finite numbers, parentheses, arithmetic, and geometry reads from
  deterministic IDs. `wmpprop:` is accepted only as an alias for that same geometry grammar.
  Calls, assignments, statements, script globals, ambiguous/unknown IDs, cycles, and excessive
  dependency depth stay unresolved *for the scene builder*, which never executes skin code and never
  invents fallback geometry. The general path is the live context in `WMPScriptRuntime`, whose
  resolved values arrive as scene overrides; the static grammar remains the fast, script-free
  evaluator the builder uses before any transaction has run.
- Scene coordinates remain top-left throughout layout, clipping, dirty bounds, hit metadata, and
  paint commands. Core Graphics conversion happens once in `WMPRenderer`; images and text each use
  an explicit counter-transform so pixels and glyphs remain upright.
- The immutable scene owns no `CGImage` or cache state. `WMPImageStore` performs bounded ImageIO
  metadata/decode off-main, supports BMP/GIF/JPEG/PNG, and uses a byte-bounded LRU keyed by canonical
  resource path plus color key.
- **ImageIO is stricter about BMP than Windows is, so a `.bmp` it refuses falls back to
  `WMPBitmapDecoder`** — never to a failure the user sees as a blank skin. Nine of the corpus's
  3,687 bitmaps are rejected by ImageIO alone: eight set `biClrImportant` while `biClrUsed` is zero
  (Windows reads the palette size from `biClrUsed` and treats the other as advisory), and one is a
  BI_RLE8 stream that walks clean and is refused anyway. The fallback runs *only* after ImageIO has
  failed, under the same dimension/pixel/byte bounds, applied before it allocates — an oversized
  bitmap still fails `WMP0034`. Do not "fix" such a file by patching its header, and do not relax a
  limit to admit one.
- **A mapping mask is authored top-left, and the render CTM is y-flipped, so clipping through one
  needs the same counter-flip `drawImage` applies.** `WMPRenderer.clip(to:mask:context:)` owns that;
  it undoes the CTM by hand rather than with `restoreGState`, which would discard the clip too. A
  mask fixture split left/right cannot see this class of bug — split it top/bottom.
- **A node keys out every colour it declares, not one.** `transparencyColor` and `clippingColor` are
  both keys — the second is the colour WMP cuts out of a subview's own artwork to shape it — and a
  subview routinely carries both with *different* values (`Alpine7618_v09` keys `#FF00FF` and
  `#FF0033`). 103 of the 180 archives author clipping attributes, so an engine honouring one key per
  image paints the other as a flat slab over most of the window. `WMPSceneImage.colorKeys` is
  therefore a list, in authored order, and the image-store cache key contains all of it. PNG and
  GIF color keys compare exact un-premultiplied RGB; **BMP keys also match the key's 16-bit
  representations** (W277, narrowed by W282), because the corpus's bitmaps were saved off 16-bit Windows displays and hold the
  key as that display stored it: `YIL!OMA2K` declares `#6699FF` and its `ySpeakers 1.bmp` and
  `jButtonsFlat.bmp` hold `#639CFF`, so an exact compare drew both speakers as blue slabs. Sweep
  (179 archives): 21 images, every changed pixel a matte leaving — `Crystalball` lost four black
  corner patches, `Asimov_Radio` a dark-gold ring round its outline, the rest edge speckle. **W282 narrowed it**: a channel matches the key exactly or as a 16-bit display stores it —
  truncated to 5 bits or bit-replicated — never the whole 5-bit bucket. The bucket also cleared
  channels 0-7 under a black key, and `gnome` paints its face on a flat `(4,4,4)`: 24,000 pixels of
  `gnome3a.bmp` went transparent, which W277's sweep could not see because gnome's view drew nothing
  then (W281). Narrowed, `YIL!OMA2K` keys identically; Crystalball's fringe and Asimov's ring
  return. JPEG keys allow the bounded 64-value
  compression fringe per channel because lossy decoding turns authored `#FF00FF` into a
  blue-channel ramp (W125, Plus! Professional). Preserve the source alpha of every non-matching
  pixel.
- **A container's `backgroundColor` fill and its `backgroundImage` are one layer, and the
  container's keys apply to the composite (W199).** Painting the fill as a bare rectangle under a
  keyed image is two layers, and it fills in every hole the image cuts — the `clippingColor` matte
  *outside* the silhouette, so the window is a slab rather than a shape, and the
  `transparencyColor` hole *inside* it, which on this idiom is **always the visualizer's**.
  `WMPSceneBuilder.backgroundFillMask` emits the fill inside a mask of the node's own artwork keyed
  by both, and `backgroundColor="none"` — 639 corpus containers — already got this by having no
  fill at all. **Both keys, unlike `groundShape`, and the difference is deliberate**: that one
  answers *where the window is* and must never read a hole as a matte (W174, `Plus! BubbleSkin`);
  this one answers *where the composite is opaque*, and there a hole is as transparent as the matte
  around it. The population is **10 nodes in 9 archives** (`Asimov_Radio`, `Nautical`, `anime`,
  `aoe`, `bluegrid`, `cerulean`, `claw`, `gadget`, `pharaoh` twice) and **five of them hang an
  `<EFFECTS zIndex="-1">` under the hole** — `aoe`, `bluegrid`, `claw`, `gadget`, `pharaoh`, each
  rect within 2 px of the hole's own bounds — so all five drew an opaque rectangle with a live,
  hosted, invisible visualizer inside it. `pharaoh` states the control in its own archive: `vRos`
  is the same markup with `backgroundColor="none"` and it clipped correctly throughout.
  **This replaces a one-skin exemption whose stated reason was the opposite of the measurement.**
  `isCeruleanFace` matched `cerulean.wms` + `face.bmp` + `#9AACDB` and suppressed that fill alone,
  on the claim that a corpus sweep had shown the general rule "erased intentional interiors in
  Claw, Gadget, and Pharaoh". Those interiors are the visualizer holes. The general rule moves
  exactly five images, each by exactly its own skin's matte count, and cerulean's PNG is
  byte-identical across it. **The guards are `clipMask`'s and they keep their counter-evidence** —
  untiled, and authored at the node's own size, so `Gorillaz` is untouched; `isShapeMask` is
  deliberately *not* required, for `groundShape`'s reason, so `YIL!OMA2K` is not in the population
  at all. See `reference/skins/pharaoh.md`.
- **A node that declares no key at all still gets one: magenta, whatever alpha the sprite carries.**
  WMP's implicit transparency colour (W78, W78a). The corpus is authored against it — 4,979 of its
  6,076 `transparencyColor` declarations (82%, 142 skins) are `#ff00ff`, `Halo 2` keys three
  siblings by hand and leaves `m_trans_no.png` to the default, and `Main_Street` authors one key in
  the whole file. The scene builder decides (`WMPSceneImage.implicitColorKey`, set only when the
  node declares nothing) and the image store applies it. **The sprite's own alpha channel does not
  veto it, and W78 shipped believing it did.** The reasoning was that a PNG or GIF which authored
  transparency has already said what is see-through; the corpus says the alpha channel is an export
  format instead. `scripts/wmp_implicit_key.py --alpha only` measures the complement — 76 references
  across 21 skins and 62 sprites — and **11 of those nodes carry two states of the same button, one
  exported without an alpha channel and one with, holding pixel-for-pixel identical magenta**
  (`Half-Life_2` `m_pause_no.png`/`m_pause_hov.gif`, both 1,394; `Harry_Potter…`
  `bottomgroup_no.png`/`bottomgroup_hover.gif`, both 5,866). Under the veto the normal state keyed
  and the hover state did not, so the button turned magenta under the pointer. **Never pass the
  implicit key on a mapping image, position map or clipping mask**: they are read for their colours,
  and keying one deletes a `#FF00FF` mapping colour from its own map. Measure the class with
  `scripts/wmp_implicit_key.py` before touching the rule; the default removed 315,157 magenta pixels
  across 87 corpus views, and dropping the alpha veto took the corpus residual from 7,253 px across
  15 views to 878 across 2, changing 13 PNGs and nothing else.
- The opt-in render dump writes one untracked PNG per view plus a JSON report. Corpus paths and
  output directories are local inputs/artifacts and must never be staged.

## Drawing the skin's own controls

- **`hoverDownImage` is the face of a control *latched* down with the pointer on it, never of a
  press (W132).** `button-element`: "the image displayed when the **BUTTON** is in the down state and
  the user hovers over it". It is drawn only when `WMPInteractionState.isHoverDown` holds — the node
  is in `stickyDownNodes`, hovered, and not pressed; a press keeps `downImage`. **The corpus settles
  the press case**: 21 of the 62 skins authoring it name their `hoverImage` file as
  `hoverDownImage` (`Windows XP`, `Roundlet`, `NVIDIA`, `circle`, the Xbox family…), so a press
  drawn through it would never look pressed. In a `BUTTONGROUP` the down sheet still covers every
  latched child and `hoverDownImage` is laid over it, masked to the hovered child alone; a missing
  file falls back to `downImage` (`Ice`, `claw`). **It needed a parser change as well as a state**:
  the attribute was absent from `WMPAttributeParser.resourceNames`, so its value parsed as a literal
  and no lookup could ever find it — a new image attribute is invisible until it is listed there.
  Verified live on `NVIDIA`'s shuffle group; `WMPHoverDownImageTests`.
- **Hosted `PLAYLIST` chrome attributes are unread, and verification halves the row (W133).**
  `playlist-element` defines 37 attributes; the engine reads background/foreground/itemPlaying
  colours via `WMPSurfacePalette` and nothing else. **Most of the corpus authors values that *agree*
  with what the overlay already does** — `playlistItemsVisible="false"` is 3 skins against 117
  authoring `"true"`, `moveButtonsVisible` is `"false"` in all 57 skins that author it,
  `checkboxesVisible` is `"false"` in 24 of 32 — so only the genuine differences rank:
  `columnsVisible="true"` **74 skins** (with `columns` in 131), `leftStatus`/`rightStatus` 27,
  `dropDownImage`/`dropDownBackgroundImage` 27/25, `toolbarVisible="true"` 12, `toolbarMargin` 14.
  `disabledItemColor`'s 74 have no meaning here at all — there are no disabled tracks. **The
  substance is column headers, which the overlay draws none of.** `dropDownVisible="true"`
  (114 skins) is explicitly **not** part of it: a documented deliberate refusal in `object-model.md`
  pending W66. **Closed 2026-09-24 without implementing**: the column playlists render at a median
  327 px, too narrow for readable columns — measurements in `docs/wmp-skin/wmp-backlog-archive.md` (W133).

- **A `<BUTTONGROUP>`'s artwork is a sheet the size of the whole group, and every state of it is
  painted through the group's mapping mask (W154).** The dead area a sheet carries around its
  controls is keyed by the **mapping image**, not by the group's `transparencyColor`: an author
  names the *map's* dead colour there, because that is the one colour every one of the group's
  bitmaps shares. `portals/mode1` states it three times in one view and settles it —
  `cbuttons_play`'s sheet is white around the transport ovals against 24,997 black mask pixels (a
  white slab at `13,236 280x140`, which was also hiding the brass casing under it);
  `sysbuttons_group` is the same shape in magenta, 829 against 829, and was the whole of the corpus
  PNG sweep's opaque-magenta residual outside `Plus! Pulsar`; and `shufrep_buttons` is the
  **control case**, 3,723 magenta in the art against 3,723 magenta in the *map*, where the one
  declared key covers both and nothing was ever wrong. The base sheet takes the union of every
  registered child, a lit sheet takes the children in that state, and a group lit by itself rather
  than by a child takes the union too. It also keeps the natural-size anchoring every other
  foreground image has (W122) — `Plus! SlimLine`'s `perfectV_SideBar_normal.jpg` is authored
  shorter than its 35x243 group and stretched when it did not.
  - **`showBackground="true"` is the author's exemption, and it is measured rather than inferred:
    41 declarations across 7 of the 177 measurable archives, every one `true` except `Compact`,
    which writes `showBackground="false"` twice and is the only skin in the corpus that states the
    default.** A group whose `image` is genuinely the window's own artwork says so — `elvis` wraps
    its entire 335x396 body in one, as do `Plus! HueShifter`, `Plus! Plasma Ball`,
    `Plus! Hard Boiled`, `Plus! SlimLine` and `Asimov_Radio`. Masking those leaves a hole where the
    player was. Only the *base* sheet is exempted; a lit state is still cut to the control the
    pointer is on, which is W108 and is what makes `elvis`'s `elvis_body_down.jpg` light one button
    instead of redrawing the whole body.
  - **The derived mask is cached and must stay cached (W155).** It is a pure function of the bitmap
    and the child set and never changes with interaction state, so `WMPImageStore.mappingMask` keys
    on the resource path plus the sorted node ids. Rebuilding it per draw cost **173.1 ms per
    render** on `New Super Mario Bros` against 0.3 ms cached, and saturated six cooperative threads
    while the main thread sat idle. Anything that adds a mask to more commands inherits that.

- **A hosted AppKit surface obeys the container's `alphaBlend`; it is not exempt because it is not
  a paint command.** `alphaBlend` inherits, and a `.wmz` closes a pane it has not opened by fading
  the container to zero — so `WMPWidget` carries the walk's inherited alpha, `WMPMainView` hosts
  **no view at all** at `alpha == 0` (rather than `alphaValue = 0`, so a shut pane runs no GL engine
  and no 30fps readback), and a partial fade is applied every sync. `Plus! Bionic Dot` is the worked
  case twice over: its `<subview id="visMask" alphaBlend="0">` correctly drew no artwork while the
  `<EFFECTS>` inside it put a 169x160 visualizer across the face, and its `checkPlayerState()` also
  runs `visMask.alphaBlendTo(0,500)` whenever `player.controls.isAvailable("Stop")` is false — so a
  stopped player is *supposed* to show no visualizer and a disabled vis button. Six archives author
  the idiom, five of them Plus!.
- **A hosted surface is confined by the window's own shape as well, and that is a third statement
  (W198).** The two idioms below are about the *container's artwork*; this one is about whether the
  window exists at all. `clippingColor` marks pixels the skin cut out of its own silhouette, nothing
  is painted there, and therefore nothing occludes a surface that reaches into them — so a rect
  confined "by paint" is not confined at the edges of the skin. Cerulean is the reported case and
  the smallest of six: `face.bmp`'s last three columns inside the `<EFFECTS>` rect are `#FF0000`,
  and 104 px of visualizer stood outside the right of the head. `WMPSceneBuilder.groundShape`
  already computed that silhouette for `WMPEffectsGround`; `WMPWidget.clippingShape` now carries it
  to the surface, which clips to it **and** to `regionMask`, intersected. **`clippingColor` only,
  never `transparencyColor`** — a hole inside the silhouette is where the surface is *meant* to
  show, which is the same rule `groundShape` states and for the same reason.
  `WMP_RENDER_PROBE`'s `offshape=` is the only instrument that sees this class; `outside=` cannot,
  because the leak is inside the widget's own rect. `offshape>0` measures what the skin *authored*,
  so it stays non-zero after the fix: it is a rect to check, not a defect. **`pharaoh` was the
  counter-evidence and W199 is what it was pointing at** — five of the six skins W198 moved cut only
  pixels the scene leaves fully transparent, and `pharaoh`'s 1,524 were opaque because its
  container's `backgroundColor` fill was not clipped by its own keys. Confining the surface was
  right and was never the whole of it; the fill was the other half, and the two together are what
  give that window a pyramid instead of a slab and a visualizer instead of a black apex.
- **A container shapes its windowless `<EFFECTS>` in one of two ways, and they read the colour key
  oppositely. Measure which before touching either.**
  - *Artwork with a keyed hole* — every pixel is the key or opaque paint. The key is the **opening**;
    the paint occludes the rest, and the engine already renders that by hosting the container's own
    paint commands above the surface (`WMPWidget.commandSplitIndex`). **Cerulean is this** —
    `face.bmp`, 56% key, 44% paint, 0% transparent.
  - *A shape mask* — the file carries a **third state**. The key marks the **outside**, genuinely
    transparent pixels mark the opening, and the little paint there is is trim. `WMPWidgetRegionMask`
    clips the surface to it, counter-flipped exactly as `WMPRenderer.clip(to:mask:)` is.

  **The Plus! archives are a sub-family with their own idioms, and both halves of this rule came out
  of them** — `reference/skins/plus-family.md` is the dossier, including what has been ruled out.

  The discriminator is *has transparent pixels alongside keyed ones* — not a threshold, not a skin
  name. Measured over all 30 `<EFFECTS>` in the corpus whose container declares a background image
  and a transparency colour, **28 are two-state and 2 are three-state**: `Plus! Bionic Dot`'s
  `main_vis_back.png` (36/58/5) and `Plus! Professional`'s `vis_mask_s.png` (23/59/18). Getting the
  sign wrong on Cerulean does not distort its visualizer, it **erases** it: the mask would keep the
  surface only where the face already covers it and clip it away inside the hole.

  **An `<EFFECTS>` that names its own `clippingImage` is shaped by that, first (W309).** The US
  forces family (`US Army` and five siblings) writes `clippingImage="vismask.gif"
  clippingColor="#FF00FF"` on the surface itself; its container's `backgroundImage` is the same
  opaque two-state plate, which the discriminator above rightly refuses, so the spectrum filled the
  whole 370x370 window instead of the small disc. The key is `clippingMaskKeys` (the corner when
  none is authored); a mask with no key and its own alpha still shapes nothing. 14 `<EFFECTS>`
  declarations across 11 archives author one (`Secura`, `Windows XP`, `deepbluesomething`,
  `holiday_skin`, `gnome`, `Charlies_Angels_Full_Throttle`, `portals` and the six) — only the
  six were checked on screen.
- **The skin draws its controls; an AppKit overlay is only for what the scene genuinely cannot
  paint.** What is left hosted is `PLAYLIST`, `DROPDOWNPLAYLIST`, `EFFECTS`, `EDITBOX`, `LISTBOX`
  and `POPUP`. `VIDEO` is not: its placeholder filled every `<VIDEO>` frame with opaque black over
  the artwork of 166 of 177 archives, and an audio player has nothing to put there instead. Adding
  an overlay back needs the same argument — name what the renderer cannot draw.
- **A popup's height is a host metric when the markup omits it.** Measured 2026-09-10 over 177
  readable archives, both `DROPDOWNPLAYLIST`s (Corona and 9SeriesDefault) and all four `POPUP`s
  omit `height`; they have no artwork from which the generic geometry path can infer one. Their
  `NSPopUpButton` host measures 24 points high, so `WMPWidgetKind.intrinsicHeight` supplies exactly
  that value only for an unauthored, unoverridden height. The scene builder remains off-main and
  does not construct AppKit controls; an authored or scripted height wins.
- **The visualization surface is this player's own visuals in the rect the skin authored (W101).**
  `WMPEffectsSurfaceView` draws compact WMP-native **Spikes**, **Bars**, **Ambience**, **Cava**, and
  **vis_classic** directly. Cava uses its actual presenter/full-stereo tap and vis_classic uses its
  actual waveform/profile core, each with a WMP-only preference scope. Their right-click controls are
  therefore the real Cava tuning menu and vis_classic profile menu, not inert replicas.
  `WMPEffectSelection` is the one place the choice lives, because 96 archives bind
  `currentEffectType` to `wmpprop:mediacenter.effectType`. Three rules it is built on: **nothing
  playing draws nothing at all** (the skin's own screen artwork stands); **the surface never takes a
  click**, because 51 archives wire an `onClick` on `<EFFECTS>` and that handler belongs to scene hit
  testing; and **the skin's selector is not the app's preference** — cycling from the rect, its menu,
  or the arrow keys never writes `visualizationEngineType`, which the visualization window and
  menu bar share.
  **The keys are two-level, because the catalogue is.** Eight effects, and most carry a list of
  their own, so **up/down pick the effect and left/right step inside it** — ProjectM's presets,
  Geiss's and Tripex's effects, vis_classic's profiles, Cava's mono/stereo. An effect with no
  inside (Spikes, Bars, Ambience) *refuses* left/right rather than swallowing them, so the key
  falls through. Two things this wiring depends on: a preset step goes through
  `WMPEffectSelection.setPreset`, never the engine's own `nextPreset()`, or the `currentPreset` /
  `currentPresetTitle` bindings 144 archives read would show a preset that is not on screen; and
  `applySelection` must tell a preset change from an effect change, because `setPreset` posts the
  same notification as `select` and rebuilding the engine for it reinitializes ProjectM on every
  key press.
  **Do not fill the widget's rectangle.** The effect is composited over the scene, and its untouched
  pixels must stay transparent: every renderer draws into the full authored rect and the skin's own
  artwork is what shapes it, through the z-order split above. **A suite renderer needs two extra
  conversions:** Cava's shared drawer assumes a y-up AppKit host and vis_classic emits top-row-first
  BGRA, so both require a local y-flip inside the flipped WMP view. Test the effect with a real skin
  at playback and inspect the AppKit-hosted frame; a static render dump cannot show its pixels.
- **The ban on hosting ProjectM / Geiss / Tripex in the slot is reversed, and this records why
  (W140).** The rule read: *it must never host ProjectM, Geiss, Tripex, or any other standalone
  visualization window in that slot*, with the black panels reported in Asimov Radio and Cerulean as
  its evidence, and `WMPEffectsSurfaceView.makeEngineView()` / `applyPreset(to:engine:)` were left in
  the file as dead code with zero call sites.

  **Those black panels were the occlusion defect, not the engines.** `WMPMainView` blitted the whole
  scene as one flattened image and hosted every widget above it with a plain `addSubview`, so nothing
  a skin drew could ever cover the surface. An opaque renderer that nothing can occlude *is* a black
  rectangle over the artwork — it would have been one whatever was drawing in it. With the split
  above, the artwork composites over the rect and opacity stops mattering; WMP's own visualizers were
  opaque too.

  What does not change: **the selection stays WMP-session-scoped** — a skin cycling `visEffects`
  never writes `visualizationEngineType`, which is why `switchEngine(to:forceReload:)` grew a
  `persistPreference` parameter rather than the surface calling it as the visualization window does
  — and **`VisualizationGLView` is not mounted live between the two raster layers**. A legacy CGL
  drawable's ordering against sibling `CALayer`s is not guaranteed the way normal layer z-order is,
  and its own `CVDisplayLink` clock tears against the overlay's alpha-blended edge. Do not mount it
  live "just to try"; that is what produced the black panels the first time.

  **How the three are hosted.** `WMPEffectsSurfaceView` builds a `VisualizationGLView` and never adds
  it to the hierarchy: its display link never starts, and a 30fps timer pulls one frame at a time
  through `renderOffscreenImage(pixelWidth:pixelHeight:)` — an FBO render plus `glReadPixels` — which
  `draw(_:)` presents like any other picture. **The GL path takes no y-flip**, where vis_classic
  does: `glReadPixels` returns rows bottom-first, a `CGImage` calls row 0 its top, and this view is
  flipped, so the two reversals cancel. The view's frame is set in **points** before each pull, not
  pixels — `initializeEngineOnRenderThread` sizes the engine from `convertToBacking(bounds)`, so a
  frame in pixels creates the engine at twice the surface it renders into. The readback is verified
  headlessly by `WMPPhase7Tests.testOffscreenEngineReadbackProducesAnImage`, which is the only thing
  in the suite that drives an `NSOpenGLView` outside a window.
- **The effects slot's settings belong to the skin, not to the session (W157).** A `.wmz`'s
  `<EFFECTS>` rect is part of its look — Cerulean's 103x75 frame and a full-width panel want
  different effects — so `WMPVisualizationSettingsStore` files them against the installed skin name
  (length-prefixed key, as `WMPViewFrameStore` does) and `WMPMainWindowController` restores them at
  the top of `reloadSelectedSkin()`, before the scene and therefore before the surface is built.
  **What is in scope is what WMP owns**: the effect and preset, plus the keys already namespaced to
  the slot — `cava.wmpEffects.*` and `visClassic*.wmpEffects`, both asked of the subsystem that
  names them (`CavaSettings.preferenceKeys(for:)`, `PreferenceScope.wmpEffects`) so a new key is
  carried without a change here. ProjectM / Geiss / Tripex cycle and sensitivity are **not**: those
  keys are shared with the standalone Visualizations window and the `.wal` surface by design, and
  per-skin copies would rewrite that window's settings on every skin switch.
  Three things it is built on. **A skin with no record restores the app's defaults** — every scoped
  key is cleared, and `WMPEffectSelection.restore` falls back to the default effect where `select`
  would change nothing — or the second skin silently inherits the first one's choices, which is the
  half that regresses invisibly. **Capture is driven off `UserDefaults.didChangeNotification`**,
  not off each menu item: the Cava and vis_classic controls in the slot's menu write their own keys
  and offer no callback. That makes the write conditional — an unchanged record must not be
  rewritten, or the observer feeds itself. And **a captured change is filed against the skin that
  was showing when it was made**, held in `visualizationSettingsSkin`, because the defaults
  notification is delivered on the main queue asynchronously: a change made just before a skin
  switch would otherwise land in the record of the skin being switched *to*. `restoreVisualizationSettings`
  flushes the outgoing skin first for the same reason.
- **PCM arrives on the audio thread and an overlay must not hop to the main actor to take it.**
  `.audioPCMDataUpdated` is posted from inside `AudioEngine.processAudioBuffer`; a
  `MainActor.assumeIsolated` in that observer is a `dispatch_assert_queue` failure and the process
  traps the moment a surface exists and a track plays. The WMP effect surface retains the latest
  spectrum snapshot and schedules its AppKit redraw on the main actor.
- **A semantic slider tag is itself a binding, and its range is part of what the tag says (W118).**
  `<SLIDER value="wmpprop:player.settings.balance">` states where a control reads; `<BALANCESLIDER>`
  states the same thing by *being* one, so a skin that uses the tag authors no `value` and usually no
  `min`. Two defaults then collided: `sliderMetrics` falls back to *the value of a slider nobody has
  told anything is its own minimum*, on a range defaulting to 0-100 — so **15 of the corpus's 16
  balance sliders drew their thumb at the bottom of the track, which on balance is hard left**,
  reported live as "balance is fully to the left by default on all skins". `VOLUMESLIDER` (31 uses /
  23 skins) drew empty and `SEEKSLIDER` (18 / 15) stuck at the track start for exactly the same
  reason; balance is the one where the wrong end of the track *means* something, which is why it is
  the one that got reported. `WMPObservablePropertyRegistry.implicit` synthesizes the binding the tag
  stands for, so the value arrives through the same coalesced, echo-guarded path an authored
  `wmpprop:` does and follows the host live. **The seek slider needs both halves**: WMP puts its
  position on the track in *seconds*, so `max` is synthesized onto `player.currentMedia.duration` and
  `value` onto `player.controls.currentPosition` — two paths the registry already answers, rather
  than a new percent path it does not. Ranges stay in `sliderMetrics.defaultRange(for:)`, which is
  `-100…100` for `.balanceSlider` and 0-100 for every other kind. An authored attribute always wins:
  one corpus balance slider states its own `value` and keeps it. **And a skin says the same thing a
  second way, by the range it declares (W120): 73 sliders across 61 of the 177 measurable archives
  author `max="wmpprop:player.currentMedia.duration"` and no `value` at all** — 58 as
  `<CUSTOMSLIDER>`, 15 as `<SLIDER>`, and no script in any of them ever writes one. That is the
  corpus's own seek bar, the way the Plus!, Xbox, Alienware, BlueCrush, Halo and Catwoman families
  all write it, and `positionSliderPaths` reads it: a control whose far end is the end of the track
  *is* a position control. Without it the filmstrip sat on frame 0 for the length of the track and
  the digit strips a skin positions from `value_onchange` sat with it — reported as "the clock does
  not work and seek does not work" and measured, seeded, as 68 rows across 52 skins moving off
  frame 0. **The other half of that report is the same slider read from the other direction (W51): a
  control is bound both ways, so the *host* moving it raises `value_onchange` too.** The user-driven
  half closed with W52; this is how a seek bar's readout follows playback and how a preset moving
  ten gains re-runs each band's handler. `Catwoman` draws its clock as four digit filmstrips
  positioned by `value_onchange="drawSeekDigits(value)"`, so until the handler was raised the slider
  tracked the song and the clock sat at zero. Two things make it safe rather than a feedback loop,
  and both were measured before it was written: **the registry only reports values that actually
  moved**, so a write-back handler (`eq.gainLevel1=value`, 2,141 of the 2,488 host-bound sliders
  carry one) hands the host the number it just gave and produces an identical snapshot; and **every
  one of the 19 handlers on a position-bound slider is a readout painter** — `drawSeekDigits(value)`
  ×17, `DrawTimeNormalView(value)`, `seek2.value=seek.value` — so nothing re-seeks. It is bounded
  like the two cascades beside it: only what the markup authored, only `value`, once per element per
  transaction, raised *before* the completion and geometry cascades so a repaint that writes
  geometry still propagates in the same frame. Its side effect is honest new demand rather than
  regression: 42 handlers that never ran now run and 30 of them abort on `event.shiftKey`, an
  **`event` object in a handler** that nothing binds on either direction of `change`. **The audio was never wrong** here —
  `AudioEngine.balance` defaults to centre and `performSlider` already wrote `fraction × 2 − 1` — so
  the whole defect was a drawn thumb lying about a centred pan, and no sweep of default-state images
  could have called it one.
- **A slider is a track plus a thumb the scene places**, and `WMPSliderMetrics` owns that geometry
  alone so each of its rules is testable: `borderSize` is dead track at *both* ends (171 skins),
  a **vertical** slider's maximum is at the **top** (1,312 of 1,968 `direction` attributes are
  vertical — every equaliser band is one), and the same metrics read the pointer back so a drag runs
  along the axis the skin authored. `foregroundImage` is the filled part of the track, cropped
  rather than scaled, and `useForegroundProgress="true"` (46 skins) redirects that fill to
  `foregroundProgress` — a buffer bar behind a thumb showing position, which are different numbers.
- **A `.wmz` says where a slider writes by binding its value, not by choosing a tag.** 163 skins
  author a plain `<SLIDER value="wmpprop:player.settings.volume">` rather than `<VOLUMESLIDER>`, so
  `WMPTransportAction.boundAction` maps the declared `wmpprop:` path to the action. Adding a bindable
  host property means adding it to `WMPObservablePropertyRegistry` *and* deciding whether writing it
  back is an action — one without the other is a control that moves and does nothing.
- **`EQUALIZERSETTINGS` is a settings object, not a control.** 163 skins author it and none give it
  geometry; the skin's own ten bound sliders *are* the equaliser. It is `isNonLayout`, like
  `<player>` and `<network>`.
- **`alphaBlend` is 0-255, inherits down the subtree, and 717 of its 778 corpus uses are `"0"`** —
  an element the skin hides and fades in later. A zero-alpha node still lays out, so its geometry
  stays readable, but it must not reach the command list at all: leaving it there put invisible
  artwork inside `visibleBounds` and every dirty rect derived from it. Honouring it changed what
  several skins draw, because the engine had been painting the topmost of eight stacked shells
  rather than the one authored visible — and it makes `alphaBlendTo` (W38) load-bearing, since a
  skin that fades its own panels in now shows less until that lands.
- **`passthrough="true"` (82 skins) is drawn and never hit.** A decorative overlay registered as a
  hit target swallows the controls beneath it.
- **`TEXT` reads `fontFace`, not `fontType`** — 109 skins against 21 — and `fontStyle` is a *set*
  (`"UNDERLINE, bold"` is authored), not one word. `fontSmoothing="false"` (95 skins) is a readout
  drawn as pixels; antialiasing it turns a 6 px digit into grey mush.
- **A `CUSTOMSLIDER` is the size of its `positionImage`, and its `image` is a filmstrip.** This was
  read out of the art rather than assumed, and `WMPPositionMap` carries the evidence:
  `ALXMorph/seek_map.png` is 86x10 whose columns step 0, 2, 5 … 252 — a **greyscale ramp whose
  luminance is the fraction** — against a `seek.png` of 86x600, sixty frames stacked vertically;
  its `volume_map.png` is a 72x38 arc against a 2232x38 strip of thirty-one frames laid out
  horizontally. So the strip's axis comes from whichever one is a whole multiple of the map, the
  value picks the frame, and a drag reads its value out of the map — which is the whole point of the
  element: its track need not be a straight line. Sizing one from `image` makes it 2,232 px wide.
- **Which end of a filmstrip is the minimum is a property of the art, not of the markup.** The
  corpus authors both orders against identical markup: `Catwoman/srs_slider.png` fills downward
  across 18 frames and `Halo 2/srs_slider.png` — the same control, the same left-to-right `0…251`
  map, the same `min="0" max="100"` — runs the other way, frame 0 all thirteen segments lit and
  frame 13 empty. So the *map* answers which end of the control is the minimum and the *art*
  answers which end of the strip is, separately. `WMPImageStore.filmstripIsDescending` measures it
  two ways — lit coverage for a fill bar, centre-of-mass travel along `WMPPositionMap.gradient()`
  for a moving thumb — and selects **17 of the 342 stripped `CUSTOMSLIDER`s across 6 skins** (19 in 7
  before W307 returned `Secura`'s pair), every
  one of the 6 travel-selected ones a Halo 2 or STALKER control. Indexing Halo 2 forwards drew one
  segment for a TruBass of 95 and the full bar for 0 while the audio followed the pointer: reported
  as *"the SRS WOW effect and TruBass level controls do not fire correctly"*.
  **Brightness is only a proxy for "fill", and it fails one way (W307):** `Secura`'s `bar.gif` is
  a *dark* fill over a light ground, so the empty frame read as lit and both its bars drew backwards
  — while its light `barhover.gif` read forwards, so the bar flipped whenever the pointer left it.
  A second reading can now take a reversal away, never add one: per line along the map's axis, the
  middle frame must cross the stretch that differs between the end frames exactly once, and the
  side nearest the map's minimum names the full end; three unanimous lines undo a brightness
  reversal. Allowed to *add* reversals it moved five strips in `Crimson_Skies`, `Gold`,
  `Plus! Professional` and `T3-Skynet` on unchecked evidence (`T3-Skynet`'s arcs are plainly
  ascending). Census with `WMP_STRIP_TRACE=1`: exactly one strip changes, `bar.gif`; the 11 other
  brightness reversals all vote backwards too. **Known miss:** `NVIDIA`'s `volume.png` counts
  99 → 00 and both readings draw it forwards.
- **A host change the skin drove through its own command still has to settle its own bindings.**
  `eq.*` is the one host surface a `.wmz` both writes and binds. Halo 2's SRS button posts
  `eq.enhancedAudio = !eq.enhancedAudio` and its TruBass and WOW sliders carry
  `enabled="wmpprop:eq.enhancedAudio"`, so the transaction that flipped it resolved that binding
  against the snapshot it started with — `false` — and nothing re-resolved it: the sliders drew and
  hit testing refused every click on them. With a track playing the clock tick settled them a tenth
  of a second later and they worked, which is what "sometimes" meant in the report.
  `refreshHostState` now diffs `equalizer`, and `dispatchScriptTransaction` re-settles at scope exit
  when its own commands moved the snapshot. Every other host surface was already covered because
  each of its edges is an event there.
- **The binding-only host tick is `hostsettle`, and it used to be `positionchange`, which was not
  free.** `onPositionChange` is the `CUSTOMSLIDER` handler WMP raises when the **user** moves the
  control, and **24 of the 180 installed archives author 71 of them** — every `srs_slider` and `eq`
  slider in the Halo 2, STALKER, Catwoman, Alienware and Plus! families. `handlers(in:event:)`
  strips the `on` prefix, so the name a clock tick raised was the name those handlers answer to. It
  was inert only because `onpositionchange` is not in `WMPAttributeValue.handlerNames`; registering
  it without renaming the tick would have run all 71 ten times a second with `value` unbound. Pick a
  tick name no archive authors, and check that it is one.
- **`clippingImage` shapes an element, and it is what makes a shaped window shaped.** 172 corpus
  nodes author a non-empty one and 169 of them declare a `clippingColor` beside it, which is what
  the mask keys out. Before it, `TDK`, `elvis`, `Secura`, `portals` and the six `US *` service skins
  all drew a black or grey rectangle behind their round artwork.
  - **A `clippingImage` with no key beside it takes the mask's own corner (W171).** The three
    exceptions to the count above name a mask and no key at all — `Plus! HueShifter`'s
    `body_lower.jpg` group, `Charlies_Angels_Full_Throttle`'s `visEffects`, `gnome`'s `myeffects2` —
    and all three masks are **fully opaque**, so reading that as "no key" left `clippingMask`'s
    source-alpha test keeping every pixel and the node drew its whole rectangle. On HueShifter that
    was `body_lower.jpg`, a 213x66 lavender plate boxed hard-edged across the bottom of the player
    with the skin's green bottom candy behind it. The colour is the mask's corner — the same
    derivation `auto` uses, and white in all three files, which is the `clippingColor="white"` their
    sibling layers state by hand. **Only for a mask with no transparency of its own**: one that
    authored alpha has already said what it cuts, and a corner key would cut it twice.
  - **`clippingColor` keys the *clipping image*, never the node's own artwork (W169).** The two keys
    were read as one list, which is harmless while they name the same colour and destructive when
    they do not — and it is the largest single defect this engine has had by reach. A JPEG keys with
    `WMPColorKey.jpegComponentTolerance`, so on the skins writing `clippingColor="white"` every tone
    within 64 components of white was deleted from the picture: **`Plus! Plasma Ball`'s
    `eq_panel_normal.jpg` 85.7% of its pixels, `Plus! HueShifter`'s `hueshifter_top.bmp` 76%,
    `Plus! SlimLine`'s `perfect_body_normal.jpg` 47.5%, `TDK`'s `info_bg.jpg` 52.1%, `elvis`'s
    `elvis_tray.jpg` 39%, and `Plus! Hard Boiled`'s `Egg_Body_Normal.jpg` 27%.** Reported as *"you
    made the high res graphics low res"* and then *"fix the other skins that were addressed with plus
    egg commit"*, and **W160 had already chased the same pixels as a resampling defect** — a quarter
    of the egg was not being upscaled badly, it was being erased. A node with no `clippingImage`
    keeps the old reading, because there `clippingColor` is the only thing shaping it. Measure the
    class by keying each node's artwork against its own declared clipping colour at the format's
    tolerance and reporting the share hit; 13 of 535 corpus views move and every one is a gain.
  - **`clippingColor="auto"` is a colour, not an absence (W167).** Four declarations across three
    archives — `Plus! Plasma Ball` twice, `Compact` and `digitaldj` once each — and the parser
    rejecting the word is not the same thing as the author declaring no key. `Plus! Plasma Ball`'s
    `mainButtons` states `clippingImage="screen_MASK.gif" clippingColor="auto"` over a mask with
    **zero** transparent pixels, so an unresolved key cut nothing and the whole 242x299
    `screen_normal.jpg` drew opaque over the plasma globe — reported as *"a gray box background"*.
    WMP takes it from the bitmap the declaration governs and the corner is where all four authors
    put it: `screen_MASK.gif` and `playlist_vid_panel_MASK.gif` are white at 0,0, the same
    `clippingColor="white"` their four sibling layers in the same file state by hand, and
    `digitaldj/preview.bmp` is `#FF0000` there over 10% of the file. `clippingColor` reads the
    clipping image, every other key the node's own artwork; `WMPImageStore.cornerColor` is nil for a
    corner that is already transparent, because a file that authored its own alpha has said what is
    see-through and there is no matte to infer.
- **A clipping shape shapes the element's *contents*, not only the element (W168).** A `<SUBVIEW>`
  or `<VIEW>` in WMP is a window region and its children are inside it, so every paint command in
  the subtree carries its ancestors' shapes (`WMPSceneClipMask`, applied against the *container's*
  frame rather than the command's). `Combat_Flight_Simulator_3` hangs its whole 584x321 body off
  `<subview id="mainBody" backgroundImage="main_bg_mask.png" clippingColor="#ffffff">` and draws
  `main_bg.jpg` inside it as a child that declares **no key of its own** — so the flat `#88A4B9`
  matte filling 67% of that JPEG had nothing to cut it away and the window was a rectangular slab.
  `Melvin` is the same rule seen the other way: its two eye sockets are `clip.gif` subviews, and
  before the shape reached their children a head-coloured sibling covered both eyes.
  - **`transparencyColor` states the shape too, on the background-image path only (W172).** A
    `<SUBVIEW>` whose whole ground *is* a two-tone mask has said the same thing whichever attribute
    names the key. `Plus! HueShifter` writes `transparencyColor` on all five of its subviews over
    `body_Mask.gif`, `playlist_tray_wholemask.gif`, `eq_tray_wholemask.gif`,
    `video_tray_wholeMASK.bmp` and `body_lower_wholeMASK.gif`, and reading only `clippingColor` left
    every one of them a plain rectangle: its bottom candy hung 22 px below the player's silhouette
    and the body's own edge was fringed with keying speckle, because `bodyNormalMask.gif` is a
    dithered 254-colour GIF whose white region carries 2,108 px of near-white noise. **127 nodes
    across 17 archives qualify**, every one naming a file `…mask`, under the same three guards —
    untiled, authored at the node's own size, two-toned. `clippingImage` is deliberately **not**
    widened the same way: a node that names a mask file outright has one key attribute for it.
    **Cerulean is not this case and never was** — its `face.bmp` subview writes
    `clippingColor="#FF0000"` beside `transparencyColor="#FF00FF"`, so the shape comes from the
    clipping colour either way, and the bitmap is 18,601 colours, which `isShapeMask` rejects. The
    rule that said otherwise cited Cerulean and was wrong on its own evidence.
  - **A container's shape is a *region*, not a clipping image (W172).** `WMPSceneClipMask` renders
    through `regionMask` — in the region wherever the pixel is not the key, **whatever its alpha**.
    The two readings differ only on a mask that carries transparency of its own, and there the
    difference is total: `Ice`'s `Clip.png` is 379x183 in exactly two values, 17,558 px of opaque
    `#FF00FF` outside the player and 51,799 px of **alpha-zero** white over it, so honouring the
    mask's own alpha cut the keep region and the key alike and both of its `Frost` layers vanished.
    Every other mask in the corpus is opaque and reads the same either way. A `<BUTTONGROUP>`'s own
    `clippingImage` still honours alpha — that is an authored mask bitmap, not a container's ground.
  - **A `clippingImage` larger than its node on both axes shapes nothing (W309).** `US Army` and its
    five siblings clip the 191x143 `helpmask`/`creditsmask` panes with the 370x370 `infomask.gif`,
    whose black key is exactly the pane's rect in its *parent's* coordinates. Every placement was
    tried live and every one was wrong: stretched to the pane, the key cut a hole in the help text
    and the pane's `backgroundColor="pink"` showed through; at the pane's origin, unscaled, it cut the
    bottom-right corner; at the parent's origin it keys out the whole pane, text included. With no
    mask the opaque `infohelp1.gif`/`infocred1.gif` cover the pink, which is the skin as designed.
    `clippingImageFits` in `clipMask`/`groundShape`. Those 12 nodes are the whole population
    (a scan of every `clippingImage` against its authored `width`/`height`); every other mismatched
    mask is smaller than its node on at least one axis and keeps the stretch.
  - **A `backgroundImage` is a shape only when it is untiled, authored at the node's own size, and
    two-toned.** 84 `<SUBVIEW>`s across 38 archives and 26 `<VIEW>`s across 17 declare a
    `clippingColor` with no `clippingImage`, and they are two authoring idioms the attribute cannot
    tell apart. *A mask*: `main_bg_mask.png` is 584x321 in three colours — 71% white, 29% black, one
    stray pixel. *Artwork with a keyed hole*: `YIL!OMA2K`'s `yMain Body.bmp` is 530x440 in **34,688**
    colours with a 246x179 rectangle of `#6699FF` cut out for the video and a `<subview zIndex="-2">`
    of solid black parked behind the body to show through it — shaping children by that clips the
    backdrop away and leaves the display empty. `WMPImageStore.isShapeMask` asks the question as a
    *share* rather than a colour count, because a mask's own edges are antialiased:
    `main_vismask.png` is 10 colours at 100.0% in its top two. The size and tiling test is
    `Gorillaz`: its `noodle` view is 781x467 over a `background.gif` that is a 50x28 swatch of solid
    `#33CC66` with `backgroundTiled="true"`, and its `clippingColor="#33CC66"` says *my ground is
    invisible*, not *my window is empty* — reading the tile as a shape erased the whole skin, all
    143,248 px of it, and it was the only total loss this rule produced anywhere in the corpus.
- **A view with no shape of its own is shaped by its body, and the body's outer matte cuts every
  sibling (W279).** `WMPSceneBuilder.bodySilhouette`: when a `<VIEW>` states no `clippingColor`,
  `clippingImage` or background, its single lowest subview — at 0,0, sized by its artwork alone to
  the whole canvas, untiled, keyed by `transparencyColor` — is the window, and the view pushes that
  shape over everything it holds. A WMP window is a region, so a control drawn over the matte is
  outside the window: `xXx_night_vision_redx`'s open, info and EQ buttons carry a flat `#ADCC31`
  field outside the ring, **every pixel of it over `main_bg.png`'s `#FF00FF`**, and they drew as
  green boxes on the window's edge. **Only the matte connected to the bitmap's edge is cut**
  (`WMPSceneClipMask.exteriorOnly`, a flood from the border): `transparencyColor` alone does not say
  hole from matte — `Plus! BubbleSkin`'s reason — and a keyed hole inside a body is where it shows
  its visualizer. Sweep (179 archives): `xXx_night_vision_redx` 3,278 px and `Erektorset` 13 px — a
  slider end-cap's outline hanging 1-2 px past its body, which the same region rule predicts.
  `WMPClippingShapeTests.testAWindowBodysMatteClipsItsSiblingsButNotItsInteriorHole` pins it.
- **A mask buffer's row zero is the authored top row.** A `CGImage` drawn into a bitmap context
  arrives that way round — `WMPMappingImage` says so in as many words — so "correcting for
  CoreGraphics" by reversing the rows mirrors the mask and clips the half it should keep. That is
  W47 arriving by a second route, and only a **top/bottom** fixture can see it: a left/right one is
  identical under a vertical flip, and so is a horizontal position ramp.
- **`cursor` names a shape, not a file, in 2,246 of its 2,319 non-empty uses.** Classifying them all
  as artwork made every named cursor a *missing bitmap* (`BITMAPS … missing=hand sizenwse` across
  145 skins) and hid the name from the builder, which reads literals. `WMPAttributeParser` decides
  from the value; the ~70 `.cur`/`.ani` files stay resources and resolve to no cursor (W67).
- **Animation lives in the renderer, not the scene.** `WMPRenderer.render(clock:)` picks the frame,
  so a 10 fps GIF costs a re-render rather than a rebuild — a rebuild runs the skin's script
  transaction, which must not happen ten times a second. 90 of the 180 archives carry a multi-frame
  GIF (2,166 files). `animationCadence(for:)` gives the repaint loop its period *and* the union of
  only the animated frames, because repainting a whole window for one blinking LED is the difference
  between a skin that animates and one that burns a core. **A render dump is a still, so without
  `WMP_RENDER_CLOCK` an animation is unfalsifiable** — frame zero looks exactly like an engine that
  never animates.
- **The rate a user sees is not the rate `ANIMATION` reports, and nothing headless can tell them
  apart (W142).** Reported live as "the animation fps is low in general". `WMP_ANIM_TRACE=1`
  separated two independent causes on its first line — `want=25.0fps got=20.0fps frames=21
  restarts=10 sleep=42.3ms render=4.5ms` — and both are about *when* a frame is drawn, so a dump,
  a cadence line and a corpus sweep are all blind to them. **It also closed W69, the one reported
  *flicker*, and that is the row's sharpest lesson.** `Xbox Live Skin`'s 145-frame intro was filed
  with three written-down compositing candidates — a whole-`NSImage` replacement against a sub-rect
  invalidation, an animated `bounds` union computed once, and a 64 MiB LRU thrashing — and **none of
  them was implemented, because none of them was the cause.** Frames arriving at an irregular rate
  look exactly like a bad composite. Suspect the clock before the compositor whenever the symptom is
  a picture that will not settle; confirmed gone live on 2026-09-12.
  * **A rebuild must not restart the repaint loop.** `startAnimation` runs on every rebuild and a
    `.wmz` rebuilds constantly — AlienMorph's 100 ms view timer alone restarted it ten times a
    second — and each cancel discarded a partly-elapsed sleep, so a 40 ms frame period inside a
    100 ms rebuild window landed exactly two frames per window. The loop now keeps running while
    `WMPViewPresentation.animationCadence` compares equal to the new one, and renders
    `activeScene` rather than the scene it was started with: a rebuild replaces *what* it draws
    without interrupting *when*. **That equality is the fix**, so anything that makes an unchanged
    animation produce an unequal cadence silently restores the defect.
  * **Frames are scheduled against the animation epoch, not "now + period".** `Task.sleep`
    overshoots and the render after it is serial, so a period per frame accumulated both into
    every interval. Deadlines off the epoch absorb them and are the same clock
    `WMPImageAnimation.frame(at:)` picks a frame with; falling a whole period behind skips to the
    next boundary rather than bursting.
- **A GIF delay of 0 or 1 cs means "as fast as possible", and the browser's answer to it is not
  this corpus's answer (W142).** `WMPImageStore.animationFloor` floors them at 0.0667s (15 fps);
  the browser convention of 0.1s was the largest single cause of "the animations are slow".
  **768 of the 2,166 multi-frame GIFs, across 62 of the 90 skins that animate, author a minimum
  delay of 0 or 1 cs, and 625 of those author nothing else** — at 0.1s `AlienMorph`'s 119-frame
  shutter took 11.9 seconds to open. **679 of the 768 are one-shot**, so this number is choosing
  how long a *transition* takes, not how fast a loop spins, and only one endless corpus GIF is
  short enough for the rate to read as a flicker. The floor itself is set **by eye against the
  running app** and there is no measurement that can set it — the file said "as fast as possible".
  0.04s was tried first, argued from the delays the corpus authors when it names one, and was
  reported too fast on sight. Do not re-derive it from the corpus; that argument is what produced
  0.04.
- **A `<POPUP>` is an equaliser preset menu and its items come from the skin's own script.** All four
  corpus popups call `appendItem` in an `onLoad` and apply the choice through
  `eq.currentPreset`; `WMPScriptOutput.listItems` carries them out of the transaction, because the
  markup names none of them. The four hardcoded entries that used to be shown were in no skin.
- **An `<EDITBOX>`'s `value` is a string.** Nine of the corpus's ten are `plSearchEdit`, a playlist
  search field whose `onKeyUp` reads it straight back, so it needs its own text path
  (`setWidgetText`) rather than the numeric `setWidgetValue`.
