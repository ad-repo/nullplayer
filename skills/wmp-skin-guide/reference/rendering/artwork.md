# `.wmz` artwork: sizing, scaling, decoding and animation

Moved verbatim from `reference/rendering.md` § *Static scene and image contracts* and *Drawing the skin's own controls* on 2026-09-25; the router is
`reference/rendering.md`. Before an engine-wide change here, check the counter-evidence table in
`reference/skins/README.md`.

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
  size and the artwork agree, a canvas the user grew still stretches the background as before.
  **A view the user cannot resize anchors too, whatever size its own script gives it** (2026-09-26):
  `gadget` opens its drawer with `view.height = 333` over a 336x246 `base_unit.bmp`, and stretched
  the player grew 35% taller while the view's black `backgroundColor` — keyed only when the art
  matches its frame — filled the window edge to edge. `backgroundFillMask` takes the anchored frame,
  so the fill stops where the art does and the rows below are the drawer's alone. Corpus sweep: 527
  of 529 images identical; `Asia MP11/vidWindow` (`SnapToVideo()` sizing a fixed view to the video
  plus a 92x93 border) now crops its 621x404 frame rather than squashing it, and `Scooby-Doo_2` is
  its known `Math.random()`. 17 corpus views declare a literal size alongside a resolvable background image and exactly
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

- **A one-shot animation that comes to rest on the still beneath it also ends showing nothing
  (landing).** `QuickSilver` (both releases) opens its shutter with a 30-frame `Shutter.gif` on a
  `zIndex="5"` button, ending on the same blue plate as `Shutterbg.gif`, the static button at
  `zIndex="1"` in the identical 300x56 rect. Between them sit the `zIndex="3"` `Meta` readout
  (status, artist - title, elapsed) and the closing `Shutter-rev.gif`, and nothing in the script
  ever hides the opening shutter. So holding its last frame showed the skin with no track info and
  a close button that animated invisibly. The GIF has no terminator, and **its disposal flags cannot
  tell it apart**: it switches to *restore to background* only on its last frame, exactly as
  `BlueCrush`'s hover pulses do, and those must hold. The art tells it apart:
  `WMPImageStore.finalFrame(of:landsOn:frameCount:)` compares the final frame against an earlier
  command with the same frame, clip, clip masks and at least the same alpha. It needs identical
  coverage and a mean channel difference of at most 4/255. The two QuickSilver GIFs are quantized
  separately (1.6 mean, single pixels 29 apart), so an exact match finds nothing.

  **Blast radius, measured 2026-09-26 over 180 archives.** Pairing every one-shot GIF's last frame
  with every same-size still in its archive gives **~130 candidate pairs in 30 skins**, almost all
  hover/down faces that settle back to the normal face (`The Unit`, `TripleX`, the Xbox family,
  `deepbluesomething`, `Stars and Stripes` and the `US …` family). The rule acts only where the
  still is *drawn beneath* in the same rect, and dropping a frame that matches what is beneath is
  invisible unless something sits between the two layers. A corpus render sweep with
  `WMP_RENDER_CLOCK=120` (past every one-shot end, unlike the default clock 0) fires it on **one of
  599 views**, `QuickSilver/mainView`'s `shutterbut`. Scripted, hover and click states are not in
  that sweep. `WMPGIFTerminatorTests` pins both the landing and the mismatched-art guard.

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

- **A slider spells `backgroundTiled` as `tiled`.** The SDK's `SLIDER.tiled` is the background's
  tiling, and 114 slider backgrounds across 24 skins author it that way (`Colorchooser`, `Compact`'s
  seek bar, `Headspace`, `Mandalay`'s EQ, `iconic`, `raveworld`, …). Reading only `backgroundTiled`
  sent them through the own-size rule above, which drew `Colorchooser`'s 1x11 `sliderBack.bmp` one
  pixel wide in its 40 px slider — thumbs over no track (reported 2026-09-26). Before that rule the
  bitmap was stretched, which hid the missing read. `WMPSceneBuilder.backgroundTiles`.

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

- **A node draws the artwork a script last gave it, not the one its markup declares.** Images were
  the one property class the script-override path skipped, and `Alienware Invader` — whose whole
  player is behind a 568-frame intro of `mainBack.backgroundImage = "png24/intro_anim_f<N>.png"` —
  drew nothing at all because of it (W75). An override is an authored path string and resolves under
  the same provider rules as markup; one the skin does not contain warns and leaves the authored
  artwork in place; `""` clears the property the way an absent attribute does. The rules and the
  traps are in `reference/object-model/reads.md` § *What a property read answers, and who wins*.

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

- The opt-in render dump writes one untracked PNG per view plus a JSON report. Corpus paths and
  output directories are local inputs/artifacts and must never be staged.

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
