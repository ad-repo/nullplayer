---
name: wmp-skin-guide
description: Windows Media Player .wmz/.wms skin engine, bounded loading, retained graph, compatibility reporting, rendering, the persistent JScript runtime and host object model, and WMP-specific app-mode integration.
---

# Windows Media Player skin engine

Read this skill before changing `Sources/NullPlayer/WMPSkin/` or
`Sources/NullPlayer/Windows/WMPSkin/`. The current security decisions and locked limits are in
`phase-0-decision-record.md`.

**This engine is a clean-room reverse-engineering effort, and it is incomplete.** A corpus sweep
compares it against its own last guess, not against WMP, so an engine-wide change that moves skins
nobody reported is often unlocking behaviour they were silently missing — or it is collateral. A
diff is unclassified until it is judged against the skin's own artwork and script; the method is
`skin-subsystem-blueprint` § *A sweep diff is unclassified, not a regression*. Classic and Original
are the exception: a diff there from `.wmz` work is always a regression.

**The script runtime and everything skin JScript can reach is `reference/object-model.md`.** It is
the canonical reference for the persistent `JSContext`, the three member resolutions
(`ok`/`INERT`/`UNRECOGNISED`), element and expression semantics, and how to add a member without
making the demand tally lie.

**Not every skin in the corpus is work.** `scripts/wmp_corpus_exclusions.txt` is the blacklist both
corpus scripts read, and a skin belongs on it when no work in this engine changes its outcome —
`Darkling` is authored against WMP's Party Mode host and draws its own "designed for Party Mode"
panel without one, exactly as real WMP does. An excluded archive never ranks work; see
`reference/harness.md`.

**A skin that has taught this engine something has a dossier: `reference/skins/`.** One file per
`.wmz` that produced two or more unrelated defects, or one no probe could see — what it exercises,
what it found, **what was ruled out**, and the decoded coordinates that reach its controls.
`reference/skins/README.md` says when to write one and what belongs in it, and carries the
counter-evidence table: the skins that disagree with a change that looked right, and the rule each
one holds down. Check that table before landing an engine-wide change.

**Measure before you reason.** `reference/harness.md` is the canonical probe and corpus reference —
every env-var flag, the line grammar, `scripts/wmp_skin_census.sh`, `scripts/wmp_render_sweep.sh`,
`scripts/wmp_markup_census.sh`, and the traps those scripts enforce. No other file restates a command; add a flag there in the same
change that adds it. The ranked backlog it feeds is `WMP_TASKS.md` at the repo root, and a closed
entry moves to `docs/wmp-skin/wmp-backlog-archive.md` in the same change that closes it. A row with a
defect in the **row** rather than in the work — stale past the point of trust, not a unit of work,
stripped of its own justification — moves to `LOW_QUALITY_TASKS.md` instead, which is neither the
archive nor a rejection; six went there in one audit on 2026-09-19, and two of them left real work
behind (W241; and W242, retired 2026-09-20 after finding W243). Re-measure anything revived from it.

**The `phase-*-handoff.md` files are unverified narrative.** Check every claim in them against the
code before relying on it: phase 7 asserts that WMP "remains explicitly unavailable in release/MAS
products through `AppCapabilities.wmpSkinMode`", and `AppCapabilities.supports` returns `true`
unconditionally unless `EDITION_CUSTOM` is defined, which nothing defines. That is a false claim,
not a self-qualified one. The census likewise found their corpus numbers wrong in both directions —
see `reference/harness-history.md` § "What the harness measured".

## WOW and TruBass audio enhancements

Read [reference/audio-enhancements.md](reference/audio-enhancements.md) for the WMP-only DSP design,
source research, control round trips, graph ownership, mode gating, and verification. The skin’s
`eq.enhancedAudio`, `wowLevel`, `truBassLevel`, and `speakerSize` now drive audio processing.

## Isolation boundary

WMP is an independent skin engine. Keep engine/model work in `WMPSkin/`, AppKit work in
`Windows/WMPSkin/`, and tests/fixtures under the WMP test paths. Do not teach Classic, Original, or
Winamp Modern types about WMP markup. Change shared application files only when no WMP-owned seam can
satisfy the requirement; keep that seam minimal, gate it explicitly on the WMP controller family,
and prove all existing modes retain their behavior. Record every shared path and the rejected local
alternatives in the phase handoff.

Never put WMP input work on the main thread. Archive validation/inflation, decoding, XML/graph/report
construction, image work, expressions, and script evaluation run on a WMP-owned background
executor — the script context has its own serial queue, so a skin that loops forever wedges that
queue and nothing else. Never use `DispatchQueue.main.sync`. Hand only completed immutable snapshots and typed host
commands to `MainActor`, where the work is limited to AppKit presentation.

