# Audion Faces Phase 0 decision record

**Date:** 2026-10-08
**Implementation branch:** `feat/audion-faces` (worktree `.claude/worktrees/audion-faces`)
**Implementation base:** `a950f44e` (`origin/main`)
**Product exposure:** none — `AppFeature.audionFaceMode` is DEBUG-only until Phase 7
**Baseline at the base commit:** `swift build --build-system native` passes; `swift test --build-system native`
executes 2,972 tests, 18 skipped, 0 failures.

Audion faces are the fifth skin family, beside Classic, Original, Winamp Modern (`.wal`) and Windows
Media Player (`.wmz`). The plan this record locks is `~/.claude/plans/in-a-worktree-only-rippling-kay.md`;
the ranked work is `AUDION_TASKS.md`.

## Decisions

- **This engine is a port, not a reverse engineering.** Panic's own viewer library, FaceKit, is the
  authority on what a face means. Where this record and FaceKit disagree, FaceKit wins unless the
  disagreement is listed under *Deliberate departures from FaceKit* below.
- **A FaceKit oracle is part of the harness (Phase 2).** FaceKit renders ground-truth images, so an
  Audion sweep diff is classified against a real reference. This is the one family where a diff
  against the oracle *is* evidence of a defect, unlike `.wal` and `.wmz`.
- **Port the semantics into NullPlayer's layering; do not vendor FaceKit.** FaceKit is an AppKit view
  with buttons as subviews. NullPlayer splits it into a pure engine (`AudionFace/`) and an AppKit
  layer (`Windows/AudionFace/`) with one draw path shared by the harness and the screen.
- **Every face button is wired**, including the five Panic's viewer leaves disabled (eject, close,
  info, playlist, mode). The mapping is *Button mapping* below.
- **NullPlayer's own windows are painted from a face-derived `SkinnedSurfaceStyle`**, the answer
  `.wmz` uses. See *Auxiliary-window policy*.
