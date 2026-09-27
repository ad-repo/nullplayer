# `.wmz` controls: buttons, button groups and sliders

Moved verbatim from `reference/rendering.md` § *Static scene and image contracts* and *Drawing the skin's own controls* on 2026-09-25; the router is
`reference/rendering.md`. Before an engine-wide change here, check the counter-evidence table in
`reference/skins/README.md`.

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

- **A `<POPUP>` is an equaliser preset menu and its items come from the skin's own script.** All four
  corpus popups call `appendItem` in an `onLoad` and apply the choice through
  `eq.currentPreset`; `WMPScriptOutput.listItems` carries them out of the transaction, because the
  markup names none of them. The four hardcoded entries that used to be shown were in no skin.

- **An `<EDITBOX>`'s `value` is a string.** Nine of the corpus's ten are `plSearchEdit`, a playlist
  search field whose `onKeyUp` reads it straight back, so it needs its own text path
  (`setWidgetText`) rather than the numeric `setWidgetValue`.