WMP owns a dedicated app-authored unskinned player. On a fresh public-release profile with no
persisted mode and before the user has downloaded/imported a skin, launch that WMP view. Missing,
deleted, corrupt, or rejected selections also recover to it while remaining in `.wmp`. Never use an
Original/Classic/Winamp Modern controller, preference, `skin.json`, or artwork as WMP's default or
fallback. Existing users keep their persisted mode.

## Where everything lives

This file is the router: the rules every `.wmz` change must hold, the contracts short enough to keep
in one place, and *Debugging a live defect*. Everything else is a reference file — read the one that
owns the code you are changing.

| Read | Before changing | Sections it holds |
|---|---|---|
| [reference/windows.md](reference/windows.md) | a window: its hosting, chrome, frame, placement, size, restore, docking, or how a skin is presented in one | a router over `reference/windows/`: the hosting contract, routing and the borrowed frame, NullPlayer's own windows, placement and raising, sizing, mode switching and presentation |
| [reference/rendering.md](reference/rendering.md) | anything drawn: the scene, images, `backgroundImage`, keying, text, controls, hover/down/latched faces | a router over `reference/rendering/`: artwork, keys and shapes, geometry, paint order, views, compact mode, script timing, text, video, controls, hosted surfaces |
| [reference/input.md](reference/input.md) | hit testing, mapping images, clicks, keys, transport | *Which control a click reaches*; *Phase 4 input and transport contracts* |
| [reference/bindings.md](reference/bindings.md) | `WMPScriptRuntime`, expressions, `wmpprop:` bindings, `<TEXT>` sizing | *Script, expression, and binding contracts* |
| [reference/object-model.md](reference/object-model.md) | a member skin JScript can reach | the shape, the three resolutions and adding a member; a router over `reference/object-model/`: property reads, elements, the library (W136), methods and tweens, events and the keyboard, handlers and timers, classification and *Verified **not** gaps* |
| [reference/loading.md](reference/loading.md) | the archive, text decoding, XML tolerance, `WMP00xx` codes | *Loader contracts* and the loader's governing rules |
| [reference/harness.md](reference/harness.md) | any measurement — every probe flag and corpus script | a router and flag index over `reference/harness/`: the corpus, probe flags, app flags and probes, driving the app, sweep limits, the line grammar, the scripts, trusting the instrument; dated past measurements are in [reference/harness-history.md](reference/harness-history.md) |
| [reference/audio-enhancements.md](reference/audio-enhancements.md) | WOW / TruBass | the WMP-only DSP |
| [reference/skins/](reference/skins/README.md) | an engine-wide change | per-skin dossiers and the counter-evidence table |

A reference to `SKILL.md` § *<section>* written before 2026-09-24 names a section that now lives in
the file this table gives for it.

## Phase 3 app integration contracts

- WMP maps to its own `PlayerUIControllerFamily.wmp`; it is neither Classic nor a
  `ModernSkinFamily`. Keep capability and menu exposure DEBUG-only until the public-exposure phase.
- `WMPSkinImporter` owns `Application Support/NullPlayer/WMPSkins`, complete pre-commit validation,
  same-directory atomic replacement, installed enumeration, and the `wmpSkinName` / view selection
  keys. A failed replacement must leave both the installed archive and selection usable.
- `WMPMainWindowController` must first present `WMPUnskinnedMainView`, then swap in only a completed
  static WMP scene. Missing/corrupt selections stay in WMP with an actionable diagnostic. Main-window
  fallback must never instantiate or consult Classic, Original, or Winamp Modern skin machinery.
- Persist WMP skin/view identity separately. Restore WMP geometry only when the exact mode, skin,
  and view match; preserve top-left position safely and do not apply shared UI scaling.
- Teardown is synchronous and idempotent: cancel WMP tasks, clear callbacks and images, then release
  scene, archive, and image-store ownership before the controller is discarded.
- NullPlayer-owned native windows exposed in WMP mode must be hosted in WMP-owned chrome derived
  from the active `.wmz`: borders, colors, title/window controls, metrics, resize affordances, and
  docking treatment. Never fall back to another skin family's controller or chrome. Missing skin
  chrome uses only an app-authored WMP-neutral fallback. **This shipped on 2026-09-09 and the
  "hide or disable it until it has a host" clause is spent** — `AuxiliaryControllerStyle.wmpUnavailable`
  is gone. How it works is `reference/windows/native-windows.md` § *NullPlayer's own windows beside a skin*.


