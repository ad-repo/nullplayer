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
- Font: `…DisplayFontName` at `…FontSize`. A name that does not resolve tries the font the face's
  author shipped (`AudionFaceOriginalFonts`), then a bundled lookalike (`AudionFaceFontSubstitutes`:
  Chicago and its metric-twins, Kidprint, the pixel fonts with no original, Textile, SF Digital
  Readout), then Helvetica at that size. No name is Geneva 9, Audion's default; size 0 is 12; a
  missing size is Helvetica 12. An artist line with no font name takes the album line's name and
  size. All departures from FaceKit.
- Style: eight booleans (bold, italic, underline, outline, shadow, condense, extend, justify). If
  **any one** of the eight keys fails to decode, the whole style is empty.
- Alignment: `…Justify` centres a pinned line; a right-aligned line exists only in
  `AudionFaceTextOverrides` (below).

### `Txtr`, and what the conversion lost

Panic's original faces (`.sit.bin` at `download.panic.com/audion/faces/`) were Mac resource files.
Each line's text settings were a `Txtr` resource: **200** the artist line, **201** the album line
(**128** is the face template's leftover, Geneva 9 centred black, which Audion ignored). Big-endian:

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | size (0: QuickDraw's default, 12) |
| 2 | 2 | QuickDraw style bits: bold 1, italic 2, underline 4, outline 8, shadow 16, condense 32, extend 64 |
| 4 | 2 | TextEdit justification: 0 default (left), 1 centre, −1 right, −2 force left |
| 6 | 2 | transfer mode (`…TextMode`) |
| 8 | 6 | RGBColor, three 16-bit channels |
| 15 | — | the font name: the trailing run of printable bytes; empty means the system font |

The 2021 conversion to `index.json` kept the name, size, style and the colour's high bytes (all
1,467 lines agree), but turned justification into one boolean (`Justify` = centre or right), and
**dropped a line whose `Txtr` named no font**. `scripts/audion_txtr.py table` regenerates
`AudionFaceTextOverrides.swift` from the originals: per face, keyed by the SHA-256 of `index.json`,
the dropped lines (system font → Charcoal, through its lookalike) and the right-aligned ones. A
face edited after download no longer matches and keeps its own keys.

### Fonts the faces shipped

165 of the original archives carry fonts (`FOND`, `NFNT`/`FONT` bitmap strikes, `sfnt`), which the
conversion dropped. `scripts/audion_face_fonts.py` extracts them with each one's licence evidence;
the 29 freeware families an installed face names ship in `Resources/Fonts/AudionFaces/<family>/`
as `sfnt-0.ttf` and `<size>-0.nfnt` with a `NOTICE.txt`. Commercial fonts and ones whose author
prohibited redistribution never ship (Kidprint, Sand, Textile, VT100, the Monotype/ITC/Bitstream
families, SF Digital Readout, Junior Pro and others); they keep lookalikes.
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
