# Winamp Modern (`.wal`) — Phase 23 Handoff

**For:** the agent picking up Winamp Modern work after Phase 23

**From:** Phase 23 (the Love is War Miku defect sweep)

**Date:** 2026-08-17

Read first:

- `skills/winamp-modern-skin-guide/SKILL.md` — durable versions of every finding: "How big the font
  is, and which one", "`<ProgressGrid>` — the bar's *filled* part", "A skin's own right-click menus",
  "`<vis mode>`", the `rectrgn` bullet under "Hit testing: who owns a point", the drag-policy bullet,
  and the float-decode gotcha under "MAKI"
- `skills/winamp-modern-skin-guide/compatibility.md` — supported surface for the new text metrics,
  `ProgressGrid`, `PopupMenu`, the corrected `vis mode` numbering, and the dispatched-events list
- `skills/winamp-modern-skin-guide/manual-qa-checklist.md` §1 — four new Miku lines, **the open gate**

## 1. What Phase 23 was

A GUI bug report against `Love is War Miku.wal`, opening with "the artist/time display text is above
the area where it is supposed to display" and ending, several rounds later, in a MAKI parser bug that
had been mis-decoding every float in every skin since Phase 3.

667 tests (was 666). No new phase test file: the findings are topical and went where their subject
already lives — `WinampModernPhase17Tests` (text), `WinampModernPhase22Tests` (vis mode),
`WinampModernPhase8Tests` (bytecode).

| Symptom | Cause | Fix |
|---|---|---|
| Display text too big, overflowing its slot onto the seek bar; wrong typeface | `fontsize` was taken as a point size (it is a **pixel height**, em ≈ 0.8 ×); `font="Arial"` resolved only declared `<truetypefont>` resources and fell back to monospaced; `bold`/`italic` ignored; text drawn from the top edge of its box instead of centred | `WasabiTextMetrics.pixelHeightToPointSize`, installed-family lookup, `traits(of:)`, and a centred draw rect in `drawText` |
| The clock's digits shuffled sideways and measured narrow | `forcefixed="1"` / `timecolonwidth` unimplemented | `WasabiTextMetrics.fixedPitch` — shared by the draw path and `getAutoWidth()` |
| The seek bar was an empty white box with no position anywhere in the window | `<ProgressGrid>` drew **nothing**. This skin's slider thumb is a 1×1 pixel, so the grid is its only indicator | `WasabiSceneRenderer.drawProgressGrid`, valued from the sibling slider through one shared `normalizedValue(of:)` |
| Right-click did nothing, in **any** skin | `addSubMenu` unimplemented (the handler failed closed at the first submenu) **and** `popupPresenter` was never installed by any view, so `popAtMouse` always answered 0 | `addsubmenu` + a resolved `WinampModernPopupMenuItem` tree + `WinampModernMainView.presentScriptPopup` (a real `NSMenu`, run at the mouse) |
| Volume buttons did nothing | `System.Integer`/`Float`/`String`/`Boolean` casts unimplemented — the handler aborted before `setVolume` — and then, underneath that, **every float constant decoded to a fraction of its value** | The casts, `stringToFloat`, `onVolumeChanged` dispatch, and the mantissa widening in `MakiBytecodeParser` |
| Menu's *Spectrum Analyzer* and *Oscilloscope* entries drew the other one | `<vis mode>` numbering was inverted | `1` = analyzer, `2` = oscilloscope |
| An invisible control could not be clicked, and dragged the window instead | `rectrgn="1"` was not enough to claim a point without a bitmap; a scripted layer counted as a drag handle | `isRenderable` honours `rectrgn`; `shouldDragWindow` declines a layer a script hooks the mouse on |

## 2. The float bug, because it is the important one

```
before:  add integer(179) + double(0.0031249523) = double(179.0031)   → setVolume(179)   no change
after:   add integer(179) + double(2.5499999)    = double(181.5499)   → setVolume(181)
```

