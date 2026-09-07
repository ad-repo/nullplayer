# Winamp Modern (`.wal`) — Phase 12 Handoff

**For:** the agent picking up Winamp Modern work after Phase 12

**From:** Phase 12 (`Wasabi:Frame` — the SUI body now builds; window sizing is the open defect)

**Date:** 2026-08-16

Read first:

- `skills/winamp-modern-skin-guide/SKILL.md` — the durable guide; the Phase 12 findings are folded in
  (the splitter, text width as a layout input, the opcode-104 immediate)
- `skills/winamp-modern-skin-guide/compatibility.md` — supported surface + measured demand
- `TASKS.md` §12 — what landed and what is still open
- `docs/winamp-modern/phase-11-handoff.md` — the queue discipline this phase followed again

## 1. What Phase 12 was

Phase 11 left cPro-Bento loading with **zero** script errors and an **empty body**. The cause was one
element: `<Wasabi:Frame id="centro.mainframe" left="centro.components" right="centro.playlist1"
from="right" width="200">`. A Wasabi frame does not contain its children — it **names two groups and
instantiates them**. Ours was one of the identifier-only `wasabi.*` shells, so the library tree, the
playlist and the tab strip never entered the graph.

`WasabiFrame` now does that, and lays the panes out by writing their *own* geometry attributes, so
the existing `WasabiGeometrySpec` pipeline resolves them and a parent resize needs no frame-specific
code. On a frame, `getPosition`/`setPosition` are the divider offset (ClassicPro closes its side view
with `setPosition(0)`).

Result: cPro-Bento's `main/normal` went 102 → 168 scene nodes; the tab strip, playlist pane, playlist
buttons and album-art area render; compatibility stays `degraded` with zero error findings.

## 2. The queue behind it (Phase 11's rule, again)

Instantiating the panes let their scripts run for the first time, and each fix reached the next miss:

| Round | What it named |
|---|---|
| 1 | **parse failure**: "MAKI member access declares unknown value type 265" |
| 2 | `additem`, `getgroup`, `getnumchildren`, `getcurrenttrackrating` |
| 3 | `getnumchildren` (2nd site), `oneqfreqchanged` |
| 4 | `setsize` |
| 5 | — |

**The parse failure is the one to remember.** Opcode 104's immediate is not a plain value kind: it has
a variable record's shape — a type offset, then an "is object" flag — so `Member GuiObject Tab.left;`
is `0x0100 | classIndex`. Read as a value kind it *fails the parse*, which kills the whole skin rather
than one event. Confirmed by decoding every `.maki` in the engine (immediates seen: 2, 5, 6, and 265,
the last only in `CproTabs.maki`, whose class index 9 is `GuiObj`'s GUID).

Implemented alongside: `List` (`addItem`/`enumItem`/`getNumItems`/`removeItem`/`removeAll`/`findItem`,
bounded at 4096), `BitList` (`setSize`/`getSize`/`setItem`/`getItem`, same store),
`WinampConfig.getGroup(guid)` → `getInt`/`getBool`/`getString` against the skin's own namespaced
config, `getNumChildren`/`enumChildren`, `getCurrentTrackRating` (0 — documented stub), and *system*
events callable as methods (`System.onEqFreqChanged(freqmode)`).

## 3. Text width is a layout input

The tab labels came out clipped because ClassicPro sizes each tab to `label.getAutoWidth() + 14` and
our `getAutoWidth` was a `0.6 × fontsize × charcount` estimate, narrower than what the renderer drew.
The menu bar was worse — invisible, because a group with `autowidthsource` was never sized at all.

`WasabiTextMetrics` is now the single measurement for both sides (it hangs off the loaded skin, not
the renderer, because the runtime must measure before any renderer exists — the dump harness starts
the scripts first). The renderer honours `leftpadding`/`rightpadding` when drawing, sizes an
`autowidthsource` group to the element it names, and sizes a `<text>` with no `w` to its content.

## 4. Verification

- `swift test` → **556 pass**, 9 opt-in skipped (was 546). New: `WinampModernPhase12Tests` (10).
- Opt-in fixtures: cPro-Bento `degraded`/0 errors; CornerAmp `full`; MMD3 `degraded` (render still
  matches its `screenshot.png`); stock Winamp Modern **improved** from 5 pre-existing errors to 3
  (`getgroup` and `getnumchildren` were two of them) — checked against a stashed baseline, not assumed.
- Release build not run this phase.

## 5. Open — start here

### The window opens too small, and a too-small window scrambles the scene

A live run (user screenshot, 2026-08-16) shows cPro-Bento in a window around **376×182** with the SUI
content stacked on top of the display and transport. Two separate things, and the second is a real
renderer bug:

1. **Where the size comes from.** The skin's own default is `default_w/h = 500×500` and
   `WinampModernMainWindowController.loadSkin` does size the window to that. But
   `AppStateManager.restoreWindowFrames` later sets the saved frame verbatim, and
   `windowDidResize` then re-resolves the scene at that size. Ruled out headlessly: the skin's scripts
   do **not** ask for a resize at startup (a probe that reproduced the app's ordering — renderer built
   before `scripts.start()`, `layoutResizeRequested` wired — reported canvas 500×500 before and after,
   with no unsupported methods and no script failures). So the size is coming from restored geometry
   or from the UI-Size path, not from the skin. Confirm which before changing anything.
2. **Why it looks scrambled rather than merely cramped.** The layout's declared minimum is 317×168,
   at which the SUI area (`h - 168`) is *zero* tall. Objects inside it then resolve to **negative**
   sizes, and `WasabiRect.standardized` turns a negative height into a box drawn on the other side of
   its origin — so the tabs paint over the transport instead of vanishing. Two candidate fixes, both
   worth testing against all four installed skins: skip an object (and its subtree) whose resolved
   width or height is negative, and/or clip a group's children to the group, which is what Wasabi's
   real container windows do (we currently clip only on `clipchildren="1"`).

A probe harness for this is easy to rebuild: construct the renderer, `resize(to:)` a chosen size, and
render to PNG — that is how 376×182 was reproduced headlessly.

### Also open

- The selected tab's **content** is empty: the library host seam still returns nil and falls back to
  the classic library window (Phase 5 deferral). "Media Library" therefore has a frame and no content.
- Splitter **dragging** is not implemented, so `minwidth`/`maxwidth`/`jump` are parsed but unenforced.
- `XmlDoc` is still inert (Phase 11).
- The Phase 11 `drawText` crash is still unreproduced.