## Debugging a live defect

Read **`skills/live-ui-testing`** before diagnosing anything that only reproduces on screen, and the
process section it points at — `winamp-modern-skin-guide/reference/harness.md`
§ *Debugging a live defect* — which is the reference implementation of that workflow. The 2026-09-07
session that produced the fixes below spent hours rediscovering five rules already written there.

**The reproduction loop itself is `reference/harness/live-loop.md` § *Driving the app*** — select the skin,
launch the debug build, ask `WMP_RENDER_PROBE` where the control is and click that frame with a
`CGEvent`, then capture the window and look at it. (The `INPUT` trace this loop used to read was
removed on 2026-09-11 for being unreadable live — see `reference/harness.md`.) Three of the four
defects in the compact-mode report were app-path defects a render sweep can never see, and each took
one launch once the loop existed. The same section carries the two things that decided those fixes:
how to reduce a skin's own script to a standalone `JSContext` repro, and why a fix that closes the
report while moving images elsewhere in the corpus is the wrong fix.

**The sharpest version of that class is a defect in the *window* rather than in the scene, and
W184-W192 is three of them in one report.** A render dump rebuilds from the script's overrides, so
the canvas grows there whether or not the window ever moves: a one-axis resize that the app ignored
(W186), a stale canvas re-asserted after a user resize (W187) and a window resized ahead of its own
picture (W190) each rendered *perfectly* in every capture. **The measurement is
`CGWindowListCopyWindowInfo` filtered on owner `NullPlayer`, read before the gesture and after it** —
and for anything that flashes, a series of `screencapture -o -x -l <id>` started at staggered offsets
around the click, which is what showed the old artwork stretched into the new frame. Headlessly, the
one line that separates "the drawer opened" from "the window followed" is `viewSize=` on the `CLICK`
line; the picture cannot tell you. See `reference/skins/compact.md`.

**When the report is about a control rather than one skin — "every skin has this button and it does
nothing" — the route is `scripts/wmp_control_audit.py <member>`, which runs
`reference/harness/live-loop.md` § *Auditing one authored control across the whole corpus*, and the live half
is § *A live pass is a window frame, before and after*.** The census cannot answer that question:
it drives `onLoad` and a control's demand is in `onClick`, which is how W100 stood at a recorded
reach of 2 skins against a true 162. A window frame read before and after a `CGEvent` click is the
measurement, it scales to a skin per launch, and the first thing to check in any capture is that
the window size matches the view's canvas — the unskinned view is **440x170** and a launch that
failed to select the skin looks exactly like a button that does nothing.

The ones that cost the most, in WMP terms:

- **Number the transactions before theorising about one.** Two rounds of inference off the raw
  `INPUT` trace named the wrong cancellation check for W88 and produced a fix that was a no-op; one
  temporary `txn <n>` pair named the right one in a single launch. `reference/harness/live-loop.md`
  § *Driving the app*.
- **A green corpus sweep used to say nothing about AppKit; now it says one thing.**
  `WMP_RENDER_APPKIT=1` runs the real `NSView.draw` of the view and every overlay over it and diffs
  it against a second pass with the overlays hidden. **Start a live report here**: if the view diffs
  to zero, the defect is not the overlays and not compositing, and the scene is where to look. It
  cleared `ALXMorph/mainView` in one run. What it still does not reach is the window's shape and
  shadow (the window server), hover, a timer and live playback — W73.
- **Compare `WMPRenderer`'s own image against a screen capture of the same window rect.** Agreement
  means the defect is in the scene; disagreement means it is in the overlays or compositing. That one
  comparison ended the hunt, and `WMP_RENDER_APPKIT` is that comparison made automatic and
  corpus-wide. **Do not do it by hand against a raw screen capture unless you have to**: the two
  images go through different colour spaces, and reading that difference as a defect is what
  reported 6.8% of the *control* skin as broken.
- **A probe scoped differently from the engine reports the difference as a defect.** Both geometry
  evaluators are scoped to one `VIEW`; the `EXPR` probe walked the whole graph, so every other view's
  expressions were printed under this view's name and refused by an evaluator that could not answer
  them. That read as *82% of the corpus's expressions never reach the live evaluator* — 34,314 rows
  — and cost a whole handoff, whose worked case turned out to be a `plView` node quoted under
  `mainView`. Scoped the way the engine is, the corpus reads **7,569 / 7,569**. Before believing a
  probe about a population, check it is asking the same question the engine answers;
  `reference/harness-history.md` § *After the cascade* has the numbers and the check that holds it.
