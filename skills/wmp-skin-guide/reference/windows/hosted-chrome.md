# `.wmz` windows: routing, theming and the borrowed frame

Moved verbatim from `reference/windows.md` on 2026-09-25; that file is the router. Read it first.

### Current hosting contract, continued: routing, theming and the borrowed frame

Routing is `routeWMPSkinSurface` / `WMPSkinSurfaces` — 171 of the 180 archives declare a playlist and
164 an equaliser, so ours is the fallback for the handful that declare neither. **A fallback is
decided when the window opens, and the skin can change underneath it**: loading a `.wmz` with no
equaliser opened ours, and switching to one that has an equaliser left ours standing beside the
skin's — two equalizer windows on `xsn_sports`.
`WindowManager.dismissWMPFallbackSurfacesTheSkinProvides()` runs on every presentation and closes
(never destroys) ours, so the window keeps its frame for the next skin that needs it.

Theming is two layers, and the second is the one a skin with styled panels is asking for:

- **Colour** — `WMPSurfacePalette` → `SkinnedSurfaceStyle`, the seven roles every hosted surface
  needs.
- **Shape — the donor view is drawn *whole*, and what is the skin's own is subtracted (W209).**
  `WMPHostedFrameTemplate` → `SkinnedSurfaceFrameArtwork`. The template names a donor view — almost
  always the playlist — and `WMPHostedFrameProvider` rebuilds **that entire view** at our window's
  size through the ordinary `WMPSceneBuilder`/`WMPRenderer`, so alignment, tiling and `JScript:`
  layout expressions are resolved by the code that draws the skin rather than by a second reading of
  the same markup. Four subtractions, and nothing else is removed:
  1. the **client subview's contents** — the hole is ours;
  2. every **control** — a borrowed button is a lie about what it does;
  3. every **readout** — `<TEXT>`, `<STATUSTEXT>`, `<CURRENTPOSITIONTEXT>` are bound to the skin's
     own player state and are stale on our window;
  4. a subview whose **`backgroundImage` is also a control child's `image`** — these skins paint a
     button twice, once as the wrapper's backing, and dropping only the control leaves the glyph.
     The same image in both places is what separates a backing from a *plate*: `Back to the Future
     Trilogy`'s logo subview carries `f_logo.png` and wraps a button drawn from `f_logo_no.png`, and
     that plate is frame — it covers a join in the bottom bar.

  **Below the donor's declared floor, the view is built at the floor and the finished picture is
  scaled down.** A skin that declares `minWidth=560 minHeight=260` has never been asked what 357x238
  looks like, and its pieces come apart there. The scaling is non-uniform and the corners soften;
  that is the price of the author's own layout, and it was accepted on screen over the alternative.
  **Insets come from the client subview, never from the artwork's thickness** — `Halo 2`'s "border"
  bitmaps are 190px wide on a 406px window and mostly transparent.
