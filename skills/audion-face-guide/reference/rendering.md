# Rendering Audion faces

Read `../SKILL.md` first; its isolation rule binds every section here.

This file owns the one draw path the harness and the screen share:

| Type | Role |
|---|---|
| `AudionFaceHostState` | pure playback snapshot: play state, elapsed and duration, track index, title/artist/album/format, stream phase, window active, Reduce Motion; derives `hasTrack`, `artistLine` and `albumLine` |
| `AudionFaceInteractionState` | hovered and pressed button, and buttons the window disables (the volume button while its slider is open) |
| `AudionFaceScene` | `(face, host, interaction, frame, scale) → [AudionFaceDrawOp]`, one function per element kind; also `visibleButtons` and `button(atX:y:)`, the hit test. Each op's `Element` (`.button(.stop)`, `.label(.album, offset:)`, …) decides its layer |
| `AudionFaceText` | one text line to a `CGImage`, adapted from FaceKit's `draw(text:…)` (carries Panic's header) |
| `AudionFaceRenderer` | ops to a `CGImage`; depends on the scene, never the other way |

The rules are FaceKit `AudionFaceView`'s, verified against the oracle (`harness.md` § *The oracle*,
856/856 geometry-identical). A change here is checked with the census, the sweep and the oracle
comparison.

## Draw order

FaceKit is a layer tree, not a draw list; `AudionFaceDrawOp.Layer` reproduces it bottom to top:

| Layer | FaceKit | Contents | Compositing |
|---|---|---|---|
| `base` | the view's own layer | `base.png` stretched to the bounds, then the current animation frame | each op **clears its rect first**, so an animation frame's transparent pixels cut a hole in the base |
| `buttons` | the `NSButton` subviews, zPosition 1 | the visible buttons in `ButtonRole.allCases` order (FaceKit's `addSubview` order: play, pause, stop, rw, ff, eject, close, info, volume, menu, music) | source-over |
| `readouts` | `sublayer`, zPosition 2 | time digits 1–4, track digits 1–2, indicators CDDB, CD, NET, MP3, play, pause | its own transparent buffer, each op clearing its rect first, then source-over — **above the buttons** |
| `labels` | the `LabelView`s, zPosition 10 | artist, then album | unscaled, top-aligned, clipped to the box |
| `mask` | the layer mask | the active or inactive mask | keeps only the alpha it covers |

The zPosition order is the screen's. `CALayer.render(in:)` ignores it, which is why the oracle host
sorts by it (`harness.md` § *The oracle*); 88 faces have a button overlapping a readout.

## Images

- Every image draws with `interpolationQuality = .none`, stretched to its rect, at an integer
  scale. Digits, indicators and animation frames fill their authored rect; a button's rect takes its
  size from the sprite.
- **Button state**, first match wins: disabled → `-disabled` (else normal); pressed → `-active`;
  hovered → `-hover`; normal. Stop is disabled while the duration is zero; every other button is
  enabled (all are wired, decision record § *Button mapping*) unless the window disables it.
- Play hides while playing **if** the face has a pause button; otherwise play stays. Pause shows
  only while playing. Both share `playButtonRect`, so the hit test answers whichever is visible.

## Mask

The active window's mask is `base-alpha.png`; while the window is inactive it is `inactive-alpha.png`
when the face has one (FaceKit `updateMask`). It is drawn at its own size from the bottom-left
corner (`contentsGravity = .bottomLeft`), so a mask of another size (`AUD0008`) is anchored, never
stretched, and pixels it does not cover become transparent. At a scale above 1 it is scaled
nearest-neighbour (a departure; FaceKit uses high-quality resampling). No mask: the full rectangle.
**Decided in Phase 4: the inactive mask is used whenever the window is not key**, as FaceKit's
host does through `isInactive`; `isWindowActive` follows key status (`windowDidBecomeKey` /
`windowDidResignKey`). `useInactiveState` is not read: it is false in every corpus face (the
decision record's count), so gating on it would retire `inactive-alpha.png` everywhere.

## Digits and indicators

- Time digits show elapsed `mm:ss`: `m/10`, `m%10`, `s/10`, `s%10`. A value past the frames
  (100 minutes or more) leaves that digit undrawn, as FaceKit does.
- Track digits show the 1-based playlist index 01–99, or frame 10 (blank) with no index — a
  departure; FaceKit always draws the blank.
- Indicators: CD and CDDB off; NET on with a duration and a stream phase; MP3 on with a duration and
  none; play on while playing; pause on with a duration while not playing.
- Animation: `streamPhase` picks connecting, streaming or net-lag; the frame is
  `(tick / FrameDelay) % count`, frame 0 when the delay is not positive.

## Text

`AudionFaceText.image` is FaceKit's `draw(text:…)`: the font scaled by the view scale, the
bold/italic/condense/extend traits substituted (extend is requested under the *condensed* mask, as
FaceKit does), underline, a 4 px shadow, outline as a clear fill with a stroke, then one CoreText
line in an image as wide as the whole string, baseline at `(ascent − descent) / 2`.

| Line | Text | Truncation | Marquee |
|---|---|---|---|
| artist | the title; nothing for an empty one | always cut from the middle with `…` | never |
| album | `artist—album—format`, skipping absent parts | only when justified, or under Reduce Motion | scrolls unless Reduce Motion — **even when justified**, because FaceKit sets the album label's own `justify` to false |

A box 12 px wide or narrower draws no text (FaceKit's `rect.width > 12`). The cut trims one character from each side of the middle
until the line is strictly narrower than the box; one exactly as wide as the box draws nothing, as
in FaceKit. NullPlayer stops when nothing is left to trim, where FaceKit would loop forever.

The marquee (`AudionFaceScene.marqueeOffset`): an 80-tick hold, then one pixel every two ticks, with
the text re-entering from the right edge after a 60 px gap; all widths in device pixels.

**XOR text** (`…TextMode & 2`) is drawn plainly. FaceKit parses it and leaves its invert filter
commented out.

## Departures from FaceKit

The table is the decision record's § *Deliberate departures from FaceKit*. Of those that touch
rendering, the oracle comparison avoids each by construction: it renders at 1× (mask resampling) and
with no track index (track digits); and FaceKit rendered every corpus face's canonical states
without looping, so the text-trimming stop does not fire there.
