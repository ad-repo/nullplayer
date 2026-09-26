# `.wmz` colour keys, masks and shaped windows

Moved verbatim from `reference/rendering.md` § *Static scene and image contracts* and *Drawing the skin's own controls* on 2026-09-25; the router is
`reference/rendering.md`. Before an engine-wide change here, check the counter-evidence table in
`reference/skins/README.md`.

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

- **Drawn artwork always keys magenta, whatever alpha the sprite carries and whatever key the node declares.**
  WMP's implicit transparency colour (W78, W78a). The corpus is authored against it — 4,979 of its
  6,076 `transparencyColor` declarations (82%, 142 skins) are `#ff00ff`, `Halo 2` keys three
  siblings by hand and leaves `m_trans_no.png` to the default, and `Main_Street` authors one key in
  the whole file. The scene builder decides (`WMPSceneImage.implicitColorKey`, set only when the
  drawn artwork is not a built-in image) and the image store adds it to the declared keys. **The sprite's own alpha channel does not
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
  **A declared key does not suppress it either** (2026-09-26). `MSN`'s `funb`/`wlb` key `#ff0000`
  and their `hoverImage`s hold magenta in exactly the pixels the up and down faces hold red (193 and
  59), so the buttons grew a magenta fringe under the pointer. Every corpus node that declares a
  non-magenta key over artwork holding magenta means it transparent: `Ovoid`'s prev button
  (`#00FF00`, 332 in hover and down), `QuickSilver`'s pause (`#000000`, a 1,732-px surround) and
  `Plus! Pulsar`'s shutter (`#ffffff`, 49 on its edge). Clipping the state face to the normal face's
  keyed shape instead is **refuted** by `Grinch` and `Josie_and_the_Pussycats`, whose normal
  faces are wholly keyed and whose hover faces are the visible ones.

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

- **A child pixel of its container's key colour, over the container's keyed matte, is not drawn
  (`WMPSceneMatte`).** `robbie`'s `left_ear` keys `#FF0000` out of `robbie_ear_left.bmp` and holds
  the `vol` slider, whose three bitmaps are pure `#FF0000` in exactly the pixels the ear keys, under
  a `transparencyColor="#FF00FF"` of their own — a red wedge beside the face. The container is a
  keyed `<SUBVIEW>` whose `backgroundImage` is untiled at its own size and which states no region
  shape already (`clipMask` nil); a child draw carries the matte only when its artwork holds the key
  (`WMPImageStore.holdsKey`), and the renderer then splits it in two: plain inside the container's
  region, also keyed outside it. **Both conditions are load-bearing and each alone was measured and
  refuted** (2026-09-26): clipping children to the container's exterior matte moved 39 images —
  17,152 px of `Gorillaz`, `Ursula`'s drawer, `corona`'s `viewTiny` top edge; keying children by the
  container's colour everywhere punched out `Heart_Butterfly`'s and `Sports`' button glyphs and, on
  the white-keyed mask containers, `Plus! Hard Boiled`'s and `SlimLine`'s JPEG whites at JPEG
  tolerance. Splitting every draw under a matte left ±1-level seams on antialiased edges
  (`QuantumRedshift`, `Windows_XP_Media_Center_Edition`), which is why a child without the key keeps
  one draw. Sweep (179 archives): `robbie` 468 px and `Charlies_Angels_Full_Throttle`'s `viewPL`
  resize grip, 58 px of blue — the same idiom, its `f_resizer.png` drawn by a blue-keyed subview and
  by a magenta-keyed button inside it. `WMPClippingShapeTests
  .testAChildTakesItsContainersKeyOnlyOverTheContainersMatte` pins it.

- **A mask buffer's row zero is the authored top row.** A `CGImage` drawn into a bitmap context
  arrives that way round — `WMPMappingImage` says so in as many words — so "correcting for
  CoreGraphics" by reversing the rows mirrors the mask and clips the half it should keep. That is
  W47 arriving by a second route, and only a **top/bottom** fixture can see it: a left/right one is
  identical under a vertical flip, and so is a horizontal position ramp.
