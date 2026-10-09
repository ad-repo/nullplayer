# Audion face format

Read `../SKILL.md` first; its isolation rule binds every section here.

This is the face format as NullPlayer implements it, and the only copy of the specification (it moved
here from the decision record in Phase 1). FaceKit `AudionFace.swift` at `5b7c847` is the authority;
each rule names the FaceKit code it comes from. Where NullPlayer differs on purpose, the difference is
a row in `docs/audion-face/phase-0-decision-record.md` § *Deliberate departures from FaceKit*.

## Where it is implemented

| Concern | Type |
|---|---|
| every key's name | the role enums on `AudionFace` (`ButtonRole`, `IndicatorRole`, `DigitRole`, `AnimationRole`, `TextRole`); case order is FaceKit's draw order |
| reading `index.json` tolerantly, element by element | `AudionFaceDocument` |
| pairing elements with files, decoding | `AudionFaceLoader` (its private `Plan`) |
| font and colour resolution | `AudionFace.font(named:size:)`, `AudionFace.color(_:)` |
| top-left rects and the one flip | `AudionFaceRect.flipped(inHeight:)` |

- **Unknown keys are ignored** (`version`, `useAlphaChannel`, `useInactiveState`, `…TextRenderMode`).
- **An absent key or a zero rect is an absent element**, silently, as in FaceKit. A key that is
  present but malformed drops its element with `AUD0013`. `pause` reads `playButtonRect`, so one
  malformed play rect drops two buttons and yields two findings.
- **Files are matched case-insensitively** at the folder's top level, which is how FaceKit's lookups
  behave on a default macOS volume.
- **A file counts as present only if it carries a PNG header** and then decodes to the size that
  header declares. Anything else is absent, exactly as if it were missing.

## Files

| File | Required | Meaning | FaceKit |
|---|---|---|---|
| `index.json` | yes | geometry, colours, fonts, styles, PICT ranges | `AudionFace.load` |
| `base.png` | yes | the face artwork, drawn into the view's bounds | `init(from:)`, `draw(_:in:)` |
| `base-alpha.png` | no | window shape while active | `mask` |
| `inactive-alpha.png` | no | window shape while inactive | `inactiveMask` |
| `<name>.png`, `<name>-active.png`, `<name>-disabled.png`, `<name>-hover.png` | normal only | a button and its states | `decodeButton` |
| `<name>.png` + `<name>-on.png` | both | an indicator | `decodeIndicator` |
| `<PICTID>.png` | per range | digits and animation frames | `decodeDigit`, `decodeAnimation` |
| `window.png`, `drag.png`, `inactive.png`, `active-alpha.png`, `about.png`, `icon.png` | no | **ignored by FaceKit**; see § *Files FaceKit ignores* | — |

Button names: `play`, `pause`, `stop`, `rw`, `ff`, `close`, `info`, `volume`, `menu` (playlist),
`music` (mode), `eject`. Indicator names: `play-indicator`, `pause-indicator`, `net`, `mp3`, `cd`,
`cddb`.

Of the files FaceKit ignores, the loader reads only `about.png` (Phase 4: the info button's credit
art, decoded under the same limits as every image); § *Files FaceKit ignores* is what the census
measured in them.

## Geometry

- **Rects are top-left**, `{top, left, bottom, right}` in pixels, `right` and `bottom` exclusive.
- **A zero-width or zero-height rect means the element is absent** (`decodeRect` returns `nil`).
- **A button's size comes from its sprite**; only `top` and `left` are read from its rect.
  Indicators, digits, animations and text rects use all four edges.
- **`pause` shares `playButtonRect`.** While playing, play is hidden and pause is shown.
- **The window shape is `base-alpha.png`**, or `inactive-alpha.png` while the window is inactive and
  that file exists (`updateMask`). The mask layer uses `contentsGravity = .bottomLeft`: a mask whose
  size differs from `base.png` is anchored bottom-left, never stretched to fit. At a view scale above
  1 it is resized by that scale (`FaceKit.resize`).
- No `base-alpha.png` means no mask: the window is the full `base.png` rectangle.

## Digits and animations