`MakiBytecodeParser` built the mantissa as `Int((0x80 | (initial2 & 0x7f)) << 16) | Int(initial1)`.
`initial2` is a `UInt16`, so the shift threw the implicit leading one and every stored high bit out of
the word and left only `initial1`. Widen first: `(Int(0x80 | (initial2 & 0x7f)) << 16) | …`.

Two things to take from it:

- **Nothing failed.** No diagnostic, no unsupported method, no aborted event — the handler ran end to
  end and moved the volume by 0.003 of a step. The compatibility report cannot see a wrong *number*.
- **Scripts reach for floats rarely**, so this survived twenty phases. Assume any arithmetic result is
  untested until a skin has been watched doing the arithmetic.

## 3. How each was measured

```sh
# the scene as the user sees it — RENDER_SETTLE is what makes it the *settled* scene
env WINAMP_MODERN_WAL="$WAL" WINAMP_MODERN_RENDER_DUMP=/tmp/render \
    WINAMP_MODERN_RENDER_SETTLE=1 WINAMP_MODERN_RENDER_PROBE=main/normal \
    swift test --filter WinampModernRenderDumpTests

# what a click reaches, what a right-click builds, and what broke *because of* the click
env WINAMP_MODERN_WAL="$WAL" WINAMP_MODERN_RENDER_DUMP=/tmp/render \
    WINAMP_MODERN_RENDER_SETTLE=1 WINAMP_MODERN_RENDER_CLICK='main/normal@10,180' \
    swift test --filter WinampModernRenderDumpTests
```

New harness capability, all opt-in:

- `WINAMP_MODERN_RENDER_SETTLE=<seconds>` pumps the run loop first. Without it the dump shows a scene
  **the user never sees**: this skin's opening animation (display panel sliding to `y=84`, the
  character to `x=129`) runs on a 300 ms timer, and the panel is `alpha="0"` until it fires. The first
  half hour of this phase was spent reasoning about a window that does not exist.
- `RENDER_CLICK` now passes the click's x/y to the button events (a handler popping two arguments off
  an empty stack failed with an underflow belonging to the harness), tries `onrightbuttonup`, prints
  the menu the skin built, prints the resulting volume, and prints a compatibility report **after** the
  click — the load-time one is clean for anything only a click reaches, which is why all of this hid.

**A skin's own `screenshot.png` is ground truth.** Every text-metric number in this phase was measured
against it by pixel: the reference draws its `fontsize="30"` digits 17 px tall (Arial's cap height at a
24 pt em) between rows 239 and 255 of a box spanning 233–263, which is centred, and `fontsize="10"`
fits the same 0.8 ratio. Ours now lands on 239–256. Read the archive for one before theorising.

**Decompile the script rather than guessing the semantics.** A throwaway Python disassembler over the
`FG` format (mirroring `MakiBytecodeParser`, ~60 lines) settled four questions no amount of staring at
XML could: that the panel's final position comes from `setTargetX/Y` on a timer, that the volume
buttons carry no `action` and are driven entirely by `leftClick()` from an auto-repeat script, that
`onLeftClick`'s body is guarded so only that script-driven path changes the level, and — decisively —
that `bandwidth` + `setMode(1)` is the analyzer while `oscstyle` + `setMode(2)` is the scope.

## 4. What is still open on this fixture

- `fliph` on a `<vis>` (the skin's left-click on the same trigger toggles it) is not honoured.
- The oscilloscope remains a mirrored spectrum rather than real PCM (unchanged, `compatibility.md`).
- `volbtn` ("Show Volume Bar") has `action="TOGGLE"` with an empty `param` and does nothing — it does
  nothing in Winamp either. Not a defect.
- The vis mode the menu selects persists through `setPrivateInt`, so a QA pass that changes it changes
  what the *next* launch shows. Reset by deleting the skin's private config if a screenshot comparison
  looks wrong.

## 5. Where to look next

The pattern of this phase and the last three: **the load-time compatibility report being clean means
nothing about whether the skin works.** Every remaining defect class needs an event driven at it —
a click, a timer, a menu pick. `WinampModernCrashRepro` fires every standard event at every object and
is the closest thing to a sweep; extending *it* to check outcomes (not just survival) is the highest
-value next step, and it would have caught the volume bug.
