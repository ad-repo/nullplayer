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
| `window.png`, `drag.png`, `inactive.png`, `active-alpha.png`, `about.png` | no | **ignored by FaceKit** | — |

Button names: `play`, `pause`, `stop`, `rw`, `ff`, `close`, `info`, `volume`, `menu` (playlist),
`music` (mode), `eject`. Indicator names: `play-indicator`, `pause-indicator`, `net`, `mp3`, `cd`,
`cddb`.

The files FaceKit ignores are not read by the Phase 1 loader. Their meaning is confirmed against the
corpus by the Phase 2 census, and a later row reads one only after that. Working hypothesis:
`window.png` is a hit region, `drag.png` a drag region, `inactive.png` the full inactive artwork,
`about.png` the face's credit art.

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
- XOR text (`…TextMode & 2`) is parsed and deliberately not drawn.
- The artist line truncates in the middle of the string. The album line scrolls as a marquee: an
  80-frame startup hold, then one pixel per two frames, with a 60 px gap before it repeats. `justify`
  or Reduce Motion pins it at offset 0.
- Panic's player fills the artist line with the title (or the file name) and the album line with
  `artist—album—format`. NullPlayer does the same.

## Draw order and state

Order: `base`, the current animation, time digits, track digits, indicators, then buttons and labels.
All images draw with `interpolationQuality = .none`.

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

Not read. The Phase 2 census confirms or refutes the working hypothesis above, and the result goes
here.