- **The frame is painted *over* the content, and the interior *fill* is erased — not the rectangle
  (W209).** The old rule cut the client **rectangle** out before drawing, and these bezels are not
  rectangular, so the cut erased the frame's own inner edge wherever it dipped inside the rect.
  Instead the **most common opaque colour inside the hole** is found — *counted*, not inferred —
  flood-filled from the hole so a bezel dipping in is not mistaken for content, and everything left
  is drawn whole over our content. A donor whose interior is a *picture* has no such colour
  (`Scooby Doo`'s wallpaper) and keeps the cut; so does one where more than **10%** of the hole
  survives the erase. `SkinnedSurfaceFrameArtwork.paintsOverContent` carries the flag,
  `SkinnedSurfaceChrome.drawSkinFrame` and `PlexBrowserView.drawWinampModernChrome` honour it.
- **An animation tick that repaints content must repaint the chrome (W209).** `NetworkMonitorView`,
  `CavaView` and `PeppyMeterView` each had a content-only fast path for 60 Hz redraws that returned
  before the chrome overlay. Correct while chrome is a border *around* content; wrong the moment any
  of it overlaps, which is what painting over the content made true — the borrowed bezel was being
  erased on every tick. **The current static frame probe does not exercise this path**, which is
  why three rounds of artwork fixes changed nothing the reporter could see. Verify it with live-host,
  multi-frame captures. A hosted window with a fast path takes a
  full redraw whenever a skin lent a frame.
- **Shape, the second donor class — a *panel* (W207).** Over half the corpus lends no ring: measured
  at the library's own 550x464 on 2026-09-16, **88 of 185 archives lend a ring and 97 lend nothing**.
  But 77 of those 97 do state a window style, as **one fixed bitmap with the list inset inside it** —
  `anemone`'s `<subview id="playlisttray" backgroundImage="trayplaylist.bmp">`, 328x261 with its
  `<ITEMSPLAYLIST>` at 83,72 155x116 — which the ring rule rejected for having no edges to stretch.
  None are needed: **the hole states the four slice lines**, so the panel is nine-sliced (corners
  1:1, edge strips stretched, centre transparent) and resizes like any nine-patch. **32 archives lend
  one**, and the ring's 88 lines are byte-identical either side of the change, because a panel is
  only looked for when the skin states no ring anywhere. Three things the corpus forced, each of
  which read as "the derivation is broken": a drawer is authored `visible="false"` and a node that is
  not drawn **resolves no frame**, so the frame is built with the panel and its hole forced visible;
  a drawer is **parked outside the window it slides into** (`anemone`'s tray is at `left="307"` in a
  321-wide view), so the scene is built a second time on a canvas that contains it and the geometry
  re-read there; and **a player body with a list in it is not a frame** — `Erektorset`'s panel is its
  whole player, so a panel carrying the transport, the host sliders or the equaliser is refused, as
  the ring path refuses the player view by scoring it -100. What a panel cannot exclude is the
  donor's own *painted* controls: `Gorillaz` has a button strip in its bitmap, and those are pixels,
  not nodes.
- **A playlist that hides its items is not a hole (2026-09-26).** `firstHole` skips a
  `<PLAYLIST playlistItemsVisible="false">`: it draws only a toolbar, so it is a strip, not where the
  skin puts rows. `Heart_Butterfly`'s `panel` is a plain 149x205 blue box with such a strip 22pt
  tall at its foot, and slicing there put a 170pt band of blank panel above every hosted window
  (`caption=170`); `Josie_and_the_Pussycats`, the same Tattoo Media template, had `caption=44
  bottom=124`. Both now lend nothing and take palette chrome. Four archives author the attribute;
  `Compact`'s sits beside its real drawer list and `Radio` lends nothing, and both lines are
  byte-identical either side of the change (361x330 and 550x464). **`Compact`'s own frame is broken
  independently** — its drawer is three bitmaps and only the top one is sliced; see below (W314).
- **A panel with no top edge borrows its bottom edge (2026-09-26).** `activate`'s
  `playlist_drawer.bmp` is a U: rails and a rounded bottom, and a keyed-out 6px band where the tray
  slides out from under the player. Every hosted window wearing it had no top border and nothing
  opaque to drag by. `WMPHostedFrameTemplate.closingOpenTop` runs on the panel's slices: where the
  top strip between the slice lines is at least 90% transparent (alpha < 128 — the render leaves a
  faint fringe, and `activate`'s 9px right rail pokes one column past its 8px slice line), the
  bottom band is flipped into its place and the top margin becomes the bottom's. `borderInsets`
  reads the same slices, so growth follows. `activate` at 560x506: `caption=6` → `caption=13`.
  Panels only; a ring with an open top is not handled. Corpus on 2026-09-26 (180 archives, 45
  panels, 550x464 and 550x890, scale 1 and 2, A/B via `WMP_OPEN_TOP=0`): **one line moves in every
  configuration, `activate`'s**, top-edge gap 0.965 → 0.007 at 1x.
- **A panel still open on any side after that is refused (W314, 2026-09-26).** `Compact`'s
  `playlistDrawer` wears `drawer_right_top.bmp`, 185 of its 261 rows — the rest of its right rail
  and its bottom cap are child subviews, and it has no left edge because it slides out from under
  the player. `hasOpenSide` measures each band after `closingOpenTop` with the same 90%-transparent
  rule and throws `panelCannotBeSliced`, so the window keeps palette chrome. Assembling the panel
  with its artwork children was the other direction; it would still need a missing left side
  invented, and the reporter accepted the fallback. The top is only checked while `closingOpenTop`
  is on, so `WMP_OPEN_TOP=0` stays its own A/B; `WMP_OPEN_SIDE=0` is this rule's. Corpus on
  2026-09-26 (180 archives, 550x464, scale 1 and 2): **one line moves, `Compact`'s**.
- **Two archives lend no frame by name (2026-09-26): `Ocean` and `Plus! Pulsar`**
  (`WMPHostedFrameTemplate.lendsNoFrame`). `Ocean`'s `background_pl.bmp` carries the player's
  aquarium panel beside the list, so the sliced panel put that picture into every hosted window.
  `Pulsar`'s `plView` ring came out 0.33–0.41 bare on every side. No rule separates them: a
  bare-edge threshold that takes Pulsar also takes `deepbluesomething`, `The_Last_Samurai` and
  `KungFuChaos`. So they are named, the reporter accepted the palette fallback, and
  `WMP_FRAME_DENYLIST=0` is the A/B. Corpus at 550x464, scale 2: those two lines move and nothing
  else. A skin added here should have failed the same search for a rule first.
- **How the window and the border share the space: the window is grown (W207, closed 2026-09-16).**
  **The interior keeps its size and the border is added around it** — `HostedWindowBorderLayout`,
  one central rule for the nine registered growth participants listed in `windows/hosting.md`, driven off
  `WMPHostedFrameProvider.donorInsets`, which answers a donor's four borders *without reference to any window* because a 600x150 analyser can
  never render a frame carrying `anemone`'s 173x145 and so could never learn its insets from one.
  A panel too small to carry its borders at 1:1 is answered nil and keeps palette chrome until
  growth lands. Exact panels preserve their sliced borders; rings can scale below the donor floor
  or when mapping their cropped extent onto the target. Pending renders may return provisional
  artwork, re-laid out from the nearest render rather than scaled. `wasScaledToFit`
  records extent-to-target scaling or provisional scaling, not exclusively a below-floor case.
  Three answers preceded it and each was reported wrong:
  composing at the borders' own size (a five-point hole), refusing the window (the border came off
  everything but PeppyMeter), and a uniform scale-to-fit (the thin border the report was about).
  **Two more were tried and are wrong for reasons worth keeping.** Growing to the donor's *declared
  floor* so a ring lands 1:1 — `Ice` declares `min=585x308`, so every hosted window was forced to
  that at once, which is the ring path's own recorded rejection (*forcing every hosted window up to
  the donor's minimum moves windows the user placed*) confirmed by test. And measuring the growth
  against the donor's raw margins rather than through `reclaimingSideRacks` — `Ice`'s `plView`
  states a 157pt right rack, and growing by it put 157pt of decorative artwork on every window's
  right edge with nothing in it. Read `WMP_BORDER_TRACE` in `reference/harness.md` before touching
  this: three of its failure modes are invisible in both a screenshot and a `HOSTED-FRAME` line.
- **A donor's *own rail* is not a rack, and the reclaim stops where its artwork does (W212).**
  `reclaimingSideRacks` gives a lopsided margin back to our content on the reading that it is
  furniture; on `Alienware Invader` half of it is a 99pt opaque rail, and with the frame painted
  over the content 54pt of every hosted window was laid out under it. Neither position nor paint
  order separates the two — W210 settled that both sit in the reclaimed strip. What does is that
  the rail is *artwork* and a dropped rack leaves bare canvas, so `clearOfTheDonorsOwnRail`
  measures how far in from each edge the donor paints something that is neither transparent nor
  its **interior fill**. Excluding the fill is the whole rule: these border bitmaps carry the
  interior colour baked in for the skin's own list to cover (`f_right_tile` is 96px wide with 73
  of them opaque white), so a run measured on alpha alone reads a 96pt border and takes back the
  width the donor gives its own content. `borderInsets` **composes** the frame at the reference
  size rather than deriving insets from markup, so the window is grown by the border it will wear.