- **Expressions are not what starves a view — three engine rules were.** `starved.tsv` did not move
  by one row when the above was corrected, and `Cablemusic/mainview` — 63 unresolved nodes then, 8
  now — declares no geometry expressions at all. What it declares is unsized `<TEXT>`, unsized
  `<BUTTONGROUP>` and mapping-region `<…ELEMENT>` nodes, and those three accounted for **83% of the
  corpus's 2,380 unresolved nodes** (2026-09-09). `WMP_RENDER_UNRESOLVED` is the flag that says so;
  the count alone names nothing, which is why the file ranked views for two phases and nobody could
  take a row off the top of it. A high `unresolved` ratio also does not mean a blank window: two of the three worst-ranked
  views render substantially. See W68 and W75.
- **A ratio, not a count, ranks a starved view.** `unresolved > 0` is true of most views in the
  corpus, including corona's. `starved.tsv` from the census is the ranking; a raw count ranked
  nothing and hid ALXMorph for three phases.
- **Confirm the skin *and the view* before diagnosing.** `wmpSkinViewID` is persisted on every
  present, and Corona's compact view renders almost identically to its player.
- **"The wrong button responds" is two questions, and the harness answers one of them for free.**
  Scan the control with `WMP_RENDER_CLICK` and decode its mapping image independently: if every hit
  *and* every miss lands where the map's colour bands are, hit testing is exonerated and the defect
  is in what gets painted (W47 was a mirrored mask clip). Doing that first turned a vague live report
  into a one-line fix.

### Triage a hosted-window defect before choosing a seam

**Reported 2026-09-18: the skin's own windows are right and the borrowed ones are wrong — broken
borders and content in the wrong rectangle, repeating across the eight hosted windows and across
skins.** Two triage steps come before any fix, and both were skipped by the architecture analysis
that this section replaced.

- **Compare the skin's own window against the hosted one first, because a fine main window
  eliminates most of the engine.** The player view and a borrowed frame share archive validation,
  the XML graph, bitmap decoding, `WMPSceneBuilder`, `WMPRenderer`, paint order, colour and the
  script runtime. If the skin's own window is right, none of those is the defect, whatever the
  hosted window looks like. What is left is hosted-only and is three stages deep: subtraction and
  composition in `WMPHostedFrameTemplate`, asynchronous render and cache in `WMPHostedFrameProvider`,
  and placement by the view itself.
- **Then read the frame PNG against the live window, because they fail identically on screen.**
  A border that is broken in `WMP_HOSTED_FRAME_DUMP` is an extraction defect and belongs in the
  template. A border that dumps clean over a window that is visibly wrong is an integration defect
  and belongs in that window's WMP path — and if several windows are wrong at once, in what they
  each failed to call. **The picture alone cannot tell these apart**, which is the whole reason the
  fork is worth one capture: § *`gaps=` cannot see a hosted frame that is wrong everywhere but its
  edges* in `reference/harness/sweep-limits.md` is the same lesson learned from the opposite direction, and
  carries the alpha check that stops a frame full of white paint reading as a frame full of holes.
- **Then repeat on two more windows under the same skin, and only to confirm the failure is one
  shape.** Ten windows failing the same way against a player view that never does is one contract
  unhonoured at ten call sites, not ten defects — so the second and third captures are there to
  establish that, not to enumerate.

**Do not open this class with a skins × windows capture matrix.** It is the instrument the analysis
document reached for twice and it answers the wrong question: sweeping the skin axis measures
*donors*, and a report that the skin's own window is fine has already cleared them. The variance is
on the window axis. One skin and three hosted windows localise this faster than 185 skins and one
window, and `reference/harness/sweep-limits.md` § *A named skin outranks a corpus sweep* is the general form.
The corpus axis is for showing a landed fix did not cost another skin — after there is a fix.

### Evidence proportional to a hosted-window change

Match the evidence to what the change can reach. Every row is WMP-scoped; none of it authorises
touching another family.

| Change | Required evidence |
|---|---|
| Donor extraction or repair in the template | The triggering size and skin, plus the counterexample an over-broad rule would break. A rule used across donors needs the corpus comparison, with the changed output attributed. |
| Drawing or layout in one hosted window | Live before/after capture of that window at the failing size **and** a normal one; native child placement where the window has children. |
| A helper called from several WMP call sites | Exercise every changed call site, including the animated ones. |
| Provider completion, scale or cache handling | A focused test for the reproduced transition, and a live check at the affected backing scale or across a skin switch. |
| A WMP branch in a shared file | Diff review proving the non-WMP path is untouched, plus the behaviour checked in the other families and across entry to and exit from WMP. |

