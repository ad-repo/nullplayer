# `.wmz` geometry: extents, alignment and script-written layout

Moved verbatim from `reference/rendering.md` § *Static scene and image contracts* on 2026-09-25; the router is
`reference/rendering.md`. Before an engine-wide change here, check the counter-evidence table in
`reference/skins/README.md`.

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
  **Not re-grown is not frozen: growth *after* the write still counts.** The same skin's
  `SizeViz()` writes `myeffect.height = svScreen.height - myeffect.top - 24` when a track starts,
  and with no anchor a nested write took a delta of zero forever — drag the window larger and the
  visualizer's width stretched while its height stayed 215, the picture clipped to the old rect.
  `WMPScriptRuntime` now records, for each nested `left`/`top`/`width`/`height` write, the parent's
  extent on that axis at the write (`WMPSceneOverrides.scriptAssignedParentExtent`; the parent is
  the nearest ancestor with a resolved frame), and `scriptDelta` returns the parent's growth since.
  No record — the parent had no frame, or the view had already resized earlier in that
  transaction, so the frame is stale — keeps the old zero. Corpus sweep 2026-09-26: invariants
  identical over 179 skins, one image different and that one `Scooby-Doo_2`'s `Math.random()`
  portrait.
  **An authored `jscript:` binding on a sibling's extent is a different mechanism and was W235** —
  `NVIDIA`'s `visEffects` off `visFrame` — measured not to be this, and closed 2026-09-19 by the
  alignment-baseline half of `c78f32f7`: `ownAuthoredSize` was reading the runtime's own geometry
  override back as authored, so every child's stretch delta was zero. A gated widget like
  `visEffects` is reachable headlessly after all — one `WMP_RENDER_CLICK` on the toggle that sets
  `mainModeVis.visible`, then `WMP_RENDER_SIZE` for the stretch. See the archive.

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
  See the `windowed`/drawer entry in `rendering/paint-order.md` and `reference/skins/xsn-sports.md`. `mainView` is
  byte-identical across the whole family: a non-resizable player authors no
  centred pieces, so **this class lives entirely in the windows a skin opens beside its player** —
  which is why four phases of `mainView` work never saw it. `WMPAlignmentTests` pins both halves.

- **A centred piece sits on a whole point, rounded down (2026-09-29).** `(parent − own) / 2` with an
  odd remainder put `Crimson_Skies`' 190pt `f_top_mid` at 91.5 in its 373pt `plView`, half a point
  clear of the tile ending at 91 — a 1px seam down both bars at 2x, on the skin's own window. WMP
  lays out in integer pixels, so the builder floors both axes. `WMPAlignmentTests` pins it (its
  fixture's 155pt remainder is odd).

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
  to the `foregroundImage` behind it. See `reference/harness-history.md` § *The empty-value class*.

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
  field captured by a loose pattern. See `reference/harness-history.md` § *The residue is a size fallback*.

- **An origin the markup never stated can still have been written by script, and asking the markup
  first meant it never was.** `left`/`top` default to 0 when unauthored — but the check was
  `attribute == nil ? 0 : resolve`, which short-circuited *before* `parseDimension` could look in
  the scene overrides. Size never had the bug, so a script-positioned element came out the right
  size in the wrong place: `Cablemusic`'s two drawers are seventeen station rows each, laid out
  entirely by `InitPrograms()` writing `pr<N>.top`/`.left`, and all thirty-four drew on top of one
  another in the corner of the drawer. Overrides first, then the markup, then the default.

- **A zero geometry override is a value, not an absence.** Every skin with a store-thumbnail
  `previewView` collapses it in `onLoad` — `view.width = 0; view.height = 0; view.backgroundImage =
  ""; theme.currentViewID = "controlView"` — and Microsoft's own `auto.js` in `Official_Xbox_XP`
  does it with a comment saying so. Discarding a `0` override as "not positive" left 34 corpus
  skins showing a static splash bitmap where the skin had asked for its player.

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