- **The reclaim measures a rail where the rail *is*, and a donor with no fill is not a donor with
  no rail (W219).** `clearOfTheDonorsOwnRail` above assumed two things that `TheUnit` breaks at
  once, and between them our content was handed the skin's own left rail — which the rectangular cut
  then erased, leaving no left bezel on any hosted window and our black ground running out to the
  window's edge. First, the run measured **in from the window's edge**, and this border grows the
  other way: `left_stretch.png` is 37px wide with its outer **30 the transparency key** — the
  window's curved silhouette — and the rail in the inner 7, so a run anchored at the edge is starved
  by 30 bare columns and answers zero. It now skips the bare lead-in; where a border does reach the
  edge the skip is zero and every number is unchanged. Second, the rule **returned the rack
  unmeasured whenever the hole carried no dominant fill**, which is the reclaim at its most
  dangerous rather than its safest — and a donor whose client subview is a `<VIDEO>` region has no
  fill at all, because its contents are ours and are subtracted, so its hole renders 97%
  transparent. Excluding nothing measures every opaque pixel in the strip as border, which can only
  make the reclaim *smaller*. Corpus at 550x464: **8 lines move across 7 skins**, all of them
  content the donor paints (`livin_it_skate`'s green rail, `Blinx`'s orange wing, `Crimson_Skies`),
  and the four rack skins the reclaim exists for — `Star Wars`, `STALKER`, `WoW`, `Halloween` — are
  byte-identical. **A column-wise measure was tried first and is wrong**: it re-refused exactly
  those four racks, which is the 2026-09-15 *"reclaim it, we have no content for it"* report coming
  back.
