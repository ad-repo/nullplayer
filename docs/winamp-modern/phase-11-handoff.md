# Winamp Modern (`.wal`) — Phase 11 Handoff

**For:** the agent picking up Winamp Modern work after Phase 11

**From:** Phase 11 (cPro-Bento's blocking MAKI surface — COMPLETE; the SUI body is not)

**Date:** 2026-08-16

Read first:

- `skills/winamp-modern-skin-guide/SKILL.md` — the durable subsystem guide. **Start here**; the
  Phase 11 findings are folded into it (the blocking list is a queue, `delete` is an expression, the
  `Map` image-inspection surface, the `isInvalid` probe idiom, the CoreText nil rule).
- `skills/winamp-modern-skin-guide/compatibility.md` — supported/unsupported surface, the measured
  demand lists, and the open crash report
- `TASKS.md` — Phase 11 sections, including §11.5 (what is still missing) and §11.6 (the crash)
- `~/.claude/plans/i-want-to-support-frolicking-rabbit.md` — "Post-Phase-11 state and next work"

## 1. What Phase 11 was

The user's report was one sentence: *"cpro bento is missing most of its functionality."* It was
right, and the cause was legible in the render harness inside a minute — which is the lesson Phase 10
already wrote down and this phase confirms. The compatibility report said `unsupported`, with **nine
unimplemented MAKI methods aborting `onScriptLoaded` in thirteen ClassicPro engine scripts**,
including `player`, `loadattribs`, `mainmenu`, `classicVis`, `shade` and `CentroSUI`. A script that
aborts loses everything it had yet to wire up, and those are the scripts that build the UI.

Each receiver was pinned against the engine's **shipped `.m` source** rather than inferred. That is
how `getARGBValue`'s BGRA channel order, `getDateYear`'s years-since-1900 scale, and the `isInvalid`
probe idiom were established as facts instead of guesses.

## 2. The blocking list is a queue, not a set

Every method added let its script run further and reach the next thing it needed. Three full rounds:

| Round | Report | What it named |
|---|---|---|
| 1 | 9 errors | `getargbvalue`, `getwidth`/`getheight` (on `Map`), `getitembyguid`, `getposition`, `getscale`, `isinvalid`, `setredraw`, `setregionfrommap`, `getdateyear` |
| 2 | 8 errors | the `delete` stack underflow (below), then `load`/`exists` (`XmlDoc`), `getfilesize`, `getlanguageid` |
| 3 | 4 errors | `switchskin`, `getpublicstring`/`setpublicstring`, `getcurcfgval`, `onaction` as a method |
| 4 | **0 errors** | — |

**Never work from a static list.** 193 methods are *referenced* across the engine and never reached
at startup; the only list that means anything is the one the report prints after your last change.

## 3. The two findings that were not missing methods

**`delete` (opcode 97) consumed its operand.** `delete obj` is an *expression*: the compiler emits
`push; delete; pop`, so the opcode must leave the value for the statement's own discard pop. Popping
it underflowed the value stack and killed any script that deletes anything — which is most of them,
since reading a colour or a size out of a `Map` ends in `delete`. Pre-existing since Phase 3 and
invisible for eight phases because those scripts aborted earlier on a missing method. Deleting now
also releases the host-side object (`releaseObject` cancels the timer / drops the decoded map).

**`loadMap` only accepted resource identifiers.** ClassicPro's install check is a *path* load of the
engine's 1×1 `image/installed.png`, verified with `getWidth() != 1`. Failing it, cPro-Bento concluded
the plugin was missing and called `switchSkin` before building anything — i.e. the skin was actively
bailing out, and every downstream symptom followed from that. Paths resolve through the VFS like any
other resource, so the mounts still bound them.

A third, smaller one: `isInvalid()` must be true for an object whose declared **bitmap** never
resolved, not only for a null receiver. Engines probe for optional artwork by declaring a hidden
layer over it and asking that layer. Answering "valid" for a skin that ships no `mainframe_lr.png`
sent `player.maki` on to swap the window frame to bitmaps that do not exist — holes punched through
the window's edges, which is a defect Phase 11 briefly *introduced* by unblocking the script that
does it.

## 4. Result

- cPro-Bento: **unsupported → degraded**; 9 error findings → **0**; unsupported methods → **0**.
- Its render now shows the beat visualization, the spectrum, the kbps/kHz/stereo readouts and an
  intact window frame. The SUI subtree reaches the graph for the first time.
- `swift test` → **546 pass**, 9 opt-in skipped (was 535 + 8). Ten new `WinampModernPhase11Tests`.
- No regression in the other targets: CornerAmp `full`, MMD3 `degraded`, stock Winamp Modern
  unchanged at its 5 pre-existing errors (verified against a stashed baseline, not assumed).

## 5. What is open

### The SUI body is empty, and it is `Wasabi:Frame` — not the windowholders

This is the next concrete task, and it is the difference between "cPro loads" and "cPro is usable".
The subtree now reaches:

```xml
<Wasabi:Frame id="centro.mainframe" left="centro.components" right="centro.playlist1"
              orientation="vertical" from="right" width="200" minwidth="158" maxwidth="-224"/>
```

…and stops there. In Winamp that splitter **instantiates the two groups it names**; ours is one of
the identifier-only shells in `WasabiSkinInitializer.wasabiStandardLibraryGroups`, so it instantiates
nothing and the library tree, the playlist and the tabs never enter the graph at all. The machinery
to build them already exists (`runtime.instantiateGroup`, used by `System.newGroup`); what is missing
is the splitter's own behavior — instantiate `left`/`right` (or `top`/`bottom`), size them by
`width`/`from`/`orientation`, and honor the min/max.

Two smaller ones behind it: the menu-bar labels (File/Play/Options/View/Help) lay out but measure 0
wide, because `getAutoWidth` has neither a bitmap nor font metrics for a plain `text` object; and
`XmlDoc` is inert, so a skin's optional `ClassicPro.xml` extras are ignored.

### An unreproduced crash

A live cPro-Bento run aborted in `WasabiSceneRenderer.drawText`:

```
-[__NSPlaceholderDictionary initWithObjects:forKeys:count:]: attempt to insert nil object
  … NSString.size(withAttributes:) … WinampModernMainView.draw
```

A nil in a CoreText attribute dictionary aborts the **process**, from inside `NSView.draw`. The
boundary is now hardened — `WasabiResources.font` returns `NSFont?` (only an `Optional` binding can
see a null returned by an ObjC constructor imported as non-optional), point sizes are clamped to a
finite 1…256, a skin TrueType with no PostScript name is rejected, and the colour goes through the
same check.

**It is not proven.** What was ruled out, so you do not repeat it:

- Not the font resource — cPro's `truetypefont` declarations are inside an XML comment, so every
  cPro text object falls back to the system monospaced font, which does not return nil for size 0,
  negative, NaN, or 1e9 (measured).
- Not a NaN colour — `NSColor` with NaN/inf components measures fine (measured).
- Not any font in the installed fixtures — only CornerAmp ships TrueType (`lucon.ttf`, `Pixel.ttf`),
  and both have PostScript names and measure fine at every size tried.
- Not reachable from the initial scene, nor from driving every standard event at all 290 objects with
  a redraw after each, nor from a clock sweep — see `WinampModernCrashRepro`, which does exactly that
  and survives, with and without the hardening reverted.

Still untried: the **real host** (live track metadata rather than the harness's fixed strings), a
**colour-theme switch**, **UI Size**, hover/drag state, and the auxiliary container windows. Start
there, and extend `WinampModernCrashRepro` rather than writing a new harness.

## 6. Advice for the next agent

- **The report and the dump, together, before any source.** Every Phase 10 and Phase 11 defect was
  legible in one of the two within a minute. A skin that loads and paints can still be running none
  of its scripts.
- **Re-measure after every fix.** The list you started from is stale as soon as you land anything.
- **Read the engine's `.m` source** for the feature you are fixing. It ships next to the bytecode and
  it is the ground truth for semantics; the skin archive also ships `screenshot.png`.
- **When you unblock a batch of scripts, expect the next failure to be an interpreter bug**, not a
  missing method — newly reached code exercises opcodes nothing had reached before.
- **Run the app.** A green 546-test suite had nothing to say about a skin that decided its own engine
  was missing and tried to switch itself away.
