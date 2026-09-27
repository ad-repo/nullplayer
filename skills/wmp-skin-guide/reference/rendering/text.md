# `.wmz` text, fonts and string resources

Moved verbatim from `reference/rendering.md` § *Static scene and image contracts* and *Drawing the skin's own controls* on 2026-09-25; the router is
`reference/rendering.md`. Before an engine-wide change here, check the counter-evidence table in
`reference/skins/README.md`.

- **A text that states no colour draws black.** The phase-2 default was white, recorded without a
  reason. `Colorchooser` — Microsoft's own SDK sample — draws its `red`/`green`/`blue` labels and
  its panel's `x` with no colour on a white panel, legible only against a black default. Of 895
  corpus texts authoring no static colour, the switch moved **8 views** (2026-09-26 sweep):
  `Colorchooser`, `Melvin`, `PowerToys/AlertDialog` (its warning was white on white), `Zengarden`,
  `cerulean`, `rad`, `digitaldj/DigitalDJ` and `Asimov_Radio`. The last was a second defect the
  white default had hidden — see `reference/bindings.md` on `jscript:` colours.

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
  `harness/probe-flags.md` § *The probe flags* on what a clean sweep does not prove.

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
  **A `jscript:<id>.<same property>` is read from that element too (2026-09-26).** The runtime
  evaluates `jscript:` for geometry only, so `Classic`'s `fontsize="jscript:clip_label.fontsize"`
  fell to the 12pt default beside its 9pt labels and ran its marquee into the pane's edge.
  `referencedNumber` answers the one-hop shape from the target's override or literal; any other
  expression still takes the default. `Classic` is the only archive that authors it.

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

- **A comma in `fontFace` is a fallback list (2026-09-26).** `Dreamcatcher`'s clock authors
  `fontFace="arial narrow,arial,tahoma,verdana"`, and the whole string went to
  `CTFontCreateWithName`, which never fails: it drew in **Helvetica**, whose shorter ascent put the
  baseline ~1.5 px above the metadata beside it (both `top="53"`) and under the opaque logo button
  above. Reported as *"display text getting chopped"*. `WMPTextMetrics.face(_:)` now splits on
  commas and takes the first entry CoreText resolves to its own family; a list naming none keeps
  its first entry, exactly as a single uninstalled name does, and a single name is untouched.
  **Reach: 62 uses across 40 of 179 archives** (`scripts/wms_grep.py -i -c
  '(fontFace|fontType)\s*=\s*"[^"]*,'`), Microsoft's own `Windows_XP_Media_Center_Edition` among
  them — every one had been Helvetica. No corpus sweep was run; the live capture is the evidence.
  Dreamcatcher's metadata cut at its right edge is not this defect: it is a running marquee in the
  120 px box the skin authors, `marqueeTrailingPad` short of it.

- **A face the skin ships is loaded from the archive (W304).** `WMPSkinFonts.register` runs in
  `WMPSkinLoader` off the main thread and registers each `.ttf`/`.otf` entry for the process, so
  `CTFontCreateWithName` finds the family by name — `Alpine7618_v09`'s `fontFace="Quartz"` drew in
  Helvetica before, wider than the LCD it was laid out for. **A family already installed is never
  registered over**: a skin must not change what `Arial` means to another window or skin family.
  Registrations are never undone; a second load of the same PostScript name is a no-op. Reach: 1 of
  180 installed archives ships a font (2026-09-25).

- **A text baseline may never sit higher than the face's own ascent (W114).** The rule was
  `max(fontSize, (height + fontSize) / 2)` measured from the box's bottom — fine while every
  `<TEXT>` had a generously tall authored box, and four pixels *above* the box once a text is sized
  by its own glyphs. `CTFontGetAscent` is the floor. It moves nothing that was already inside its
  box and 142 corpus images where text was drawing over the artwork above it.