- **A panel declared larger than its bitmap ends where the bitmap does (2026-09-29).** `Kids`
  declares `vPl` 201x137 over a 127-tall `background_pl.bmp`, so the slice's bottom 10pt was empty
  and every hosted window wore a see-through strip under its bottom edge (`gaps=` bottom 1.000).
  `panelSlices` trims transparent rows and columns off the **bottom and right only** — a bitmap is
  drawn from its top-left — and never past `minimumBorder` outside the hole. `WMP_PANEL_TRIM=0` is
  the A/B. Corpus at 430x306 and 550x464: 13 panel lines move, `Kids` to 0 bare on every edge, and
  a before/after picture of each showed none worse (`Grinch`, `deepbluesomething` and `New Super
  Mario Bros` reach the window edge where they fell short).
- **A view drawn whole cannot come apart, but it can still be drawn short (W212).** The frame build
  is outside the script runtime, so a side tile whose height only the skin's `onResize` sets keeps
  its bitmap's — a 20% bare run down each side of `Alienware Invader`, which is the desktop showing
  through a 99pt rail. The span repair is reachable under the whole-view render, under three guards
  that each answer a measured failure: **furniture is classified on the first pass** (a stretched
  rack reaches the bottom edge and the edge exemption lets it back in), **only the axis that came
  out bare is spanned** (`edgeGaps` is `[top, left, bottom, right]`; spanning the top tile too
  painted its white filler over both rails, which are drawn before it), and the repair is refused
  if the window's **content rect moves** (stretching a tile down grows the alpha bounding box and
  the hole rides the crop — `KungFuChaos` and `The_Last_Samurai` are that shape).