**For animation, capture several live frames**: the failure mode is content redraw erasing the
bezel, and a single frame catches it only by luck. **For asynchronous arrival, verify relayout and
not only repaint** — a window that repaints without laying out leaves its children in the old
rectangles, which is how W190 and the TheUnit report both presented. **Use the reported dimensions**;
357x238, 550x464 and 710x810 are useful historical cases and not a substitute for the size the
reporter was looking at. **Use both backing scales** whenever the change touches pixels or a
coordinate conversion.

A check in another family verifies isolation and nothing else. A failure there means the WMP change
is wrong and must be revised or dropped; it is never a licence to fix that family.

## Phase 6 widget and view contracts

- `WMPScene.widgets` is immutable semantic metadata for accessibility and native surfaces. AppKit
  overlays are created only after a completed scene arrives and are replaced with the scene.
- Playlist snapshots are capped at 4,096 rows. Selection, scrolling, play, removal, and movement use
  typed host actions; scripts receive plain copied item values, never `Track` objects.
- WMP exposes ten EQ gains. `WMPAudioEngineHost` uses `EQBandRemapper` at the boundary when the live
  engine is in its 21-band layout; every write remains clamped to ±12 dB.
- `EFFECTS`/`WMPEFFECTS` hosts the visualization surface. Its single ref-counted spectrum consumer
  must be registered only while an effects surface exists in the active view and removed on
  switch/teardown.
- `VIDEO`/`WMPVIDEO` draw nothing — the placeholder that painted them opaque black over the skin's
  own artwork is gone (W9). Their `backgroundColor` paints only over what is already drawn beneath
  it (`confinedToPaint`, W312), so it never adds to the window's shape. WMP plug-ins, ActiveX, DLLs, and arbitrary media surfaces remain denied.
- A view switch cancels capture and outgoing timers, stops continuous commands, clears view-local
  overrides, resolves off-main, preserves safe top-left, applies per-skin/view size, atomically swaps
  scene/native/accessibility state, then dispatches the view event.
- Auxiliary NullPlayer windows stay hidden in WMP mode until they have WMP-owned chrome. Never expose
  them through another skin family's provider or artwork.

## Verification

Use the committed original fixtures in `Tests/NullPlayerAppTests/Fixtures/WMPSkin/`. Run focused WMP
tests first, the user-supplied `WMP_TEST_WMZ` corpus check when available, then full `swift test` and
`git diff --check`. Do not commit third-party skins or build a DMG unless the user requests it.

## Phase 8 public exposure contracts

- The full edition supports `.wmp` in debug and release builds. A custom edition still decides
  through `EditionPolicy`; do not bypass that capability seam.
- `PlayerUIMode.stored(in:)` defaults to `.wmp` only when neither the current mode key nor the legacy
  `modernUIEnabled` key exists. Every persisted four-mode choice and both legacy Boolean values are
  upgrade inputs and remain authoritative.
- Keep `-uiMode wmp -wmpSkinPath /absolute/skin.wmz` available in packaged builds as a diagnostic
  launch hook. It imports through the production bounded importer and grants no direct file access to
  skin script.
- Public UI owns import, installed-skin selection, selected-skin removal, authored view selection,
  unskinned recovery, and bounded JSON compatibility-report export. Archive removal never deletes
  the user's original downloaded file.
- User support instructions live in `docs/wmp-skin/user-guide.md`; the exact implemented object-model
  contract stays in `docs/wmp-skin/compatibility.md`.

## Phase 7 hardening contracts

- `WMPCorpusReportHarness` is the reusable corpus seam. It emits archive hashes/facts, compatibility
  demand and unknowns, diagnostics, cold/warm load plus render/layout/hit metrics, and confidence.
  It must never serialize local input paths, source text, archive payloads, pixels, or screenshots.
- Keep reports outside the repository. `WMP_CORPUS_PATH` selects an external corpus directory and
  `WMP_CORPUS_REPORT_DIR` selects an external report directory for the opt-in Phase 7 test.
- Fuzz/mutation outcomes are success or `WMPFailure`; exercise archive metadata/payloads, strict
  text, XML, attributes/colors, mapping images, image decode, and bridge bounds.
- Render at the window's current backing scale and rebuild when backing properties change. Keep 1×
  and 2× correctness in original-fixture tests; never add real-skin goldens.
- Corpus-driven compatibility defaults must remain narrow. Empty optional images warn; text outside
  UTF-8/UTF-16/Windows-1252 and malformed duplicate-attribute XML remain typed rejections unless the
  security contract and compatibility rationale are deliberately amended.