- **Faces install as folders.** Import accepts a face folder, or a `.zip` holding one or more face
  folders (Panic's distribution format).
- **The loading limits below are locked**, and are never relaxed to make one face load. A limit that
  turns out to be mis-specified against its own threat model is amended here, with the argument made
  about the threat and not about the face.

## Provenance and attribution

| Item | Value |
|---|---|
| Upstream | FaceKit, `https://gitlab.com/panicinc/facekit` |
| Pinned commit | `5b7c847` ("Remove personal xcuserdata directory") |
| Copyright | Copyright 2020-2021 Panic Inc. |
| License | GPL-3.0-or-later (each file's header: "either version 3 of the License, or (at your option) any later version") |
| NullPlayer license | GPL-3.0-only — compatible: a "3 or later" work may be combined under 3 |
| Files that define the format | `FaceKit/AudionFace.swift` (519 lines), `FaceKit/AudionFaceView.swift` (1029 lines), `FaceKit/AudionSliderWindow.swift` |

Rules:

- **An adapted file keeps Panic's header verbatim**, followed by a NullPlayer line naming the FaceKit
  file it adapts and the pinned commit. Candidates: `AudionFace.swift` (from `AudionFace.swift`),
  `AudionFaceRenderer.swift` (text drawing from `AudionFaceView.swift`), the slider popup (from
  `AudionSliderWindow.swift`). A file written from scratch carries no Panic header.
- **The notice lands with the first adapted file (Phase 1), not in Phase 7.** The adapted code is
  compiled into every build from the moment it is committed, DEBUG gate or not. The mechanism is the
  existing notice system (`docs/third-party-notices.md`): one row in
  `scripts/third_party_components.tsv`, then `scripts/generate_third_party_notices.sh`.

  ```text
  facekit	FaceKit (Panic Audion face viewer)	GPL-3.0-or-later	Copyright 2020-2021 Panic Inc.	https://gitlab.com/panicinc/facekit	5b7c847 (adapted source)	ThirdPartyLicenses/licenses/GPL-3.0.txt	-
  ```

  Phase 7 adds the human-readable credit to `LICENSE` and the user guide; it does not introduce the
  notice.
- **No Panic artwork is committed or bundled.** That includes `Smoothface 2`, the face FaceKit
  bundles as its default: its artwork's licence is not stated separately from the code, and the
  family's fallback is app-authored (`AudionFaceUnskinnedView`). Test fixtures are synthesized in the
  test that uses them. The corpus lives outside the repo.
- **Oracle output is never committed.** The oracle script clones FaceKit at the pinned commit into a
  cache outside the repo.

## Format specification

A face is a folder holding `index.json` and PNGs. FaceKit is the authority; each rule below names
the FaceKit code it comes from.

### Files

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

### Geometry

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

### Digits and animations

- Time digits: four, 10 frames each starting at `timeDigitNFirstPICTID`. They show elapsed `mm:ss`.
- Track digits: two, **11 frames** each; frame 10 is blank. FaceKit always draws frame 10.
- **A digit with any frame missing is dropped whole**, and so is an animation (`return nil`).
- Animations — `connecting`, `streaming`, `netLag` — have `NumPICTs` frames at `FrameDelay` ticks of
  FaceKit's 60 Hz timer.

### Text

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

### Draw order and state

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

### Deliberate departures from FaceKit

Each is classified as an expected oracle difference, never silently.

| FaceKit | NullPlayer | Why |
|---|---|---|
| A missing `…TextMode` or `…FirstPICTID` key throws, and the whole face fails to load | the element is dropped with a finding | one malformed key must not cost the face; FaceKit's own handling of every other key is already per-element |
| The mask is resized with `interpolationQuality = .high` at scale > 1 | nearest-neighbour at an integer scale | a 1-bit window shape should stay 1-bit; antialiased mask edges blend into the desktop. Oracle comparison runs at 1×, where the two agree |
| Track digits always draw the blank frame | the real playlist index 01–99, blank when there is none | NullPlayer has a playlist; the face authored the digits. The oracle comparison renders with no track index, so the two agree |
| eject, close, info, playlist and mode are disabled | wired (see *Button mapping*) | user decision, 2026-10-08 |
| The volume and position sliders are FaceKit's own `NSWindow` subclass | ported into `Windows/AudionFace/`, drawn the same way | layering |

## Button mapping

Each button maps to an existing NullPlayer action. No new behaviour is introduced for a face.

| Face element | NullPlayer action |
|---|---|
| play / pause | play / pause (they swap while playing) |
| stop | stop; enabled while there is a duration |
| rw / ff | previous / next track |
| volume (`volume*.png`) | popup vertical slider window, ported from `AudionSliderWindow` |
| time digits (click) | position slider; scrubbing pauses and resumes like FaceKit |
| playlist (`menu*.png`) | toggle the NullPlayer playlist window |
| eject | Open Files… |
| info | track info panel; `faceInfo` and `about.png` in a sub-item |
| mode (`music*.png`) | cycle shuffle/repeat |
| close | close the main window, the same as the app's close action |
| track digits | real playlist index 01–99; blank frame 10 when there is none |
| MP3 / NET / CD / CDDB | local file / stream / off / off |
| connecting / streaming / lag animations | radio and stream buffering states from `AudioEngine` / `StreamingAudioPlayer` |

Right-click opens the standard main context menu. Keyboard shortcuts go through the existing handlers.

## Auxiliary-window policy

Two separate decisions, as `skin-subsystem-blueprint` requires.

- **NullPlayer's own windows** (playlist, EQ, library, visualizers, spectrum, waveform, analysis,
  PeppyMeter, Cava, Flow) use the shared controllers, painted from `AudionFacePalette`'s
  `SkinnedSurfaceStyle` through `WindowManager.hostedSurfaceStyle`. Every foreground goes through
  `SkinnedSurfaceStyle.legible` against the ground it is drawn on. Never another family's chrome.
- **The face's own windows:** a face declares none. It has no playlist, no equaliser and no second
  view, so the "ask what the skin provides first" rule always answers *declared nowhere* — every
  NullPlayer window is the fallback. The only extra windows are the two slider popups above, which
  are transient and not managed windows.
- **Route to a track from day one** (Phase 5): the playlist button, the library and Open Files.
- **Placement:** the shared tiler (`tiledOrigin`, `rescuedOrigin`), placed once on first show and
  never yanked back, with an `AUDION_PLACE_TRACE` flag from the first commit that places a window.
- **Docking:** the face window joins `managedWindowRecords` as a snap target, not a centre-stack
  member.

## Threat model

A user-supplied face is a hostile folder or `.zip`: attacker-controlled names, file count, sizes,
JSON, and PNG headers and payloads. The attacker may attempt path escape through symlinks or zip
entry names, decompression bombs, oversized or numerous images to exhaust memory, deeply nested or
huge JSON, and out-of-range integers.

The trust boundary:

1. The folder walk is bounded and rejects symlinks before any file is opened.
2. A `.zip` is checked from its central directory before any payload is inflated, then unpacked into
   a temporary folder and run through the same loader.
3. `index.json` is size-checked before it is parsed.
4. Every PNG's dimensions are read from its header, and the per-image and whole-face pixel budgets
   checked, **before any image is decoded**.
5. Decoding runs off the main thread with ImageIO. `MainActor` receives only a completed immutable
   `AudionFace`.

There is no script surface: a face is data.

## Loading limits

`AudionFacePolicy` is the executable source of truth from Phase 1. Codes are stable identifiers;
their wording may improve without changing their meaning.

| Code | Condition | Outcome |
|---|---|---|
| `AUD0001` | missing `index.json` | fatal |
| `AUD0002` | missing `base.png` | fatal |
| `AUD0003` | `index.json` larger than 256 KB | fatal |
| `AUD0004` | an image the loader decodes is larger than 4096 px on a side, or more than 8 MB on disk | fatal |
| `AUD0005` | more than 2,000 files or 64 MB total | fatal |
| `AUD0006` | a symlink, or a path that escapes the face folder | fatal |
| `AUD0007` | a PICT ID outside 0…99,999 | warning; element dropped |
| `AUD0008` | mask size differs from `base.png` | warning; mask anchored as FaceKit does |
| `AUD0009` | a button with a non-zero rect but no normal sprite | warning; button dropped, as FaceKit does |
| `AUD0010` | zip ratio or size over its limit | fatal |
| `AUD0011` | more than 64 Mpx across the images the loader decodes, summed from headers | fatal |

`AUD0011` is added to the plan's table here. Without it the other limits allow 2,000 images at 4096²,
about 128 GB of decoded RGBA; 64 Mpx caps a face at 256 MB decoded.

**What each limit covers.** `AUD0005` bounds the walk, so it counts every file in the folder.
`AUD0004` and `AUD0011` bound decode memory and time, so they apply only to the images the loader
decodes; a file the loader never opens poses neither threat, and `AUD0005` still caps it on disk.
A missing `-active`, `-disabled` or `-hover` sprite is not a finding: FaceKit treats each as
optional, and only about 260 of the 856 faces ship `-hover`.

`AUD0010`'s exact zip bounds are set in Phase 1 alongside the fixtures that prove them, under the
same rule as `.wmz`'s Amendment 1: absolute expanded bytes bound the threat, and a ratio test applies
only above a size floor.

### Measured headroom (2026-10-08, the 856 faces in `/Users/ad/Downloads/Faces`)

| Limit | Bound | Corpus maximum | Face |
|---|---:|---:|---|
| `AUD0003` `index.json` | 256 KB | 4,561 B | Audion XP 1 |
| `AUD0004` side | 4096 px | 1600 px | Black Bar (`drag.png`, 1600×13) |
| `AUD0004` image on disk | 8 MB | 613,876 B | Jack&Sally (`base.png`) |
| `AUD0005` files | 2,000 | 257 | Puffhookah v.1.0 |
| `AUD0005` total | 64 MB | 4,094,887 B | Matrix |
| `AUD0006` symlinks | 0 | 0 | — |
| `AUD0007` PICT ID | 0…99,999 | 0…15,000 | — |
| `AUD0011` decoded pixels | 64 Mpx | 5,368,982 px | Escher∆ |

The median face decodes 355,603 px. Every file in the corpus besides `index.json` is a PNG. The
tightest margin is `AUD0004`'s side at 2.5×. These maxima were taken over every PNG, including the
files the loader does not decode, so they overstate the decoded-image figures. Measured with throwaway Python over PNG headers; the
Phase 2 census replaces these numbers with ones a committed script reproduces.

## Corpus facts carried into Phase 1

From the planning session's measurement, to be re-measured by the Phase 2 census:

- 856 faces, all of whose `index.json` parse; 74 keys, all present in every face except the font
  name and Txtr colour keys (about 735 of 856).
- `version`: 0 in 777 faces, 1 in 72, 128 in 6, 100 in 1. `useInactiveState` is false in all 856.
  `useAlphaChannel` is false in 35; FaceKit ignores it and uses `base-alpha.png` when present (836).
- `base.png` ranges from 24×11 to 1600×760 across 725 distinct sizes; 34 faces are under 60×30.
- 59 mask-size mismatches against `base.png`: `window.png` 30, `drag.png` 21, `base-alpha.png` 8,
  `active-alpha.png` 6, `inactive-alpha.png` 5, `inactive.png` 2.
- Folder names can carry leading or trailing spaces and characters like `™` and `∆`.

## Follow-up requirements

- Phase 1 implements `AudionFacePolicy` with every code above and a hostile-input test per code, and
  adds the `facekit` notice row with the first adapted file.
- Phase 2's census and oracle replace every measured number in this record with one a committed
  script reproduces, recorded in `skills/audion-face-guide/reference/harness.md`.
- The Phase 2 census confirms or refutes the meaning of the five files FaceKit ignores; nothing
  reads them before that.