- **And what reaches that repair is a *length*, not a share of the edge (W228).** The run a
  script-sized rail leaves is the same at every window size — `Alienware Invader`'s is **107pt** —
  so a gate on `gaps` alone asks a question about the window: 107pt is 0.231 of a 464pt-tall one
  and 0.132 of the library browser's 810. The identical hole was therefore repaired on nine hosted
  windows and left open on the tenth, which is the only one that opens taller than 107 / 0.15 =
  713pt, reported 2026-09-18 as *"alien invader media library window draws broken. the other
  nullplayer windows draw ok"*. `edgeCameOutBare` now takes either test — the fraction, **or**
  `ringEdgeGapPointLimit` = 40pt measured along that edge — and 40 is in the same empty middle
  0.15 sits in: at 710x810 the corpus's closing rings run 0 to 24.3pt and its open ones 49.7, 85.2
  and 106.9. One `HOSTED-FRAME` line moves corpus-wide and 550x464 is unchanged. **Read a `gaps=`
  fraction back into points before believing a defect belongs to the window it showed up on** —
  the number is the frame's defect divided by the window's size, and one hosted window differing
  is otherwise the signature of that window's own layout (`reference/harness/live-loop.md` § *Capturing the hosted windows*).
- **A strip in a corner slot that its script sizes reaches the corner in its row (2026-09-29).**
  `Crimson_Skies` and `T3-Skynet_Media_Player` (one author) fill the right half of their top and
  bottom bars with `plTopStretch`/`plBotStretch`: tiled, no width, no alignment — so they land in
  the top-left and bottom-left slots as *extras*, which `note` never spans — widened only by
  `checkPlViewSize()` (`width = view.width / 2`). The strip kept its 4px bitmap width and a column
  opened that grows by half of every point past the donor's 373: 31pt at 430, under the 40pt the
  repair above needs. `spannedAcrossNodeIDs` gives such a tile its width on **every** pass, first
  included, read off one extra build: **to its row's right corner, not the canvas edge** — the
  154-tall `f_top_s_2.png` spanning the canvas hung 6pt of black shadow across the 148-tall
  corner's rail — and **only if it shares at least half its height with that corner**, because
  `Alienware Invader`'s second left-rail tile is the same markup shape further down the side and
  was laid across the window. `WMP_FRAME_SPAN_TILES=0` is the A/B. Corpus at 430x306 and 550x464:
  those two skins move and nothing else.
- **A frame piece the donor's `onLoad` shows or hides follows it (2026-09-29).** W145 kept only
  `alphaBlend` and `backgroundImage` from the off-screen `onLoad`. `WALL-E` stacks two frame sets in
  `mainView` — `sub1_*` shown, `sub2_*` authored `visible="false"` — and its white theme is
  `onLoad` revealing `sub2_*` while `sub1_*` takes the narrower `_4` bitmaps, so the frame wore
  only the underlay: a seam in its top edge, no right rail. `appearing(_:)` now keeps `visible`
  too, **on `ringNodeIDs` only** — a script showing the skin's own content is not the frame's
  business. The probe runs no `onLoad`, so no sweep measures this; it was checked live on
  PeppyMeter under `WALL-E`'s white theme.
- **A rail that is mostly hole is still a rail, and a stretch baseline read through an expression
  is read at the authored canvas (2026-09-23).** Two defects kept `Back to the Future Trilogy`'s
  right edge bare on any window taller than about 300pt, and 21 skins' bottom bars bare on tall
  windows. `authoredDimension` read `height="jscript:view.height"` at the live canvas, so a
  `stretch` child of that container never grew; that bug was in the skin's own window too. And
  `ringRender`'s furniture test dropped wide side tiles that carry the list's colour baked in
  beside a thin rail. A bitmap subview authored to stretch along a side that runs out past the
  hole is now kept (`railsDownNodeIDs`/`railsAcrossNodeIDs`). **Probe a hosted frame at a tall
  size, not only at 357x238 and 550x464**: a script- or expression-sized rail's bare run grows
  with height and is invisible below it. The measurements are in
  [the dossier](../skins/back-to-the-future-trilogy.md).