- Time digits: four, 10 frames each starting at `timeDigitNFirstPICTID`. They show elapsed `mm:ss`.
- Track digits: two, **11 frames** each; frame 10 is blank. FaceKit always draws frame 10.
- **A digit with any frame missing is dropped whole**, and so is an animation (`return nil`).
- Animations — `connecting`, `streaming`, `netLag` — have `NumPICTs` frames at `FrameDelay` ticks of
  FaceKit's 60 Hz timer.

## Text

- Two lines: **artist** (`artistDisplayRect`) and **album** (`albumDisplayRect`).
- Colour: the `…TextFaceColorFromTxtr` key when it decodes, else `…TextFaceColorFromFace`, else black.
- Font: `…DisplayFontName` at `…FontSize`. A name that does not resolve falls back to Helvetica at
  that size; a missing name or size falls back to Helvetica 12.
- Style: eight booleans (bold, italic, underline, outline, shadow, condense, extend, justify). If
  **any one** of the eight keys fails to decode, the whole style is empty.
- XOR text (`…TextMode & 2`) is parsed and drawn plainly: FaceKit leaves its invert filter
  commented out.
- The artist line truncates in the middle of the string. The album line scrolls as a marquee: an
  80-frame startup hold, then one pixel per two frames, with a 60 px gap before it repeats. Only
  Reduce Motion pins it; `justify` truncates its text but it still scrolls (FaceKit sets the album
  label's own `justify` to false). `rendering.md` § *Text* has the full rule.
- Panic's player fills the artist line with the title (or the file name) and the album line with
  `artist—album—format`. NullPlayer does the same.

## Draw order and state

Layers, bottom to top: `base` and the current animation; the buttons; time digits, track digits
and indicators (FaceKit's `sublayer`, zPosition 2, **above** the buttons at 1); the labels; the
mask. All images draw with `interpolationQuality = .none`. `rendering.md` § *Draw order* has how
each layer composites.

| Element | State rule (`AudionFaceView`) |
|---|---|
| button image | disabled, then pressed, then hover, then normal — the first present wins |
| CD, CDDB | always off |
| NET | on when duration ≠ 0 and a stream animation is active |
| MP3 | on when duration ≠ 0 and no stream animation is active |
| play indicator | on while playing |
| pause indicator | on when duration ≠ 0 and not playing |
| stop | enabled while there is a duration |
| volume | a popup slider window, 19×96 |
| time digits (click) | a popup position slider, 192×19; scrubbing pauses playback and resumes on mouse-up |

## Files FaceKit ignores

FaceKit reads none of these, so neither does NullPlayer. What they hold, from
`scripts/audion_face_census.sh` over the 856-face corpus (2026-10-08; commands and raw tallies in
`harness.md` § *Measured*):

| File | Faces | What it is |
|---|---:|---|
| `window.png` | 853 | **The window region**, 1-bit: opaque, black inside, white outside — Mac OS 9's shape for a window with no per-pixel alpha. Against `base-alpha.png`'s non-zero alpha its region has a median IoU of 0.973 (548 of 803 measurable at ≥ 0.95); it is coarser where the mask carries a soft glow or shadow. 30 are another size than `base.png`. |
| `drag.png` | 853 | **The drag region**, 1-bit like `window.png`. Inside the window region in 800 of 818 measurable faces, and smaller than it in 566; the rest of the face (artwork the author meant as a control or a label) does not drag. |
| `inactive.png` | 376 | **The whole face's inactive artwork**, opaque, `base.png`'s size in 374. Repaints none of `base.png`'s visible pixels in 180, under 5% in 67, 5% or more in 127. |
| `active-alpha.png` | 225 | **The active window's mask**, a duplicate of `base-alpha.png`: alpha identical in 151, different in 69, another size in 5. |
| `about.png` | 848 | **Credit art**, any size (`faceInfo` is the text form). |
| `icon.png` | 856 | **A 32×32 icon** for the face, in every face. Not in the Phase 0 list of five. |

The plan's Phase 3 view hit-tests by mask alpha, then control rects, then `drag.png`; these numbers
are what that rests on.
