# `.wmz` paint order and the effects surface's occlusion

Moved verbatim from `reference/rendering.md` § *Static scene and image contracts* on 2026-09-25; the router is
`reference/rendering.md`. Before an engine-wide change here, check the counter-evidence table in
`reference/skins/README.md`.

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

- **A windowless `<EFFECTS>` surface is clipped to the window the skin painted, and "outside" is
  what the artwork does not *enclose*** (`WMPRenderer.effectsSilhouette`, 2026-09-25). A skin
  that shapes itself with `transparencyColor` alone states no `clippingColor` shape, so neither
  `clippingShape` nor a ground confines its rect, and a rect larger than the artwork painted its
  spectrum onto the desktop. `livin_it_skate` hangs a 315x292 rect over a diagonal board and drew
  bars off the deck's lower-left corner. The mask flood-fills the unpainted pixels of the flattened
  below+over rasters from the canvas edge: those are cut, and an unpainted hole the artwork
  encloses keeps its visualizer (`pharaoh`'s apex, `anemone`'s lens). **A pixel under half
  opacity counts as unpainted**: at any-alpha the antialiased rim of the deck and wheels, and a
  stray faint row, let projectM show through as a halo and a line across the window (live QA,
  2026-09-25); no corpus rect's cut moved, since keyed art has no partial alpha. Windowed rects count as
  painted. It is nil unless the cut reaches a windowless rect. Probe (`SILHOUETTE`, 175 archives):
  12 of 82 windowless rects are cut, every one matte outside the body — `BubbleSkin`, `HueShifter`
  and `raveworld` lose rect corners, the rest a sliver. **The render sweep cannot see this**: the
  mask applies to the hosted surface only, so dumps are unchanged. It runs on every render of a
  scene with a surface, at canvas resolution over raw buffers — the first version wrote arrays
  through captured closures, took seconds per frame in a debug build, and stalled the skate's
  display window so its vis never appeared. Accepted live 2026-09-25. Pinned by
  `WMPEffectsSilhouetteTests`; A/B with `WMP_EFFECTS_SILHOUETTE=0`.

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
  **An image's own alpha is a key too** (2026-09-26): an unkeyed PNG with transparent pixels has a
  hole, and its negative children stay behind it. `Age_of_Mythology_MPXP`'s `visMask` states no key
  over `vis_back.png`, whose lens is alpha, and its `zIndex="-15"` `<EFFECTS>` drew over the
  headdress and ring instead of through the lens; the MP7 edition of the same skin keys it and was
  always right. An XML scan of all 180 installed archives found this the only container of the
  shape, so no sweep was run — and the render sweep could not show it anyway, since the surface is
  hidden until playback fades `visMask` in.

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