- **A borrowed glyph is a lie about what it does (W208, and it is why W209 subtracts).** A skin's
  own buttons are anchored to its window's edges exactly as its corner bitmaps are, so nothing in
  the markup separates them by position. `Ice` writes its playlist shuffle six nodes before
  `Vid-bottomleft.bmp`, and while the frame was *assembled from selected pieces* that glyph won the
  bottom-left corner on every hosted window. The selecting rules that answered it — transport-typed
  candidates refused, scripted transport refused in corners only — are **gone with the assembler**;
  the whole-view path drops every control unconditionally, which is both simpler and stricter, and
  it costs nothing now that no slot can be left empty by a refusal. The `HOSTED-FRAME` line cannot
  see this class of defect at all — it reports the piece count and the client hole, never which
  bitmap was drawn — so `WMP_HOSTED_FRAME_DUMP` is the instrument.
- **A resize grip is the window's corner, not a control's picture (W222).** Subtraction rule 4 — a
  subview whose `backgroundImage` is also a control child's `image` is that control's backing and
  goes with it — is right for a glyph painted twice (`Back to the Future Trilogy`'s shuffle pair)
  and wrong for a corner that is *authored as a button because that is the only node a `.wmz` can
  hang a mouse handler on*. `TheUnit` writes its rounded top-right corner and the top of its right
  rail exactly that way: `<subview backgroundImage="top2.png"><button image="top2.png"
  onmousedown="view.size('topright')"/></subview>`, three of them. The rule took all three off
  **every hosted window at once** — a square notch where the curve should be and the rail starting
  28pt down — reported 2026-09-17 as *"the issue is the right top corner … every window"*. **That
  it is the same on every window is the signature to read**: a piece the *frame* never had, as
  against a piece one window mislaid. The exemption is window geometry and nothing else
  (`isWindowGeometryGrip`): handlers that reach `view.size` or `view.dragMove` and never touch
  `player.`. The backing stays, the control walk still drops the button itself, our window keeps its
  own resize, and W193's 235 `view.size(corner)` calls are the population this serves. Corpus at
  550x464: **9 lines change and every one is a `gaps` value falling** — bare edge becoming artwork,
  on `Halo 2`, `Ice`, `Official Xbox` ×2, `XBOX`, `WWC` and both `TheUnit` archives — with no
  content rect moving. `Plus! Pulsar` is the one exception and is a pre-existing defect rather than
  this one: its donor is bigger than the window (`content=-191.111,38`, a hole starting off the
  window's left edge, before and after), so restoring a grip moved its alpha crop.
- **Refusing a corner is only right when the refusal is free, and a tie goes to the playlist
  (W179).** Both cases the corner refusal above was written for have a *second* declaration for the
  slot — `Ice` writes its shuffle glyph six nodes before `Vid-bottomleft.bmp`, `Back to the Future
  Trilogy` its repeat pair six before `f_top_left.png` — so dropping the control hands the corner to
  the real bitmap and the ring still meets. That is the whole population it was measured on, and it
  made the cost look like nothing. `Combat_Flight_Simulator_3` is the other shape: its playlist's
  top-left corner **is** the plate, `<subview backgroundImage="vid_top_left.png">` 190x29 with the
  repeat and shuffle buttons drawn on top as children with images of their own, and nothing else
  claims that slot. Refusing it emptied the corner, failed the four-corner guard, withdrew `plView`
  as a candidate **entirely**, and handed the skin's ring to `videoView` — so the library wore the
  film drawer's `BRIGHTNESS`/`CONTRAST`/`HUE`/`SATURATION` plate across its bottom bar, a
  *centre*-anchored extra that claims no slot, costs no score and is painted as decoration anyway.
  A refused corner is now taken back rather than losing the ring; nothing of the skin's behaviour
  comes with it, because the assembler draws the piece's own background command and never its
  children's and the whole-view path subtracts the subtree, exactly as W222's grip keeps its corner.
  **The second half is the donor contest.** Both views score 12 here — eight filled slots plus four
  for hosting content — so the winner was document order, which is the half of W209's `Project
  Gotham Racing 2` judgement that scoring *filled slots* never reached: that fixed the case where a
  video view scores higher and said nothing about the case where it ties. Corpus at 543x890 scale 2:
  the corner rule alone moves **nothing**, and both together move **13 lines across 12 archives,
  every one `video → playlist`**, each holding or improving its `gaps=` (`WWN` rails 98pt → 21,
  `The_Sentinel` bottom 0.416 → 0.014, `TripleX` and `xXx` tighter). **Write the tie-break as "a list
  beats anything that is not a list" and the corpus punishes it**: 17 lines, two regressions, both
  `visView → plView` — `Constantine` grows a 145pt right rack where it had an 18pt rail, which is
  `Ice`'s recorded rack rejection coming back, and `QuickSilver`'s right edge goes 0.012 bare →
  **0.908**. A skin gives its playlist a rack and its visualiser a rail, so `hostsVideo` excludes
  `<EFFECTS>` deliberately. **And read this bullet before believing a bottom-bar defect is a
  composition defect**: the ring a window wears is chosen per *view*, two steps upstream of
  anything `HOSTED-FRAME`'s inset fields describe — the field that names it is `view=`.
- **The ground a hosted window paints is its content hole, not the window**
  (`SkinnedSurfaceChrome.hostedGroundRect`). Every window in the spectrum family paints its own
  ground in its own `draw` and nothing shared owned that step, while `drawSkinFrame` deliberately
  fills only the client hole — so a view doing `bounds.fill()` first turns a shaped frame into a
  black box with the skin drawn inside it. Cava, `flow` and PeppyMeter each had one, and it was
  latent for as long as every donor was a ring laid out to the window's own edges: a panel has a
  silhouette, and the slab showed through everywhere the skin was cut away. The rule lives in one
  place so a window added later inherits it; Waveform, Spectrum, AudioAnalysis and ProjectM never
  filled the full bounds in the borrowed path, and Playlist, EQ and the library already filled
  `contentRect` only.
  **And the hole crosses between the two coordinate spaces as *insets*, never as a rect (W221).**
  `contentRect` is the artwork's own top-left scene space — what `drawSkinFrame` paints in, flipped
  — and those three views fill their ground in the window's bottom-left space, so handing the rect
  over mirrored the hole vertically. Invisible while a donor's caption and bottom border are about
  equal, which every donor before this one was; `TheUnit` lends a **5pt caption over a 60pt bottom
  bar**, and all three grounds landed 55pt low — the top of every hole left transparent with the
  desktop showing through it and the ground running out under the bottom bar. It reads exactly like
  a window with a hole punched in it, and it survived the first round of fixes because the *frame*
  was correct in every capture. `hostedGroundRect` now builds the rect from
  `artwork.scaled(to:).metrics`, which is orientation-free, and any new caller filling a rect in a
  view's own space must do the same.
- **A borrowed frame that arrives late is a *layout*, not a repaint (W220).** The ring is derived
  asynchronously for the window's own size, so it lands **after** the view has already laid out
  against the classic fallback metrics, and `hostedSurfaceStyleDidChange` did nothing but
  `needsDisplay = true`. A repaint redraws the chrome around subviews still framed for the old hole:
  three of these windows host one (`ProjectMView`'s GL view, `AudioAnalysisView`'s SwiftUI host,
  `SpectrumView`'s), and on Visualizations that subview kept the **whole window** and buried every
  borrowed piece under the visualization — no caption, no rail, no bottom bar, on a window whose
  `HOSTED-FRAME` line was perfect. All nine hosted views now mark the layout dirty on that
  notification, and `ProjectMView` re-frames its GL view explicitly; it costs nothing where a view
  has no subviews. **A new hosted window wires this in step 3 of the checklist in `windows/native-windows.md`**, and the
  probe cannot see it: the frame is right, the artwork is right, and the picture is wrong.

**Nothing of ours is drawn over a borrowed ring — no title, no close glyph.** The ring is the
window's chrome, whole, and the only thing we add is a **hit area in its top-right corner**
(`SkinnedSurfaceChrome.closeButtonRect`, 40x26pt, capped by the band), because that corner is where
these skins paint their own close button and that painted × is what the user aims at. Every close
hit test reads that rect, `EQView` and `WaveformView` included — their classic 9x9 boxes are the
no-ring case now, not a separate answer.

**Four rules were tried in the band before this one and all four were wrong in the same way.** Guard
the lettering's contrast against the ring (W178), plate each control in a palette tone the artwork
cannot be confused with, centre them in the *lit* title bar found in the rendered pixels rather than
in the whole gap above the client hole, inset the close by the ring's right border and then cap that
inset at the band's height. Each was measured over the corpus, each shipped, and each had a
counter-example in the next skin the reporter opened — because **all four are inferences about
someone else's finished chrome, and `.wmz` markup states none of it**. `NVIDIA` is where the model
broke rather than the tuning: an 84pt band with too little contrast to call a bar (`strip=none`), so
the controls centred in the whole band and landed on the curve where its body starts, directly under
the restore, minimise and close the skin paints there itself. Reported 2026-09-15 as *"issue after
issue — what is the problem with your implementation"*, and the answer was that there was nothing
left to tune.

**This is the difference `.wal` makes, and it is worth stating.** A Winamp Modern skin has a real
frame system: `<Wasabi:StandardFrame:*>` declares the frame, the client rect is measured from its
resize strips, and its title bar and buttons are declared controls wired to actions — so a hosted
window is *mounted* in the skin's frame and we draw no chrome at all. Nothing is inferred, and none
of this class of defect exists there. A `.wmz` has no frame system: no title-bar element, no close
element, no standard client-rect contract. Donor selection uses authored geometry and alignment;
rings are rendered whole after subtraction and panels are nine-sliced at their content hole.
The close target remains a convention rather than a declared skin control.
**When a `.wmz` question can only be answered by reading the artwork,
that is the signal to stop answering it.**

Placing the control *inside* the client hole was tried in between and rejected on sight — a close
box a user has to hunt for is not an improvement on one drawn over artwork. `WMP_CAPTION_TRACE=1`
prints the hit rect and the hole it was resolved against.

**The donor view is ranked, not taken.** Several skins wrap the *same* ring around an `upgradeView`
— the "your Windows Media Player is too old" nag panel — and declare it before the real one, so
document order borrows the frame of a window nothing was ever meant to look at (`xsn_sports`,
`Halo 2`, `T3-Skynet_Media_Player`). A view holding a `PLAYLIST`, `VIDEO`, `EFFECTS`, `LISTBOX` or
`EQUALIZERSETTINGS` outranks one holding nothing, and the presented player ranks last — its body is
what the user is already looking at.

**How the ring numbers were measured.** Not by the markup census: `harness.md` records that views are
the one thing it does not count, so these came from splitting each `.wms` on `<VIEW` with a
`WMPTextDecoder`-shaped decoder (BOM, then a positional BOM-less UTF-16 sniff, then Windows-1252) and
classifying each direct `<SUBVIEW backgroundImage=…>` child by its `horizontalAlignment` /
`verticalAlignment` pair. **85 of 180** archives by that scan; **86 of 180** when
`WMPHostedFrameTemplate.derive` is run over the installed corpus through `WMPSkinLoader`. Quote
whichever you re-derive, with the method — the engine's own answer is the authoritative one, and the
one-skin gap is the scan's, not the engine's.