- **`STATUSTEXT` and `CURRENTPOSITIONTEXT` are text controls with native WMP values, not unknown
  tags.** Model them as text for intrinsic sizing and paint; synthesize the latter's value from
  `player.controls.currentPositionString`. WMP right-aligns an otherwise-unqualified
  `CURRENTPOSITIONTEXT`, because it is normally the trailing cell beside a scrolling title.
  Cerulean exposed both requirements: omitting the tag removed its clock, and left alignment made
  the clock touch the title. `DURATIONTEXT` is the other half of the same clock and takes the same
  default. **An authored `justification="left"` must be named, not left to the default** — the
  default is `right` for these two tags, so a missing `left` case drew `pharaoh`'s
  `justification="Left"` duration flush right, 30 px clear of its `/` (W203).

- **Every overflowing `<TEXT>` scrolls, whatever `scrolling` says — a deliberate departure from
  WMP.** WMP defaults it to `false` and clips an overflowing readout. By the user's request an
  unauthored `scrolling` scrolls (`modernblue`'s artist and title), and since 2026-09-26 an authored
  or scripted `false` does too (`Science` authors it on its title and artist, and its shadow copies
  underneath scroll in step because they share the clock); the builder sets `scrolling` true for
  every text. The renderer and `animationCadence` still run a marquee only when the measured text
  overflows its box, so a readout that fits stays still. 67 of 180 installed archives author
  `false` somewhere; the scripted writes in the corpus are all `scrolling = (textWidth > width)`,
  which the overflow test already answers.
- **A marquee repaints at `marqueeFramePeriod` (30 fps), not once per `scrollingDelay` — also a
  departure, by request.** The offset is continuous in the clock, so `scrollingAmount` per
  `scrollingDelay` stays the speed and only the stepping goes: the 1 px / 100 ms default read as a
  10 fps stutter. **A frame repaints only the marquee's box over the last frame**
  (`WMPRenderer.render(reusing:dirty:)`, keyed on the same scene and dirty rect in
  `WMPViewPresentation.animationFrame`), and keeps the effects silhouette when the box's alpha is
  unchanged. `WMP_ANIM_TRACE` on `Science`, debug build: 18 ms → 2.4 ms a frame; 85% of the 18 was
  the silhouette flood fill. The dirty rect is the box widened to the line's full height, because
  the text clip is horizontal only and a descent below a short box was left behind by a box-sized
  repaint. `testARepaintOfTheDirtyBoxMatchesAWholeRender` pins repaint == whole render at 1x and 2x.
  A running marquee is clipped `marqueeTrailingPad` (4 px) short of its box's right edge — part of
  the same departure: `Classic`'s readouts end exactly on the info pane's border, and text scrolling
  out through it read as jammed against the frame (2026-09-26). A static readout is untouched.
- **An unsized `<TEXT>` is bounded by the surface it is drawn on — also a departure (2026-09-26).**
  WMP sizes a `<TEXT>` with no `width` to its glyphs, so the marquee above never engages: the box
  always fits. `anime` hangs its `wmpprop:player.currentmedia.name` title at `left="400"` with no
  width, and a real track name ran off the screen, over the bezel and out of the window. The
  builder now caps such a text at the right edge of the **smallest drawn sibling `<SUBVIEW>` under
  its origin**, and — when a sibling's artwork is transparent at the origin (the text starts in a
  keyed hole) — at the first opaque pixel of that hole across the text's own rows. The second half
  is not optional: `anime`'s screen is the `#00FF00` hole in the bezel drawn over the panel, and at
  the title's rows the rounded corner comes in 16 px short of the panel edge, so the panel bound
  alone left the last glyphs on the grey rim. A value that fits is untouched. **Reach, measured
  with `WMP_RENDER_HOST` seeding a long title/artist/album over the 185 installed archives: one
  node, `anime`'s `metadataTitle`** — a stopped-player sweep cannot see it at all.
  `WMPTextIntrinsicSizeTests.testAnUnsizedTextStopsAtTheEdgeOfTheHoleItStartsIn` pins it.
- **`<TRACKNAMETEXT>` is a `TEXT`.** `modernblue` is its one use (1 of 179) and authors its own
  `value`, so it needs no host default; as `.unknown` the title never drew.

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

- **`TEXT` reads `fontFace`, not `fontType`** — 109 skins against 21 — and `fontStyle` is a *set*
  (`"UNDERLINE, bold"` is authored), not one word. `fontSmoothing="false"` (95 skins) is a readout
  drawn as pixels; antialiasing it turns a 6 px digit into grey mush.
