---
name: wmp-skin-guide
description: Windows Media Player .wmz/.wms skin engine, bounded loading, retained graph, compatibility reporting, rendering, the persistent JScript runtime and host object model, and WMP-specific app-mode integration.
---

# Windows Media Player skin engine

Read this skill before changing `Sources/NullPlayer/WMPSkin/` or
`Sources/NullPlayer/Windows/WMPSkin/`. The current security decisions and locked limits are in
`phase-0-decision-record.md`.

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
see `reference/harness.md` § "What the harness measured".

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

## Every NullPlayer window in WMP mode is the skin's or is themed

**The rule, stated by the reporter on 2026-09-12: a NullPlayer window that can open in `.wmz` mode
either routes to the skin's own window or wears the skin — if it can be themed at all.** A window
that draws no skin chrome in any mode (the video player, the radio sheets, compact mode, the debug
window) is outside it; one that draws chrome is inside it, and there is no third option.

### Current hosting contract

- Native library, Flow, PeppyMeter, Spectrum, AudioAnalysis, Cava, waveform, ProjectM and Sonos
  Rooms windows receive WMP palette chrome and borrowed donor artwork when available. These nine are
  the `WindowManager.hostedBorderWindows` participants; `HostedWindowBorderLayout` grows their frames
  around saved interiors using donor reference insets.
- **Sonos Rooms is one controller for all four families, so its entry is gated on
  `isRunningWMPUI`** — every other participant has a family-specific controller and is listed
  unconditionally. Its chrome (`SonosWindowChrome`) branches on `isRunningWMPUI` ahead of the `.wal`
  palette, so Classic, Original and `.wal` run the code they ran before. Reported 2026-09-23 as the
  window "wearing the classic skin": it asked only for `winampModernSurfaceStyle`, which is nil in
  `.wmz`, and fell through to Classic sprites. **Palette alone was rejected the same day** as
  "fallback chrome" — a window inside this rule takes the borrowed frame, the growth entry and the
  pre-show `presizeHostedWindow` together.
- Playlist and equalizer route to skin-provided surfaces first. Their native fallbacks receive
  WMP theming but **do not participate in border growth**: their classic sprite geometry does not
  follow the shared metrics. Video, radio sheets, compact mode, and debug windows have no skin
  chrome and are outside this policy.
- Borrowed rings use whole-donor rendering with subtraction; fixed panels use nine-slicing.
  Apply the supplied geometry and `paintsOverContent` policy. Borrowed artwork receives no added
  title or close glyph; the close target is the capped 40×26-point top-right hit area.
- Asynchronous frame completion is a layout change, not just a repaint. Consumers relayout and
  invalidate display; the border-layout observer may also grow windows. The authoritative event
  semantics are documented at `Notification.Name.hostedSurfaceStyleDidChange` in `WindowManager`.
- **Measuring a hosted window is a different seam from drawing one, and must not move it or cost a
  render (W238).** `hostedSurfaceFrameArtwork(for:)` serves a `draw`: it *schedules* the build for a
  size it has not got and answers the nearest thing available meanwhile — the last ring stretched
  onto that size. Both are wrong for a rule that reads a window's border back to decide how big the
  window should be, and `HostedWindowBorderLayout` reading through it was a feedback loop:
  measuring a window scheduled a donor rebuild, and a *stretched* ring's insets are stretched with
  it, so the reading disagreed with the border `apply()` adds and each pass left a residue.
  Measured on `Ice` 2026-09-19 — opening PeppyMeter beside a settled library ran the layout ten
  times over both windows, walked the library 603x594 → 603x732 → **603x709**, and paid two extra
  full donor renders (395 ms, 363 ms) for sizes nothing asked for. **The measuring seam is
  `hostedSurfaceRenderedFrameArtwork(for:)`: the cache or nothing, no stand-in, nothing scheduled.**
- **The half of the border rule that adds the border and the half that subtracts it must be the same
  number (W238).** `apply()` grows by `hostedSurfaceBorderInsets`; `windowDidResize` reads the
  interior back by subtracting it. One `borderInPlay` helper serves both, which makes the read a
  round trip rather than a measurement — a window resized by the user or by the docking pass lands
  on exactly the interior it was dragged to, and a pass that only measures never moves anything.
- **`donorInsets == nil` answers two different questions and they need telling apart (W238).** A
  skin that lends no border at all is settled the moment it loads; one that lends a ring is still
  resolving, and a frame read back during that gap is read against the previous skin's border — the
  poisoned interiors that left Cava wanting 299x70 and the waveform 355x111. `lendsFrame` separates
  them and `WindowManager.hostedSurfaceBordersAreSettled` is the predicate the rule gates on. Gating
  on resolved insets alone would freeze every window under a skin that lends nothing: its insets
  never resolve, so a resize would never be adopted and the rule would put the window straight back.
- Exact artwork may include below-floor or extent scaling. During pending renders the provider
  can return a scaled previous image; a panel allows this only within 15% on both axes.
  `wasScaledToFit` is not a readiness flag.
- **A hosted window is sized before it is shown, and a stand-in is refused when it would be a
  different window's (W248).** The first open was four visible stages, all of them *after* the
  window was on screen: it appeared at the size its controller built it, jumped to the positioned
  frame, was grown to `interior + donorBorder` a runloop turn later by a notification observer that
  cannot fire until the window is visible, and drew a stretched ring at each of those sizes until a
  render at the last one landed. Reported 2026-09-20 as *"the window loads with stretched graphics,
  might resize and then snaps in"*. Neither W230 nor W238 could reach it — both worked *inside* that
  sequence. The two halves of the answer are `HostedWindowBorderLayout.prepare(_:)`, which is
  `apply()`'s loop body for one window run **before `showWindow(nil)`** while the window is still off
  screen (nothing in the target needs it to be visible: the donor's border is per-skin and the
  interior is persisted or just-positioned), and the 15% stand-in tolerance, which now holds **every
  donor** rather than only panels — a first open finds `mostRecent` holding the ring W230 primed at
  the *donor's reference size*, and stretching 389x247 onto a 550x890 library is the reported defect.
  **`showPlexBrowser` and `showProjectM` positioned the window after showing it** and were reordered;
  the other six already positioned first. Verified live on `ALXVortex` 2026-09-20 — the reporter's
  words were *"it loaded chrome and then the skin with no resize"*.
- **The wait for a ring belongs to the skin load, not to the user's click (W248).** What A and C
  left was the render itself — **1.28 s** for `ALXVortex`'s library ring, during which the window
  wears palette chrome — and nothing about that build needs the window: the size is
  `persisted interior + donorInsets`, both known once the skin has loaded. `WMPHostedFrameProvider.prewarm(_:)`
  builds them **serially** while nothing is on screen waiting, and `HostedWindowBorderLayout`
  chooses the sizes from the interiors it already persists, **most-recently-opened first**
  (`hostedWindowRecency`): the eleven persisted interiors span two controller families and rendering
  all of them would put minutes of speculative work behind every skin load. A fresh install
  therefore prewarms nothing and learns from the first session that opens anything. **The cap was
  four and is now eight, and the guard was once-per-skin and is now once-per-size — both because of
  W250 below**; at four it covered the library and left the spectrum analyser opening onto the
  palette, and once-per-skin fixed the queue on the first broadcast so a window whose size only
  became knowable later never got a speculative build at all. `prewarmedSizes` is cleared by
  `reset()`, which also answers two skins that lend identical borders with an emptied cache between
  them — "the border changed" was always the wrong test. A speculative
  failure records nothing: `refused` and the template-dropping verdicts belong to the drawing path,
  which has a window behind it. Measured on `ALXVortex` 2026-09-20: `prewarm queued=550x890` at
  load, 1.277 s, and then a cold library open with **zero** misses and zero builds.
- **A hosted window is not shown until the skin can dress it (W250). This is the guarantee; the
  prewarm is only an optimisation of it.** W248 refused a stand-in past 15% and what it left in its
  place was *flat palette chrome*, so every window the prewarm did not reach opened onto bare chrome
  — a worse picture than the stretched ring it replaced. The prewarm could never be the guarantee:
  it speculates from persisted interiors, so it reaches no window this user has not opened and no
  size it could not know, and it was capped at four of eight. Measured on `ALXVortex` 2026-09-21,
  reported as *"still showing in other skins and even in ALX skins on other non library windows"*:
  the spectrum analyser opened 368x145 and drew palette chrome **20 times** over
  `standin=out-of-scale from=550x893` before its ring landed 263 ms later.
  `HostedWindowBorderLayout.hold(_:until:)` is the answer and it is the **last** thing
  `prepare(_:)` does — the window is already positioned and sized and is still off screen, so the
  size is exact and nothing is on screen to wait. It is made transparent rather than kept out of the
  window list, because the show path belongs to the controller and this rule must not fight it, and
  it is revealed when `hostedSurfaceHasSettledFrameAnswer(for:)` says the skin has a *final* answer
  for the size it is **at** — a frame, a refusal, or a skin that lends nothing. Three things that
  are easy to get wrong, each of which was:
  - **A held window's size changes under it**, so the reveal is asked at `window.frame.size`, never
    at the size it was held for, and a hold that is not yet settled demands the live size — which
    makes it self-terminating rather than dependent on the prewarm having guessed the same number.
  - **A hold must never be computed against an unresolved border.** While the skin is resolving,
    `prepare(_:)` sizes the window against its *own* chrome, so demanding that size buys a full
    donor render of a frame nothing will wear — two of them at launch, 296 ms and 1342 ms — and
    worse, that frame settles the hold and reveals the window at a size `apply()` is about to grow.
    So `isDressed(at:)` is `hostedSurfaceBordersAreSettled && hasSettledFrameAnswer`, both halves.
  - **A skin on its way is a third state** (`WMPMainWindowController.isResolvingHostedFrames`). The
    provider is configured only once the player has *rendered*, so before that it has no template
    and answers "I lend no frame" for every size — indistinguishable from the settled truth for a
    skin that really lends none. That is how a **restored** hosted window came up at launch wearing
    palette chrome: `ALXVortex` 2026-09-21, Cava and the library drew **155** times before the
    donor's borders had resolved. It folds into `hostedSurfaceBordersAreSettled`, so a resize read
    during a skin load is not trusted either.

  Every failure path reveals: a `WMP_HOSTED_HOLD_MS` timer (default 4000 ms), `willClose`, and
  `deinit`. **A `reveal … reason=budget` line is this rule failing**, not working — the healthy
  outcome is `reason=frame`, and the measured spread is 276 ms for a cold analyser to 2.09 s for the
  library at launch, of which 1.4 s is the ring render alone. `WMP_HOSTED_HOLD=0` is the A/B switch.
  Every non-`.wmp` family answers "settled" unconditionally, or the hold would never end.
- **A skin change holds the outgoing skin's frames until the incoming skin can replace them
  (W248).** `configure(skin:)` emptied the cache the instant a new skin arrived, so every hosted
  window on screen was stripped to flat palette chrome for the length of one scene build — measured
  on the reporter's own pair, AlienMorph → ALXVortex, 2026-09-20: **51 draws on bare chrome, 1.29
  s**. *The prewarm cannot reach this case*, and that is the point worth remembering: the window is
  already open when the skin changes, so it asks for its frame the same instant the prewarm queues
  it and both wait on the one build. There is no "before" left to move the work into. What the
  window was wearing a moment ago, though, is real, complete, correctly-proportioned artwork for
  exactly that size — the wrong *skin* for a beat, which is a far smaller lie than a stretched ring
  or than nothing at all. So `outgoing` carries the old cache across the change and each entry is
  dropped the moment the new skin answers for that size, **with a frame or with a refusal**; a skin
  that lends nothing carries nothing, because its windows *should* go back to the palette. The
  lookup falls back to the nearest held frame within the same 15%, because a skin change is usually
  a size change too: different borders move every hosted window by the difference, and the
  reporter's pair moves the library 890 → 887. After: all 51 of those draws are
  `standin=outgoing from=550x890`, and no frame is bare. **An outer-size change is expected when
  borders differ.** W249 attributed it to a docking conflict, but live retesting preserved the
  interior: 890 → 887 → 890 with 822 points inside, and 890 → 893 → 890 with 825 points inside.
  Its cited trace prints before the resize, not after a refusal. The row and reproducible evidence
  moved to `LOW_QUALITY_TASKS.md` on 2026-09-20; do not restore that diagnosis without a settled
  interior change. A new skin still needs its own donor render, held behind the outgoing frame.
- **The stand-in is primed before any window opens, so a first open is never unskinned (W230).**
  Learning a ring donor's borders *is* composing a ring — `WMPHostedFrameTemplate.border` does it at
  the reference size when the skin loads — and the composition used to be discarded, so the first
  hosted window found `mostRecent` nil, was answered no artwork, and drew palette chrome until a
  render at its own size landed. It is now adopted as `mostRecent`, never into `cache`: a cache hit
  promises the frame was built for the size asked for, and this one was built for the donor's.
  **Rings only** — a panel's borders are four constants of its own bitmap, read without composing
  anything, and a stretched nine-patch is what the 15% guard exists to refuse. The current static frame probe does not exercise live
  child composition or animation; verify those through live-host captures.

**Every rule above is a rule each hosting view has to apply for itself, and that is the standing
weakness of this contract.** Relayout on artwork arrival, the correct ground fill, the overlay
policy, the metrics, the growth registration — each is centralised as a value or a helper and each
remains *optional at the call site*. Flow, Cava and PeppyMeter each carry their own borrowed-frame
fast path; the library computes its content rectangle somewhere else again. A frame dump can be
clean while the window is wrong, so nothing headless catches a view that simply did not call.
When a hosted defect reproduces on several windows at once, suspect the call sites before the frame.

**Rejected approach, 2026-09-18: the hosted-window container.** The
[architecture analysis](../../docs/wmp-skin/hosted-window-architecture-analysis.md) first proposed a
`WMPHostedSurfaceContainer` owning composition, placement and hit testing for all eight windows, with
a content protocol, adapters, a presentation state machine, a second border coordinator and a
migration of `PlexBrowserView`. **It is withdrawn, and re-proposing it needs new evidence.** It was
priced against a defect population nobody had measured, its state/identity work landed in
`App/Skinning/` — shared with Winamp Modern and with playlist/EQ, which it did not migrate — and it
would have made the failures uniform rather than fewer. What the document now carries is WMP-local
incremental correction plus **one narrowly named helper under `Windows/WMPSkin/` where several WMP
call sites need the same conversion corrected**. That helper is in scope; the framework is not.
It does not replace the implemented contract above. The mechanism notes below retain measured
counterexamples and rejected approaches.

Routing is `routeWMPSkinSurface` / `WMPSkinSurfaces` — 171 of the 180 archives declare a playlist and
164 an equaliser, so ours is the fallback for the handful that declare neither. **A fallback is
decided when the window opens, and the skin can change underneath it**: loading a `.wmz` with no
equaliser opened ours, and switching to one that has an equaliser left ours standing beside the
skin's — two equalizer windows on `xsn_sports`.
`WindowManager.dismissWMPFallbackSurfacesTheSkinProvides()` runs on every presentation and closes
(never destroys) ours, so the window keeps its frame for the next skin that needs it.

Theming is two layers, and the second is the one a skin with styled panels is asking for:

- **Colour** — `WMPSurfacePalette` → `SkinnedSurfaceStyle`, the seven roles every hosted surface
  needs.
- **Shape — the donor view is drawn *whole*, and what is the skin's own is subtracted (W209).**
  `WMPHostedFrameTemplate` → `SkinnedSurfaceFrameArtwork`. The template names a donor view — almost
  always the playlist — and `WMPHostedFrameProvider` rebuilds **that entire view** at our window's
  size through the ordinary `WMPSceneBuilder`/`WMPRenderer`, so alignment, tiling and `JScript:`
  layout expressions are resolved by the code that draws the skin rather than by a second reading of
  the same markup. Four subtractions, and nothing else is removed:
  1. the **client subview's contents** — the hole is ours;
  2. every **control** — a borrowed button is a lie about what it does;
  3. every **readout** — `<TEXT>`, `<STATUSTEXT>`, `<CURRENTPOSITIONTEXT>` are bound to the skin's
     own player state and are stale on our window;
  4. a subview whose **`backgroundImage` is also a control child's `image`** — these skins paint a
     button twice, once as the wrapper's backing, and dropping only the control leaves the glyph.
     The same image in both places is what separates a backing from a *plate*: `Back to the Future
     Trilogy`'s logo subview carries `f_logo.png` and wraps a button drawn from `f_logo_no.png`, and
     that plate is frame — it covers a join in the bottom bar.

  **Below the donor's declared floor, the view is built at the floor and the finished picture is
  scaled down.** A skin that declares `minWidth=560 minHeight=260` has never been asked what 357x238
  looks like, and its pieces come apart there. The scaling is non-uniform and the corners soften;
  that is the price of the author's own layout, and it was accepted on screen over the alternative.
  **Insets come from the client subview, never from the artwork's thickness** — `Halo 2`'s "border"
  bitmaps are 190px wide on a 406px window and mostly transparent.
- **The frame is painted *over* the content, and the interior *fill* is erased — not the rectangle
  (W209).** The old rule cut the client **rectangle** out before drawing, and these bezels are not
  rectangular, so the cut erased the frame's own inner edge wherever it dipped inside the rect.
  Instead the **most common opaque colour inside the hole** is found — *counted*, not inferred —
  flood-filled from the hole so a bezel dipping in is not mistaken for content, and everything left
  is drawn whole over our content. A donor whose interior is a *picture* has no such colour
  (`Scooby Doo`'s wallpaper) and keeps the cut; so does one where more than **10%** of the hole
  survives the erase. `SkinnedSurfaceFrameArtwork.paintsOverContent` carries the flag,
  `SkinnedSurfaceChrome.drawSkinFrame` and `PlexBrowserView.drawWinampModernChrome` honour it.
- **An animation tick that repaints content must repaint the chrome (W209).** `NetworkMonitorView`,
  `CavaView` and `PeppyMeterView` each had a content-only fast path for 60 Hz redraws that returned
  before the chrome overlay. Correct while chrome is a border *around* content; wrong the moment any
  of it overlaps, which is what painting over the content made true — the borrowed bezel was being
  erased on every tick. **The current static frame probe does not exercise this path**, which is
  why three rounds of artwork fixes changed nothing the reporter could see. Verify it with live-host,
  multi-frame captures. A hosted window with a fast path takes a
  full redraw whenever a skin lent a frame.
- **Shape, the second donor class — a *panel* (W207).** Over half the corpus lends no ring: measured
  at the library's own 550x464 on 2026-09-16, **88 of 185 archives lend a ring and 97 lend nothing**.
  But 77 of those 97 do state a window style, as **one fixed bitmap with the list inset inside it** —
  `anemone`'s `<subview id="playlisttray" backgroundImage="trayplaylist.bmp">`, 328x261 with its
  `<ITEMSPLAYLIST>` at 83,72 155x116 — which the ring rule rejected for having no edges to stretch.
  None are needed: **the hole states the four slice lines**, so the panel is nine-sliced (corners
  1:1, edge strips stretched, centre transparent) and resizes like any nine-patch. **32 archives lend
  one**, and the ring's 88 lines are byte-identical either side of the change, because a panel is
  only looked for when the skin states no ring anywhere. Three things the corpus forced, each of
  which read as "the derivation is broken": a drawer is authored `visible="false"` and a node that is
  not drawn **resolves no frame**, so the frame is built with the panel and its hole forced visible;
  a drawer is **parked outside the window it slides into** (`anemone`'s tray is at `left="307"` in a
  321-wide view), so the scene is built a second time on a canvas that contains it and the geometry
  re-read there; and **a player body with a list in it is not a frame** — `Erektorset`'s panel is its
  whole player, so a panel carrying the transport, the host sliders or the equaliser is refused, as
  the ring path refuses the player view by scoring it -100. What a panel cannot exclude is the
  donor's own *painted* controls: `Gorillaz` has a button strip in its bitmap, and those are pixels,
  not nodes.
- **How the window and the border share the space: the window is grown (W207, closed 2026-09-16).**
  **The interior keeps its size and the border is added around it** — `HostedWindowBorderLayout`,
  one central rule for the nine registered growth participants listed above, driven off
  `WMPHostedFrameProvider.donorInsets`, which answers a donor's four borders *without reference to any window* because a 600x150 analyser can
  never render a frame carrying `anemone`'s 173x145 and so could never learn its insets from one.
  A panel too small to carry its borders at 1:1 is answered nil and keeps palette chrome until
  growth lands. Exact panels preserve their sliced borders; rings can scale below the donor floor
  or when mapping their cropped extent onto the target. Pending renders may return provisional
  scaled artwork, including panels within the provider's 15% per-axis guard. `wasScaledToFit`
  records extent-to-target scaling or provisional scaling, not exclusively a below-floor case.
  Three answers preceded it and each was reported wrong:
  composing at the borders' own size (a five-point hole), refusing the window (the border came off
  everything but PeppyMeter), and a uniform scale-to-fit (the thin border the report was about).
  **Two more were tried and are wrong for reasons worth keeping.** Growing to the donor's *declared
  floor* so a ring lands 1:1 — `Ice` declares `min=585x308`, so every hosted window was forced to
  that at once, which is the ring path's own recorded rejection (*forcing every hosted window up to
  the donor's minimum moves windows the user placed*) confirmed by test. And measuring the growth
  against the donor's raw margins rather than through `reclaimingSideRacks` — `Ice`'s `plView`
  states a 157pt right rack, and growing by it put 157pt of decorative artwork on every window's
  right edge with nothing in it. Read `WMP_BORDER_TRACE` in `reference/harness.md` before touching
  this: three of its failure modes are invisible in both a screenshot and a `HOSTED-FRAME` line.
- **A donor's *own rail* is not a rack, and the reclaim stops where its artwork does (W212).**
  `reclaimingSideRacks` gives a lopsided margin back to our content on the reading that it is
  furniture; on `Alienware Invader` half of it is a 99pt opaque rail, and with the frame painted
  over the content 54pt of every hosted window was laid out under it. Neither position nor paint
  order separates the two — W210 settled that both sit in the reclaimed strip. What does is that
  the rail is *artwork* and a dropped rack leaves bare canvas, so `clearOfTheDonorsOwnRail`
  measures how far in from each edge the donor paints something that is neither transparent nor
  its **interior fill**. Excluding the fill is the whole rule: these border bitmaps carry the
  interior colour baked in for the skin's own list to cover (`f_right_tile` is 96px wide with 73
  of them opaque white), so a run measured on alpha alone reads a 96pt border and takes back the
  width the donor gives its own content. `borderInsets` **composes** the frame at the reference
  size rather than deriving insets from markup, so the window is grown by the border it will wear.
- **The reclaim measures a rail where the rail *is*, and a donor with no fill is not a donor with
  no rail (W219).** `clearOfTheDonorsOwnRail` above assumed two things that `TheUnit` breaks at
  once, and between them our content was handed the skin's own left rail — which the rectangular cut
  then erased, leaving no left bezel on any hosted window and our black ground running out to the
  window's edge. First, the run measured **in from the window's edge**, and this border grows the
  other way: `left_stretch.png` is 37px wide with its outer **30 the transparency key** — the
  window's curved silhouette — and the rail in the inner 7, so a run anchored at the edge is starved
  by 30 bare columns and answers zero. It now skips the bare lead-in; where a border does reach the
  edge the skip is zero and every number is unchanged. Second, the rule **returned the rack
  unmeasured whenever the hole carried no dominant fill**, which is the reclaim at its most
  dangerous rather than its safest — and a donor whose client subview is a `<VIDEO>` region has no
  fill at all, because its contents are ours and are subtracted, so its hole renders 97%
  transparent. Excluding nothing measures every opaque pixel in the strip as border, which can only
  make the reclaim *smaller*. Corpus at 550x464: **8 lines move across 7 skins**, all of them
  content the donor paints (`livin_it_skate`'s green rail, `Blinx`'s orange wing, `Crimson_Skies`),
  and the four rack skins the reclaim exists for — `Star Wars`, `STALKER`, `WoW`, `Halloween` — are
  byte-identical. **A column-wise measure was tried first and is wrong**: it re-refused exactly
  those four racks, which is the 2026-09-15 *"reclaim it, we have no content for it"* report coming
  back.
- **A view drawn whole cannot come apart, but it can still be drawn short (W212).** The frame build
  is outside the script runtime, so a side tile whose height only the skin's `onResize` sets keeps
  its bitmap's — a 20% bare run down each side of `Alienware Invader`, which is the desktop showing
  through a 99pt rail. The span repair is reachable under the whole-view render, under three guards
  that each answer a measured failure: **furniture is classified on the first pass** (a stretched
  rack reaches the bottom edge and the edge exemption lets it back in), **only the axis that came
  out bare is spanned** (`edgeGaps` is `[top, left, bottom, right]`; spanning the top tile too
  painted its white filler over both rails, which are drawn before it), and the repair is refused
  if the window's **content rect moves** (stretching a tile down grows the alpha bounding box and
  the hole rides the crop — `KungFuChaos` and `The_Last_Samurai` are that shape).
- **And what reaches that repair is a *length*, not a share of the edge (W228).** The run a
  script-sized rail leaves is the same at every window size — `Alienware Invader`'s is **107pt** —
  so a gate on `gaps` alone asks a question about the window: 107pt is 0.231 of a 464pt-tall one
  and 0.132 of the library browser's 810. The identical hole was therefore repaired on nine hosted
  windows and left open on the tenth, which is the only one that opens taller than 107 / 0.15 =
  713pt, reported 2026-09-18 as *"alien invader media library window draws broken. the other
  nullplayer windows draw ok"*. `edgeCameOutBare` now takes either test — the fraction, **or**
  `ringEdgeGapPointLimit` = 40pt measured along that edge — and 40 is in the same empty middle
  0.15 sits in: at 710x810 the corpus's closing rings run 0 to 24.3pt and its open ones 49.7, 85.2
  and 106.9. One `HOSTED-FRAME` line moves corpus-wide and 550x464 is unchanged. **Read a `gaps=`
  fraction back into points before believing a defect belongs to the window it showed up on** —
  the number is the frame's defect divided by the window's size, and one hosted window differing
  is otherwise the signature of that window's own layout (§ *Capturing the hosted windows*).
- **A borrowed glyph is a lie about what it does (W208, and it is why W209 subtracts).** A skin's
  own buttons are anchored to its window's edges exactly as its corner bitmaps are, so nothing in
  the markup separates them by position. `Ice` writes its playlist shuffle six nodes before
  `Vid-bottomleft.bmp`, and while the frame was *assembled from selected pieces* that glyph won the
  bottom-left corner on every hosted window. The selecting rules that answered it — transport-typed
  candidates refused, scripted transport refused in corners only — are **gone with the assembler**;
  the whole-view path drops every control unconditionally, which is both simpler and stricter, and
  it costs nothing now that no slot can be left empty by a refusal. The `HOSTED-FRAME` line cannot
  see this class of defect at all — it reports the piece count and the client hole, never which
  bitmap was drawn — so `WMP_HOSTED_FRAME_DUMP` is the instrument.
- **A resize grip is the window's corner, not a control's picture (W222).** Subtraction rule 4 — a
  subview whose `backgroundImage` is also a control child's `image` is that control's backing and
  goes with it — is right for a glyph painted twice (`Back to the Future Trilogy`'s shuffle pair)
  and wrong for a corner that is *authored as a button because that is the only node a `.wmz` can
  hang a mouse handler on*. `TheUnit` writes its rounded top-right corner and the top of its right
  rail exactly that way: `<subview backgroundImage="top2.png"><button image="top2.png"
  onmousedown="view.size('topright')"/></subview>`, three of them. The rule took all three off
  **every hosted window at once** — a square notch where the curve should be and the rail starting
  28pt down — reported 2026-09-17 as *"the issue is the right top corner … every window"*. **That
  it is the same on every window is the signature to read**: a piece the *frame* never had, as
  against a piece one window mislaid. The exemption is window geometry and nothing else
  (`isWindowGeometryGrip`): handlers that reach `view.size` or `view.dragMove` and never touch
  `player.`. The backing stays, the control walk still drops the button itself, our window keeps its
  own resize, and W193's 235 `view.size(corner)` calls are the population this serves. Corpus at
  550x464: **9 lines change and every one is a `gaps` value falling** — bare edge becoming artwork,
  on `Halo 2`, `Ice`, `Official Xbox` ×2, `XBOX`, `WWC` and both `TheUnit` archives — with no
  content rect moving. `Plus! Pulsar` is the one exception and is a pre-existing defect rather than
  this one: its donor is bigger than the window (`content=-191.111,38`, a hole starting off the
  window's left edge, before and after), so restoring a grip moved its alpha crop.
- **Refusing a corner is only right when the refusal is free, and a tie goes to the playlist
  (W179).** Both cases the corner refusal above was written for have a *second* declaration for the
  slot — `Ice` writes its shuffle glyph six nodes before `Vid-bottomleft.bmp`, `Back to the Future
  Trilogy` its repeat pair six before `f_top_left.png` — so dropping the control hands the corner to
  the real bitmap and the ring still meets. That is the whole population it was measured on, and it
  made the cost look like nothing. `Combat_Flight_Simulator_3` is the other shape: its playlist's
  top-left corner **is** the plate, `<subview backgroundImage="vid_top_left.png">` 190x29 with the
  repeat and shuffle buttons drawn on top as children with images of their own, and nothing else
  claims that slot. Refusing it emptied the corner, failed the four-corner guard, withdrew `plView`
  as a candidate **entirely**, and handed the skin's ring to `videoView` — so the library wore the
  film drawer's `BRIGHTNESS`/`CONTRAST`/`HUE`/`SATURATION` plate across its bottom bar, a
  *centre*-anchored extra that claims no slot, costs no score and is painted as decoration anyway.
  A refused corner is now taken back rather than losing the ring; nothing of the skin's behaviour
  comes with it, because the assembler draws the piece's own background command and never its
  children's and the whole-view path subtracts the subtree, exactly as W222's grip keeps its corner.
  **The second half is the donor contest.** Both views score 12 here — eight filled slots plus four
  for hosting content — so the winner was document order, which is the half of W209's `Project
  Gotham Racing 2` judgement that scoring *filled slots* never reached: that fixed the case where a
  video view scores higher and said nothing about the case where it ties. Corpus at 543x890 scale 2:
  the corner rule alone moves **nothing**, and both together move **13 lines across 12 archives,
  every one `video → playlist`**, each holding or improving its `gaps=` (`WWN` rails 98pt → 21,
  `The_Sentinel` bottom 0.416 → 0.014, `TripleX` and `xXx` tighter). **Write the tie-break as "a list
  beats anything that is not a list" and the corpus punishes it**: 17 lines, two regressions, both
  `visView → plView` — `Constantine` grows a 145pt right rack where it had an 18pt rail, which is
  `Ice`'s recorded rack rejection coming back, and `QuickSilver`'s right edge goes 0.012 bare →
  **0.908**. A skin gives its playlist a rack and its visualiser a rail, so `hostsVideo` excludes
  `<EFFECTS>` deliberately. **And read this bullet before believing a bottom-bar defect is a
  composition defect**: the ring a window wears is chosen per *view*, two steps upstream of
  anything `HOSTED-FRAME`'s inset fields describe — the field that names it is `view=`.
- **The ground a hosted window paints is its content hole, not the window**
  (`SkinnedSurfaceChrome.hostedGroundRect`). Every window in the spectrum family paints its own
  ground in its own `draw` and nothing shared owned that step, while `drawSkinFrame` deliberately
  fills only the client hole — so a view doing `bounds.fill()` first turns a shaped frame into a
  black box with the skin drawn inside it. Cava, `flow` and PeppyMeter each had one, and it was
  latent for as long as every donor was a ring laid out to the window's own edges: a panel has a
  silhouette, and the slab showed through everywhere the skin was cut away. The rule lives in one
  place so a window added later inherits it; Waveform, Spectrum, AudioAnalysis and ProjectM never
  filled the full bounds in the borrowed path, and Playlist, EQ and the library already filled
  `contentRect` only.
  **And the hole crosses between the two coordinate spaces as *insets*, never as a rect (W221).**
  `contentRect` is the artwork's own top-left scene space — what `drawSkinFrame` paints in, flipped
  — and those three views fill their ground in the window's bottom-left space, so handing the rect
  over mirrored the hole vertically. Invisible while a donor's caption and bottom border are about
  equal, which every donor before this one was; `TheUnit` lends a **5pt caption over a 60pt bottom
  bar**, and all three grounds landed 55pt low — the top of every hole left transparent with the
  desktop showing through it and the ground running out under the bottom bar. It reads exactly like
  a window with a hole punched in it, and it survived the first round of fixes because the *frame*
  was correct in every capture. `hostedGroundRect` now builds the rect from
  `artwork.scaled(to:).metrics`, which is orientation-free, and any new caller filling a rect in a
  view's own space must do the same.
- **A borrowed frame that arrives late is a *layout*, not a repaint (W220).** The ring is derived
  asynchronously for the window's own size, so it lands **after** the view has already laid out
  against the classic fallback metrics, and `hostedSurfaceStyleDidChange` did nothing but
  `needsDisplay = true`. A repaint redraws the chrome around subviews still framed for the old hole:
  three of these windows host one (`ProjectMView`'s GL view, `AudioAnalysisView`'s SwiftUI host,
  `SpectrumView`'s), and on Visualizations that subview kept the **whole window** and buried every
  borrowed piece under the visualization — no caption, no rail, no bottom bar, on a window whose
  `HOSTED-FRAME` line was perfect. All nine hosted views now mark the layout dirty on that
  notification, and `ProjectMView` re-frames its GL view explicitly; it costs nothing where a view
  has no subviews. **A new hosted window wires this in step 3 of the checklist below**, and the
  probe cannot see it: the frame is right, the artwork is right, and the picture is wrong.

**Nothing of ours is drawn over a borrowed ring — no title, no close glyph.** The ring is the
window's chrome, whole, and the only thing we add is a **hit area in its top-right corner**
(`SkinnedSurfaceChrome.closeButtonRect`, 40x26pt, capped by the band), because that corner is where
these skins paint their own close button and that painted × is what the user aims at. Every close
hit test reads that rect, `EQView` and `WaveformView` included — their classic 9x9 boxes are the
no-ring case now, not a separate answer.

**Four rules were tried in the band before this one and all four were wrong in the same way.** Guard
the lettering's contrast against the ring (W178), plate each control in a palette tone the artwork
cannot be confused with, centre them in the *lit* title bar found in the rendered pixels rather than
in the whole gap above the client hole, inset the close by the ring's right border and then cap that
inset at the band's height. Each was measured over the corpus, each shipped, and each had a
counter-example in the next skin the reporter opened — because **all four are inferences about
someone else's finished chrome, and `.wmz` markup states none of it**. `NVIDIA` is where the model
broke rather than the tuning: an 84pt band with too little contrast to call a bar (`strip=none`), so
the controls centred in the whole band and landed on the curve where its body starts, directly under
the restore, minimise and close the skin paints there itself. Reported 2026-09-15 as *"issue after
issue — what is the problem with your implementation"*, and the answer was that there was nothing
left to tune.

**This is the difference `.wal` makes, and it is worth stating.** A Winamp Modern skin has a real
frame system: `<Wasabi:StandardFrame:*>` declares the frame, the client rect is measured from its
resize strips, and its title bar and buttons are declared controls wired to actions — so a hosted
window is *mounted* in the skin's frame and we draw no chrome at all. Nothing is inferred, and none
of this class of defect exists there. A `.wmz` has no frame system: no title-bar element, no close
element, no standard client-rect contract. Donor selection uses authored geometry and alignment;
rings are rendered whole after subtraction and panels are nine-sliced at their content hole.
The close target remains a convention rather than a declared skin control.
**When a `.wmz` question can only be answered by reading the artwork,
that is the signal to stop answering it.**

Placing the control *inside* the client hole was tried in between and rejected on sight — a close
box a user has to hunt for is not an improvement on one drawn over artwork. `WMP_CAPTION_TRACE=1`
prints the hit rect and the hole it was resolved against.

**The donor view is ranked, not taken.** Several skins wrap the *same* ring around an `upgradeView`
— the "your Windows Media Player is too old" nag panel — and declare it before the real one, so
document order borrows the frame of a window nothing was ever meant to look at (`xsn_sports`,
`Halo 2`, `T3-Skynet_Media_Player`). A view holding a `PLAYLIST`, `VIDEO`, `EFFECTS`, `LISTBOX` or
`EQUALIZERSETTINGS` outranks one holding nothing, and the presented player ranks last — its body is
what the user is already looking at.

**How the ring numbers were measured.** Not by the markup census: `harness.md` records that views are
the one thing it does not count, so these came from splitting each `.wms` on `<VIEW` with a
`WMPTextDecoder`-shaped decoder (BOM, then a positional BOM-less UTF-16 sniff, then Windows-1252) and
classifying each direct `<SUBVIEW backgroundImage=…>` child by its `horizontalAlignment` /
`verticalAlignment` pair. **85 of 180** archives by that scan; **86 of 180** when
`WMPHostedFrameTemplate.derive` is run over the installed corpus through `WMPSkinLoader`. Quote
whichever you re-derive, with the method — the engine's own answer is the authoritative one, and the
one-skin gap is the scan's, not the engine's.

### Adding a NullPlayer-native window in WMP mode

The windows inside the rule today: playlist, library, equalizer, visualizations, spectrum, Cava,
Flow, PeppyMeter, audio analyzer, waveform, Sonos Rooms. The growth subset is the nine windows listed in the
current contract; playlist/EQ are explicit exceptions to step 8. A new metrics-based hosted window
wires every applicable step in the same change; each prevents a previously reported defect.

1. **Route before you host.** Ask `WMPSkinSurfaces` whether the skin declares this surface itself
   (§ *Ask what the skin provides before opening a window of your own*). A routing case added before
   the surface is hosted trades a duplicate window for an empty drawer.
2. **Colour** — nothing to do; `WindowManager.hostedSurfaceStyle` already answers for the family.
   Take the roles from there, never a hard-coded pair.
3. **Layout and hit testing** — `SkinnedSurfaceChrome.metrics(for:fallback:)`. The close control is
   a **hit area in the borrowed frame's top-right corner**, not a glyph of ours; nothing of ours is
   drawn over a borrowed frame. **Relayout on `hostedSurfaceStyleDidChange`, not just repaint**
   (W220) — the frame arrives after your first layout pass, and a subview framed for the old hole
   covers the ring.
4. **Chrome** — `WindowManager.hostedSurfaceFrameArtwork(for:)`.
5. **Paint the ground as `hostedGroundRect`, never `bounds`.** A `bounds.fill()` turns a shaped
   frame into a black box with the skin drawn inside it.
6. **Honour `paintsOverContent`** — draw your content, then the frame on top. The frame is not a
   border around a rectangle any more; it overlaps.
7. **If the view has an animation fast path, disable it whenever a skin lent a frame.** A 60 Hz
   content-only redraw erases overlapping chrome. The current static frame probe cannot exercise
   that redraw path; verify it with live-host, multi-frame captures.
8. **Grow, don't shrink** — `HostedWindowBorderLayout` adds the border around the interior off
   `WMPHostedFrameProvider.donorInsets` for registered metrics-based windows. Playlist/EQ remain
   excluded because their layout uses classic sprite geometry. Never scale content to make room.
9. **Verify on screen.** The `HOSTED-FRAME` line reports piece counts and rects; it cannot see a
   wrong bitmap, an erased bezel or a borrowed glyph. `WMP_HOSTED_FRAME_DUMP` and a
   `screencapture` of the live window are the instruments — § *Debugging a live defect*.

## Which control a click reaches

**Three rules decide it, and each was measured against the corpus rather than reasoned from the SDK
(W148).** `WMP_RENDER_OCCLUDED=1` is the instrument and `reference/harness.md` describes it; the
report that produced them is *"plus pulsar skin seems to ignore most clicks despite showing hover
graphics"*. Hover and click take the same path, so a control that highlights and does nothing is not
a dispatch defect — it is a control the pointer never reached at all.

- **Order by the paint traversal, not by `zIndex`.** `WMPHitMetadata.paintOrder` is the position
  `WMPSceneBuilder.walk` had reached, which is the order `commands` is already built in: DFS,
  siblings sorted by `zIndex`, negative-z children ahead of their parent's artwork. Sorting the flat
  `hits` array on the authored `zIndex` compares literals from unrelated branches — the same
  flattening `cerulean` rules out for paint. `Plus! Pulsar` is the worked case.
- **A control is its artwork, not its rectangle.** `WMPHitCoverage` falls a click through a pixel
  the skin keyed out of the node's own sprite, exactly as `mappingImage` already does per colour for
  a `<BUTTONGROUP>`'s children. `Navigator` states the intent outright: its `progress` slider spans
  the whole player and `progress_map.bmp` has holes cut in it where the close, full-mode and
  visualization buttons sit. **Two guards, and both cost controls when they were missing** — a
  sprite with *nothing* opaque in it is a hit catcher rather than a shape (`holiday_skin`, `Grinch`
  and `Josie_and_the_Pussycats` build whole transports that way, 104 controls across 21 archives),
  and a node with a `mappingImage` takes its region from the *map*, never from its art.
- **A hosted surface is its picture, and its picture ends where the skin paints over it (W213).**
  `<EFFECTS>` and `<VIDEO>` already rank last, which keeps the controls drawn over them; what
  ranking cannot give back is the artwork *between* those controls, which is not a control at all.
  `circle`'s `<EFFECTS>` is `jscript:vMain.width` by `jscript:vMain.height` — the whole player — so
  every press answered "visualization" and **the window could not be dragged**.
  `WMPHitCoverageBuilder.surfaceCoverage` reads the layer `commandSplitIndex` already separates for
  drawing and leaves the surface reachable only where it can be seen. **The half that decides the
  corpus is that a command paints only where the shapes it is inside keep it**: `clippingColor` keys
  a container's shape and never its artwork (W169), so `cerulean`'s `face.bmp` is opaque `#FF0000`
  across its own lens and only the container's region mask opens the hole. Read without the masks it
  buried the surfaces of `cerulean`, `aoe`, `claw`, `gadget` and `pharaoh`. Measured over the 184
  installed archives: the `rect-only` set is identical to the baseline — no control lost — and 20
  surfaces tighten. A **windowed** surface is excluded: nothing the skin paints is drawn over it.
- **A `CUSTOMSLIDER`'s `positionImage` is the authority on its region, and the colours the node
  keys out are not part of it (W150).** `WMPPositionMap` marked only *alpha-zero* pixels as outside
  the control, and `Plus! Pulsar`'s `seek_map.png` marks the 66% of its 79x136 square that is not
  the arc as opaque `#ff00ff` — averaged to a luminance that is a fraction of `0.667`, so two thirds
  of the seek control answered "seek to 67%". Coverage for such a node comes from the **map**, never
  from the sprite: `seek.png` is a 13-frame filmstrip whose opaque area is a property of the frame
  the current value selects, and deriving the region from it cost the arc 577 of its own pixels —
  the soft edges a pointer aims for. Measured before landing: **173 corpus sliders declare a key on
  a node with a position image and not one of them is a grey**, so no ramp value can be clipped by
  this.
- **A slider's region is the track it authored, not the artwork drawn in it (W256).** Every other
  control is its artwork; for a slider that rule reads the **thumb**, because a `<SLIDER>` paints a
  thumb at the current value and nothing else unless the skin gave it a track sprite. `elvis`'s
  eight bands are `<slider width="10" height="75" thumbImage="elvis_eqknob.gif">` with no track, so
  coverage claimed the 11x12 knob: four fifths of each band rejected the pointer, the press fell
  through to the tray's `<buttonGroup>` behind it, and pressing the track **dragged the window**.
  Driven live, `eq1` was the front-most candidate at the press point and lost on coverage alone.
  WMP moves the thumb to wherever the track is clicked, so the frame *is* the control — the skin
  authored a 10x75 box because that is the box it wants pressed. **A `CUSTOMSLIDER` is the
  exception and keeps its position map**, which is a better answer than the frame rather than a
  worse one (W150). **Reach: 448 sliders across 41 of 184 archives** paint a thumb and no track, measured
  2026-09-22 by `python3 scripts/wmp_slider_drag_census.py` (population B).
- **Whatever advertises a control must agree with the hit tester.** `resetCursorRects` and the
  `stringForToolTip` widget fallback both scanned bounding boxes, so Pulsar's dead corners kept a
  hand cursor and a "Seek" tip over pixels that hit nothing — reported as *"a clickable artifact to
  the right of the seek that does nothing"*. Both now consult `WMPHitCoverage`; the cursor is added
  as one rect per run of covered pixels per scanline, because `addCursorRect` is a list AppKit scans
  and an arc is ~136 bands where a pixel mask would be thousands. **A new surface that reads
  `hit.frame` to offer the user something inherits this bug** — ask coverage too.
- **A control the pointer is holding is the user's, and the host does not write to it (W151).**
  `WMPPropertyRegistry.positionSliderPaths` gives any slider whose `max` binds to
  `player.currentMedia.duration` an *implicit* `value` binding to `player.controls.currentPosition`
  — that is W128 and it is right, or the filmstrip never advances. But it settles on **every**
  transaction, including the one the release raises, and a skin that commits its seek by reading the
  control back (`onmouseup="player.controls.currentPosition=seekMain.value;"`) therefore seeks to
  wherever the track already was. `changes(for:origin:holding:)` skips `value` for held elements —
  only `value`, so `enabled` and `max` still settle — and `sliderCaptureActive` suppresses the two
  position events that raise the skin's own write-back. **Reach: 148 sliders across 112 of the 180
  archives**, every one whose `max` binds to the duration *and* which commits in its own handler. A
  slider with a `value` binding to a transport path is immune and is **not** the test:
  `performSlider` commits those natively through `WMPTransportAction.boundAction`, which is why
  `Plus! Pulsar`'s volume arc always worked while its identical seek arc did nothing.
- **A seek is committed once, on release — every other slider action is continuous (W156).**
  `WMPMainView.performSlider` runs from `mouseDragged`, so a `.seek` used to reach
  `AudioEngine.seek` on every mouse-move: **21 commits across a 200 px drag**, each one a
  `playerNode.stop()` and a reschedule with no ramp, which is what *"a harsh audio artifact at the
  time adjustment"* was. It is now held in `pendingSeek` and handed to `onSliderRelease` at
  `mouseUp` (`cancelInputCapture` drops it — a cancelled drag asks for no seek). Volume, balance and
  the equaliser bands still commit per move; a volume drag the user cannot hear is a broken control.
  **Who commits it is decided after the skin's own handlers have run, never from the markup**:
  `WMPMainWindowController` awaits the release transaction and commits `pendingSeek` only if that
  transaction posted no `seekSeconds` (`scriptDidCommitSeek`). Both halves are load-bearing — 111 of
  the corpus's 141 `onDragEnd` sources are `player.controls.currentPosition = value` and would
  otherwise be seeked twice, while a bare `<SEEKSLIDER>` authors no release handler at all and has
  no other committer. **The thumb is not deferred, only the audio**: `widgetValues` and
  `onElementValueChanged` are untouched and W151's hold keeps the position binding off the user's
  value. **The skin the report blamed was not the difference.** `New Super Mario Bros` was reported
  harsh and `corona` clean; driven live, they are identical — 21 commits apiece, Mario through its
  `value` binding and corona through `target.action` — and the markup changes only the 22nd. How
  harsh it sounds is the material and the distance dragged, not the authoring.
- **A transport element that issues its own command in `onClick` owns the click, and the engine must
  not post the command as well (W243).** `<NEXTELEMENT onClick="player.controls.next()">` says the
  same thing twice — the kind carries `.next` and the handler calls it — and `WMPMainView.mouseUp`
  raised the handler *and* applied `WMPHitTarget.action`, so **one click on `ALXMorph`'s Next
  advanced two tracks** of a three-index cue (First → Second → Third, 10 ms apart, driven live).
  `WMPTransportAction.handlerOwnsAction` decides it at scene build and the flag rides on the hit and
  on every mapping child; the keyboard activation path had the mirror defect — it posted the action
  and never ran the handler at all. **Reach: 73 elements across 19 of 182 archives** (`next` 17 uses
  / 16 skins, `previous` 15 / 14, `play` 20 / 19, `stop` 14 / 13, `pause` 7 / 7), counted over
  `wmp_markup_census.sh`'s flat files. **It is a dedupe and not "an authored handler wins"**: three
  corpus elements author a handler that only plays a sound and rely on the tag for the transport,
  and it is scoped to actions that come from the *tag*, so the Phase 4 fallback that derives an
  action from a plain `<BUTTON>`'s own literal keeps it. This is the rule `dispatchScriptEvent`
  already applied to `<RETURNBUTTON>`, where `anemone` and `modernblue` spell
  `view.returnToMediaCenter()` themselves. **Why it outlived every headless sweep:**
  `WMP_RENDER_CLICK` runs the authored handler and prints its host command and never applies
  `action`, so the probe shows one command where the app sent two — `harness.md` § *The probe flags*
  states the gap on the flag itself. The symptoms are shaped like the engine losing a click, not
  doubling one: `play`/`pause`/`stop` are idempotent and hide it, a `sticky` toggle driven this way
  returns to where it started, and only `next`/`previous` show the skip.
- **A control the host has greyed out is still a control, and the window does not move under it
  (W154).** `WMPMainView.interactiveTarget` answers `nil` for a disabled target exactly as it does
  for bare artwork, and `mouseDown` reads that as "no control here" — so pressing a greyed transport
  button **dragged the whole player**. Reported on `portals/mode1`, where a press on play with an
  empty playlist moved the window from `680,279` to `374,509`; `refreshHostState` disables every
  transport child while `player.controls.play` is unavailable, which is most of the corpus's
  five-button `<BUTTONGROUP>`s on a cold start. A disabled target now swallows the press. **An
  authored `enabled="false"` is not this case and still drags**, because those never reach the hit
  tester at all — which is what keeps `portals`' own 305x400 decorative `main_button` backdrop
  movable, and is the distinction to preserve if this is ever touched again.
- **`host.snapshot` is computed live and carries the clock, so never diff it across a transaction
  (W157).** `WMPAudioEngineHost.snapshot` reads `engine.currentTime` on every access; two readings
  taken either side of a 10 ms transaction always differ while a track plays. `dispatchScriptTransaction`
  used to end on `if host.snapshot != hostStateBeforeCommands { refreshHostState() }` to notice a
  host its own commands had moved, and with playback that fired on **every** pass — raising
  `currentposition_onchange`, which dispatched another transaction, whose defer raised another.
  Measured live on `NVIDIA`, release: **39.9 refreshes/s from that defer against 9.9/s from the real
  10 Hz tick**, every one of them from a transaction that posted zero commands. It is now taken only
  when `output.hostCommands` is non-empty. Anything that wants "did the host move" must compare the
  fields it cares about, never the whole snapshot.
- **A transaction whose overrides are unchanged has nothing to draw, and must not build a scene
  (W158).** `transact` returns the view's **cumulative** committed overrides, so equality with
  `presentation.sceneOverrides` means every geometry value, property and `wmpprop:` binding resolved
  as it already had — `WMPSceneBuilder.build` takes no host snapshot, so there is no third input
  except a `LISTBOX`'s script-filled rows (`presentation.presentedListItems`). Without the skip, a
  skin's own `onTimer` cost a full rebuild and full-window re-render per tick whatever its handler
  did: **442 `timerInterval`/`onTimer` uses across 91 archives**, and `NVIDIA`'s 100 ms timer alone
  redrew an identical 730x574 playlist ten times a second. Stopped, all of its ticks now skip (CPU
  22% → 9.5%); *playing*, none of them do, and that is correct — the trace names what moves and it is
  the seek slider's bound `value` at 16/s. **Repainting the whole view because one clock digit moved
  is the remaining cost and it is a dirty-region problem, not this one.**
- **Measure a `.wmz` perf claim in release, and say which build it came from.** A debug scene build
  is ~31 ms where release is ~4.6 ms, which is the difference between "the playlist runs at 1 fps"
  (debug, arrivals beating completion so nearly every transaction is cancelled mid-flight) and "it
  runs at 22" (release, same code, same skin, same track). Both readings above are real; only one of
  them is what a user sees.
- **Two ordering traps live in `dispatchScriptTransaction`, and both give plausible wrong answers.**
  It **cancels the presentation's previous script task**, so dispatching two events back to back
  loses the first — put both handler sets in one event. And it only *creates* a task, so anything
  that must outlive the transaction (releasing a hold, clearing a gate) has to `await
  presentation.scriptTask?.value`, not simply follow the call.
- **`<EFFECTS>` and `<VIDEO>` are fallbacks, never blockers.** Both are click-through by design —
  `WMPEffectsSurfaceView.hitTest` returns `nil` — but 51 skins wire an `onClick` on the effects node,
  so they rank last rather than not at all. Both are routinely the largest node in their view and
  declared late, so paint order alone buries whatever is drawn over them: `Alienware Invader`'s
  rating stars, `Radio`'s equalizer sliders, `XBOX`'s `xDown`.

Net over the 180-archive corpus, `WMP_RENDER_HOST=playing`: **112 controls in 33 archives recovered,
11 lost**. The 11 are open and named in `WMP_TASKS.md` (W149): `Sports`'s 7 equalizer sliders under
its playlist text, `anime`, `STALKER`, `T3-Skynet_Media_Player`, and one `<BUTTONGROUP>` container
with no mapping children, which dispatches nothing in any case.

## Loader contracts

- `WMPPhase0Limits` and stable codes `WMP0001`–`WMP0020` are locked. Production loading must preserve
  their meanings and reject metadata bounds before decompressing payloads. One amendment exists:
  `WMP0005`'s 200:1 ratio is tested only on entries expanding past `entryCompressionRatioFloorBytes`
  (1 MiB), because a ratio is not the quantity a bomb is dangerous in and flat-colour BMPs are not
  bombs — see Amendment 1 in `phase-0-decision-record.md`. It is not a precedent: **never relax a
  limit to make a skin load.** That one held only because the limit was mis-specified against its
  own threat model, and it was argued about the threat rather than about the skins.
- Archive paths normalize Windows separators, use Unicode-composed case-insensitive lookup, and
  reject absolute paths, drive prefixes, traversal, symlinks, collisions, excess wrapper depth, and
  CRC failure. The provider is read-only and never extracts to disk.
- A skin contains exactly one unambiguous `.wms` at root or under one wrapper directory. Resources
  resolve relative to the declaring file and then the skin root, never outside the provider.
- Text decoding is BOM-aware UTF-8/UTF-16LE/UTF-16BE, then a **positional** BOM-less UTF-16 sniff,
  then a deterministic Windows-1252 fallback for unmarked legacy WMP text. Do not guess other ANSI
  code pages, shell out to `iconv`, accept malformed surrogates, or allow embedded NULs.
- XML is parsed by a hand-rolled lenient parser, **not** `XMLParser` — libxml2 aborts on a duplicate
  attribute before the delegate runs, which rejected 4 of 14 archives. It retains authored
  tag/attribute spelling, **attribute document order**, and source locations while bounding depth and
  node count. Unknown elements stay in the graph for compatibility reporting.
- `reference/loading.md` is the contract for both: what is tolerated, what stays fatal, and the two
  things (attribute order, CR-only line endings) that look cosmetic and are not.
- Attribute parsing classifies expressions, bindings, handlers, colors, and resources without
  executing skin code. `res://` and optional missing artwork warn; path escapes and required missing
  scripts fail.
- **TEXT colour roles follow interaction state.** Resolve `hoverForegroundColor` and
  `hoverBackgroundColor` only while the TEXT hit target is hovered, then fall back to the normal
  roles; resolve `disabledFontStyle` only while disabled, then fall back to `fontStyle`. Use
  `WMPAttributeParser.color(from:)` for every role so named SDK colours stay consistent (W131).
- Graph IDs and registry order are deterministic. Duplicate authored IDs are retained and warned,
  not silently collapsed.
- **A skin that names no `scriptFile` still has a script, and it is found by name.** Seven archives
  declare none and ship one `.js` whose basename is the skin definition's own; all seven call into it
  from their handlers, so registering only what `scriptFile` names left each of them throwing on the
  first statement of its first handler (W163). The fallback is narrowed to **both** conditions — no
  `scriptFile` anywhere in the skin, and a basename match against the `.wms` — because a skin that
  names its scripts has said what it wants loaded. See `reference/loading.md` § *The script a skin
  never names*.

Skin JScript runs in one persistent in-process `JSContext` per skin session, on a WMP-owned serial
queue, with the object model as the security boundary — see Amendment 2 in
`phase-0-decision-record.md` for why the helper process was retired and what that costs. An in-app
`WKWebView` remains prohibited.

## Static scene and image contracts

- **What WMP does with a `backgroundImage` whose frame is not its bitmap is unsettled, and it must be
  measured before the rule changes (W123).** `Ice` authors
  `<button image="Pl-xp.bmp" width="196" height="144">` over a bitmap that is really 196x**44**,
  inside `<subview id="Drawerbutton2" backgroundimage="Pl-xp.bmp" width="313" height="144">`. Both
  were stretched and therefore agreed; the button is now drawn at its own 196x44 (W122) and **a seam
  appears in the lower shell**. **1 view measured** (`Ice/videoView`) out of the 545-image corpus
  capture; the wider class — every `backgroundImage` whose frame is not its bitmap — is unmeasured.
  Reproduce with `WMP_SKIN=…/Ice.wmz WMP_RENDER_PROBE=videoView`. **It cannot be answered by
  extending W122**: `Ice`'s own frame tiles all author `backgroundtiled="true"`, which suggests WMP
  does not stretch and a skin tiles deliberately — but `Vidcolorbox` is
  `horizontalAlignment="stretch" verticalAlignment="stretch"` with an untiled `Vid-bg.bmp`, and
  `LostPlanet`'s stretch tiles are 61 px of window frame that would punch through. Check
  `reference/skins/README.md`'s counter-evidence table first, and settle it together with W240 —
  `Radio` is in both, and in `harness.md`'s *17 views, 4 mismatched* table.

- **A `.wmz` is 1x artwork and this app draws it on a 2x display, so the upscale is done by Lanczos
  ahead of the draw — never by CoreGraphics' own filter.** This is the one rendering rule that is
  about *resolution* rather than geometry, and it is settled:
  `WMPBitmapInterpolationPolicy.decision` says whether a draw qualifies, and
  `WMPImageStore.upscaledImage` does the resample once and caches it in the same LRU as every
  decoded image. **`.low` and `.high` are byte-identical on the draw path** — measured on
  `Plus! Hard Boiled/Egg_Body_Normal.jpg` at 2x — so the interpolation *quality* is not a lever and
  changing it is a no-op; the only choices CoreGraphics offers are bilinear, which blurs, and
  `.none`, which blocks. A reporter rejected both in turn (W160).

  Three conditions must all hold before a bitmap is resampled, and each one exists because the
  version without it moved artwork nothing was wrong with:

  1. the skin draws the bitmap at its **authored size** — a stretched gradient is asking to be
     interpolated, and resampling it as artwork changes a picture nobody complained about;
  2. the device scale is a **whole multiple**;
  3. the destination lands **on the pixel grid** — a fractional origin has no whole-pixel
     destination, and snapping it is a shift, not a sharpening.

  Everything else keeps `.low`, which is what the engine has always passed. **A corpus render sweep
  cannot see any of this**: `WMPRenderer.dump` renders at 1x, where the device scale is 1 and no
  draw qualifies, so a clean sweep here proves only that nothing *else* moved. The measurement is a
  `screencapture` of the live window on a Retina display — see `reference/skins/plus-family.md`
  § *W160*.

  **The crop happens before the scale, never after.** Lanczos reads a ~3px neighbourhood, so
  resampling a filmstrip whole would bleed each sprite into the one beside it; `sourceRect` is part
  of the cache key for that reason. **Alpha is never sharpened** — the sharpen unpacks to planes and
  skips it — or a keyed silhouette grows a ringing halo.

- **A `<VIEW>` anchors background artwork that is not its declared size; it never stretches to fill
  (W164).** The image is the window's picture, and where the two disagree the author meant the
  surplus to be empty — `transparencyColor` keys it out and the window simply is not there.
  `Colorchooser` declares `width="300" height="200"` over a 246x202 bitmap, and stretched by 1.22 its
  drawn box landed at x=87…299 while the opaque panel that belongs inside it stayed at the authored
  77…241. **Scoped to a mismatch the markup states, not one a resize produced**: where the authored
  size and the artwork agree, a canvas the user or a script grew still stretches the background as
  before. 17 corpus views declare a literal size alongside a resolvable background image and exactly
  4 disagree — `Colorchooser`, `Cubist`, `Radio`, `Tomb Raider 2`, each of which authors a band or a
  plate rather than a full-window picture. `Ice` is what this deliberately does **not** settle: a
  `<BUTTON>` sized against a background image is the natural-size rule (W122), not the root's art.

- **`hueShift` rotates a node's artwork, and it is the property a skin is named after (W173).**
  One archive in 180 uses it and all ten uses are script writes: `Plus! HueShifter`'s paintbrush is
  `changeHue()`, which steps a JS global by `360.0 / 11` and assigns it to the five "candy" pieces
  ringing the player — `topCandy`, `botCandy`, `leftCandy`, `rightCandy`, `botCandyFacade` — so the
  ring cycles through the spectrum. Unimplemented, every write was inert and the candies were frozen
  at their native green, reported as *"is it supposed to be green or not because it still is"*. The
  green **is** the artwork — the skin ships a 600x600 self-portrait, `hueshifter_final.jpg`, and the
  bottom clamshell is green in it at the coordinates the markup puts `botCandy` — and the defect was
  that it could never be anything else.

  **The unit is degrees, and the skin is the authority.** `changeHue()` offers ten stops at 33°,
  65°, 98° … 327° and `savePrefs` clamps to `0…360`. Read as -1…1 every one of them would clamp to
  the same value and the button would do nothing visible, which is not what Microsoft shipped.
  `WMPImageStore.canonicalHueShift` wraps; 0 and 360 are both no shift and take the untouched decode.

  **Use the standard `hue-rotate` matrix, not the NTSC YIQ constants.** The YIQ form rotates the
  *other* way — 120° takes red to blue, `(24, 42, 255)`, where every other implementation gives
  `(0, 113, 0)` — and its blue row carries coefficients of 1.25 and -1.05, which drive a saturated
  pixel far out of gamut and then clamp it, costing the luminance the rotation exists to keep. The
  SVG/CSS matrix turns the chroma about the luma axis: measured at all ten of the skin's stops on
  in-gamut colours the worst luma drift is **0.45 of 255**, which is rounding, and a grey does not
  move at any angle — which is what keeps the candies' black wedges and white specular highlight.
  A fully saturated pixel always clips and always will; that is inherent to the operation.

  **The rotation is folded into the decode, not applied at the draw**, and the angle is part of the
  cache key — so the crop, the Lanczos upscale (W160) and every mask see the colour the skin asked
  for, and five elements at five angles are five entries rather than one shared bitmap. `hueshift`
  is in `standardNumericProperties` because it is *rendered*: stored inert it would never reach the
  scene, which is exactly what the defect was. **A corpus sweep proves nothing here** — the property
  defaults to 0, so 179 archives are byte-identical and the one that moves does so only after a
  handler runs. Drive the button with `WMP_RENDER_CLICK` and read the `changed=` line.

- **A colour has three sources and the markup is only one of them (W165).** `mirroredColor` resolves
  them in WMP's order: the value a handler assigned, then the authored attribute, then one hop
  through `wmpprop:<element>.<property>` — the named element's own override first, then its markup.
  One hop, like `mirroredVisibility`, because a mirror of a mirror is authored nowhere in the corpus.
  `Colorchooser` is the **only archive that binds a colour with `wmpprop:`** and needs all three at
  once; reading markup alone drew its caption white on a white panel, painted no fill behind its
  transport, and left its three RGB sliders with nothing to change. **A write the colour parser
  cannot read is no answer, not black** — `theme.loadPreference` answers WMP's `--` sentinel for an
  unsaved key and skins assign it without checking, so an unparseable override leaves the authored
  colour standing. The reach beyond that skin is the mechanism's, not a heuristic's: 8 further corpus
  images moved, every one a colour the skin's own script had always assigned and nothing painted.

- **A script owns paint order as much as the markup does (W166).** `zIndex` is an ordinary writable
  property and seven archives animate it — 58 assignments across `Beck`, `Cablemusic`,
  `Charlies_Angels_Full_Throttle`, `Colorchooser`, `Plus! Professional`, `Spider-man` and
  `cyberchannel`. Reading only the markup left every one of those swaps drawing in its authored
  order, and on `Colorchooser` it reached the window itself: `checkForContent()` raises
  `viz.zIndex` from -5 to 5 to bring the visualizer forward, and with the node still sorted at -5
  the opaque panel the player sits on counted as artwork *above* a **windowed** surface and was
  punched out by `windowedEffectsRects` (W144). Below it the view's own artwork keys white to
  transparent, so the result was a click-through hole through a borderless `isOpaque = false` window
  for as long as a track played. **W144's rule is unchanged** — what belongs in a windowed rect is
  still whatever the skin painted before the effects node — and so is `cerulean`'s: the number is
  still sorted **among a node's own siblings**, never flat across the view. Only where it comes from
  moved. **No headless probe and no corpus sweep can see this class**: the sweep runs a stopped
  player, which is the one state in which the skin is correct, and `WMP_RENDER_HOST=playing` seeds
  the snapshot without raising the `playstatechange` the write lives in.

- **A `<VIEW>` that declares both `clippingColor` and `transparencyColor` has said two different
  things, and an `<EFFECTS>` rect over the second one is not a hole (W174).** The clipping colour is
  the matte outside the window's silhouette; the transparency colour is a hole *inside* it, and what
  a hole inside the window shows is the control behind it. Both were keyed straight out of the
  artwork, so `Ovoid`'s screen — 11,400 magenta pixels in the middle of a 153x200 oval whose 6,468
  red ones are its corners — was a hole through a borderless `isOpaque = false` window: *"missing its
  backing in the center, it click through to the desktop"*. Behind it is
  `<EFFECTS zIndex="-1" left="24" top="29" width="105" height="142">`, and **an `<EFFECTS>` that
  authors no backdrop of its own still has one, and in WMP it is black** — two corpus rects restate
  it as `backgroundColor="#000000"` and none names another colour. `WMPEffectsGround` is the rule.

  **The ground goes under everything in the below layer, never over it**, so a skin that paints its
  own backdrop behind the rect covers it completely and W9 is intact: 78 of the corpus's 95 effects
  rects are already fully backed and render byte-identically. **The shape it is clipped to comes
  from `clippingColor` alone** — the nearest *ancestor*'s background artwork with that colour keyed
  out, at the container's own size (the `Gorillaz` guard). This is the one place the W172 widening to
  `transparencyColor` must not reach: a container that shapes itself with the transparency key alone
  has not distinguished the outside from a hole, and `Plus! BubbleSkin` would take 44% of its rect
  black outside the silhouette. **`circle` holds down the other half — the ancestor.** Its `vMain`
  declares the `<EFFECTS>` and the vis field that keys a hole in it as *siblings*, so no shape is in
  scope and the rect takes no ground; and that is the right answer, because `visfield.bmp`'s 1,122
  magenta pixels are a one-pixel antialias fringe between the grey field and the red matte rather
  than a screen. Relaxing either half draws a black halo round that skin.

  **This class a corpus sweep can arbitrate, and the ground is drawn in the flat dump for that
  reason** — it is the *skin's* backdrop, not the hosted surface. Sweep over 184 archives: **5 images
  move and every changed pixel is a former hole becoming opaque black** — `rad` 27,090 px, `Ovoid`
  11,400, `Goo` 2,993 (through its `bigGoo` subview), `digitaldj/DigitalDJMini` 1,973, and
  `cerulean` 20 isolated pinholes along its vis hole's antialiased curve. Nothing already painted
  moved. **The reach is measured by rendering, not by the markup**: dump the corpus, then count the
  fully transparent pixels inside each `WIDGET … effects` frame — that is the whole population, and
  it is 17 rects of 95 before the clipping-colour gate takes it to 5.

- **A one-shot GIF that ends on a degenerate `restore to background` frame ends showing nothing,
  and holding its last frame buries whatever it was drawn over (W161).** A `.wmz` opens its shutter
  by assigning an animated GIF to a `<SUBVIEW>` over the player's face and never hides that subview
  again — the *closed* state is held by a separate static child the same handler toggles, which only
  makes sense if the animation leaves nothing behind. On `Windows_XP_Media_Center_Edition` the held
  frame is an opaque blue plate, so the metadata, `STATUS:`, elapsed readout, seek slider **and the
  equaliser panel the skin opens in the same rectangle** were all drawn and then covered — reported
  as *"the eq does not work"*. `WMPGIFTerminator` is the rule and only `WMPRenderer` consults it, so
  hit testing and coverage still read the sprite.

  **Disposal alone is not the test, and reading it that way erases artwork.** 379 corpus GIFs are
  one-shot with a full-size disposal-2 final frame, `ALXMorph`'s six-frame idle logo among them. The
  **degenerate final block** — 1x1, disposing to background, on a canvas larger than that — is what
  separates them: **79 files across 33 archives**. `Age_of_Mythology` settles the shape inside one
  skin: `open_shutter.gif` carries the terminator and `close_shutter.gif` does not, ending instead on
  a full-size 80%-opaque closed shutter that has to persist. `Halo 2` says the same thing the other
  way — its `m_shutter_open.gif` ends on a full-size frame that is *entirely the key colour*, so it
  was already invisible and this rule changes nothing there. **A corpus render sweep cannot see any
  of this**: it draws at clock 0, before any animation has finished, so a clean sweep here proves
  only that nothing else moved — the measurement is the live window.

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

- **A view is sized like any other node: authored literal, then script override, then the natural
  size of its own `backgroundImage`.** WMP skins routinely author `<VIEW backgroundImage="...">` with
  no width or height — the window *is* the bitmap — and demanding a positive literal at the root was
  the largest single cause of a skin that loaded and then drew nothing (89 views across 48 skins).
  The same artwork fallback already applied to every non-root node. **A view with no size and no
  artwork of its own is then sized by the union of the subtree it can place from literals and
  artwork alone** — `iconic` hangs its whole player off one `<SUBVIEW backgroundImage="base.gif">`.
  That union descends into a container whose own size is unknown and ignores `visible`, because a
  skin authors every wrapper hidden and turns one on in `onLoad`. Anything needing script
  contributes nothing, and the builder never invents geometry.
- **A view with nothing to draw is `0x0`, not a rejection, and a literal or scripted zero is an
  authored answer.** A `.wmz` names views that are never windows: 25 corpus skins author a
  `controlView` holding only `<player>` and a hidden `<video>` so an `onLoad` can run with host
  bindings and no window, and `pharaoh` writes the same idea as `<view id="vGhost" width="0"
  height="0">` whose handler redirects. Rejecting them was the last of `WMP0032`. The builder still
  invents nothing — the honest size of empty content is empty — and **`WMPMainWindowController` is
  what refuses to make a window out of it**: initial load walks its candidate list (persisted view,
  then `vPlayer`, then document order) running each view's script and following the views it asks
  for next until one has a canvas, and `switchView` runs a windowless view's script, honours its host
  commands, and stays where it is. `WMPRenderer` still refuses a non-positive canvas; a zero-area
  scene must never reach it.
- **What a windowless view asks for next is two different requests, and collapsing them into one
  `last` picks the wrong player (W175).** `theme.currentViewID` is a redirect and the last write
  wins. `theme.openView` is not a redirect at all — WMP opens a window per call and leaves the caller
  alone — so a dispatcher that opens its playlist, its player and its equaliser is asking for three
  windows, and `WMPMainWindowController.windowlessSuccessors` is where the distinction is made.
  **The player is the earliest of the opened views in the skin's own declaration order**, the rest
  are replayed against it through `applyHostCommands` once it is on screen, and every one of them
  stays in the candidate list so a player that is windowless in its turn still falls through.
  Reading only the last command opened `XBOX Music Mixer` on the equaliser its `onLoadSkin()` opens
  *after* `mainView` — *"it opens to the playlist and there is no route to get to the main window"* —
  and it is the only one of that skin's views whose buttons reach the others. **The old rule was
  right by luck wherever the skin happened to open its player last, which is most of them** — 21 of
  the 25 windowless `onLoadSkin` dispatchers end on `openView('mainView')`, and the panels they
  opened before it had therefore never opened at launch at all. Measured live, `Halo 2` goes from
  1 window to 5 and `xsn_sports` from 1 to 5, each of the extras a panel its own preferences say was
  open. The ranking is by declaration order because **all 21 archives that declare both a `mainView`
  and a panel view declare `mainView` first**; both scans, and the four dispatchers that are the
  exception, are in `reference/skins/xbox-music-mixer.md`.
  **The persisted view is the trap when this is touched**: `wmpSkinViewID` is written on every
  present, so a wrong player is sticky across relaunches and a fix is not visible until it is
  cleared — which is also what selecting the skin again does (`WMPSkinImporter.select`).
  `WMPWindowlessSuccessorTests` holds the ranking down.
- **`theme.openView` opens an additional window beside the opener; `theme.currentViewID` replaces the calling window's view. A skin's extra views are real windows.** 90 of the 180 archives call `openView`, 579 times. For four phases this engine had exactly one WMP window and the call was reduced to "present the view here and remember the one it covered" (`openedViewStack` / `CoveredView`) — and **that reduction was itself the cause of three reported defects**, not merely a deviation: W90 ("closing an interior window closes the whole UI"), W96 ("the skin is empty and shows no player") and W127 (the macOS close control stranding the user) each existed only because a covered view had to be *simulated*. `WMPViewWindowMaterializer` builds one borderless window per open view, all against **one shared script runtime**, modelled directly on `WinampModernHostedWindowMaterializer` — the only one of the three other families whose recipe transfers, because a `.wmz` view is an arbitrary authored canvas with no stack to join (Halo 2's panels are 406x209 against a 327x294 player). The first view presented binds the app's own window and is **the player**: the `MainWindowProviding` anchor, the restore anchor, the tiler's anchor, and the only presentation that writes `wmpSkinViewID` or is sampled for `WMPSurfacePalette`. **That window is the app's, not the skin's, and ordering it out is what a *close* means and nothing else** — a skin reload and a mode teardown drop its presentation without touching the window, because the caller is about to put a new skin (or the unskinned view) into it. Sharing one `remove` between close and teardown cost exactly that: `AppStateManager.restoreWindowFrames` calls `restoreFrame`, which reloads the skin when one is already loaded, so **every launch with a persisted `.wmz` and a saved frame ordered the main window off screen** with nothing anywhere to put it back. Reported as "main windows launch minimized". An *auxiliary* window is ordered out either way — it belongs to the skin, and a skin going away must not leave its panels behind. `theme.closeView(name)` closes the named window (84 skins, and every one of them had been aborting the handler that called it) and `openViewRelative` places the new window at its authored offset from the opener's top-left (W50 closed). **The drawer exception is what this does not touch**: Corona's sliding playlist and equaliser and NVIDIA's embedded modes are `<SUBVIEW>`s of the presented view's own canvas, never reach `openView`, and behave exactly as they did. See `reference/object-model.md`.
- **A windowless view opened by `theme.openView` owns the window it was asking for, and its
  window-scoped commands must never reach the opener (W200).** `openView` opens a window beside the
  opener and leaves the opener alone; a view with no canvas has no window to leave anything in, and
  running *every* command it posts against `existing ?? opener ?? player` is correct for the
  host-level ones and destructive for the three that are about a window.
  `WMPMainWindowController.redirectedToOwnWindow` rewrites `setCurrentView` to `openView` and drops
  a valueless `closeView`/`minimizeWindow`, and it applies **only when there is no `existing`
  window** — a view that becomes windowless in its own `onLoad` (`Halo 2`'s `previewView`) is
  reached by a switch, has a window, and is unchanged. `theme.closeView('name')` is untouched:
  naming a target is not the same as meaning your own, and 84 archives call the named form.
  **`pharaoh` is the whole case and only 2 of 185 archives reach this at all** (its two ghosts, and
  `cyberchannel`'s `playView`). Its transport calls `theme.openView('vGhostAutoDetect')`, that 0x0
  view's `onLoad` writes `theme.currentViewID='vRos'`, and the redirect landed on the player — the
  400x249 sphinx *became* the 197x194 rosetta panel, whose own close button then closed the app's
  only window; two clicks left the process running with zero windows. Reported as *"you can get
  trapped in the mini windows with no way back to the main window"*, and **it survived a relaunch**,
  which is the half that matters: `OnLoad()` opens `vGhost` on every launch and its `onLoad` reads a
  preference the skin itself saves, so one branch closed the player before it was seen and the other
  replaced it. A defect that persists through a restart has no route out inside the skin.
- **The app menu must open a skin-owned auxiliary surface through `openView`, never `switchView`.** The reason has changed and the rule has not: `openView` is the call the skin's *own* button makes, so routing a menu toggle through it means the panel behaves identically however it was opened — its own window, its own close. `switchView` would instead replace the player's view with the panel, which is what it means, and it is not what a menu item asking for a playlist means. `revealSkinSurface` routes every off-screen WMP surface through the `openView` host command. `WindowManager.wmpSkinShowsInActiveView` asks about **any open WMP window**, not the one presented view, so a toggle for a playlist already up reports checked-and-inert rather than opening it twice.
- **Do not mistake an in-place mode for an auxiliary view.** NVIDIA is the counterexample: its playlist and video layouts live inside `mainView`, while its top-right control still calls `view.close()`. There is no window of its own to close, so treating that command like an EQ close hides the player and leaves its last embedded mode as the apparent main window. The guard used to read "nothing has been opened over the player" and now reads "this is the player and it is the only window open" — the same statement in the new vocabulary. NVIDIA's close route instead runs its authored audio transition, first clearing its `videoItem` preference because `audioModeToggle()` otherwise redirects back into video mode. The installed-skin key is `NVIDIA` — `WMPSkinImporter` removes `.wmz` — so a compatibility guard must compare the installed name, not the archive filename. `WMPPhase9Tests.testNVIDIAEmbeddedPlaylistCloseReturnsToAudioMode` holds the route down.
- **A skin sound effect must not abort its state transition.** NullPlayer does not play bundled WMP skin sounds, but `theme.playSound(...)` is an inert host call rather than an unrecognised member: AlienMorph opens its shutter, plays `intro.wav`, then stops its intro timer. Throwing on the sound call skipped the stop and re-toggled the shutter every second.
- **A view the skin never shows can still have to keep running, and a view it only covered has to come back as it was left.** Two different things this engine used to treat the same way — "not the presented view, therefore gone" — and each is a whole class of dead controls. **A windowless view that declares `timerInterval` + `onTimer` is a *dispatcher*** (W89): 24 of the 180 archives author `<view id="controlView" timerInterval="100" onTimer="checkRemoteViewStatus()">` and route their panel, minimize and close buttons through it — the button does not call the host at all, it writes `theme.savePreference('remoteCallPl','true')` and that handler reads it back. Real WMP keeps it open beside the player. `WMPMainWindowController.adoptDispatcher` **scans** for it after presenting; keying it off the candidate walk works only on a profile with no persisted view, because `wmpSkinViewID` is written on every present and the walk then stops at the player. It runs through `WMPScriptRuntime.dispatch`, which commits no overrides and does not consume the observable-property changes — a dispatcher has no window, so it has no scene — and its elements are swapped in and the presented view's swapped back, objects and all, because every view root is called `view`. **And `theme.openView` opens a *second window*: the opener is never touched** (W90). That used to be simulated — the covered view's overrides, its timer period and its animation clock were stashed and a `closeView` return was a *restore* rather than a load, because rebuilding it discarded the overrides its script had accumulated and reinstated the markup `timerInterval` the script had overridden. On `Alienware Invader` that returned to `commands=0` and let the markup's 500 ms re-fire `toggleShutter()` with `introStatus` already true, shuttering the whole player; reported as "closing an interior window closes the whole UI". **The simulation is gone and so is everything built on it** — `CoveredView`, `openedViewStack`, `switchView(to:restoring:)` and `WMPScriptRuntime.prepareForRestore` — because the opener is now genuinely still running in its own window, which is what the restore was imitating. What survives is the primitive underneath: `WMPScriptContext.restoreElements(for:)` swaps each window's live elements in for the length of its own transaction, since one `JSContext` serves them all and every view root is called `view`. A genuine view change still loads exactly like a launch (W46).
- **A view arrived at by a switch loads exactly like one arrived at by launch, and a `.wmz` compact mode is built entirely out of that.** `switchView(to:)` raises `load` on the new view, applies the host commands the handler posts — *after* `apply`, which sets the view timer from markup, so the script's `setViewTimerInterval` is the override and not the other way round — and schedules its `timerRequests`. It did none of the three for a long time (W46), and Corona's `viewTiny` is authored `timerInterval="0"` and animates itself into the mini player from `OnTinyLoad` alone: the switch happened, nothing ran, and the compact view drew **the same artwork at the same size as the player**. The only visible symptom was the playlist and equaliser drawers going away, because `viewTiny`'s markup does not have them. Two consequences bind: the initial-load `collapsed` guard applies here too, since a view can now blank itself in an `onLoad` this path finally runs; and `viewchange` is dispatched only when the markup authors a handler, because a transaction's `timerRequests` are what *that* transaction registered and an unconditional binding-only one posts an empty set that cancels what `load` just scheduled.
- **The skin's own JScript is ES3, and `JSContext` is not — `WMPJScriptDialect` is where that is reconciled (W86).** WMP9's `corona_tiny.js` chains its compact-mode animation by appending a timer event to the array its `TimerDispatch` is enumerating with `for-in`. JScript visits the appended index; JavaScriptCore snapshots and does not, so the chained event was dropped on the tick it was registered and the whole WMP9 family could neither collapse its video panel nor get back to `vPlayer`. Corona's 2002 script splices the array instead and is unaffected, which is what made `corona` the control and `9SeriesDefault` the case. The rewrite is bounded, skips strings/comments/regex literals, and leaves a program with no `for-in` byte-identical; **3 of 180 archives use `for-in` at all and one depends on the live semantic**, so the corpus sweep is the proof it changed nothing else. **Before ranking a "the script runs and nothing happens" defect, ask whether the handler depends on an ES3 semantic** — no headless probe here can see that class, and the live `INPUT script-diag` line stays silent because nothing throws. And when you add to this file's scanner: **test a CRLF fixture.** Swift folds `"\r\n"` into one `Character` that is not `"\n"`, and the first version of the rewrite silently did nothing to the entire corpus for that reason while every LF-only unit test passed.
- **A `<property>_onchange` fires in the same transaction as the write that triggered it, and the view's `JScript:` geometry expressions are *not* re-run to achieve the same thing.** A `.wmz` animates by writing geometry once per timer tick, so a pane positioned off a moving one has to move in the same frame; letting it catch up on the next transaction tore the compact view into two visible halves that closed four seconds later (W87). Only what the skin declared is raised — 16 geometry `_onchange` attributes across 6 archives — bounded and once per property per transaction, so two panes positioned off each other cannot loop. **Re-resolving the expression set after the handlers is the tempting general form and it is wrong**: those attributes are an initial layout rather than a live binding, and several read the property they write (`left="JScript:svBottomLeft.width-left"`), so re-running them moved 175 of 545 corpus images and shattered `Back to the Future Trilogy`'s `videoView` and `ALXMorph`'s frame. That is what a sweep is for; it was reverted on the measurement, not on taste.
- **A tween's endpoint is not readable by the rest of the handler that started it (W112).** WMP
  animates `moveTo`/`resizeTo`/`alphaBlendTo` over the call's duration argument, so an element's
  `left` still answers where it *is* for the remaining statements — and skins are written against
  exactly that. `Cablemusic`'s playlist tab is `onClick="PlayListMove();HidePlist();"`: the first
  slides the drawer, the second reads `subPlayList.left` to decide whether it is now open or shut.
  With the endpoint applied inside the call that read answered the destination, so closing the
  drawer never hid the playlist and it stayed over the player forever — reported as "the playlist is
  always showing". **A duration of zero is not a tween** and applies immediately, which is what
  `movePlayButton()`'s `moveTo(x, 116, 0)` toggle depends on.
- **And the tween now runs for the duration it was given, but only where something is drawing
  frames (W194).** For four phases the endpoint landed at the handler boundary and the completion
  was raised in the same transaction, so a 1,000 ms slide took one frame and nothing in the corpus
  ever animated — reported against `Compact`'s drawers as *"its not a smooth opening"*. **The
  decision is made per transaction, not per call**: `WMPScriptRuntime.transact(animatesTweens:)` is
  a caller promising a frame clock, and only a window has one. A render dump, the corpus census and
  the windowless dispatcher (W89) do not, and for them the call behaves exactly as it did before —
  endpoint at the handler boundary (W38), completion from it (W55) — so **the settled state is
  identical either way and every measurement taken against a headless probe still holds**. That is
  also why a sweep cannot see this row at all; it is drivable only live.
  With a clock, `WMPObjectModel` holds the motion as a `WMPScriptTween` (channels with `from`/`to`,
  duration, completion event), the runtime keeps it per view scope, and
  `WMPMainWindowController.startTweenLoop` steps it at 30 fps through
  `WMPScriptRuntime.tweenFrame` — a real transaction per frame, so the interpolated value is
  written through the object model, becomes a mutation and therefore a scene override, and the
  element reads where it *is* mid-slide. Three things still arrive instantly under a clock, each
  because a frame would be a guess: a duration of zero, a channel already at its destination (its
  completion is raised at once, or a sequence chained off a no-op move would stall), and a channel
  whose current value the model does not hold — which is why `alphaBlendTo` on an **unauthored**
  `alphaBlend` still arrives rather than fading, and the ALX family keeps the subtrees it depends on
  arriving. A later call on the same element and property **replaces** the one running, so a drawer
  re-toggled mid-slide reverses from wherever it is.
  **The callback is the load-bearing half.** Moving `onEndMove` from end-of-handler to end-of-tween
  changes when 36 views chain their next step: `Compact` shrinks its own window inside
  `Playlist_OnEndMove`, so the window now shrinks a beat after the drawer starts closing, which is
  what WMP does.
- **And `load` carries a clock too, which is the half W194 left out (W253).** It was enabled on the
  click and view-timer paths only, so a tween a skin authored in its `onLoad` still landed its
  endpoint in one frame — `Revert (1)`'s `onLoad="vwPlayer_OnLoad();alphaBlendTo(40,9000);"` is the
  clean case, a nine-second fade to translucent that arrived fully faded before the window was ever
  shown. **`WMPMainWindowController` has two load sites and the row named the wrong one**: ~1348 is
  `theme.openView`, the skin's *extra* windows, while the player itself opens on the skin-load walk
  at ~404. Both now pass `animatesTweens:` and call `startTweenLoop`; fixing only the first
  compiled, passed, and changed nothing on screen. `WMP_LOAD_TWEENS=0` is the A/B and
  `WMP_TWEEN_TRACE=1` the instrument — see `reference/harness.md`.
  **W194's stated risk did not materialise, and it was measured rather than reasoned about**: an
  `onLoad` sequence chained through `onEndMove` now presents its pre-tween state and completes a
  beat later, exactly as WMP does. Ten skins A/B'd at t=16 s — `9SeriesDefault`, `corona`,
  `Back to the Future Trilogy`, `Plus! Professional`, `TripleX for XP`, `US Marine Corps`, `WoW`,
  `Rave-MP`, `Revert` — settle byte-identical at identical window sizes.
  **`Alienware Invader` is the one that cannot be A/B'd this way and is the trap worth keeping**:
  it differed, and four runs of it produce four distinct hashes because its intro never settles, so
  the diff is the skin's own animation and not the change. Its ON run ran **zero** tweens, which is
  what says so. A skin that never settles needs a same-mode control before any comparison is read.
  **The corpus numbers on this row are void.** `WMP_TASKS.md` carried 108 of 184 archives and a
  static walk of `onLoad` handlers gives 67; both count markup rather than execution. `Blinx`'s only
  `moveTo` sits inside a `/* */` block, and a walk that follows every call from `onLoad` follows
  branches that never run. Only `WMP_TWEEN_TRACE` can count this, per skin, and it has not been run
  corpus-wide.
- **Compact mode is authored by 11 archives, and the button every skin has is not it — audited 2026-09-12.**
  The corpus splits three ways and conflating them wastes a session. **Real compact toggles: 11 skins**, by two
  mechanisms — a switch to a smaller view (`corona`, `9SeriesDefault` → `viewTiny`; `Main_Street` slim/mini;
  `T3-Skynet_Media_Player`; `digitaldj`; `holiday_skin`; `portals`) and an in-place `view.width`/`view.height`
  write (`Cablemusic`, `Goo`, `iconic`, `Melvin`). Every one of them was clicked in the running app with a track
  playing and **10 of the 11 change the window**: 859x468→596x468, 593x600→475x373, 324x253→163x114,
  288x255→79x70, 440x336→280x130, 516x496→214x49, 317x330→400x81. `portals` is the exception and its cause is not compact mode:
  the walk opened the wrong view (**W153**, closed 2026-09-13) and the right one turned out to drag the window
  instead of clicking (**W154**). `digitaldj` works from `DigitalDJMid` and not from `DigitalDJ`, which is W152. **The
  five *"Return to Player/Main Mode"* buttons are video-mode returns, not compact** (`Plus! Professional`,
  `QuickSilver` ×2, `TripleX` ×2, `xXx_night_vision_redx`) and all reach `setCurrentView` cleanly. **And the
  button the reporter meets in nearly every skin is `view.returnToMediaCenter()` — 162 archives, 196
  controls, 179 of them tooltipped "Return to full mode".** It toggles the Library Browser (opens when hidden, closes when visible) since W100 closed on
  2026-09-13; before that it was dead in every one of them, which is why *"the compact button does nothing"*
  was that button and not compact mode. Name the skin and check it against this list before reading such a
  report as a compact defect.
  **This button's glyph is not its meaning, and a report about it is usually about the glyph
  (W176).** Re-derived 2026-09-19 over the 185 installed archives: **204 controls in 169 archives**,
  and *every one* tooltipped some spelling of "Return To Full Mode". **139 of them are
  `<BUTTONELEMENT>` with no image at all** — a mapping colour on a shared bitmap — 61 are
  `<BUTTON>` and 4 are bare `<RETURNBUTTON>`. Of the 65 that name a file the stems are
  `full`/`fullmode`/`max`/`fullbutton`, **and 5 are `close*`**: the notice-view close boxes, which
  is why those five now close their window instead (W176). So the same call wears a maximize box, a
  full-mode arrow, an unmarked colour region and, in five skins, an X — and a reporter naming the
  icon is not naming the control. **Read the authored `id` and `upToolTip` off `WMP_RENDER_PROBE`
  before believing any report that identifies one of these by what it looks like.**

  **`WALL-E` is the worked case, and the lesson is the button order rather than this button.** Its
  `mainView` system strip is **minimize, full mode, close** left to right at `305,4` / `333,4` /
  `361,4` — Windows order, where macOS puts close leftmost. Read left to right as macOS, that gives
  *"the X to close maps to minimize and the minimize maps to library toggle"*, which is what it was
  reported as. All three are correct: `WMP_RENDER_CLICK` at each centre hits the button under it,
  the bitmaps are a dash on the left and a red X on the right as authored, and driven live the X
  leaves 0 windows with the process alive while the dash leaves `AXMinimized=true` with 1. A
  `.wmz` is a Windows skin and orders its title strip the Windows way; **check the strip's order
  before reading a report that names two of its buttons.**

  Rapid library toggles require `WMPMainView.acceptsFirstMouse` so the click after the library
  takes focus still activates the skin control, and WMP-only `animationBehavior = .none` in
  `WindowManager.showPlexBrowser` so native window animations do not race visibility. Verified
  on New Super Mario Bros with six consecutive clicks about 0.3 seconds apart, then user-confirmed.
  **A window bigger than the compact artwork is not a defect here**: `corona`'s `viewTiny` is authored 596x498 and
  draws a 346x103 mini player into it, exactly as its markup asks — WMP shapes that window with the transparency
  key and this engine leaves it transparent, which looks the same. Measure the window, not the ink.
- **A view's own size is the one expression input a handler can change out from under the pass that
  already read it, and the builder can refuse the change (W99).** `WMPScriptContext` resolves the
  `JScript:` geometry before the handlers run — a pane positioned off another must see the frame that
  pane lands at — so a handler that assigns `view.width`/`view.height` leaves every expression
  reading it a transaction stale. **And `canvas = resizeLimits.clamp(…)`, so a view declaring
  `minWidth`/`minHeight` has a floor its own script cannot write through**: `ALXMorph` is
  `<view id="videoView" height="357" minHeight="357">` and `onLoadVid()` assigns 316, which the
  canvas rejects while the script goes on answering it. The transaction now clamps the view element
  to its own limits and re-resolves the expressions against that; `WMPScriptRuntime` reports the
  clamped size as `viewSize`, so the window, the next transaction and the expressions carry one
  number. **Re-resolving against the *raw* assignment instead is the defect with more reach** — it
  walked `Back to the Future Trilogy/videoView` to `x=-94` — which the 20-archive sweep caught and
  no single-skin check would have. `EXPR`'s two columns are the instrument: `->` is the initial
  resolver against the canvas, `live=` is the runtime's, and **a disagreement between them where the
  deps are only `view.width`/`view.height` is this class and nothing else** (corpus-wide: 809 before,
  0 after). **A view with an `onTimer` hides it**, because the next tick opens a transaction at the
  corrected size — `xsn_sports` read as a drawer button drifting 20 px rather than as a broken
  window. 217 corpus views author the shape and **146 have no timer and never correct**, which is
  part of what W68's "draws a shell" has been all along.
- **A script resizing its own window is four separate claims, and `Compact.wmz`'s drawers needed all
  four (W184-W192, 2026-09-16).** They are listed here because each one *renders perfectly* in a
  capture and does nothing on screen: the builder takes its canvas from the script's overrides, so
  every headless probe agrees with the skin while the window stays where it was. **Read `viewSize=`
  on the `CLICK` line, never the picture.**
  1. **One axis is a resize.** `assignedViewSize` demanded an override for *both* `width` and
     `height`; this skin grows only the width for one drawer and only the height for the other, so
     it answered nil and the window never moved (W186).
  2. **The axis the transaction did not assign is the *window's*, not the one left in the
     overrides.** Those are cumulative, so a handler touching only the height re-asserted a width
     from ten minutes ago and undid the user's stretch (W188).
  3. **A script-assigned alignment is anchored at the canvas it was assigned at, and the canvas moves
     *within* the transaction.** `SetAlignment(false)` → `view.width += rightMove` →
     `SetAlignment(true)` is how a skin says *the body keeps its size and the space I just added is
     the drawer's*; measured from the authored size instead, the body stretched over the drawer it
     had opened (W185).
  4. **A piece pinned to an edge rides it through a resize in the same handler.** The same idiom
     with `right`/`bottom` instead — `SnapToVideoSize` — must move the piece, because this engine
     lays out once per transaction and the middle state otherwise never exists. Without it the
     drawer stays put while the window grows past it and **its tab ends up outside the window, where
     nothing can ever click it again** (W192). One archive in the corpus assigns an alignment from
     script, so 3 and 4 can move nothing else.
  Two more from the same report are about *when* the window moves, not what size it takes: a script
  transaction rebuilds at the **window's current size**, never the last scene's (a transaction in
  flight across a user resize otherwise re-presents the stale canvas and stores it, permanently —
  W187); and the frame is set in the **same main-actor turn as `present`**, because resizing ahead
  of the render leaves AppKit stretching the old picture into the new frame — reported as "a big UI
  flash when the drawer opens" (W190). See `reference/skins/compact.md`.
- **`view.size(corner)` blocks in WMP, and a skin's resize bracket is built entirely out of that
  (W225, 2026-09-18).** 235 calls in 88 of the 185 archives, every one of them `onMouseDown`, and
  the statements *after* the call are what the skin does when the drag is over. `Compact`'s
  `DoSize()` pins `playlistDrawer` to `right` and `settingsDrawer` to `bottom` so both ride the
  window's corner, calls it, and unpins them. Nothing here can block, so the pin and the unpin both
  landed before the first pixel moved: the drawers kept their absolute positions while `playerView`
  (`stretch`) grew over them, and their tabs ended up buried under the body where no click could
  reach them. Reported as *"when you stretch compact skin it breaks the drawers and the main body
  will absorb them and also not allow them to close"*. Three claims, and the report needed all three:
  1. **The mutation count is the seam.** `WMPObjectModel.resizeCallMutationIndex` records where the
     call fell; `WMPScriptRuntime` holds the tail and `resumeAfterWindowResize` replays it against
     the size the window finished at. **Gated on `animatesTweens`** for the same reason a tween is
     (W194) — that is the caller promising it is a window, and only a window runs a drag — so a
     render dump, the corpus census and the windowless dispatcher still run the handler straight
     through and every measurement taken against them holds.
  2. **The tail is the *last* word on the release, not the first.** Raised at the top of `mouseUp`,
     it fell straight through into the ordinary control path, whose `mouseup`/`click` dispatch calls
     `presentation.scriptTask?.cancel()`. The unpin lost that race and `playerView` stayed pinned
     `left`/`top` while both drawers stayed pinned to the corner — a player drawn small in the
     top-left with its drawers stranded out at the window's edges, for the rest of the session. It
     is raised from a `defer`.
  3. **Assigning an alignment freezes the element where it is *drawn*, and the extent half of that
     must stay out of the geometry overrides.** WMP re-measures the margins at the write, so the
     unpin must not teleport the drawer back to its authored `left`. But
     `WMPSceneBuilder.ownAuthoredSize` reads the geometry overrides and **is what every child's own
     alignment delta is measured from**: written there, `SetAlignment(true)` made `playerView`'s
     authored 422 read as the 754 it had been dragged to, and its whole chrome — tiles, corners,
     the transport strip — saw a zero delta and collapsed back to the authored arrangement inside a
     754-wide frame while both drawers sat correctly at the edges. Reported as *"the drawer and
     resizing is totally broken in every way"*. The origin half is an ordinary script-assigned
     coordinate; the extent half is `WMPSceneOverrides.scriptAlignmentExtent`, consulted only by the
     `stretch` case. **One archive in the corpus assigns an alignment from script**, so 3 can move
     nothing else — verify with a decoded scan for `.horizontalAlignment =` before touching it.
  **Drivable only live**, and `WMP_RESIZE_TRACE=1` is the instrument: read `release script=true`
  against the `resume` that must follow it. See `reference/skins/compact.md`.
- **The window edge is ours, and AppKit takes it before the view can (W227).** `WMPMainView` has
  carried a 6pt edge band since W193 and for a real drag it had never run: a `.wmz` window is
  `[.borderless, .resizable]`, and `.resizable` alone is enough for AppKit to claim a press near the
  frame in `NSWindow.sendEvent` and run its own resize loop — the view is sent no `mouseDown`, no
  `mouseDragged` and no `mouseUp`, and the window is resized entirely outside the skin. A *click* on
  the same pixel does reach the view, which is why the band read as live and why `edge-band press`
  only ever printed for gestures that resized nothing. `WMPSkinWindow.sendEvent` claims the press
  first, and only where the view says no control is there, so a control drawn against the window
  edge keeps every pixel it had.
  **What the bare band skipped is the skin's bracket, and the corpus is emphatic about it**: 69 of
  the 87 archives authoring `view.size` run something after the call, and in 68 it is one idiom —
  `saveVidSize()` / `onVidSetSize()` / `g_fUserHasSized = true`, persisting the size the user just
  dragged to. Pulled by the edge, the window resized and the skin forgot it the moment the view
  closed. So the band raises the view's own grip handler (`WMPResizeGrip` names the node; 233 of the
  234 corpus calls are spelled into the handler attribute and the one that is not is `Compact`'s
  `DoSize()`, so it resolves one hop through the skin's scripts), W225's machinery holds the tail,
  and the release replays it. `beginScriptResize` **adopts** a drag already under the pointer rather
  than refusing it: refusing answers `false`, which is the caller's signal that no release is
  coming, and the held tail would then run mid-drag against the size the window started at.
- **A script-assigned extent is an answer, not a baseline, and a nested one must not be re-grown.**
  W225's re-anchoring is the growth of the element's *parent* since the assignment, and only a child
  of the view root has a parent whose extent the canvas is; deeper, the fallback was the growth since
  the *markup*, added on top of a number the handler measured at the current size — the resize
  counted twice. `Compact` is the worked case: `svBanner`'s `visible_onchange` writes
  `svScreen.height = svScreenOuter.height - svScreen.top` the first time a track plays, and
  `myeffect` is `height="jscript:svScreen.height - top"` under it. Stretch the player to 620x573 and
  *then* start playing — both wrote the right number for that canvas, 435 and 410, and both were
  drawn 195 taller, 195 being 573 − 378. The visualizer spilled out of the window over the transport
  strip, and the drawers read as missing underneath it. **The order is the reproduction**: with a
  track already playing the same stretch is correct, because the write happens before the resize
  rather than after it. Nothing moves for a node the script never wrote.
  **An authored `jscript:` binding on a sibling's extent is a different mechanism and was W235** —
  `NVIDIA`'s `visEffects` off `visFrame` — measured not to be this, and closed 2026-09-19 by the
  alignment-baseline half of `c78f32f7`: `ownAuthoredSize` was reading the runtime's own geometry
  override back as authored, so every child's stretch delta was zero. A gated widget like
  `visEffects` is reachable headlessly after all — one `WMP_RENDER_CLICK` on the toggle that sets
  `mainModeVis.visible`, then `WMP_RENDER_SIZE` for the stretch. See the archive.
- **WMP's `event` object is a global, and 84 of 185 archives read it (W184).** `Compact`'s drawer
  handlers open `view.maxWidth = event.screenWidth` from a plain function call, and its view root
  reads the same thing from a `jscript:` attribute where no event exists at all — so it is bound
  like `player` and `theme`, not like a handler argument. `screenWidth`/`screenHeight` answer the
  window's display (a fixed 1920x1080 headlessly, so a sweep reads the same on every machine) and
  `shiftKey`/`ctrlKey`/`altKey` answer the dispatching event. **`keyCode` stays unrecognised on
  purpose** — 433 uses across 79 archives, and nothing here dispatches `onKeyDown`, so answering `0`
  would tell every one of those handlers that a key it never saw was pressed. A member that cannot
  be answered honestly belongs in the demand tally, not in a default.
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
  `harness.md` § *The probe flags* on what a clean sweep does not prove.
- **`<RETURNBUTTON>` is the command, not a button that happens to be there (W191).** 19 uses across
  15 archives and **15 author no `onClick` at all** — the element's own behaviour is the return to
  the media centre, so treating the kind as an ordinary button left the library unreachable from
  those skins. It posts `toggleLibrary` only when the markup authored nothing: `anemone` and
  `modernblue` spell `view.returnToMediaCenter()` themselves, and doing both toggles it twice.
- **A `.wmz` compact mode is a script resizing its own window, and it is the script's output rather
  than the drawing's (W113).** `SwitchSmall()` writes `view.width = 475; view.height = 373` and
  swaps one shell for another. Three separate things had to hold and none of them did:
  **the view root reads its own size overrides before its markup**, like every other node — the
  literal used to win, so a `<VIEW width="593">` could never be resized by its own script;
  **the size a script assigns is not the size alignment is measured from** — `ownAuthoredSize` stays
  the markup's, because `LostPlanet`'s `onLoadInfo` opens with `view.width = view.minWidth` and
  collapsing the delta to zero stopped its stretch tiles covering the 61 px they were covering,
  punching holes through the window frame; and **it is committed in the uncancellable half of the
  transaction**, beside the host commands, because with a track playing a `status_onchange` lands
  five times a second and cancels the click's task after its render (W88). The overrides had already
  committed, so the *next* rebuild drew the compact player at the old canvas — a 475x373 player in a
  593x600 window, which is the "large overlay" that was reported. `WMPScriptOutput.viewSize` carries
  it, keyed off the **mutations** so an expression-driven `<VIEW width="jscript:…">` — which already
  read the window's current size — is not mistaken for a resize request. A non-positive result is
  not a size: that is the store-thumbnail collapse, and ten more `mediaSwitcherView`s joined the
  documented `WMP0035` windowless class when the override finally reached the view root.
- **Three of the four alignments are margins and `center` is not, and reading it as one cost a whole
  window frame (W143).** `right`, `bottom` and `stretch` say *hold this edge's authored distance to
  the parent's edge* — the delta form, a no-op at the view's own authored size, and what W113's
  `ownAuthoredSize` and `LostPlanet` exist to protect. `center` says the element **stays centred**,
  so its coordinate is `(parent − own) / 2` computed fresh, and the authored coordinate on that axis
  is not an offset into it — which is exactly why a skin that wants a centred piece authors none at
  all. Read as a margin, every one of them collapsed to the parent's origin. **The Alienware/ALX
  frame is built out of this and nothing else**: each of their playlist, equaliser, visualisation and
  video windows hangs its two 175px side columns off `<subview id="plLeftCenter"
  verticalAlignment="center" backgroundImage="f_left_center.png"/>` with no `top`, plus a tile above
  and below at `top="wmpprop:plLeftCenter.top"`, so the columns landed on top of
  `f_top_left.png`/`f_top_right.png` and took the window's whole title bar and the top of its inner
  border with them. Reported as "the playlist and eq windows are not properly constructed … the
  window border and details are not correct and there are large gaps". **The blast radius is the
  measurement, and it is the largest of any single line in this engine: 139 of 535 corpus images
  moved, and every one sampled is a repair** — WALL-E's logo and transport row, `PowerToys`' cancel
  button, `xsn_sports`' progress panel finally sitting over its own pointer arrow, `TripleX`'s
  clipped `X3-080902` readout, the five `US …` video placeholders, `Plus! Pulsar`'s side-drawer tab,
  `Project Gotham Racing 2`'s frame stripes, and `T3-Skynet_Media_Player`, which had been drawing a
  half-width frame with its own buttons outside it. **The axes are independent** (AlienMorph's
  `plRightCenter` is centred vertically and pinned right). **Amended by W144: nothing outranks
  centring on the centred axis** — the `isComputed` guard was carried onto `center` alongside the
  other three, justified by WoW's `left="JScript:view.width-202"` beside an alignment, and WoW's
  alignment on that node is `right`. A decoded corpus scan finds **3** centred nodes authoring an
  expression on the centred axis, all in `Ice`, against 376 that author no coordinate at all — so
  the guard protected nothing it was written for, and it cost every drawer a skin slides by script.
  See the `windowed`/drawer entry below and `reference/skins/xsn-sports.md`. `mainView` is
  byte-identical across the whole family: a non-resizable player authors no
  centred pieces, so **this class lives entirely in the windows a skin opens beside its player** —
  which is why four phases of `mainView` work never saw it. `WMPAlignmentTests` pins both halves.
- **A `wmpprop:` read of another element's geometry answers where that element *is*, not what it
  authored (W212).** One hop on from the rule above, and the half of it that had no answer: the same
  family states the tiles either side of its centred column as `top="wmpprop:plLeftCenter.top"`, and
  centring computes a coordinate the markup does not carry, so `WMPInitialLayoutResolver` — which
  reads the target's authored attribute — answered **0** and both tiles painted over the corner
  pieces. `WMPSceneBuilder.parseDimension` answers such a read from the target's **resolved frame**,
  or, when the layout walk has not reached it yet, from the coordinate its centring computes: the
  walk is in *paint order*, so a tile at `zIndex=6` routinely reads a centre piece at `zIndex=10`.
  **This only ever showed on a surface built without the script runtime**, because WMP answers the
  read from the live object model and a skin's own window does the same through the runtime — so the
  corpus render sweep is byte-identical across the change (552 of 553 images, the odd one being
  `Scooby-Doo_2`'s random picture) and the one caller it moves is the borrowed frame
  (`WMPHostedFrameTemplate`), where it was three white blocks on every hosted window. The
  counter-evidence is pinned beside it: a target that states its own coordinate is read at that
  coordinate.
- **A container collapsed to zero area clips its children away too — and only that one.**
  `WMPSceneBuilder` passes children `nil` for "no clip at all", and `WMPRect.intersection` also
  answers `nil` for an empty result, so a pane collapsed to zero height handed its children *no*
  clip. `Classic` sets `view.height = 359 - 183` for audio, its `stretch` video pane goes to 0, and
  the centred `wmlogo` inside it drew across the nav bar. A zero-area frame now hands down a
  zero-area rect. **The wider rule — any frame that misses its parent's clip — was tried first and
  rejected by the corpus sweep**: it also removed `Back to the Future Trilogy`'s "previous
  visualization" button, authored at `left="-25"` wholly outside its logo strip and mirroring the
  next button. **Whether WMP draws that button is unknown** — no WMP was available to check, and
  the wider rule is the consistent one (a child 1px inside is clipped to 1px, one 0px inside draws
  whole). Narrowed was kept because a wrong guess there costs a working control. A WMP screenshot
  of that skin's visualization window settles it. Narrowed, the sweep (stopped and
  `WMP_RENDER_HOST=playing`, 184 archives) moves `Classic/view-2` and nothing else in pixels;
  `Blinx/mainView` hosts two fewer text widgets that were already `visible=none`. The cursor-rect
  pass in `WMPMainView` treats a clip that misses a control as hidden, not unconfined.
  `WMPAlignmentTests.testAChildOfACollapsedStretchPaneIsClippedAway` pins it.
- **A hidden element still has a place, and the extent a binding gives it is not a baseline
  (W226).** Two more steps along the same read, both found by measuring `Compact`'s visualizer at
  two window sizes. **First: the walk returns on an invisible node before recording a geometry**, so
  `parseDimension` had nothing to answer a `wmpprop:` read from and fell through to the markup —
  which is the size the window was *born* at, not the size it has been dragged to. `Compact` sizes
  its vis pane with `<subview id="svVisual" height="wmpprop:video1.height">` and `video1` is
  `visible="false"` for the whole of audio playback, so stretching the window grew the pane's width
  and left its height at the authored 240. WMP lays hidden elements out and answers the read from
  its live object model; so does this, for a hidden node **some other node actually binds a
  coordinate off** (`geometryBindingTargets`) and no other — measured only, with no paint, no hit
  target, no widget, no children and no entry in the resolved or unresolved tallies. **Second: the
  alignment baseline must not read the resize back as if it were authored.** `ownAuthoredSize` takes
  the geometry overrides because W225's rule says a container a *handler* sized is a baseline — but
  `WMPScriptRuntime` writes an override for a script assignment *and* for its own re-evaluation of
  an authored expression or binding, and the second is only this canvas's answer echoed back. With
  the pane reading 462 on both sides of the subtraction, every child's delta was zero and the strip
  under the visualizer froze at its authored `top` while the pane grew around it.
  `WMPSceneBuilder.authoredDimension` takes an override only when `overrides.scriptAssignedGeometry`
  says a handler wrote it. `jscript:` attributes are untouched — the static resolver evaluates them
  at the current canvas, which is the number `parseDimension` already had. Corpus-wide the render
  sweep is byte-identical (706 invariant lines, 553 PNGs, the one differing being `Scooby-Doo_2`'s
  random picture again). Reported as "when you stretch the window the visualization does not follow
  the stretch"; `WMPAlignmentTests` pins all four halves, including the two counter-cases — a hidden
  node nobody binds to is still not measured, and a script-assigned extent is still a baseline.
- **A `windowed="true"` `<EFFECTS>` is a real child window: nothing the skin paints goes over it
  (W144).** This is the *other* answer to the occlusion question the entry below settles for the
  windowless case, and the two are opposite on purpose — which is why 106 corpus skins say
  `windowed="false"` and only 17 say `true` (18 nodes; absent on 52 nodes / 46 skins, and absent
  means windowless). A windowless surface is composited into the artwork at its own place in the
  paint order and the skin draws over it deliberately; a windowed one is an HWND in WMP and cannot
  be layered on at all. `WMPScene.windowedEffectsRects` is cleared out of the overlay raster after
  it is drawn. **Three near-misses are worth not repeating.** It is not z-order — `cerulean` is the
  counter-evidence and holds per-parent ordering down; it is not "drop the overlay", because the
  surface is transparent while idle *and* the artwork must still draw outside the rect; and it is
  not "make the surface opaque", because a stopped player draws no visualization and what belongs
  in the hole is whatever the skin painted **before** the effects node. `xsn_sports` retracts its
  settings drawers to a resting place 26px (`visView`) and 108px (`videoView`) inside the effects
  rect and relies on the surface to hide them; reported as the drawer's contents showing through the
  video window while shut. `WMPEffectsOcclusionTests` pins both sides.
- **An authored `JScript:` geometry expression re-applies only when its own value changes (W144).**
  It is re-evaluated every transaction — that is what makes `top="jscript:view.height-123"` follow a
  resize — and committing it unconditionally put it **ahead of the mutations**, so any transaction
  whose handlers did not touch the node snapped the node back to its authored place. **Any view with
  an `onTimer` therefore undid its own script within one tick**: `xsn_sports` slides its drawers with
  `visDrawer.moveTo(0, view.height-73, 400)` against `timerInterval="500"`, and half a second after
  every click the drawer was back where the markup put it. Reported as "it still does not open".
  Comparing against the value the expression last produced was the first form of this rule and it
  is **superseded by W159 below**: an expression never takes back an address the script has written,
  changed value or not.
  This is the same distinction `WMPScriptRuntime.assignedViewSize` already drew for the root: an
  expression that re-resolves is a layout reading the current size, not a fresh request. **A plain
  render sweep cannot see this class** — it renders one transaction per view, and base-vs-change came
  out identical either side of the fix. `WMP_RENDER_SETTLE` is the instrument.
- **A script assignment retires the authored expression for that address, and alignment is what
  carries the value forward (W159).** Two halves, and the second is not optional. `WMPScriptRuntime`
  keeps the geometry addresses a script wrote (with the **canvas each was written at**) and skips the
  authored `jscript:` expression for them — in `WMPScriptContext.resolveExpressions` too, or the
  dependants go on resolving against a value nothing draws. `WMPSceneBuilder` then treats such an
  address as a literal for `right`/`bottom`/`stretch` and re-anchors it by the growth **since the
  assignment**, never since the authored size. Reported on `NVIDIA`: `setModesMinWidth('playlist')`
  writes `mainModeMetadata.width = view.width-266` while the view is still 285 — the number is 19 —
  and resizes the view in the same handler, so `width="jscript:view.width-101"` answered 629 on the
  next transaction and took the property back; the bar drew 119 px past the window's right edge and
  the time readout on `jscript:mainModeMetadata.width-80` went off-window entirely. With the rule the
  bar is the script's 464 (19 + the 445 the view grew) and the digits sit where audio mode puts them.
  **Reach: 18 of 180 archives, 86 element/property pairs.** Both halves were found by corpus A/B, not
  by reasoning: retiring alone froze `xsn_sports`'s drawer floating in the middle of `visView`, and
  anchoring at the *authored* size instead of the assignment slid open 15 default-state panels
  (`Catwoman`'s video settings, the Alienware/ALX `videoView` family, `Scooby-Doo_2`'s info panel).
  The 13 views that legitimately change are the same defect being fixed — `Catwoman`'s `onLoadVid`
  calls `toggleVidDrawer('0')`, so its drawer is *meant* to be out. `WMPAlignmentTests` and
  `WMPScriptRuntimeTests` pin the two halves.
- **`onClose` is a view's last transaction, and it is where a `.wmz` saves its state (W144).** It had
  **no dispatch site at all**: `discardView` dropped the view's scope and its live elements and the
  handler never ran, so **373 `onClose` handlers across 133 of the 180 archives** were dead. What
  they do is persist — `xsn_sports` writes `visDrawerStatus` and its own view size through
  `theme.savePreference` and restores both in `onLoad`, branching on the `--` absent sentinel, so
  with nothing ever saved its settings drawer opened itself on every single launch and no window
  remembered its size. The transaction runs **before** `discardView`, because the handler needs the
  view's elements and the skin's globals, and it renders nothing: the window is already gone.
  **Quitting is a close too**, and `applicationWillTerminate` returns and the process exits, so the
  `Task` an ordinary close posts never runs — `flushCloseHandlersOnTermination` runs the same
  transaction for every open view and waits for it, which is safe only because nothing on the script
  path touches `MainActor`.
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
- **An element's own artwork is drawn at its own size, and the box it does not fill is left to
  whatever is under it (W122).** WMP never scales a `<BUTTON>`'s `image` to the authored frame, and
  a skin that swaps that image from script is written against exactly that: **563 script `.image`
  assignments across 51 of the 180 archives**, of which **23 paint a clock out of digit strips**
  (`drawSeekDigits` / `DrawTimeNormalView`) and **6 give the digit a frame wider than the digit**.
  The ALX/Alienware readout is four `<BUTTON>`s authored the width of a *ten-digit strip* —
  `time1.png` is 250x23 — each inside a 25 px `<SUBVIEW>` that clips it to the first cell, and
  `drawSeekDigits()` then assigns a single 25x23 `time1_<n>.gif` per tick. Scaling that to the 250 px
  frame drew one tenth of one digit blown up ten times: reported as "in all the alien type skins the
  numeric display is illegible". `WMPSceneBuilder` clamps the foreground image command to the
  artwork's natural size, anchored at the frame's top-left, so the smaller bitmap lands where the
  strip's first cell did and the parent's clip is unchanged. **Only the foreground image takes the
  rule** — `backgroundImage` still fills its frame, because a `stretch`-aligned subview grows with a
  resizable window and its background is what covers the delta (`LostPlanet`, in the counter-evidence
  table). **A default-state sweep cannot see the defect and can see the collateral**, which is what
  makes it worth running: the strip *is* the frame until a script swaps it, and `drawSeekDigits()`
  returns early on an empty playlist, so the 545-image corpus capture moved **16 images, none of them
  a clock** — every one an oversized bitmap that had been upscaled and is now crisp (`portals/mode2`,
  the five `US …` `videoUSM` logos, `tubeframe`, `Ice/mainView`), one nondeterministic
  (`Scooby-Doo_2`), and one that is now half-right and is the open row: `Ice/videoView` draws
  `Pl-xp.bmp` as a 196x44 button inside a subview that still stretches the *same* bitmap to 313x144,
  so the two no longer meet.
- **A `<VIDEO>` box shrinks the picture to fit by default and never enlarges it (W102).** The two
  fit flags are independent and neither means crop or fill: `shrinkToFit` governs the picture being
  *reduced*, `stretchToFit` its being *enlarged*, and `maintainAspectRatio` (default true) decides
  whether the two axes scale together. **`shrinkToFit` defaults to true and `stretchToFit` to
  false**, which is not symmetry for its own sake — it is what the corpus is authored against.
  **77 of the 97 sized `<VIDEO>` elements declare no `shrinkToFit` at all and 73 of those are boxes
  under 640x480** (`Heart_Butterfly` is 89x130, `Creed` 131x88, `Cablemusic` 341x215), and **not one
  archive anywhere authors `shrinkToFit="false"`** while 19 author `stretchToFit="true"` and one
  `"false"`. Defaulting the shrink flag off therefore drew every unattributed box at the stream's
  native pixel size, centred and clipped to the middle sliver of a 1080p frame — reported as "the
  video opens at full resolution instead of scaled to the window". The corresponding read defaults
  in `WMPObjectModel` are the same three values, because a skin that reads back a flag it never
  authored must be told what is actually on screen. **This is not `mediacenter.videoShrinkToFit`**,
  which is a different object with its own defaults in `reference/object-model.md`.
- **The picture is lent to the skin as a *child window*, and `isVideoOutputHosted` is our flag while
  being a child is AppKit's fact — they drift apart (W102).** A child window is the isolation that
  makes hosting work at all: VLCKit installs its own output view and sizes that view's *ancestors*,
  so moving `videoPlayerView` into the skin's tree runs the skin's content view away by tens of
  thousands of pixels, while `addChildWindow` keeps a separate layout tree glued to the skin. The
  trap is that the link can go without the flag changing, and `hostOutputWindow` re-parents only when
  `!isVideoOutputHosted`, so nothing puts it back. **Three symptoms that read as three bugs are this
  one cause**: the picture goes black while the audio plays and seeking still works (it fell *behind*
  the skin — a real child window cannot); it lags out of the window frame on a drag (the 10 Hz
  reposition trailing a tick behind); and switching apps fixes it (activation re-collects children).
  `WMPVideoSurface.update` re-asserts the relationship every tick and traces `video reparented` /
  `video reordered above parent` — **if those fire continuously rather than once per incident, the
  repair is masking a call site that keeps breaking the link, and that is the thing to fix.** Suspect
  anything that orders the parked window out: on macOS that drops its parent relationship.
- **Video readiness has two consumers and they need different truths (W124).** `WMPHostSnapshot.video`
  is the live drawable state: when VLC drops `hasVideoOut` or `videoSize` during a same-media vout
  rebuild, it must become empty so `WMPVideoSurface` detaches the child window and releases mouse
  capture. `WMPHostSnapshot.videoEvent` is the last valid state for `videostart`/`videoend` edges,
  latched by media identity and cleared by a media change or `didReachEndOfMedia`. Feeding the
  latched event state back through `video` kept the child window over the skin and made buttons look
  globally dead when the track panel had pointer capture. Test the split state: output teardown
  produces no `videoend`, the surface detaches, and a genuine media end still produces exactly one.
- **A video's natural end is not a manual Next press.** `WindowManager.videoTrackDidFinish`
  routes WMP completion to `AudioEngine.wmpVideoTrackDidFinish`, which shares the audio engine's
  natural-end repeat/shuffle/queue-exhaustion rules without running audio reporters or gapless
  promotion. Manual `next()` wraps unconditionally; using it at EOF looped a one-video playlist
  forever with repeat off. Keep the new callback gated to `.wmp`. Verified live on 2026-09-10 with
  Corona and a 6.29-second local video: EOF stopped playback, and a subsequent Play click replayed
  it and stopped again.
- **A paused film reports no time, and in `.wmz` mode that was the only thing refreshing the host
  (W102).** `videoDidUpdateTime` is driven by VLC's time-changed callback, so a pause silenced the
  whole host tick and the skin went on drawing *and hit-testing* a pause button. What that costs is
  not a stale glyph: the next click's `mousedown` triggers the rebuild that finally sees `paused`,
  the button under the pointer is swapped mid-gesture, and `WMPMainView.mouseUp`'s
  `result.activated == capturedTarget.stableID` guard drops the click — **the click is destroyed by
  the state change it triggered**, reported as "play then pause then play just breaks it".
  `videoDidChangePlaybackState` closes it, gated to the WMP family. **The general rule this leaves:
  any state a skin hit-tests against must be pushed when it changes, never sampled on the next
  rebuild** — a rebuild driven by the very gesture that needs the old geometry will always eat that
  gesture.
- **A text baseline may never sit higher than the face's own ascent (W114).** The rule was
  `max(fontSize, (height + fontSize) / 2)` measured from the box's bottom — fine while every
  `<TEXT>` had a generously tall authored box, and four pixels *above* the box once a text is sized
  by its own glyphs. `CTFontGetAscent` is the floor. It moves nothing that was already inside its
  box and 142 corpus images where text was drawing over the artwork above it.
- **A call that lands its endpoint completes in the same transaction, and a skin's sequence is
  chained from that completion (W55).** *Superseded in one direction by W194 above: under a frame
  clock the completion is raised when the tween ends instead, and everything below still describes
  the headless path and the mechanism both share.* `moveTo`/`alphaBlendTo` have applied their
  endpoint immediately since W38, so the step that follows was the missing half: `onEndMove` is 247 uses
  across 113 archives, `onEndAlphaBlend` 50 / 21, and **`onEndResize` is zero, so it is deliberately
  not implemented.** `WMPScriptContext.raiseCompletionHandlers` raises them before the geometry
  cascade, bounded and once per `(element, event)`. **The template Microsoft shipped is built out of
  this**: `toggleVidDrawer()` slides the drawer and `onEndMove="checkVidDrawer()"` is the only thing
  that shows or hides its contents, so without it 36 corpus views drew a drawer's controls stranded
  outside a drawer that had already slid shut — and seven views (the `US …` military family,
  `Secura`, `Stars and Stripes`) drew a closed shell with no player in it at all. **Landing this
  removes an accidental compensation, so budget for what it uncovers**: where a drawer fails to open
  for an unrelated reason, the user now sees an empty drawer rather than usable controls in the
  wrong place. `onDragEnd` is the input-side sibling, raised from `WMPMainView.mouseUp` for a
  captured slider, and it is one of the two places a seek commits — see W156 above for the other and
  for how the engine chooses between them. See `reference/object-model.md` § *Methods*, and
  `reference/harness.md` for why an image-only sweep cannot see any of it.
- **A `<TEXT>`'s own artwork is its glyphs, and a `<BUTTONGROUP>`'s is its mapping image.** Every
  other node falls back to the natural size of its `backgroundImage`; these two have none, and both
  were the largest starvation classes in the corpus. **1,441 `<TEXT>` nodes across 127 of the 179
  archives** resolved no size — 1,058 of them missing width *and* height — because WMP sizes a text
  from the face and the string and a skin therefore never states it: `Cablemusic`'s script lays out
  ten readouts with `txtShow.top/left/width/fontSize` and no `height`, so the whole
  show/clip/author/copyright block never drew and the report was "there is no track display". A
  width measured from the *current* value is WMP's own behaviour — the box grows with the string, an
  empty value is honestly zero-wide, and it starts drawing on the transaction that gives it one.
  **31 `<BUTTONGROUP>`s across 16 skins** resolved no size for the mirror reason: the group's normal
  state is the window's own background artwork, so the skin authors no `image` and no geometry at
  all, and with no frame the group registered no hit target — every control in it dead while the
  artwork beneath still drew the buttons. `Cablemusic`'s presets, stop, close, minimize, next and
  previous effect, shrink, bandwidth and all three drawer tabs are one such group each: "most
  buttons don't work". The mapping image is definitionally the group's own pixel grid.
- **An attribute authored with an empty value is not an attribute, and for geometry it never was
  one** (W241). `<attr>=""` is authored **970 times across 135 of the 182 measured archives**, and
  the engine's every "did the skin state this dimension?" test is `attribute(named:) == nil` — so a
  present-but-empty `height` closed the intrinsic-size gate that an *absent* `height` opens, and
  the node resolved no size and was never painted. `Beck` authors `height=""` on each of its ten
  `eq1`…`eq10` bands over a real `foregroundImage`, and its equalizer tray drew ten empty slots.
  Ask the statedness question through `WMPNode.statedAttribute(named:)`, never
  `attribute(named:)`, anywhere a missing attribute has an ambient default — 0 for an origin, the
  artwork's own size for an extent.
  **Three things this rule is not.** It is not a coercion of `""` to zero: a zero-height slider is
  as invisible as an unresolved one, so that closes the row and changes no pixel. It is not for
  strings, handlers or colours — `tooltip=""` (299 uses) and `value=""` (101) are authored absences
  that already behave correctly, and widening it there makes 970 the blast radius instead of the
  denominator. And it is not the resource path, which implements the rule for itself:
  `WMPArchive.resolve` returns nil for an empty path, so `backgroundImage=""` already falls through
  to the `foregroundImage` behind it. See `reference/harness.md` § *The empty-value class*.
- **A geometry value the grammar cannot read is unstated too, and for extents only** (W240). W241's
  rule one step out: `XBOX`'s `xLogo` authors `width="jsa:centerBox.width"` where the `<video>` two
  lines above it in the same container writes `jscript:` — a typo WMP cannot parse either, so WMP
  falls back to the ambient default and draws the logo at `x_logo.jpg`'s own size, while the gate
  here saw a *stated* width and drew nothing. `WMPInitialLayoutResolver.Resolution.unresolved`
  carries `interpretable:` and the parser's own failures come back `false`; a **dependency**
  failure — unknown object, cycle, depth, a reference whose target failed — stays `true`, because a
  script may still satisfy it and stamping a bitmap over one is the `corona`/`svVideo` regression.
  **Extents only, and that boundary is the point**: an origin has no content-derived default, so an
  unreadable `left` stays a rejection and `left="JScript:danger();"` is still refused rather than
  drawn at 0. `jsa:` is **not** a dialect to implement — answering a typo the way WMP answers it is
  not the same as matching it, exactly as with `scrollingAmmount`. **The row was ranked on
  `33 of 458` unresolved nodes carrying a bitmap and was really one node**: 13 of 16 name a bitmap
  that cannot resolve, two more clear their own artwork from script, and the 33 was an empty `bg=`
  field captured by a loose pattern. See `reference/harness.md` § *The residue is a size fallback*.
- **`STATUSTEXT` and `CURRENTPOSITIONTEXT` are text controls with native WMP values, not unknown
  tags.** Model them as text for intrinsic sizing and paint; synthesize the latter's value from
  `player.controls.currentPositionString`. WMP right-aligns an otherwise-unqualified
  `CURRENTPOSITIONTEXT`, because it is normally the trailing cell beside a scrolling title.
  Cerulean exposed both requirements: omitting the tag removed its clock, and left alignment made
  the clock touch the title.
- **An origin the markup never stated can still have been written by script, and asking the markup
  first meant it never was.** `left`/`top` default to 0 when unauthored — but the check was
  `attribute == nil ? 0 : resolve`, which short-circuited *before* `parseDimension` could look in
  the scene overrides. Size never had the bug, so a script-positioned element came out the right
  size in the wrong place: `Cablemusic`'s two drawers are seventeen station rows each, laid out
  entirely by `InitPrograms()` writing `pr<N>.top`/`.left`, and all thirty-four drew on top of one
  another in the corner of the drawer. Overrides first, then the markup, then the default.
- **WMP spells every transport control twice, and only one half of each pair was ever a kind.**
  `<…ELEMENT>` is a `BUTTONELEMENT` subtype — a colour region of a `BUTTONGROUP`'s mapping image —
  and `<…BUTTON>` is a `BUTTON` subtype with its own artwork and frame. `WMPElementKind` had
  `playElement` but no `playButton`, `pauseButton` but no `pauseElement`, and so on, so half the
  vocabulary fell to `.unknown`: **`PAUSEELEMENT` 80 uses / 69 skins, `PLAYBUTTON` 50 / 45,
  `PREVBUTTON` 50 / 45, `NEXTBUTTON` 49 / 44, `STOPBUTTON` 48 / 42, `MUTEBUTTON` 10 / 9,
  `REPEATBUTTON` 5 / 4.** An unknown kind still paints its `image` and is not interactive, so the
  button **drew and did nothing** and the pointer fell through to whatever overlapped it —
  `WMP_RENDER_CLICK` on `Cablemusic`'s play button answered `hit=ffw`. `MUTEELEMENT`,
  `REPEATELEMENT`, `SHUFFLEELEMENT` and `RETURNELEMENT` are zero in the corpus and are deliberately
  absent: a kind nothing authors is a phantom. The `*ELEMENT` half is `isNonLayout` — but keyed on
  **`mappingColor` under a `BUTTONGROUP`**, not on the kind and not on the attribute alone;
  `polygon` puts a `mappingColor` on a `<SUBVIEW>` with real geometry as a self-mask.
- **A `BUTTONGROUP`'s state artwork is a sheet the size of the whole group, and it is only ever
  painted through the group's mapping mask (W116).** `hoverImage`/`downImage` are the *entire*
  player redrawn with one control lit, and the mask cuts out the region the pointer is over. The
  normal `image` used to be **required** for any of that to happen, so a group that authors none —
  its normal state being the window's own background artwork — fell through to the generic
  single-image path and painted the whole sheet over the window. `Cablemusic`'s is a 593x600 bitmap
  with a dark green surround, so hovering any button in any of its six groups covered the entire
  player: reported as "when you mouse over the compact button there is a huge overlay". The normal
  artwork is now optional and only the mask is required; with no `image` there is nothing to draw
  *under* the lit region, which is correct, because what is under it is the window. **No corpus
  sweep can see this class** — a default-state capture never enters a hover or a down state (W73),
  and the 535-image sweep across this fix is byte-identical. `WMP_RENDER_HOVER` and
  `WMP_RENDER_CLICK` are what measure it.
- **A fix that makes dead code reachable is where a latent trap fires.** Sizing a `BUTTONGROUP` from
  its mapping image reached, for the first time on `Cablemusic`, a
  `Dictionary(uniqueKeysWithValues:)` over the group's `mappingColor`s — and that skin authors
  `bnpb6` and `bnpb7` both as `#00C0FF`, one preset too many for the eight regions its `map.gif`
  has. A dead control became a **crash on load**. WMP takes the first and draws it; so does this.
  **It fired twice**: the same row also made the unmasked state-sheet paint above reachable, and
  that one was invisible to every headless probe. Budget for both shapes whenever a row turns a
  whole class of nodes from unresolved into drawn.
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
- **An unanswerable `wmpprop:` is not the answer "false", and on `visible` that distinction is a
  whole control (W95).** A path can name a *host* property (`eq.enhancedAudio`) or an *element in
  the skin's own graph* (`plMode.visible`); 1,459 of the corpus's uses resolve to neither today, and
  the registry answered every one with a falsy empty string. The builder deletes a node whose
  `visible` override is false, so `WoW`'s `<PLAYLIST visible="wmpprop:plMode.visible">` — `plMode`
  being a name WMP's own UI owns and this skin never declares — had no paint command, no hosted
  widget and no rows, however many tracks were queued. Reported as "adding to the playlist does not
  work". The rule now has three cases and they were arrived at one sweep each:
  **a host root this engine does not implement stays falsy** (`xsn_sports` hangs its whole SRS WOW
  panel off `visible="wmpprop:eq.enhancedAudio"`, and showing the badge would claim a feature that
  does nothing); **an element the skin *does* declare is mirrored** by `WMPSceneBuilder`, one hop,
  which is what keeps `WoW`'s CD-rip bar hidden behind `wmpprop:playlist2.visible` (150 corpus uses
  of `visible="wmpprop:…"`); **an element it does not declare answers nothing**, leaving the markup's
  own value. Only `visible` declines to default — on every other property the empty string is the
  honest answer, and `wmpenabled:` still disables.
- **A panel opened with `theme.openView` is not the session's view (W96).** `apply` persisted
  `wmpSkinViewID` on every present, so quitting with a playlist open recorded the playlist; the
  covered view was not persisted, so the next launch restored a panel with no player and no route
  back to one. Reported as "the skin is empty and shows no player or skin windows", and it stranded
  any skin whose panels are `openView` rather than `currentViewID`. Only **the player's own
  presentation** writes the key — a simpler statement of the same rule the `openedViewStack.isEmpty`
  test was making, and one that stops being a special case once the panel has a window of its own.
  The panels themselves are persisted separately (`WMPViewFrameStore.openViews`, plus a per-view
  origin) and restored *before* the load transaction's host commands, so a dispatcher skin that
  re-opens its own panels from `theme.loadPreference` raises the restored window rather than opening
  a second one.
- **An `<EFFECTS>` rect is never shaped by this engine. The skin's own artwork occludes it, through
  plain z-order (W139).** The earlier form of this rule forbade turning "image overlap, z-order,
  alpha, or an artwork's transparent bounds into effects geometry" and named Cerulean and
  Plus! Professional as counter-evidence. **They are the clearest evidence for it, and the rule was
  backwards** — it is why an inscribed-circle clip was invented in place of the occlusion the markup
  already declares. What is still true is the half it was built on: do not *derive a mask* from a
  sibling bitmap, and `clippingColor` applies to a `clippingImage` and not to arbitrary nearby art.
  What was wrong is that z-order is not a derivation at all; it is what the markup says.

  Cerulean, measured from the archive: `face.bmp` has a magenta (`#FF00FF`) hole of 4,264 px over
  x 133..205, y 35..107 — a 73px circle against an ideal 4,185 — and the subview that draws it keys
  that colour out. Inside it, `<effects zIndex="-1" width="103" height="75">` and
  `<button id="bEye" zIndex="-2">`. **A negative `zIndex` means behind the subview's own
  `backgroundImage`.** Back to front: the eye disc, the visualizer filling its full 103×75 rect, then
  `face.bmp` with a hole in it — which is why the brass bezel and all eight rivets survive.
  Plus! Professional is the same mechanism with a tilted oval (`vis_mask_w.png` inside
  `<subview id="visMask" clippingColor="#ff00ff">`). **32 `<EFFECTS>` across 30 skins author a
  negative zIndex**, and no per-skin code renders any of them.

  How it is hosted: **a node's negative-`zIndex` children are walked before it emits its own paints**
  — DFS order cannot express "behind the parent's background" on its own, and getting this wrong is
  what drew Cerulean's bars across the whole face on the first attempt. `WMPWidget.commandSplitIndex`
  then records the index into `WMPScene.commands` the walk had reached when the widget's node was
  visited, `WMPRenderer` rasterizes the scene as two images
  either side of it, and `WMPMainView` hosts the effects surface between them —
  `WMPEffectsSurfaceView` → the "above" overlay `NSImageView` → the interactive widgets, re-enforced
  on every `synchronizeWidgetViews` pass because a plain `addSubview` goes to absolute top. **The
  split is an index and not a zIndex threshold**: `WMPSceneBuilder.walk` sorts only siblings, so
  `commands` is DFS order and a `zIndex = -5` node in one subtree can legitimately follow a
  `zIndex = 10` node in another. `WMPImageStore.clippingMask(for:keyedOut:)` and `WMPColorKey` then
  apply to the overlay for free — no new masking code exists anywhere for this.

  **The rect's own background is the one thing the split steps past.** A backdrop declared *on* the
  `<EFFECTS>` node — `backgroundColor="#000000"`, or a `backgroundImage` — is what WMP shows behind
  the visualizer while nothing plays, not artwork over it; with the split taken at the node's visit
  it landed in the overlay and was repainted over the hosted surface every frame, so the rect was a
  solid block for the whole of its skin. Reported against `New Super Mario Bros`, whose viz window
  drew its frame, its buttons and a black hole where the visualizer belongs. Decoded scan of the 178
  readable archives: **6 author an opaque `backgroundColor`** (`New Super Mario Bros`, `Gorillaz`,
  `Primitive`, `Tomb Raider 2`, `MSN`, `robbie`) and **8 a `backgroundImage`** (`XBOX`, both `Xbox`
  official releases, `Ice`, `WWC`, `The Unit`/`TheUnit`, `The_Sentinel_v.1.0`). `WMPSceneBuilder`
  patches `commandSplitIndex` forward once those two emits are done and nothing else — a foreground
  image on the node, its siblings, and the parent's keyed artwork stay in the overlay, so Cerulean,
  which authors no background on its rect at all, keeps the index it always had.

  **Nothing headless can see it.** The render dump flattens both rasters in the same order, so its
  PNG is identical either way, and `WMP_RENDER_APPKIT`'s `differing=` is 0 for *every* skin's
  `<EFFECTS>` because the surface draws nothing without live audio — `WMP_RENDER_HOST=playing` seeds
  a playing snapshot, not a signal. The instrument is the running app with `NULLPLAYER_PLAY` and a
  `screencapture -l <windowid>` of the skin's own visualization window.

  **A skin with no occluding artwork fills its authored rect exactly**: full `width × height`, a
  transparent background, no shape fitting and no aspect letterboxing. Of the 107 `<EFFECTS>` rects
  with numeric dimensions **19 are square, 83 wider than tall and 5 taller**, so a centred `min(w,h)`
  square covered a median 75% of the authored rect and as little as 17% (`Alpine7618_v09`, 150×26),
  and the inscribed circle took ~21% more again.
- **A zero geometry override is a value, not an absence.** Every skin with a store-thumbnail
  `previewView` collapses it in `onLoad` — `view.width = 0; view.height = 0; view.backgroundImage =
  ""; theme.currentViewID = "controlView"` — and Microsoft's own `auto.js` in `Official_Xbox_XP`
  does it with a comment saying so. Discarding a `0` override as "not positive" left 34 corpus
  skins showing a static splash bitmap where the skin had asked for its player.
- **A node draws the artwork a script last gave it, not the one its markup declares.** Images were
  the one property class the script-override path skipped, and `Alienware Invader` — whose whole
  player is behind a 568-frame intro of `mainBack.backgroundImage = "png24/intro_anim_f<N>.png"` —
  drew nothing at all because of it (W75). An override is an authored path string and resolves under
  the same provider rules as markup; one the skin does not contain warns and leaves the authored
  artwork in place; `""` clears the property the way an absent attribute does. The rules and the
  traps are in `reference/object-model.md` § *What a property read answers, and who wins*.
- `WMPSceneBuilder` resolves literal geometry plus the bounded static initial-layout grammar in
  `WMPInitialLayoutExpression`: finite numbers, parentheses, arithmetic, and geometry reads from
  deterministic IDs. `wmpprop:` is accepted only as an alias for that same geometry grammar.
  Calls, assignments, statements, script globals, ambiguous/unknown IDs, cycles, and excessive
  dependency depth stay unresolved *for the scene builder*, which never executes skin code and never
  invents fallback geometry. The general path is the live context in `WMPScriptRuntime`, whose
  resolved values arrive as scene overrides; the static grammar remains the fast, script-free
  evaluator the builder uses before any transaction has run.
- Scene coordinates remain top-left throughout layout, clipping, dirty bounds, hit metadata, and
  paint commands. Core Graphics conversion happens once in `WMPRenderer`; images and text each use
  an explicit counter-transform so pixels and glyphs remain upright.
- The immutable scene owns no `CGImage` or cache state. `WMPImageStore` performs bounded ImageIO
  metadata/decode off-main, supports BMP/GIF/JPEG/PNG, and uses a byte-bounded LRU keyed by canonical
  resource path plus color key.
- **ImageIO is stricter about BMP than Windows is, so a `.bmp` it refuses falls back to
  `WMPBitmapDecoder`** — never to a failure the user sees as a blank skin. Nine of the corpus's
  3,687 bitmaps are rejected by ImageIO alone: eight set `biClrImportant` while `biClrUsed` is zero
  (Windows reads the palette size from `biClrUsed` and treats the other as advisory), and one is a
  BI_RLE8 stream that walks clean and is refused anyway. The fallback runs *only* after ImageIO has
  failed, under the same dimension/pixel/byte bounds, applied before it allocates — an oversized
  bitmap still fails `WMP0034`. Do not "fix" such a file by patching its header, and do not relax a
  limit to admit one.
- **A mapping mask is authored top-left, and the render CTM is y-flipped, so clipping through one
  needs the same counter-flip `drawImage` applies.** `WMPRenderer.clip(to:mask:context:)` owns that;
  it undoes the CTM by hand rather than with `restoreGState`, which would discard the clip too. A
  mask fixture split left/right cannot see this class of bug — split it top/bottom.
- **A node keys out every colour it declares, not one.** `transparencyColor` and `clippingColor` are
  both keys — the second is the colour WMP cuts out of a subview's own artwork to shape it — and a
  subview routinely carries both with *different* values (`Alpine7618_v09` keys `#FF00FF` and
  `#FF0033`). 103 of the 180 archives author clipping attributes, so an engine honouring one key per
  image paints the other as a flat slab over most of the window. `WMPSceneImage.colorKeys` is
  therefore a list, in authored order, and the image-store cache key contains all of it. PNG, GIF
  and BMP color keys compare exact un-premultiplied RGB; JPEG keys allow the bounded 64-value
  compression fringe per channel because lossy decoding turns authored `#FF00FF` into a
  blue-channel ramp (W125, Plus! Professional). Preserve the source alpha of every non-matching
  pixel.
- **A container's `backgroundColor` fill and its `backgroundImage` are one layer, and the
  container's keys apply to the composite (W199).** Painting the fill as a bare rectangle under a
  keyed image is two layers, and it fills in every hole the image cuts — the `clippingColor` matte
  *outside* the silhouette, so the window is a slab rather than a shape, and the
  `transparencyColor` hole *inside* it, which on this idiom is **always the visualizer's**.
  `WMPSceneBuilder.backgroundFillMask` emits the fill inside a mask of the node's own artwork keyed
  by both, and `backgroundColor="none"` — 639 corpus containers — already got this by having no
  fill at all. **Both keys, unlike `groundShape`, and the difference is deliberate**: that one
  answers *where the window is* and must never read a hole as a matte (W174, `Plus! BubbleSkin`);
  this one answers *where the composite is opaque*, and there a hole is as transparent as the matte
  around it. The population is **10 nodes in 9 archives** (`Asimov_Radio`, `Nautical`, `anime`,
  `aoe`, `bluegrid`, `cerulean`, `claw`, `gadget`, `pharaoh` twice) and **five of them hang an
  `<EFFECTS zIndex="-1">` under the hole** — `aoe`, `bluegrid`, `claw`, `gadget`, `pharaoh`, each
  rect within 2 px of the hole's own bounds — so all five drew an opaque rectangle with a live,
  hosted, invisible visualizer inside it. `pharaoh` states the control in its own archive: `vRos`
  is the same markup with `backgroundColor="none"` and it clipped correctly throughout.
  **This replaces a one-skin exemption whose stated reason was the opposite of the measurement.**
  `isCeruleanFace` matched `cerulean.wms` + `face.bmp` + `#9AACDB` and suppressed that fill alone,
  on the claim that a corpus sweep had shown the general rule "erased intentional interiors in
  Claw, Gadget, and Pharaoh". Those interiors are the visualizer holes. The general rule moves
  exactly five images, each by exactly its own skin's matte count, and cerulean's PNG is
  byte-identical across it. **The guards are `clipMask`'s and they keep their counter-evidence** —
  untiled, and authored at the node's own size, so `Gorillaz` is untouched; `isShapeMask` is
  deliberately *not* required, for `groundShape`'s reason, so `YIL!OMA2K` is not in the population
  at all. See `reference/skins/pharaoh.md`.
- **A node that declares no key at all still gets one: magenta, whatever alpha the sprite carries.**
  WMP's implicit transparency colour (W78, W78a). The corpus is authored against it — 4,979 of its
  6,076 `transparencyColor` declarations (82%, 142 skins) are `#ff00ff`, `Halo 2` keys three
  siblings by hand and leaves `m_trans_no.png` to the default, and `Main_Street` authors one key in
  the whole file. The scene builder decides (`WMPSceneImage.implicitColorKey`, set only when the
  node declares nothing) and the image store applies it. **The sprite's own alpha channel does not
  veto it, and W78 shipped believing it did.** The reasoning was that a PNG or GIF which authored
  transparency has already said what is see-through; the corpus says the alpha channel is an export
  format instead. `scripts/wmp_implicit_key.py --alpha only` measures the complement — 76 references
  across 21 skins and 62 sprites — and **11 of those nodes carry two states of the same button, one
  exported without an alpha channel and one with, holding pixel-for-pixel identical magenta**
  (`Half-Life_2` `m_pause_no.png`/`m_pause_hov.gif`, both 1,394; `Harry_Potter…`
  `bottomgroup_no.png`/`bottomgroup_hover.gif`, both 5,866). Under the veto the normal state keyed
  and the hover state did not, so the button turned magenta under the pointer. **Never pass the
  implicit key on a mapping image, position map or clipping mask**: they are read for their colours,
  and keying one deletes a `#FF00FF` mapping colour from its own map. Measure the class with
  `scripts/wmp_implicit_key.py` before touching the rule; the default removed 315,157 magenta pixels
  across 87 corpus views, and dropping the alpha veto took the corpus residual from 7,253 px across
  15 views to 878 across 2, changing 13 PNGs and nothing else.
- The opt-in render dump writes one untracked PNG per view plus a JSON report. Corpus paths and
  output directories are local inputs/artifacts and must never be staged.

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
  is gone. How it works is *NullPlayer's own windows beside a skin* below.

## NullPlayer's own windows beside a skin

Landed 2026-09-09. **This section is the *colour and content* half; the *shape* half — which donor
view is borrowed, how it is drawn and what is subtracted from it — is § *Every NullPlayer window in
WMP mode is the skin's or is themed* above, and that section is the authority. Read it first.** What
follows was written when colour was all a `.wmz` could lend, and the palette work below is unchanged
by W207/W209: a window still takes the palette, and takes a borrowed frame *as well* where the skin
lends one.

Four things carry the palette, and the last two were found by looking at the screen rather than by
reasoning.

- **The seam is family-neutral, and it is the one `.wal` already had.** `SkinnedSurfaceStyle` /
  `SkinnedSurfaceChrome` (in `App/Skinning/`, formerly `WinampModernSurfaceStyle`/`Chrome`) are built
  from `SkinnedSurfaceRoles` — seven colours and nothing else — so neither engine knows the other's
  markup. `.wal` derives the roles from a `WasabiPalette`, `.wmz` from `WMPSurfacePalette`, and both
  reach the views through **one** property, `WindowManager.hostedSurfaceStyle`, a `switch` on the
  controller family. The `.wal` names survive as typealiases, so no `.wal` call site moved.
- **The palette is declaration-first and then measured off the artwork.**
  `PLAYLIST` (`backgroundColor`, `foregroundColor`, `itemPlayingColor`,
  `itemPlayingBackgroundColor`) → `VIEW`/`SUBVIEW` background plus `TEXT` foreground → the **dominant
  opaque colour of the presented view's own rendered bitmap** → an app-authored WMP-neutral pair.
  The sampling step is not a nicety: measured over the 177 readable archives on 2026-09-11, **165
  declare a background colour and 171 a foreground** now that the parser accepts the SDK's named
  colours as well as `#RRGGBB`. Counts per role are in `WMPSurfacePalette`'s own doc
  comment, next to the scan that produced them.
- **Every foreground goes through the legibility guard, against the ground it is actually drawn on.**
  `SkinnedSurfaceStyle.legible`, the same WCAG 3.0:1 bar `.wal` uses — but it is load-bearing here in
  a way it is not there, because a `.wms` declares colour per *element*: the ground can come from a
  `VIEW` and the lettering from a `PLAYLIST` three levels down that was never drawn on it, and a
  sampled ground is one no author ever chose text against. Guard each role separately: the playing
  row's text sits on the window background until the row is *also* selected, the selection's text on
  the highlight. Guarding both against one background leaves an unreadable current track, which is
  what the reporter saw.
- **A skin-owned `PLAYLIST` is an AppKit overlay, so it needs the WMP palette directly.**
  `WMPMainWindowController` sets `WMPMainView.surfaceStyle` before installing native widgets and
  `WMPPlaylistSurfaceView` uses it for its ground, selected row, current row, and all three text
  roles. Leaving its historical hard-coded black/white colours produced a foreign black rectangle
  in Cerulean even though `ITEMSPLAYLIST backgroundColor="#9AACDB"` was declared. Do not route this
  through Classic or Winamp Modern state; it is WMP-owned surface state.
- **The playlist highlight is ours, not the skin's, and it follows the playing track.** No `.wmz`
  draws its own rows: `WMPMainView` substitutes `WMPPlaylistSurfaceView` for the skin's `PLAYLIST`
  element and the skin contributes only the palette above, so one row renderer serves all 170
  archives that declare one — a defect here is never one skin's. `WMPPlaylistSurfaceView` carries two
  distinct marks: the highlight bar is `selectedIndex` (the user's selection) and the `▶` prefix plus
  `currentText` colour is `snapshot.playlistIndex` (the playing track). Seeding `selectedIndex` from
  `playlistIndex` once, at first update, left the bar parked on row 1 for the whole session while the
  marker walked down on its own — reported 2026-09-16 against `nvidia`, but visible in every skin.
  `update(_:)` now re-homes the highlight whenever `playlistIndex` changes (a click or an arrow key
  still moves it; the next track change takes it back, as WMP's own playlist does) and
  `scrollSelectionIntoView()` pulls `firstVisibleIndex` the minimum distance to keep that row on
  screen, so a playing track past the visible rows no longer scrolls away. This surface has no
  `NSScrollView` — `firstVisibleIndex` and the wheel handler are the whole of its scrolling.
- **Scrolling to the selection is an event, not a state, and a host refresh is not one (W246).**
  `scrollSelectionIntoView()` does not merely *scroll*: it clamps `firstVisibleIndex` into
  `selected - visibleRows + 1 ... selected`. Calling it from `update(_:)` — which a host refresh
  enters ~12 times a second whether or not anything moved — therefore pinned the list to the
  playing track permanently: a wheel gesture moved it and the next refresh put it back within
  ~85 ms. Reported live 2026-09-20 on `Xbox Live Skin` as *"a large playlist cannot be scrolled
  properly"*, and it was not a rate defect but a total one — with a 200-row playlist, **70 wheel
  events down reached row 19 and stopped and 40 back up reached row 2 and stopped**, because the
  playing row was pinned first to the top and then to the bottom of an 11-row window. Rows 20-200
  could not be reached at all. A refresh now runs `clampScroll()` alone (the half that keeps the
  position inside the list, which is what a shrinking playlist still needs); a **track change** and
  a **keystroke** are what scroll. The wheel also read only the *sign* of `scrollingDeltaY`, so a
  trackpad flick carrying hundreds of points moved one row: precise deltas now accumulate in points
  with a fractional remainder kept, line deltas move a row each and carry the system's own
  acceleration. **This is one view shared by 174 of the 182 measured archives** — 161 declare
  `PLAYLIST`, 13 declare `ITEMSPLAYLIST` and none of those 13 declares a `PLAYLIST` beside it
  (`scripts/wmp_markup_census.sh`, 2026-09-20) — so it was every skin's playlist, not one skin's.
  `WMPPlaylistScrollTests` holds all of it down; six of its ten cases fail against the old code and
  the other four are the invariants the fix deliberately keeps. **What is still missing is a
  scrollbar**: the corpus authors no thumb of its own against a hosted `<PLAYLIST>` and this
  surface offers none, so there is no page scroll and no drag-to-position — and the `columns`
  attribute (`Title;Artist;Album;Type;Length` on `Xbox Live Skin`) is still drawn as title and
  artist. Neither was the report.
- **A `.wmz` main window's width is not a zoom.** `playlistChromeScale` is
  `mainWindow.width / Skin.baseMainSize.width` — true of a *classic* player, whose 275px grid means
  its width is the size the user chose. A `.wmz` main window is the skin's own canvas: Corona's is
  596px, so our playlist drew its title and every row at 2.2x and the reporter's words were "the
  windows and title fonts are huge". It now falls back to the app's own scale in WMP mode, and
  `PlaylistView.scaleFactor` and the playlist's snapped default width route through that same
  property so the three cannot drift apart.

### Ask what the skin provides before opening a window of your own

**The corpus declares six surfaces and this engine hosts two.** Measured 2026-09-09 over the 179
archives and their 595 views — `views` counts views declaring the surface, `own view` counts skins
that put it somewhere other than the view they open on:

| Surface | views | skins | own view | Hosted |
|---|---:|---:|---:|---|
| `<VIDEO>` / `<WMPVIDEO>` | 268 | 170 | 165 | no (W9 removed the opaque placeholder; W102 is the row) |
| `<EFFECTS>` / `<WMPEFFECTS>` | 178 | 171 | 144 | yes — this player's own visuals in the authored rect (W101) |
| `<PLAYLIST>` family | 175 | 170 | 162 | yes |
| `<EQUALIZERSETTINGS>` | 170 | 163 | 147 | yes — the skin's own bound sliders are the equaliser |
| `<VIDEOSETTINGS>` | 94 | 94 | 93 | no (W103) |
| `<NETWORK>` | 6 | 4 | 4 | object-only, and correctly so (W104) |

**`WMPSkinSurface` models the playlist and the equaliser, and its doc comment used to claim there
was nothing else to model.** There is: the visualizer and the video window are surfaces this app has
its own window for and 170 skins declare themselves, so the menu toggles for those open ours over
the skin's own — the same defect W93 opened for the playlist. **Adding a routing case before the
surface is hosted trades a duplicate window for an empty drawer**, which is why the routing row
(W105) is ranked behind the hosting rows and not with them. W101 has landed, so `.visualization` is
the case that may now be added; `.video` still waits on W102.

**A `.wmz` also authors windows this player has no content for at all**, and they are not defects:
`infoView` (45 `openView` calls across the corpus) is the skin's own about/links/gallery panel,
`contentView` (24) a promotional content viewer, `vidRemoteView`/`remoteView` a floating remote, and
`previewView` (16 skins), `mediaSwitcherView` (21) and `versionView`/`upgradeView` are opened by the
*host*, not the user — a skin-chooser thumbnail, a media-type switch, and a "you need a newer
player" notice. `controlView` (24 skins) is the windowless dispatcher described above. None of these
wants NullPlayer content mapped into it; leave them to the skin.

**171 of the 180 corpus skins declare a playlist and 164 an equaliser** (164 declare both), so for
those two surfaces NullPlayer's window is the *fallback*, not the default — opening it
unconditionally puts a second, differently-styled playlist over nearly every skin in the corpus.
`WMPSkinSurfaces` reads what the skin declares and `WindowManager.routeWMPSkinSurface` takes the
toggle first, exactly as `routeWinampModernSurface` does for `.wal`. Three shapes, and routing has to
answer all three — the corpus splits almost evenly between the first two (87 / 84):

| The skin declares it… | What the toggle does |
|---|---|
| in the view on screen (Corona's drawer) | nothing opens; the menu item is checked and inert, because the thing it names is already there |
| in another view (WoW's `plView`) | opens that view, the way the skin's own button does through `theme.openView` |
| nowhere (9 skins for playlist, 16 for EQ) | NullPlayer's window opens, in the palette chrome above |

**Match on the authored tag, not only on `WMPElementKind`.** `ITEMSPLAYLIST` is a playlist the object
model does not model yet — Corona's drawer is one — so a kind-only test reports that skin as owning
no playlist and opens ours on top of it. What decides this routing is what the skin *declares*, not
how much of it this engine hosts today.

The restore path passes `switchingViews: false`: a saved session must never move the user to a
different view at launch.

### Window placement and recovery

**`App/WindowPlacement.swift` is the single definition of "on screen" — the window's top-left corner
is on some screen — and `.wmz` uses it. Do not re-derive it locally.** A `.wmz` window is borderless:
it has no title bar, and most skins make it unmovable by its background, so a window that lands past
an edge cannot be dragged back. Every other family can be recovered by hand; this one cannot, which
is why the rules below are contracts rather than preferences.

| Moment | Seam | `.wmz` |
|---|---|---|
| A skin's own view opens | `WMPViewWindowMaterializer.place` | authored `openViewRelative` offset or the stored top-left, else `WindowManager.tiledOrigin`, then `rescuedOrigin` as the never-`nil` backstop. Placed **once**, so a window the user moved is never yanked back |
| One of NullPlayer's own windows opens | `WindowManager.positionSubWindow` | the same `tiledOrigin` → `rescuedOrigin` pair, sharing the `.wal` branch |
| Snap To Default | `WindowManager.snapWMPToDefaultPositions` | the player re-centred, then one `WinampModernTiler` walked over every window, then an unconditional reachability pass |
| A resize | per-family | top-left anchored, so growth cannot strand the reachable corner |
| A display change, a UI Size change, a skin load | `WindowManager.ensureAllWindowsOnScreen` | run, gated `appliesPlacementRecovery` (W217 G3) |
| A restore onto a smaller desktop | `AppStateManager.correctedRestoredFrames` | run, same gate — one offset for the whole session, and the corrected `main` is what the player is restored to (W217 G2) |
| The player's own restored frame | `WMPMainWindowController.restoreFrame` | no rule of its own: it keeps the top-left it is handed, which is the corrected one (W217 G1) |

**The recovery gate is `WindowManager.appliesPlacementRecovery`, never `appliesWinampModernPlacement`.**
The second one stays what it says — the `.wal` *arrangement* — and the two are not interchangeable.
A seam about getting a window back on screen takes the first; a seam about how `.wal` lays its
windows out takes the second. `.wmz` is in the first and out of the second, and
`WMPPlacementRecoveryTests` pins exactly that, because widening the wrong one would hand `.wmz`
`.wal` layout behaviour it must not have.

**Classic and Original stay out of both, and that exclusion is the load-bearing part.** B56 is the
record of what happens when these corrections reach a family whose window positions people have laid
their desktops out around. Every site switched for W217 G2/G3 was switched to a gate that still
excludes them, and the one unconditional edit — the sweep's child-window skip — lives inside a
function they never enter.

**The hosted video output is a child window and the sweep skips it.** `WMPVideoSurface` glues it over
the skin's `<VIDEO>` box with `addChildWindow`, and it is in `managedWindowRecords`, so the sweep
walks it. AppKit carries a child with its parent: rescuing it alone displaces it off the box, and if
the parent is rescued afterwards it moves twice. `.wal` had the same latent defect and the skip fixes
both.

**`positionSubWindow` and Snap To Default both branched on `.winampModern` alone until W217, and
`.wmz` fell through to the Classic stack.** That stack opens each window flush under the lowest one
already open and clamps nothing, because in Classic a window parked past an edge is a placement the
user chose rather than damage to repair. Measured live on `Halo 2` over an 1800x1130 visible frame
with ten windows open: Cava straddled the bottom edge, the Audio Analyzer opened entirely below it
and Flow 200pt further down again — three windows gone, with no route home and Snap To Default
recentring the player and whichever unthemed fallback windows happened to exist. Both now take the
tiling branch, whose every slot `WinampModernTiler.nextSlot` clamps onto the visible frame on both
axes.

**Snap To Default walks one tiler, not `tiledOrigin` per window.** `tiledOrigin(for:avoiding:)`
builds a *fresh* tiler each call and returns the first slot clear of an occupancy set: that is how a
window opened **after** an arrangement joins one, and it is the wrong instrument for laying out a
whole session — it re-derives every column from the current window's own width, and late windows
pile onto each other (measured: four windows on one slot). A shared cursor is what makes the result
an arrangement. `WinampModernMainWindowController.arrangeWindows` is the recipe; the `.wmz` routine
is that recipe with the player re-centred first.

**A row here names the seam an audit found; the seam the *user* hits may be a different one in the
same family.** W217's G4 was written against Snap To Default, and the defect reported from the
running app was `positionSubWindow` — four lines away, never audited, and no amount of reading found
it. The app was launched, ten windows were opened and their frames were read back. **Measure the
moment the user described, not only the seam the row names.**

**The `.wmp` case in `fallbackMainSize` is dead** — the branch above it returns first — and is kept
only for exhaustiveness. `ui-guide` § *Off-Screen Window Recovery* names all four families and says
which of them the sweep reaches.

**`restoreWindowPositions` (`WindowManager.swift`) has no callers, in any family.** It was named as
the one recovery seam still `.wal`-only and as the right place to look when G1 was taken up; taking
G1 up found that nothing in `Sources` or `Tests` invokes it. It is dead code that re-applies raw
`UserDefaults` frames, and its `.wal`-only gate is therefore not a recovery gap any user can reach.
It was left untouched rather than have its gate widened for a path that never runs — **check that
before reviving it**, because in `.wmz` re-applying a raw saved rect would run behind the session
correction and undo it.

**The contract is that one press is enough and a second press is a no-op.** Verify it that way:
`diff` the window list across two presses, do not judge it by eye.

**Verify a placement change live, and measure the frames** — `WMP_PLACE_TRACE=1`, `Halo 2` as the
load case (four panels from `onLoadSkin` plus `mainView`) and `Corona` as the control; read the
frames back through `app-control`'s `winhelper windows` rather than off a screenshot. A frame outside
every screen is `rescuedOrigin` failing. Two legs cannot be exercised by hand and need the unit
tests (`Tests/NullPlayerAppTests/WMPSnapToDefaultTests.swift`): a genuinely stranded window — a
`.wmz` window is not movable by its background and macOS clamps a drag at the screen edge, so one
cannot be produced with the mouse — and a window taller than the display.

**The recovery half's pure geometry is `Tests/NullPlayerAppTests/WMPPlacementRecoveryTests.swift`**:
the gate in all four families, the docked cluster that comes back touching rather than overlapping,
the AppKit contract the child-window skip rests on, and G1's pair — the controller keeping the frame
it is handed, and the seam above still rescuing that same frame, so a regression in either is
distinguishable from a regression in both. **G1's live leg is outstanding**: unlike G2, G3 and G4 it
was closed on the unit pair alone, so a restore onto a smaller desktop, an unplugged display and a
resolution change have not been driven against it. It is the first thing to run if a `.wmz` window
comes back unreachable. Its live half — an unplugged display, a
resolution change, a restore onto a smaller desktop — has no headless instrument and was verified by
driving the app.

### A skin may not size a window from the decoder, and no `.wmz` window is a dead end

**Three rules, and the live defect needed all three.** The first attempt shipped with only the
second and the reporter's answer was *"the window is still too large … it should not open full
screen"*:

1. **A view size computed from the decoder is refused, and the view keeps its own canvas** —
   `WMPVideoPresentation.isMediaDrivenViewSize`. The picture is fitted into the authored box, which
   is what this engine has always done with the `corona`/`Classic` shell formula; that refusal now
   covers the zoom formula too.
2. **Whatever size is left is fitted into the display's *usable* area** — `WMPSize.fitted(within:)`,
   applied in the same transaction clamp that enforces the view's own `minWidth`/`maxWidth` (W99).
   A backstop, not the answer: a window the size of the whole desktop is still the wrong window.
3. **A size an earlier session filed away is not handed back if it fills or exceeds that area** —
   `WMPMainWindowController.restorableViewSize`. `WMPViewFrameStore` keeps whatever the window came
   to rest at, so the defect outlived its own fix: the view stopped *growing* and went on *opening*
   at 1800x1130 every launch. **A fix to a size a skin computes is not a fix until the sizes it
   already wrote are dealt with.**

The corpus sizes its video view from the *decoder*:
`view.width = player.currentMedia.imageSourceWidth * (zoom/100) + <shell>` is
`Combat_Flight_Simulator_3`'s `SnapToVideo()` and 80 other archives author the same shape, against a
2002 idea of how big a clip gets. Seed a 2560x1440 source and **83 views across 80 archives** ask
for a window around 2600x1600 — `Plus! SlimLine/perfectVSkin` for 5720x3480 — against **zero** views
over 1440x810 with no video playing. Reported 2026-09-19 as *"a massive window with no right click
context controls"* on a 2560x1440 `.mp4`. Three things to keep straight:

- **Recognising the zoom formula needs no authored video box, and sometimes no authored view size
  either.** A `<VIDEO>` sized `width="jscript:centerBox.width"` off a sibling has no literal box, and
  `Official_Xbox` authors the *view* as `width="player.currentMedia.imageSourceWidth+91"` — its
  `minWidth` is the only number in the markup. Requiring either left 31 archives unrecognised, and
  a skin that is only clamped is a skin that opens full screen.
- **What separates the zoom formula from ordinary layout is that the picture is most of the
  window.** `zoom × source` is ≥ 85 % of the assignment on both axes for every archive that authors
  it (96–99 % for `Combat_Flight_Simulator_3` and `Official_Xbox`); without that bound a drawer
  growing 300x200 → 400x260 beside a 320x240 clip matches `zoom = 0.5` and the skin's own drawer
  would be refused as a decoder resize.
- **The ceiling is the visible frame, not the resolution** (`WMPMainWindowController.usableScreenSize`).
  Clamped to the full frame the window's bottom edge sits under the Dock, which is exactly where
  this corpus draws its video drawer, its zoom and its resize grip. `event.screenWidth` keeps
  answering the *resolution* — that is what WMP means by it and what `Compact.wmz` divides by.
- **The clamped number has to reach the overrides, not only `viewSize`.** The builder re-applies the
  view's own floor from the markup and has no rule of its own for the display, so leaving the raw
  assignment in `overrides.geometry` builds the scene at the size the script asked for while the
  window and every `jscript:view.width` carry the clamped one — W213's scene/window disagreement.
- **`isMediaDrivenViewSize` is tested on the *raw* assignment, before the clamp.** It recognises a
  size by its formula, and a clamped number is not that formula any more: testing the clamped one
  stopped `corona`, `Classic`, `9SeriesDefault` and `Compact` being recognised at all, and the
  engine then *kept* an assignment it exists to discard — all four grew from their authored canvas
  to the whole screen. Only the corpus sweep showed it; the single-skin check was green.

The instrument is `WMP_RENDER_LIMITS=1 WMP_RENDER_HOST='playing,video=2560x1440'` over the corpus,
read as `canvas=` per view, with the same run minus `video=` as the control: 83 views over the
ceiling before, **none** after, and the 23 views that still differ from the control are the skin's
own layout reacting to a playing video (largest: `Asia/vidWindow` 621x404).

**None of that was enough to tell whether it worked**, and the first two rounds of this fix were
handed back by the reporter. What settled it was driving the app: `Windows ▸ Library Browser` →
**Movies** → double-click, then `winhelper windows`. `Combat_Flight_Simulator_3/videoView` reads
**1800x1130 before and 380x351 after** on the reporter's own 2560x1440 film. A right-click posted
with a `CGEvent` tool puts a 221x211 menu window on the list, which is how the menu half was
checked; `pgrep` after clicking the skin's own X is how the close half was. See
§ *Debugging a live defect*.

**The hosted picture carries NullPlayer's own overlay — play, subtitles, casting, fullscreen — and
the view is built wide enough to hold it.** For four phases `WMPVideoSurface` switched the command
bar off on the grounds that a `.wmz` draws its own transport; what that left was a skin's video
window with no route to a subtitle, an audio track or a cast device except a right-click. Reported
2026-09-19 as *"it is still not using the standard overlay with play, sub and casting controls"*.
Three parts, and the third is the one that is easy to miss:

- The bar does not compress — its controls are one required constraint chain — so a box narrower
  than its fitting width pushes the parked window out through the skin's chrome. `WMPSceneBuilder`
  therefore builds a view carrying a `<VIDEO>` to a width where its box reaches
  `videoControlBarWidth` (395, measured from the bar itself). The box follows, because every corpus
  box is authored `view.width` minus a constant shell. A *fixed* view is never widened: it is
  pinned to its canvas at both ends and growing one is W213.
- **And a view that is both fixed and narrow falls between those two, so the surface has to decide
  as well (W254).** It can never be widened, and the window it hosts can never be narrowed, so the
  bar's minimum simply wins: `Revert`'s `vwPlayer` is `resizable="false"` with a 92pt box and the
  parked window took 395pt — a black slab three hundred points wide hanging out through the skin's
  right edge, at the height of the video band. `WMPVideoSurface.barFits(box:minimumWidth:)` is the
  guard, and it uses the same half-point tolerance the builder does so the two can never disagree
  about which boxes are wide enough. **This is bar-or-picture rather than a layout choice, and in a
  box the skin authored the picture wins** — real WMP draws no overlay inside a skin's video rect at
  all; the transport there is the skin's own. Every view the builder *can* widen still gets the bar,
  because it has already been widened by the time the surface runs.
- **`setFrame` on the parked window is refused silently, and the engine already says so.**
  `VideoPlayerWindowController.updateHostedOutputFrame` prints
  `WinampModern video: box {W, H} refused, window took {W', H'}` on every hosted layout pass in a
  DEBUG build, with **no flag** — it named W254 exactly, ten times a second, for as long as the path
  had existed, and went unread because until W252 the `<VIDEO>` was never shown. Read it before
  theorising about anything to do with the hosted picture's size.
- The parked window takes the pointer now (`ignoresMouseEvents = false`), because an overlay nobody
  can click is not one. The cost is the 21 `onClick` / 15 `onDblClick` attributes the corpus
  authors on `<VIDEO>`; their equivalents are on the bar.
- **A refused decoder-driven resize has to drop the whole transaction's geometry, not just the
  root's two numbers.** Every `jscript:` expression in that view resolved against the size the
  handler assigned, so restoring the root alone left `Combat_Flight_Simulator_3`'s `centerBox` and
  `videoWin` — `jscript:view.width-20` — at **1900x969 inside a 380x351 window**, which is the box
  the picture is parked over. `overrides.geometry` is restored to what the last committed
  transaction held; on a first transaction that is empty, and the builder's own resolution against
  the authored canvas is exactly the layout wanted.

**A film sent to a cast device is still the skin's session, and the window that drives it stays on
screen.** Two halves, both reported 2026-09-19 ("the video player window disappeared when i casted
to chromecast", "main window controls dont control it"):

- `WMPVideoSurface.update` unparks the picture's window the moment `hasVideo` goes false, which is
  one host tick after a cast starts — and it unparked it *hidden*. It now reveals it when
  `controller.isCastingVideo`, so the window that is the cast remote in every other family is the
  cast remote here too.
- `WMPAudioEngineHost.localVideoSessionController` answers nil during a cast (there is no local
  player to drive), and everything below it fell through to `AudioEngine`: the skin's play button
  started the audio queue *behind* the film and its clock read the queue's. `castingVideo` is the
  branch that was missing — transport routes to `WindowManager`'s cast-aware calls and the snapshot
  reports the cast's state, position, duration and title. `next`/`previous` return rather than fall
  through, because a cast film has nowhere to skip to and the audio queue must not start behind it.
  Classic has always routed this way through `isVideoActivePlayback`; this is the same rule.

**Two more halves of that branch, reported 2026-09-20 ("when you seek it disconnects", "the volume
wont work it raises then snaps back to quiet"), both about the seam's *units and readback* rather
than its routing:**

- **`WindowManager.seekVideoCast(position:)` takes a fraction, not a time** — it multiplies by the
  cast's own duration itself. The `.seek` branch was handing it `fraction * videoDuration`, so the
  target came out `fraction × duration²`, the receiver honoured it, hit EOF and answered
  `MEDIA_STATUS … IDLE` — which `CastManager` reads as "media ended" once `hasSeenActive` is true
  and tears the session down. A drag on the seek bar disconnected the Chromecast. Original mode
  never hit it because `VideoPlayerWindowController`'s own slider passes the fraction.
- **A cast device's volume is write-only from here, so the skin's slider needs a memory.**
  `ChromecastManager.getVolume()` is a stub returning 1.0 and nothing parses a level out of
  `RECEIVER_STATUS`, so there is no readback to poll; the snapshot was answering `engine.volume` —
  the idle audio queue's — and every drag sent its command and then snapped the slider back on the
  next tick, which then *re-sent* that stale level to the television. `WMPAudioEngineHost` now
  remembers the level it last commanded (seeded at 1.0 per cast session, reset when a cast begins
  or ends) and reports that as `volume`/`muted` while a video cast is active. `.toggleMute` joins
  the branch for the same reason: it was muting the audio queue standing behind the film.

**`WMPAudioEngineHost.videoCast` is the seam that makes this branch testable, and it exists because
both of those shipped.** The branch is only reachable with a real Chromecast on the network, so
nothing in the suite had ever entered it: a unit slip and a missing readback both reached a user.
`WMPVideoCastTransport` is the whole of what the host asks a cast to do — `isCasting`, `isPlaying`,
`currentTime`, `duration`, `title`, `togglePlayPause`, `stop`, `seek(fraction:)`, `setVolume` — and
`WMPWindowManagerVideoCast` is the only implementation the app installs, each member forwarding to
the `WindowManager` call it always did. `WMPVideoCastTransportTests` installs a fake and drives
`perform`/`snapshot` directly; **it is proof rather than coverage — re-introducing either defect
turns its six tests into eight failures**, which is the check to repeat before trusting it. Note the
seam's own signature is the fix to the first defect: `seek(fraction:)` cannot be handed seconds
without saying so.

**And closing the player quits the app** (`closeViewWindow` → `WMPMainWindowController.terminateApplication`),
as Classic's and Original's own close buttons do and as real WMP does. Ordering the window out left
the app running behind an empty screen — reported as *"the close button does not exit"*, and before
that as the frozen-skin defect the `playerWindowIsACorpse` revival existed for. Both are gone with
the corpse state. `terminateApplication` is a seam **only** so `WMPPhase9Tests` can drive a real
player close without taking the test runner down with it.

**And `WMPMainView.menu(for:)` now answers the host's own menu everywhere the skin has nothing of
its own to show**, instead of `nil`. The old rule — a skin draws its own controls and its own menus
— holds right up until those controls are off the screen edge, and a borderless window with no
titlebar then has no route back at all; `Snap To Default` and `Exit` are the two rows that matter.
The video rect and the visualization rect still answer first, so nothing the skin owns changed.

**A refused decoder resize gives the window back its authored size on any axis it is short of.**
Refusing the formula is not refusing the video layout: `Classic` collapses its own video pane for
audio (`view.height = 359 - 183`) and asks for it back for a film with the shell formula, so keeping
the current canvas played the film into a zero-height pane. `WMPScriptRuntime.transact` now grows
the root to `max(current, authored)` per axis, drops the baseline's expression values (they were
resolved at the collapsed canvas) so the builder re-resolves them, and returns that size as
`viewSize`. An axis the user made larger stays theirs. Pinned by
`WMPVideoTests.testRefusedDecoderResizeRestoresAViewItsOwnScriptCollapsed`.

### A view sizes itself in its own `onLoad`, and the first scene is built at the size it asked for

**`WMPSceneBuilder` resolves its canvas as `resizeLimits.clamp(requestedSize ?? defaultSize)`, and a
script's `view.width`/`view.height` assignment lives in `defaultSize`.** So a caller that passes a
`requestedSize` *overrides the script*, silently — which is correct for a user drag and wrong for
the pass that opens a view, because the load transaction has already run by then.

Both load paths did exactly that: `reloadSelectedSkin` (the player view) and `loadView` (every other
view) handed the builder the **pre-`onLoad`** canvas, so the scene, the window and `activeScene`
were all built at the authored size and the skin's own assignment was thrown away. The handler path
has honoured the assignment since W113/W190 (`assignedWindowSize`); the load paths never did (W244).

`WMPMainWindowController.loadedCanvas(assigned:opened:)` is the seam, and both paths call it.
`WMPScriptOutput.viewSize` is nil unless *that* transaction assigned the root's own width or height,
and the runtime has already clamped it to the view's limits and refused it outright for a
decoder-driven size (W99) — so a view whose `onLoad` sizes nothing is built exactly as before.

**The symptom is a scene laid out for a window nobody is looking at, not a wrong-sized picture.**
`Xbox Live Skin`'s `eqView` is `width="423" height="343" minWidth="429" minHeight="197"` and its
`loadEQPrefs()` is three lines — `view.width = view.minWidth; view.height = view.minHeight`, the
compact equaliser its artwork is drawn for. Every `jscript:view.height` in the view answered the
197 the script assigned while the canvas around them stayed 343, so the frame pieces pinned
`top="jscript:view.height-181"` sat 146 px short of the bottom they belong to and what was left was
a black band with two white seams where the rails and corners no longer meet. **The harness could
not see it**: its final rebuild passes `requestedSize: probe.requestedSize`, which is nil with no
`WMP_RENDER_SIZE`, so the override won and `RENDER-DUMP eqView: 429x197` was the correct picture all
along. A dump that disagrees with the window is this class.

Measured A/B in a debug build with `winhelper windows`, on the real archive: **429x343** backed out
against **429x197** with the fix, on the player path and the `theme.openView` path alike.

### `isRunningModernUI` is a two-way switch in a four-family world

**`WindowManager.isRunningModernUI` answers `false` for `WMPMainWindowController` by construction**
(`WindowManager.swift:388`), so a guard written to mean *"Classic, not Modern"* silently admits WMP
and `.wal` too. This is W217's G4 generalised, and one instance has already cost a full live-QA
cycle: `tightenClassicCenterStackIfNeeded` grew `circle`'s 192x82 borderless player to
`Skin.mainWindowSize.height` on the mouse-up of the first click, and closed with W213 by gating on
`isRunningWMPUI`.

Four sites were audited 2026-09-17 (no corpus sweep can see this) and ranked as W214 in the order
they were worth taking. **Three were measured on 2026-09-20 and two of them were defects**; one
remains:

1. **`handleCenterStackWindowWillClose`** (`:2036`) — **measured clean 2026-09-20, nothing to gate.**
   What W213 and W237 left ungated there is `slideUpWindowsBelow` plus the child re-dock, and both
   are mode-agnostic: `classicTogglePlaylist` and every other Windows-menu toggle run the identical
   sequence (slide → tighten → notify → `updateDockedChildWindows`) in a `.wmz` session with **no
   guard at all**, so gating the close path would make the close box and the menu disagree. The
   slide is also provably safe — it lands a window in the slot the closed one vacated, which was on
   screen by construction, and the WMP tiler's clamp has nothing left to do. Driven live under
   `AlienMorph`: PeppyMeter closed by its own close box left its neighbours untouched, and two
   further closes at the top of a contiguous column slid the windows below up by exactly the closing
   height. **The live route to this function in WMP is a surface's own close box** (`PeppyMeterView`,
   `CavaView`, … all hit-test one) — the aux windows are borderless there, with no titlebar button
   and no ⌘W; `teardownModeDependentWindows` reaches it too but every window is already `orderOut`,
   so the slide's `isVisible` guard makes it inert.
2. **`normalizedCenterStackRestoredFrame`** (`:5608`) — **closed 2026-09-20**, and it was the real
   one. See *A restored `.wmz` window keeps the size it saved* below.
3. **`applyClassicVisualizationDefaults`** (`:4700`) — **closed 2026-09-20**, and it was the second
   real one. See *A `.wmz` session keeps the visualization it was given* below.
4. `expectedMainHeightForCurrentHT` (`:5534`). **Take this one next**, and measure it before gating
   it.

**Do not gate them in one sweep.** Each is a shared-`App/` path and `CLAUDE.md`'s rule binds: gate on
the mode, prove Classic and Original byte-identical, and measure each separately. Verify with
`WMP_SIZE_TRACE=1` — its `MISMATCH` line fires exactly when a window is about to be forced off its
own scene — and `WMP_PLACE_TRACE=1`.

**And measure the site before gating it: an audited site is a candidate, not a defect.** Site 1 read
as one for three days on the strength of the predicate alone, and the measurement found the rule it
still runs is the rule the menu already runs ungated. What an audit of `!isRunningModernUI` can say
is *this code is reachable in WMP*; whether the code is Classic's geometry or nobody's is a separate
question, and the answer is on screen.

### A `.wmz` session keeps the visualization it was given (W214, closed 2026-09-20)

`applyClassicVisualizationDefaults` guarded on `!isRunningModernUI`, which is `false` for the WMP
controller, so it ran in full during a `.wmz` session: it wrote Classic's six scoped visualization
keys and posted the live `.visClassicProfileCommand` reloads.

**The route is a menu item, not a launch.** Skins > Classic lists every installed `.wsz` in WMP mode,
and `selectClassicSkin` -> `loadSkin` -> `loadClassicSkin` reaches this. Launch is clean and was
measured so: `WindowManager.swift:850` skips `loadDefaultSkin()` for `.wmz`, and `AppStateManager`
restores a classic skin only in `.classic`.

**Measured live under `AlienMorph`, analyzer open, track playing — one click on `ascii`:**

| key | before | after (pre-fix) |
|---|---|---|
| `mainWindowVisMode` / `modernMainWindowVisMode` | `Matrix` | `vis_classic` |
| `spectrumQualityMode` | `Enhanced` | `vis_classic` |
| `visClassicLastProfileName.mainWindow` / `.spectrumWindow` | `Lavender Pink Tips` | `Purple Neon` |
| `visClassicFitToWidth.mainWindow` | `0` | `1` |

**The screen is what makes it a defect rather than a key diff**: the open Spectrum Analyzer flipped
from the Enhanced LED matrix to the vis_classic "Purple Neon" analyzer mid-playback, while the WMP
main window never changed at all — the classic skin the user picked is invisible in WMP, but their
visualization is gone with it.

The fix is `WindowManager.appliesClassicVisualizationDefaults(isRunningModernUI:isRunningWMPUI:)`, a
pure static the guard calls — **gate the rule, not the predicate**, as site 2 did. Verified by
driving the same gesture in all four families: `.wmz` keeps its own keys, `.classic` and
`.winampModern` still land on `Purple Neon`, and `.modern` reaches them through the designed
`reloadUI` -> classic branch (`:7962`). Pinned by
`Tests/NullPlayerAppTests/WMPClassicVisualizationDefaultsTests.swift`, both sides of the gate.

**Two traps this one set.** *"Switch to Classic" is not the test* — that item changes family and
`reloadUI` re-applies Classic's defaults on purpose, so it looks identical to the defect and is not
it; the test is a **skin name** further down the same submenu, with the title bar still reading
Windows Media Player afterwards. And *these keys are global, not per-family*, so once a family switch
has reset them the reset is still there when you come back to `.wmz` — start from a fresh WMP launch
or you will measure the previous family's reset.

**What is still there and was deliberately not taken**: `selectClassicSkin` (`ContextMenuBuilder.swift:4796`)
and `loadDefaultClassicSkin` (`:4534`) branch on the same two-way predicate, so in WMP they take the
"already in classic mode" branch and load a classic skin without switching family — the user picks a
skin and nothing visible happens. Same class, two more sites, and W214's own rule says not to gate
them in the same sweep.

### A restored `.wmz` window keeps the size it saved (W214, closed 2026-09-20)

`normalizedCenterStackRestoredFrame` rewrites a restored **PeppyMeter** and **NetworkMonitor** by
Classic's own sprite arithmetic — PeppyMeter's floor (`SpectrumWindow.windowSize.height * 1.75`) and
its legacy double-height migration, NetworkMonitor's spectrum-derived minimum — and
`isRunningModernUI` is false for the WMP controller, so both ran over the two windows that wear a
skin's borrowed frame.

**The measurement is the arithmetic, and it is worth keeping because it is how a hosted-window
restore can be checked at all.** In a `.wmz` session every hosted window comes back at *its saved
frame plus the borrowed ring* — measured `+36 x +34` under `AlienMorph`:

| window | saved | restored | |
|---|---|---|---|
| Cava | 368x145 | 404x179 | saved + ring |
| Flow | 368x145 | 404x179 | saved + ring |
| Waveform | 418x262 | 454x296 | saved + ring |
| **PeppyMeter** | **380x290** | **416x288** | **254 + ring** |

One window disagreeing with its siblings by exactly the ring is the whole diagnosis: 290 is Classic's
legacy double height (`145x2`) and 254 is Classic's floor (`145x1.75`), so the migration snapped a
height a `.wmz` session chose for a legacy size it never had.

The fix is `WindowManager.normalizedClassicCenterStackRestoredFrame(…, preservingSavedFrame:)`, a
pure static the instance method calls with `isRunningWMPUI` — **gate the rule, not the predicate**,
as W237 did. `.wal` never reaches it: `showPeppyMeter` and `showNetworkMonitor` route winampModern to
its hosted controller first. Pinned by `Tests/NullPlayerAppTests/WindowRestoreGeometryTests.swift`
§ *A restored `.wmz` PeppyMeter / Flow keeps the size the session saved (W214)*, both sides of the
flag.

**Reproducing it needs the restore path, which means two launches and a pinned default.**
`defaults write NullPlayer rememberStateEnabled -bool true` (it is off in most measurement recipes,
which is exactly why this class was invisible), size the window with
`osascript -e 'tell application "System Events" to tell (first process whose unix id is <pid>) to set
size of (first window whose name is "NullPlayer PeppyMeter") to {416, 290}'`, ⌘Q, relaunch, and read
`winhelper windows`. The saved frames themselves are in the `savedAppState` JSON blob of the
`NullPlayer` domain — `peppyMeterWindowFrame` and its siblings — which is the cheapest way to confirm
what the app actually wrote before blaming the restore.

### The centre stack does not size a `.wmz` window

**A NullPlayer window docked beside the player in `.wmz` keeps the size the user gave it. Nothing
about the centre stack — how many of our fallback windows are open, or how tall they are — may
resize it.** That is a Classic and Original rule: there the library's height *is* the stack's, and
it grows and shrinks as EQ/playlist/spectrum windows open and close. In `.wmz` the same window
wears the skin's borrowed frame, and a stack-driven resize re-renders that frame at a size the
donor never authored.

W237, closed 2026-09-19, was that rule leaking in. The leak is worth remembering because the
obvious suspect was not the cause: `toggleHideTitleBars` resizes the side-docked windows by the
main window's height delta and is *already* excluded by `isRunningModernUI`. The live path was
`WindowManager.refitDockedPlexBrowserToVerticalStack`, reached from every
`updateDockedChildWindows` caller — and one of those is `handleCenterStackWindowWillClose`, whose
guard reads `!isRunningModernUI` and is therefore **true** in a WMP session. **A `!isRunningModernUI`
guard is an open door into WMP** (W214); when a geometry rule reaches a `.wmz` window through one,
gate the rule itself on `isRunningWMPUI` rather than teaching the four-family predicate a new answer.
The reopen path is gated the same way, through the pure
`WindowManager.dockedLibraryReopenFrame(reDerived:remembered:preservingRememberedHeight:)`, which
re-derives the dock edge and keeps the remembered height, top-anchored.

**Verify it the way it was verified: two modes in one binary, frames read back, never by eye.**
Launch `-uiMode wmp`, open Windows → Library Browser, then open and close a centre-stack window
(Cava is the cheapest), reading `app-control`'s `winhelper windows` at each step; the library's
height must not move. Then the identical sequence in `-uiMode classic` and `-uiMode modern`, where
it must still track — an A/B in the same binary is what proves the gate is narrow rather than the
path dead. Measured on `corona`: `.wmz` 547x890 throughout, Classic 580 → 290, Original
580 → 290 → 580. `Tests/NullPlayerAppTests/WMPLibraryStackSizingTests.swift` pins the reopen
arithmetic; the live path has no headless probe.

**The `.wal` half of W237 is B147 and is not answered by this.** `WinampModernMainWindowController`
is not named in `isRunningModernUI`, so a `.wal` session still answers whichever value the user last
left in the persisted preference.

**`WMPWindowRestorePolicy.safeFrame` was a second, weaker definition of "on screen"** (an 80pt strip,
a 24pt bottom margin, and `first(where: intersects)` rather than `hostScreen`). It was deleted with
W217 G1 on 2026-09-20 rather than rewritten against `WindowPlacement`, because **the clamp was
measured against a size the window never has**: `restoreFrame` keeps only the saved top-left and the
apply takes width and height from the loaded scene. A validation of the saved rectangle was
validating a rectangle that does not survive the next statement. See § *Window placement and
recovery* for the two seams that own reachability instead.

## Debugging a live defect

Read **`skills/live-ui-testing`** before diagnosing anything that only reproduces on screen, and the
process section it points at — `winamp-modern-skin-guide/reference/harness.md`
§ *Debugging a live defect* — which is the reference implementation of that workflow. The 2026-09-07
session that produced the fixes below spent hours rediscovering five rules already written there.

**The reproduction loop itself is `reference/harness.md` § *Driving the app*** — select the skin,
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
nothing" — the route is `reference/harness.md` § *Auditing one authored control across the whole
corpus*, and the live half is § *A live pass is a window frame, before and after*.** The census
cannot answer that question: it drives `onLoad` and a control's demand is in `onClick`, which is how
W100 stood at a recorded reach of 2 skins against a true 162. A window frame read before and after a
`CGEvent` click is the measurement, it scales to a skin per launch, and the first thing to check in
any capture is that the window size matches the view's canvas — the unskinned view is **440x170** and
a launch that failed to select the skin looks exactly like a button that does nothing.

The ones that cost the most, in WMP terms:

- **Number the transactions before theorising about one.** Two rounds of inference off the raw
  `INPUT` trace named the wrong cancellation check for W88 and produced a fix that was a no-op; one
  temporary `txn <n>` pair named the right one in a single launch. `reference/harness.md`
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
  `reference/harness.md` § *After the cascade* has the numbers and the check that holds it.
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
  edges* in `reference/harness.md` is the same lesson learned from the opposite direction, and
  carries the alpha check that stops a frame full of white paint reading as a frame full of holes.
- **Then repeat on two more windows under the same skin, and only to confirm the failure is one
  shape.** Ten windows failing the same way against a player view that never does is one contract
  unhonoured at ten call sites, not ten defects — so the second and third captures are there to
  establish that, not to enumerate.

**Do not open this class with a skins × windows capture matrix.** It is the instrument the analysis
document reached for twice and it answers the wrong question: sweeping the skin axis measures
*donors*, and a report that the skin's own window is fine has already cleared them. The variance is
on the window axis. One skin and three hosted windows localise this faster than 185 skins and one
window, and `reference/harness.md` § *A named skin outranks a corpus sweep* is the general form.
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

## Presenting a skin in a window

Learned by driving the real app on 2026-09-07, after a headless sweep said everything was fine. Each
of these was invisible to the harness and visible in the first minute of live QA.

- **A skinned WMP window carries no macOS shadow.** It is genuinely shaped — Corona is transparent
  across the 250 px its playlist slides into and the 124 px its equaliser drops into — and AppKit
  caches a borderless window's shadow from whatever content it last saw. On a shape that changes with
  every drawer and every repaint that goes stale, and a stale shadow over a transparent region reads
  as a dark box the size of the window. `invalidateShadow()` on each present fixed it, then on each
  frame change fixed it again, then playback's continuous repaints brought it back a third time. So
  `hasShadow` is **off** while a skin is shown and on for the opaque app-authored player. There is no
  drop shadow in Windows Media Player to lose.
- **A script transaction repaints in full.** The dirty region cannot be derived from what a handler
  *wrote*: it writes `svEqualizer.top` and a whole subtree moves that it never mentioned, and a
  `SUBVIEW` carries no hit metadata at all, so the narrowed bounds collapse to roughly the button
  that was clicked. Partial repaints belong to hover and slider drags, where only artwork state
  changes — and there the dirty rect must union the **old and the new** frame of every node whose
  geometry moved. Unioning only the old one erases correctly and paints only the overlap; unioning
  neither never erases, and a closed drawer stays on screen forever.
- **A new scene needs a layout pass.** The AppKit overlays are positioned in `layout()`, which AppKit
  will not run just because a scene arrived, so an equaliser the skin slid away keeps its old frame.
- **The overlays are not in the dumped PNG.** The renderer draws the scene; playlist, equaliser,
  popup, effects and video are `NSView`s hosted over it, and `WMPVideoPlaceholderView` and
  `WMPEffectsSurfaceView` both paint an opaque background. A skin can dump a perfect frame and look
  wrong on screen. `WMP_RENDER_PROBE`'s `WIDGET` line reports where the scene put them, and
  **`WMP_RENDER_APPKIT` is what actually runs their `draw(_:)`** — it hosts the scene in a real
  `WMPMainView`, `cacheDisplay`s it twice (once with the overlays hidden), and reports what the
  AppKit layer added. `outside=` is the number that ranks: an overlay inside its own widget frame is
  the hosting working. Corpus-wide that is **zero** since W74 closed 2026-09-19; it was two views in
  one skin, which was the whole of this class in the default state.
- **An overlay is placed at frame ∩ clip ∩ bounds, and the clip is the half that is easy to forget
  (W74).** `WMPSceneBuilder` records the container a widget was declared in as its `clipRect` and
  every paint command intersects with it, so the scene has always confined a control authored past
  its container's edge. `layout()` placed the `NSView` from the raw frame instead and the overlay
  drew wherever the markup reached — `Revert`'s `ctrlPlaylist` resolves `3,14 250x257` against a
  container box of `250x242`, and the extra fifteen points covered the bevel that closes the
  playlist window's frame. It was reported on screen as "there is no bottom border on the playlist"
  and the harness had been printing it as `outside=4000` all along. `WMPVideoSurface.update` had
  the arithmetic right from the start; `layout()` now matches it.
- **`intersection(_:) ?? frame` is wrong for a clip and is the trap inside that fix.** `WMPRect`
  answers `nil` both for *no clip* and for *a clip that misses the frame entirely*, so the tidy
  one-liner hosts a fully clipped-away widget at full size — the exact defect, reintroduced by the
  fix for it. Unwrap the optional once and keep the two cases apart. The same `?? frame` idiom is
  still live in `WMPRenderer`, `WMPHitCoverage` and `WMPSceneBuilder`, where it computes a rect for
  *measurement*; painting is clipped by `CGContext.clip(to:)` and is unaffected, but a `visible=`
  number taken off those paths reads a disjoint clip as unclipped.
- **An overlay fills `bounds`, never `dirtyRect`.** AppKit is free to hand a view a dirty rect
  larger than itself, and it does: the 320x240 `WMPEffectsSurfaceView` was called with
  `{{-269, -26}, {596, 468}}` — the whole window in its own coordinates — and a layer-backed view
  does not clip that (`masksToBounds` is false). `dirtyRect.fill()` therefore painted the spectrum
  pane's translucent wash over the entire skin, reported as "a giant black box over the player".
  Both `WMPEffectsSurfaceView` and `WMPPlaylistSurfaceView` had it. It only appears once the overlay
  exists, and the overlay only exists after a skin reload with a track playing, which is why it read
  as "switching skins causes it".
- **The selected view is persisted on every present, and Corona's route into its compact view is an
  unnamed button inside the equaliser drawer.** Land in `viewTiny` and it is restored on every
  launch; it also renders almost identically to `vPlayer`, so there is no visual signal that it
  happened. Confirm skin *and* view before diagnosing anything in this engine.

- **The player's window outlives its presentation, so re-showing it must rebuild it (W233).** The
  controller keeps **one** `playerWindow` for its whole life and the materializer lends it to
  whichever view is the player. `closeViewWindow` tears that presentation down and orders the window
  out — but the `NSWindow` is still the controller's `window`, so `WindowManager.showMainWindow`
  ordered a corpse back in: the last picture the skin drew, no scene, no hit map, no timer, and
  `WMP_WIDGET_TRACE` recording **zero presents** afterwards. `showWindow(_:)` rebuilds the session
  when there is no presentation behind the window it is about to reveal, and `reloadSelectedSkin`
  is the right rebuild rather than a re-present: the close discarded the script view, and the reload
  runs the skin's own `onLoad`, which is what clears the preference that asked for the close.
  **A skin's close button is not always about the thing it sits on** — the Skins Factory close in a
  playlist writes `exitView`, the windowless dispatcher reads it back and posts `view.close()`, and
  W89 runs a dispatcher's commands against the player, so closing "the playlist" closes the player.
  That is WMP's own behaviour; the route back is the part that has to work. Reported as *"if you
  close the playlist you do not return to the main window … the playlist is frozen"*.

- **`.wmz` mode must offer a route to a track.** The auxiliary NullPlayer windows stay hidden here
  until they have WMP-owned chrome, so the skin's own Open button — `theme.openDialog('FILE_OPEN')` —
  is the only one. Before it was implemented the only way to start playback was to leave WMP mode and
  come back, which is not a mode.

## Phase 4 input and transport contracts

- `WMPMappingImage` stores canonical, un-premultiplied RGB plus alpha in authored top-left row
  order. Alpha-zero and unregistered colors never hit. Sample by scaling the original unclipped
  control frame into mapping pixels; apply inherited clipping as a separate hit-test gate.
- Mapping-image child bounds are only rejection/dirty metadata. Irregular regions may have empty
  corners inside their bounding box, so activation always samples an exact pixel. Cache mapping
  buffers through `WMPImageStore` with a byte bound and a key containing canonical path plus the
  color-to-node assignment.
- `WMPHitTester` walks reverse z/document order. Mapped unknown/transparent pixels fall through to
  lower controls; disabled controls do not intercept input. Window dragging is reached only after
  interactive hit testing returns no target.
- Mouse capture belongs to the pressed node until release or cancellation. Activation requires an
  inside release on that same node. Seek/volume/balance continue tracking while captured; scan
  commands always stop on release, cancellation, or teardown.
- Normal, hover, down/sticky, and disabled artwork selection is resolved off-main by rebuilding an
  immutable scene. AppKit invalidates only the union of changed control frames while retaining the
  full last rendered image.
- `WMPHost` is a main-actor, typed command/snapshot boundary. `WMPAudioEngineHost` clamps all numeric
  values and exposes metadata, time strings, playlist position, command-enabled state, shuffle,
  repeat, mute, volume, and balance without exposing `AudioEngine` to skin code. JScript remains
  disabled; Phase 4 recognizes semantic transport elements and only a small exact allowlist of
  literal transport statements.
- Both the skinned and app-authored unskinned WMP players use this same host. Custom-drawn controls
  publish accessibility children with stable `wmp.*` identifiers.
- **A skin switches the equaliser on in its markup, and it is the only place it ever does (W117).**
  `<equalizerSettings id="eq" enable="true"/>` is authored by **148 of the 180 archives**; exactly
  **one** skin (`gnome`) ever writes `eq.enabled` from script, and **no archive anywhere authors
  `"false"`**. `EQUALIZERSETTINGS` has been a non-layout element since W65 — correctly, it has no
  geometry — so nothing read its attributes at all, and the engine's equaliser node stayed bypassed
  under every skin in the corpus: a band bound to `wmpprop:eq.gainLevelN` dragged, wrote, reached
  `AudioEngine.setEQBand`, and was inaudible. `WMPDeclaredHostState.equalizerEnabled` reads it; both
  spellings count (`enable` 88 skins, `enabled` 57) and only a **literal** decides, because a
  `wmpprop:` binding asks the host what the host is about to be told. **Apply it once per skin load,
  not in `apply(skin:…)`** — that re-runs on every `switchView` and would undo a user who turned the
  equaliser off. The 19 skins with band sliders and no declaration are covered by
  `WMPAudioEngineHost.engageEqualizer`: a band, preamp or preset write engages a bypassed equaliser,
  which is what `EQView`, `ModernEQView` and `WinampModernComponentBridge` already do on a preset and
  the only route a `.wmz` with no toggle of its own has. The enable state is global and persisted, so
  a `.wmz` turning it on carries into the other skin modes exactly as the equalizer window does.
  **Before ranking a "the control moves and nothing happens" defect, ask whether the markup declared
  a host state nothing reads** — this class is invisible to every image sweep and to the call trace
  alike: there is no script call to trace.
- **A skin's own name for its `<EQUALIZERSETTINGS>` is another spelling of `eq` (W256).** `eq` is a
  bound global on the *path* `eq`, so `<equalizerSettings id="ElvisEQS">` was an ordinary element:
  `ElvisEQS.gainLevel1 = value` landed in its own property bag, reached no audio, and the band
  slider bound to `wmpprop:ElvisEQS.gainLevel1` never moved, because that binding resolves from the
  host. The name is folded to `eq` in `WMPObservablePropertyRegistry.init` for bindings and routed
  in `WMPObjectModel`'s read/write/call for script; `enableSplineTension`, `splineTension` and
  `bypass` stay the element's bookkeeping (W134). Reach **7 of 184 archives**; the full rule and the
  numbers it replaces are `reference/object-model.md` § *The `eq` object and the element are one
  surface (W39)*.

## Script, expression, and binding contracts

- `WMPScriptRuntime` is the only production route for skin JScript: one persistent `JSContext` per
  skin session, one transaction at a time, expressions then handlers. `reference/object-model.md`
  is the contract for what it exposes; do not add a member without reading its rules.
- A skin's programs evaluate once per session, **after** the view's elements are installed as
  globals and the host objects are bound, because skins run top-level code that touches both.
- Fail closed per handler, never per session: an unrecognised member aborts that one handler and is
  tallied as measured demand. There is no session-wide script kill switch — a skin puts its whole
  startup in one handler, and a kill switch makes that invisible rather than visible.
- **A handler's scope starts at the element it is written on (W216).** A markup handler runs inside
  `with (__wmpWrap('element:<owner>'))`, so `previous()`, `down` and `toolTip='Seek'` mean the
  element's own method and properties — the corpus writes it that way in 20 archives for calls and
  100 for properties. **The arbiter is `WMPObjectModel.recognises`, not the open read surface**, and
  the two rules it enforces are what make the scope safe: an element never claims its own
  `on*`/`*_onchange` attribute names (a `<VIEW onLoad="OnLoad();">` would otherwise swallow the
  skin's `OnLoad` function), and it *does* claim the computed properties `readElement` answers from
  the host, which `computedElementProperties` lists beside it — **a computed property added to one
  and not the other is readable qualified and invisible bare**. See
  `reference/object-model.md` § *An unqualified name in a handler resolves against its own element
  first (W216)*.
- **An inert member that answers a constant is still a phantom.** `mediacenter` was the largest
  cause of a dead handler in the corpus — 159 `ReferenceError`s across 110 of 179 archives (W37) —
  and every one of its nine members is honestly `inert()`: there is no video surface, one effect
  with no type and no presets, no high-contrast mode. But skins *round-trip* these, writing
  `mediacenter.effectPreset` in one view and reading it back in another, so an inert member stores
  session state and answers what was written. A constant looks identical from every instrument and
  is wrong. See `reference/object-model.md` § `mediacenter`.
- **Closing the biggest row raises the ones behind it, and the capture must show both.** W37 took
  the runtime error class 252 → 127 while distinct causes went *up*, 41 → 55: handlers that died on
  their first missing member now reach their second. Never read one row falling as progress without
  re-measuring the whole table in the same capture, and never read lost pixels as a regression
  before finding the statement that hid them — a script that finally runs is a script that finally
  hides panes. `reference/harness.md` § *After W37*.
- **A host command is the script's output, not the drawing's, and it is applied when the
  transaction returns rather than after the scene is presented (W88).** The build and the render are
  the slow half of a transaction, so a view timer that fires during them cancels the task — right
  for the drawing, because a newer transaction is already building a newer scene, and it used to
  discard the commands with it. `Alienware Invader` is what that cost: its 568-frame intro ends on
  the heaviest tick in the skin — `toggleShutter()` swaps `mainBack` to `main_back.png`, turns
  `mainBackGroup1` on and posts `view.timerInterval = 0` — and building that one frame decodes the
  whole player's artwork, overrunning the 50 ms period. The reveal was never presented and the `0`
  never applied, so the timer kept firing with the skin's own `introStatus` now true and the very
  next tick took the *other* branch of `toggleShutter()`, closing the shutter it had just opened.
  Reported live as "it opens to reveal the controls and then closes and stops responding".
  **A transaction that has returned from `transact` has already committed its writes to the runtime,
  so anything downstream of it is not optional.** A command that switches views owns everything
  after it, so this transaction's scene is abandoned rather than drawn over the new view's.
- Authored handlers are selected **per view**. A `.wmz` declares every view in one file, so an
  unscoped scan runs another view's `onLoad` against elements that do not exist in this one.
- Expression reads form a per-view dependency graph. Resolve in stable topological order and commit
  one immutable scene. Missing/ambiguous IDs, cross-view reads, cycles, non-finite values, negative
  sizes, and depth/pass overflow never partially update the visible scene.
- Resizes evaluate from proposed view dimensions off-main. AppKit keeps drawing the last scene until
  the resolved replacement is complete; never synchronously rendezvous with script work.
- `WMPObservablePropertyRegistry` owns both `wmpprop:` and `wmpenabled:`. Coalesce host snapshots,
  retain committed values across batches, and tag origins so script echoes cannot create feedback.
- Host timers enforce the Phase 0 count and period limits. Preferences are bounded and namespaced by
  the SHA-256 of skin archive contents; reset only the active skin namespace.
- Dispatch authored handlers in document order. Host changes use open, play, status, position, mode,
  buffering, then reception order; input uses mouse-down, mouse-up, click/change semantics from the
  Phase 4 capture model.
- **A clock tick is not `status_onchange`, and a transaction's timers are a delta rather than the
  live set (W119).** Both were one path — `refreshHostState` — and both only bite while a track is
  playing, which is why no capture in this harness could see either: every probe ran against a
  stopped, empty-playlist `WMPHostSnapshot()` until `WMP_RENDER_HOST` existed. **`status_onchange`
  means the status *string* changed**, and `player.status` is inert and empty here; raising it on
  every 100 ms position tick made **70 of the 177 measurable archives** re-run their metadata
  handler ten times a second, and since **all 75 authored sources are metadata updaters** — 35 of
  them `updateMetadata()`, whose body is `metadata.value = player.status` — the track readout was
  blanked continuously. Reported as no track information under `9SeriesDefault`, whose
  `ShowStatus(player.status)` drew an empty metadata line beside a correct clock. A tick now raises
  `positionchange`, **a name no archive authors** (0 uses), so it resolves to no handler and is the
  binding-only transaction that lets the 108 archives' elapsed readout and the 89 archives' seek
  slider settle; a `duration` change is a media opening rather than a clock ticking and keeps the
  status raise. And **a transaction that registered no `setTimeout` must not cancel the ones already
  running**: `timerRequests` is what *that* transaction asked for, so replacing the set wholesale
  killed every script timer in the skin within 100 ms of pressing play, and restarted the survivors'
  sleeps from zero. `applyTimerDelta` adds, honours `clearTimeout` (the context reports cleared
  tokens too, because a cleared token can belong to a transaction long past), leaves a running token
  alone, retires a one-shot when it fires, and bounds the *resulting* set. `dispatchTimer` applies
  the delta as well — the WMP idiom is a callback that ends by registering the next step, and
  dropping that made a chain fire once. **Before ranking a "it works until you press play" defect,
  ask what the host refresh is dispatching ten times a second.**
- **An open state and a play state are two different quantities, and pausing changes only one of
  them (W170).** `openstatechange` and `playstatechange` were raised together off `snapshot.state`,
  so every pause told the skin a media had just opened. **109 of the 180 installed archives author
  `OpenState_onchange`** and three answer it by playing — `Plus! HueShifter`, `Plus! Plasma Ball` and
  `Plus! SlimLine` share an `OnOpenStateChange` whose `osMediaOpen` arm ends in
  `player.controls.play()` — so 16 ms after every pause the skin restarted playback, and after a
  stop the re-play found the player stopped and **reloaded the track from zero**. Reported live as
  *"pressing pause does not pause the stream"*, then *"stop does not stop"*. Each event now rides its
  own quantity: `WMPMainWindowController.stateEdgeEvents` compares `state` for one and
  `openState` — derived from whether anything is open, the same derivation `arguments(for:)` and the
  object model use — for the other. **Raising an event for a quantity that did not change is not a
  harmless extra**: the handler behind it is written to act, and here it acted by playing.
  **It is also the sharpest case yet of what a corpus sweep cannot see**, and the reason the rule is
  extracted as a static rather than left inline: the harness seeds *one* host snapshot and never
  transitions, so this edge is never computed headlessly, and the click sweep reported `action=pause`
  dispatched correctly in all 149 skins it drove. The measurement is the app's own log — a
  `pause` immediately followed by `play(): Starting streaming playback`. It reproduces only through
  the streaming path (a Plex/Jellyfin track); with a local file the same re-play lands on an
  already-loaded engine and is invisible, which is how a first live pass cleared it wrongly.
- **Hover is two events and a gate.** Crossing from one control to another raises `onMouseOut` on
  the node left *before* `onMouseOver` on the node reached — a skin that fades a readout in on entry
  never fades it back out otherwise — and nothing is raised while the pointer stays inside the same
  node. Unlike every other dispatch site, a hover edge runs a transaction **only where the markup
  authored a handler for it** (`WMPMainWindowController.hoverEvents`): the pointer crosses a whole
  row of buttons on the way to the one it wants, and a transaction rebuilds and re-renders the
  entire scene. Hover *artwork* is unaffected by any of this — it never went through script.
  Measure it with `WMP_RENDER_HOVER`; `onmousemove`, `ondblclick`, `onfocus` and `onblur` are the
  same shape and still unraised.

### A `<TEXT>` is sized by its glyphs, including on the frame before any layout exists

`WMPScriptContext.perform` syncs every element's `left/top/width/height` from **the layout the skin
is currently drawn at**. On the opening transaction there is no such layout, so the sync is skipped
and every geometry property an element did not author falls through to the object model. For a
`<TEXT>` the honest answer there is not the unset-numeric 0: a text node is sized by its own glyphs,
and `WMPObjectModel` measures it the way `WMPSceneBuilder.intrinsicTextSize` does — **trimmed**,
because `literalString` trims and a frame the script runtime computes has to agree with the frame
the builder lays out. An authored dimension, a script assignment and a real laid-out frame all still
win; the measurement is only ever the answer for a dimension nothing else has stated.

Three rules come out of W218, and the first is the one worth carrying to unrelated work:

- **A defect that repairs itself on the first interaction is still a defect, and the corpus sweep is
  the only instrument that sees it.** `Colorchooser` chains its five transport buttons
  `left="jscript:<prev>.left+<prev>.width"`; with every width answering 0 they stacked on one pixel,
  the webdings glyphs overprinted, and the first click anywhere in that row fired **previous**
  because `prevbutton` is last in z-order. The relayout that click triggers is the first one there
  is, so the row is correct from the second click onward. Hand-testing cannot reproduce it — the
  reporter tried and could not — and `reference/skins/colorchooser.md` had filed it as *not a
  defect* on the strength of the mechanism alone.
- **`WMP_RENDER_SETTLE` does not stand in for an event.** Settling pumps the run loop and drives
  `onTimer`; it does not raise the input that creates the first layout. A cold `WMP_RENDER_CLICK`,
  one point per process, is what distinguishes "correct" from "correct after one wasted click".
- **Frame 0 is a state a user is always in.** A skin gets exactly one first frame and the first
  click lands on it, so a rule that only holds from the second transaction holds for nobody.

## Drawing the skin's own controls

- **`hoverDownImage` is never selected, and the fix is not just a name (W132).** `button-element`:
  "the image displayed when the **BUTTON** is in the down state and the user hovers over it with the
  mouse pointer." `WMPSceneBuilder.swift:490-493` resolves `.down` to `["downImage", "image"]` and
  never consults it. **126 nodes across 62 skins** (`BUTTON` 86, `BUTTONGROUP` 38, `MUTEBUTTON` 2),
  and **every one also authors `downImage`** — checked, zero exceptions — so the fallback is the
  correct down artwork missing only its hover lighting. **Deliberately ranked low, and kept rather
  than dropped** because the sticky case is the one a user looks at for seconds at a time:
  repeat/shuffle/mute left toggled on. `WMPInteractionState.swift:63` collapses a pressed node and a
  sticky-down node into the same `.down`, so **this needs a distinct hover-down face in the state
  machine before the attribute has anywhere to go**, and it needs the live loop for the same reason
  W131 did.
- **Hosted `PLAYLIST` chrome attributes are unread, and verification halves the row (W133).**
  `playlist-element` defines 37 attributes; the engine reads background/foreground/itemPlaying
  colours via `WMPSurfacePalette` and nothing else. **Most of the corpus authors values that *agree*
  with what the overlay already does** — `playlistItemsVisible="false"` is 3 skins against 117
  authoring `"true"`, `moveButtonsVisible` is `"false"` in all 57 skins that author it,
  `checkboxesVisible` is `"false"` in 24 of 32 — so only the genuine differences rank:
  `columnsVisible="true"` **74 skins** (with `columns` in 131), `leftStatus`/`rightStatus` 27,
  `dropDownImage`/`dropDownBackgroundImage` 27/25, `toolbarVisible="true"` 12, `toolbarMargin` 14.
  `disabledItemColor`'s 74 have no meaning here at all — there are no disabled tracks. **The
  substance is column headers, which the overlay draws none of.** `dropDownVisible="true"`
  (114 skins) is explicitly **not** part of it: a documented deliberate refusal in `object-model.md`
  pending W66.

- **A `<BUTTONGROUP>`'s artwork is a sheet the size of the whole group, and every state of it is
  painted through the group's mapping mask (W154).** The dead area a sheet carries around its
  controls is keyed by the **mapping image**, not by the group's `transparencyColor`: an author
  names the *map's* dead colour there, because that is the one colour every one of the group's
  bitmaps shares. `portals/mode1` states it three times in one view and settles it —
  `cbuttons_play`'s sheet is white around the transport ovals against 24,997 black mask pixels (a
  white slab at `13,236 280x140`, which was also hiding the brass casing under it);
  `sysbuttons_group` is the same shape in magenta, 829 against 829, and was the whole of the corpus
  PNG sweep's opaque-magenta residual outside `Plus! Pulsar`; and `shufrep_buttons` is the
  **control case**, 3,723 magenta in the art against 3,723 magenta in the *map*, where the one
  declared key covers both and nothing was ever wrong. The base sheet takes the union of every
  registered child, a lit sheet takes the children in that state, and a group lit by itself rather
  than by a child takes the union too. It also keeps the natural-size anchoring every other
  foreground image has (W122) — `Plus! SlimLine`'s `perfectV_SideBar_normal.jpg` is authored
  shorter than its 35x243 group and stretched when it did not.
  - **`showBackground="true"` is the author's exemption, and it is measured rather than inferred:
    41 declarations across 7 of the 177 measurable archives, every one `true` except `Compact`,
    which writes `showBackground="false"` twice and is the only skin in the corpus that states the
    default.** A group whose `image` is genuinely the window's own artwork says so — `elvis` wraps
    its entire 335x396 body in one, as do `Plus! HueShifter`, `Plus! Plasma Ball`,
    `Plus! Hard Boiled`, `Plus! SlimLine` and `Asimov_Radio`. Masking those leaves a hole where the
    player was. Only the *base* sheet is exempted; a lit state is still cut to the control the
    pointer is on, which is W108 and is what makes `elvis`'s `elvis_body_down.jpg` light one button
    instead of redrawing the whole body.
  - **The derived mask is cached and must stay cached (W155).** It is a pure function of the bitmap
    and the child set and never changes with interaction state, so `WMPImageStore.mappingMask` keys
    on the resource path plus the sorted node ids. Rebuilding it per draw cost **173.1 ms per
    render** on `New Super Mario Bros` against 0.3 ms cached, and saturated six cooperative threads
    while the main thread sat idle. Anything that adds a mask to more commands inherits that.

- **A hosted AppKit surface obeys the container's `alphaBlend`; it is not exempt because it is not
  a paint command.** `alphaBlend` inherits, and a `.wmz` closes a pane it has not opened by fading
  the container to zero — so `WMPWidget` carries the walk's inherited alpha, `WMPMainView` hosts
  **no view at all** at `alpha == 0` (rather than `alphaValue = 0`, so a shut pane runs no GL engine
  and no 30fps readback), and a partial fade is applied every sync. `Plus! Bionic Dot` is the worked
  case twice over: its `<subview id="visMask" alphaBlend="0">` correctly drew no artwork while the
  `<EFFECTS>` inside it put a 169x160 visualizer across the face, and its `checkPlayerState()` also
  runs `visMask.alphaBlendTo(0,500)` whenever `player.controls.isAvailable("Stop")` is false — so a
  stopped player is *supposed* to show no visualizer and a disabled vis button. Six archives author
  the idiom, five of them Plus!.
- **A hosted surface is confined by the window's own shape as well, and that is a third statement
  (W198).** The two idioms below are about the *container's artwork*; this one is about whether the
  window exists at all. `clippingColor` marks pixels the skin cut out of its own silhouette, nothing
  is painted there, and therefore nothing occludes a surface that reaches into them — so a rect
  confined "by paint" is not confined at the edges of the skin. Cerulean is the reported case and
  the smallest of six: `face.bmp`'s last three columns inside the `<EFFECTS>` rect are `#FF0000`,
  and 104 px of visualizer stood outside the right of the head. `WMPSceneBuilder.groundShape`
  already computed that silhouette for `WMPEffectsGround`; `WMPWidget.clippingShape` now carries it
  to the surface, which clips to it **and** to `regionMask`, intersected. **`clippingColor` only,
  never `transparencyColor`** — a hole inside the silhouette is where the surface is *meant* to
  show, which is the same rule `groundShape` states and for the same reason.
  `WMP_RENDER_PROBE`'s `offshape=` is the only instrument that sees this class; `outside=` cannot,
  because the leak is inside the widget's own rect. `offshape>0` measures what the skin *authored*,
  so it stays non-zero after the fix: it is a rect to check, not a defect. **`pharaoh` was the
  counter-evidence and W199 is what it was pointing at** — five of the six skins W198 moved cut only
  pixels the scene leaves fully transparent, and `pharaoh`'s 1,524 were opaque because its
  container's `backgroundColor` fill was not clipped by its own keys. Confining the surface was
  right and was never the whole of it; the fill was the other half, and the two together are what
  give that window a pyramid instead of a slab and a visualizer instead of a black apex.
- **A container shapes its windowless `<EFFECTS>` in one of two ways, and they read the colour key
  oppositely. Measure which before touching either.**
  - *Artwork with a keyed hole* — every pixel is the key or opaque paint. The key is the **opening**;
    the paint occludes the rest, and the engine already renders that by hosting the container's own
    paint commands above the surface (`WMPWidget.commandSplitIndex`). **Cerulean is this** —
    `face.bmp`, 56% key, 44% paint, 0% transparent.
  - *A shape mask* — the file carries a **third state**. The key marks the **outside**, genuinely
    transparent pixels mark the opening, and the little paint there is is trim. `WMPWidgetRegionMask`
    clips the surface to it, counter-flipped exactly as `WMPRenderer.clip(to:mask:)` is.

  **The Plus! archives are a sub-family with their own idioms, and both halves of this rule came out
  of them** — `reference/skins/plus-family.md` is the dossier, including what has been ruled out.

  The discriminator is *has transparent pixels alongside keyed ones* — not a threshold, not a skin
  name. Measured over all 30 `<EFFECTS>` in the corpus whose container declares a background image
  and a transparency colour, **28 are two-state and 2 are three-state**: `Plus! Bionic Dot`'s
  `main_vis_back.png` (36/58/5) and `Plus! Professional`'s `vis_mask_s.png` (23/59/18). Getting the
  sign wrong on Cerulean does not distort its visualizer, it **erases** it: the mask would keep the
  surface only where the face already covers it and clip it away inside the hole.
- **The skin draws its controls; an AppKit overlay is only for what the scene genuinely cannot
  paint.** What is left hosted is `PLAYLIST`, `DROPDOWNPLAYLIST`, `EFFECTS`, `EDITBOX`, `LISTBOX`
  and `POPUP`. `VIDEO` is not: its placeholder filled every `<VIDEO>` frame with opaque black over
  the artwork of 166 of 177 archives, and an audio player has nothing to put there instead. Adding
  an overlay back needs the same argument — name what the renderer cannot draw.
- **A popup's height is a host metric when the markup omits it.** Measured 2026-09-10 over 177
  readable archives, both `DROPDOWNPLAYLIST`s (Corona and 9SeriesDefault) and all four `POPUP`s
  omit `height`; they have no artwork from which the generic geometry path can infer one. Their
  `NSPopUpButton` host measures 24 points high, so `WMPWidgetKind.intrinsicHeight` supplies exactly
  that value only for an unauthored, unoverridden height. The scene builder remains off-main and
  does not construct AppKit controls; an authored or scripted height wins.
- **The visualization surface is this player's own visuals in the rect the skin authored (W101).**
  `WMPEffectsSurfaceView` draws compact WMP-native **Spikes**, **Bars**, **Ambience**, **Cava**, and
  **vis_classic** directly. Cava uses its actual presenter/full-stereo tap and vis_classic uses its
  actual waveform/profile core, each with a WMP-only preference scope. Their right-click controls are
  therefore the real Cava tuning menu and vis_classic profile menu, not inert replicas.
  `WMPEffectSelection` is the one place the choice lives, because 96 archives bind
  `currentEffectType` to `wmpprop:mediacenter.effectType`. Three rules it is built on: **nothing
  playing draws nothing at all** (the skin's own screen artwork stands); **the surface never takes a
  click**, because 51 archives wire an `onClick` on `<EFFECTS>` and that handler belongs to scene hit
  testing; and **the skin's selector is not the app's preference** — cycling from the rect, its menu,
  or the arrow keys never writes `visualizationEngineType`, which the visualization window and
  menu bar share.
  **The keys are two-level, because the catalogue is.** Eight effects, and most carry a list of
  their own, so **up/down pick the effect and left/right step inside it** — ProjectM's presets,
  Geiss's and Tripex's effects, vis_classic's profiles, Cava's mono/stereo. An effect with no
  inside (Spikes, Bars, Ambience) *refuses* left/right rather than swallowing them, so the key
  falls through. Two things this wiring depends on: a preset step goes through
  `WMPEffectSelection.setPreset`, never the engine's own `nextPreset()`, or the `currentPreset` /
  `currentPresetTitle` bindings 144 archives read would show a preset that is not on screen; and
  `applySelection` must tell a preset change from an effect change, because `setPreset` posts the
  same notification as `select` and rebuilding the engine for it reinitializes ProjectM on every
  key press.
  **Do not fill the widget's rectangle.** The effect is composited over the scene, and its untouched
  pixels must stay transparent: every renderer draws into the full authored rect and the skin's own
  artwork is what shapes it, through the z-order split above. **A suite renderer needs two extra
  conversions:** Cava's shared drawer assumes a y-up AppKit host and vis_classic emits top-row-first
  BGRA, so both require a local y-flip inside the flipped WMP view. Test the effect with a real skin
  at playback and inspect the AppKit-hosted frame; a static render dump cannot show its pixels.
- **The ban on hosting ProjectM / Geiss / Tripex in the slot is reversed, and this records why
  (W140).** The rule read: *it must never host ProjectM, Geiss, Tripex, or any other standalone
  visualization window in that slot*, with the black panels reported in Asimov Radio and Cerulean as
  its evidence, and `WMPEffectsSurfaceView.makeEngineView()` / `applyPreset(to:engine:)` were left in
  the file as dead code with zero call sites.

  **Those black panels were the occlusion defect, not the engines.** `WMPMainView` blitted the whole
  scene as one flattened image and hosted every widget above it with a plain `addSubview`, so nothing
  a skin drew could ever cover the surface. An opaque renderer that nothing can occlude *is* a black
  rectangle over the artwork — it would have been one whatever was drawing in it. With the split
  above, the artwork composites over the rect and opacity stops mattering; WMP's own visualizers were
  opaque too.

  What does not change: **the selection stays WMP-session-scoped** — a skin cycling `visEffects`
  never writes `visualizationEngineType`, which is why `switchEngine(to:forceReload:)` grew a
  `persistPreference` parameter rather than the surface calling it as the visualization window does
  — and **`VisualizationGLView` is not mounted live between the two raster layers**. A legacy CGL
  drawable's ordering against sibling `CALayer`s is not guaranteed the way normal layer z-order is,
  and its own `CVDisplayLink` clock tears against the overlay's alpha-blended edge. Do not mount it
  live "just to try"; that is what produced the black panels the first time.

  **How the three are hosted.** `WMPEffectsSurfaceView` builds a `VisualizationGLView` and never adds
  it to the hierarchy: its display link never starts, and a 30fps timer pulls one frame at a time
  through `renderOffscreenImage(pixelWidth:pixelHeight:)` — an FBO render plus `glReadPixels` — which
  `draw(_:)` presents like any other picture. **The GL path takes no y-flip**, where vis_classic
  does: `glReadPixels` returns rows bottom-first, a `CGImage` calls row 0 its top, and this view is
  flipped, so the two reversals cancel. The view's frame is set in **points** before each pull, not
  pixels — `initializeEngineOnRenderThread` sizes the engine from `convertToBacking(bounds)`, so a
  frame in pixels creates the engine at twice the surface it renders into. The readback is verified
  headlessly by `WMPPhase7Tests.testOffscreenEngineReadbackProducesAnImage`, which is the only thing
  in the suite that drives an `NSOpenGLView` outside a window.
- **The effects slot's settings belong to the skin, not to the session (W157).** A `.wmz`'s
  `<EFFECTS>` rect is part of its look — Cerulean's 103x75 frame and a full-width panel want
  different effects — so `WMPVisualizationSettingsStore` files them against the installed skin name
  (length-prefixed key, as `WMPViewFrameStore` does) and `WMPMainWindowController` restores them at
  the top of `reloadSelectedSkin()`, before the scene and therefore before the surface is built.
  **What is in scope is what WMP owns**: the effect and preset, plus the keys already namespaced to
  the slot — `cava.wmpEffects.*` and `visClassic*.wmpEffects`, both asked of the subsystem that
  names them (`CavaSettings.preferenceKeys(for:)`, `PreferenceScope.wmpEffects`) so a new key is
  carried without a change here. ProjectM / Geiss / Tripex cycle and sensitivity are **not**: those
  keys are shared with the standalone Visualizations window and the `.wal` surface by design, and
  per-skin copies would rewrite that window's settings on every skin switch.
  Three things it is built on. **A skin with no record restores the app's defaults** — every scoped
  key is cleared, and `WMPEffectSelection.restore` falls back to the default effect where `select`
  would change nothing — or the second skin silently inherits the first one's choices, which is the
  half that regresses invisibly. **Capture is driven off `UserDefaults.didChangeNotification`**,
  not off each menu item: the Cava and vis_classic controls in the slot's menu write their own keys
  and offer no callback. That makes the write conditional — an unchanged record must not be
  rewritten, or the observer feeds itself. And **a captured change is filed against the skin that
  was showing when it was made**, held in `visualizationSettingsSkin`, because the defaults
  notification is delivered on the main queue asynchronously: a change made just before a skin
  switch would otherwise land in the record of the skin being switched *to*. `restoreVisualizationSettings`
  flushes the outgoing skin first for the same reason.
- **PCM arrives on the audio thread and an overlay must not hop to the main actor to take it.**
  `.audioPCMDataUpdated` is posted from inside `AudioEngine.processAudioBuffer`; a
  `MainActor.assumeIsolated` in that observer is a `dispatch_assert_queue` failure and the process
  traps the moment a surface exists and a track plays. The WMP effect surface retains the latest
  spectrum snapshot and schedules its AppKit redraw on the main actor.
- **A semantic slider tag is itself a binding, and its range is part of what the tag says (W118).**
  `<SLIDER value="wmpprop:player.settings.balance">` states where a control reads; `<BALANCESLIDER>`
  states the same thing by *being* one, so a skin that uses the tag authors no `value` and usually no
  `min`. Two defaults then collided: `sliderMetrics` falls back to *the value of a slider nobody has
  told anything is its own minimum*, on a range defaulting to 0-100 — so **15 of the corpus's 16
  balance sliders drew their thumb at the bottom of the track, which on balance is hard left**,
  reported live as "balance is fully to the left by default on all skins". `VOLUMESLIDER` (31 uses /
  23 skins) drew empty and `SEEKSLIDER` (18 / 15) stuck at the track start for exactly the same
  reason; balance is the one where the wrong end of the track *means* something, which is why it is
  the one that got reported. `WMPObservablePropertyRegistry.implicit` synthesizes the binding the tag
  stands for, so the value arrives through the same coalesced, echo-guarded path an authored
  `wmpprop:` does and follows the host live. **The seek slider needs both halves**: WMP puts its
  position on the track in *seconds*, so `max` is synthesized onto `player.currentMedia.duration` and
  `value` onto `player.controls.currentPosition` — two paths the registry already answers, rather
  than a new percent path it does not. Ranges stay in `sliderMetrics.defaultRange(for:)`, which is
  `-100…100` for `.balanceSlider` and 0-100 for every other kind. An authored attribute always wins:
  one corpus balance slider states its own `value` and keeps it. **And a skin says the same thing a
  second way, by the range it declares (W120): 73 sliders across 61 of the 177 measurable archives
  author `max="wmpprop:player.currentMedia.duration"` and no `value` at all** — 58 as
  `<CUSTOMSLIDER>`, 15 as `<SLIDER>`, and no script in any of them ever writes one. That is the
  corpus's own seek bar, the way the Plus!, Xbox, Alienware, BlueCrush, Halo and Catwoman families
  all write it, and `positionSliderPaths` reads it: a control whose far end is the end of the track
  *is* a position control. Without it the filmstrip sat on frame 0 for the length of the track and
  the digit strips a skin positions from `value_onchange` sat with it — reported as "the clock does
  not work and seek does not work" and measured, seeded, as 68 rows across 52 skins moving off
  frame 0. **The other half of that report is the same slider read from the other direction (W51): a
  control is bound both ways, so the *host* moving it raises `value_onchange` too.** The user-driven
  half closed with W52; this is how a seek bar's readout follows playback and how a preset moving
  ten gains re-runs each band's handler. `Catwoman` draws its clock as four digit filmstrips
  positioned by `value_onchange="drawSeekDigits(value)"`, so until the handler was raised the slider
  tracked the song and the clock sat at zero. Two things make it safe rather than a feedback loop,
  and both were measured before it was written: **the registry only reports values that actually
  moved**, so a write-back handler (`eq.gainLevel1=value`, 2,141 of the 2,488 host-bound sliders
  carry one) hands the host the number it just gave and produces an identical snapshot; and **every
  one of the 19 handlers on a position-bound slider is a readout painter** — `drawSeekDigits(value)`
  ×17, `DrawTimeNormalView(value)`, `seek2.value=seek.value` — so nothing re-seeks. It is bounded
  like the two cascades beside it: only what the markup authored, only `value`, once per element per
  transaction, raised *before* the completion and geometry cascades so a repaint that writes
  geometry still propagates in the same frame. Its side effect is honest new demand rather than
  regression: 42 handlers that never ran now run and 30 of them abort on `event.shiftKey`, an
  **`event` object in a handler** that nothing binds on either direction of `change`. **The audio was never wrong** here —
  `AudioEngine.balance` defaults to centre and `performSlider` already wrote `fraction × 2 − 1` — so
  the whole defect was a drawn thumb lying about a centred pan, and no sweep of default-state images
  could have called it one.
- **A slider is a track plus a thumb the scene places**, and `WMPSliderMetrics` owns that geometry
  alone so each of its rules is testable: `borderSize` is dead track at *both* ends (171 skins),
  a **vertical** slider's maximum is at the **top** (1,312 of 1,968 `direction` attributes are
  vertical — every equaliser band is one), and the same metrics read the pointer back so a drag runs
  along the axis the skin authored. `foregroundImage` is the filled part of the track, cropped
  rather than scaled, and `useForegroundProgress="true"` (46 skins) redirects that fill to
  `foregroundProgress` — a buffer bar behind a thumb showing position, which are different numbers.
- **A `.wmz` says where a slider writes by binding its value, not by choosing a tag.** 163 skins
  author a plain `<SLIDER value="wmpprop:player.settings.volume">` rather than `<VOLUMESLIDER>`, so
  `WMPTransportAction.boundAction` maps the declared `wmpprop:` path to the action. Adding a bindable
  host property means adding it to `WMPObservablePropertyRegistry` *and* deciding whether writing it
  back is an action — one without the other is a control that moves and does nothing.
- **`EQUALIZERSETTINGS` is a settings object, not a control.** 163 skins author it and none give it
  geometry; the skin's own ten bound sliders *are* the equaliser. It is `isNonLayout`, like
  `<player>` and `<network>`.
- **`alphaBlend` is 0-255, inherits down the subtree, and 717 of its 778 corpus uses are `"0"`** —
  an element the skin hides and fades in later. A zero-alpha node still lays out, so its geometry
  stays readable, but it must not reach the command list at all: leaving it there put invisible
  artwork inside `visibleBounds` and every dirty rect derived from it. Honouring it changed what
  several skins draw, because the engine had been painting the topmost of eight stacked shells
  rather than the one authored visible — and it makes `alphaBlendTo` (W38) load-bearing, since a
  skin that fades its own panels in now shows less until that lands.
- **`passthrough="true"` (82 skins) is drawn and never hit.** A decorative overlay registered as a
  hit target swallows the controls beneath it.
- **`TEXT` reads `fontFace`, not `fontType`** — 109 skins against 21 — and `fontStyle` is a *set*
  (`"UNDERLINE, bold"` is authored), not one word. `fontSmoothing="false"` (95 skins) is a readout
  drawn as pixels; antialiasing it turns a 6 px digit into grey mush.
- **A `CUSTOMSLIDER` is the size of its `positionImage`, and its `image` is a filmstrip.** This was
  read out of the art rather than assumed, and `WMPPositionMap` carries the evidence:
  `ALXMorph/seek_map.png` is 86x10 whose columns step 0, 2, 5 … 252 — a **greyscale ramp whose
  luminance is the fraction** — against a `seek.png` of 86x600, sixty frames stacked vertically;
  its `volume_map.png` is a 72x38 arc against a 2232x38 strip of thirty-one frames laid out
  horizontally. So the strip's axis comes from whichever one is a whole multiple of the map, the
  value picks the frame, and a drag reads its value out of the map — which is the whole point of the
  element: its track need not be a straight line. Sizing one from `image` makes it 2,232 px wide.
- **Which end of a filmstrip is the minimum is a property of the art, not of the markup.** The
  corpus authors both orders against identical markup: `Catwoman/srs_slider.png` fills downward
  across 18 frames and `Halo 2/srs_slider.png` — the same control, the same left-to-right `0…251`
  map, the same `min="0" max="100"` — runs the other way, frame 0 all thirteen segments lit and
  frame 13 empty. So the *map* answers which end of the control is the minimum and the *art*
  answers which end of the strip is, separately. `WMPImageStore.filmstripIsDescending` measures it
  two ways — lit coverage for a fill bar, centre-of-mass travel along `WMPPositionMap.gradient()`
  for a moving thumb — and selects **19 of the 342 stripped `CUSTOMSLIDER`s across 7 skins**, every
  one of the 6 travel-selected ones a Halo 2 or STALKER control. Indexing Halo 2 forwards drew one
  segment for a TruBass of 95 and the full bar for 0 while the audio followed the pointer: reported
  as *"the SRS WOW effect and TruBass level controls do not fire correctly"*.
- **A host change the skin drove through its own command still has to settle its own bindings.**
  `eq.*` is the one host surface a `.wmz` both writes and binds. Halo 2's SRS button posts
  `eq.enhancedAudio = !eq.enhancedAudio` and its TruBass and WOW sliders carry
  `enabled="wmpprop:eq.enhancedAudio"`, so the transaction that flipped it resolved that binding
  against the snapshot it started with — `false` — and nothing re-resolved it: the sliders drew and
  hit testing refused every click on them. With a track playing the clock tick settled them a tenth
  of a second later and they worked, which is what "sometimes" meant in the report.
  `refreshHostState` now diffs `equalizer`, and `dispatchScriptTransaction` re-settles at scope exit
  when its own commands moved the snapshot. Every other host surface was already covered because
  each of its edges is an event there.
- **The binding-only host tick is `hostsettle`, and it used to be `positionchange`, which was not
  free.** `onPositionChange` is the `CUSTOMSLIDER` handler WMP raises when the **user** moves the
  control, and **24 of the 180 installed archives author 71 of them** — every `srs_slider` and `eq`
  slider in the Halo 2, STALKER, Catwoman, Alienware and Plus! families. `handlers(in:event:)`
  strips the `on` prefix, so the name a clock tick raised was the name those handlers answer to. It
  was inert only because `onpositionchange` is not in `WMPAttributeValue.handlerNames`; registering
  it without renaming the tick would have run all 71 ten times a second with `value` unbound. Pick a
  tick name no archive authors, and check that it is one.
- **`clippingImage` shapes an element, and it is what makes a shaped window shaped.** 172 corpus
  nodes author a non-empty one and 169 of them declare a `clippingColor` beside it, which is what
  the mask keys out. Before it, `TDK`, `elvis`, `Secura`, `portals` and the six `US *` service skins
  all drew a black or grey rectangle behind their round artwork.
  - **A `clippingImage` with no key beside it takes the mask's own corner (W171).** The three
    exceptions to the count above name a mask and no key at all — `Plus! HueShifter`'s
    `body_lower.jpg` group, `Charlies_Angels_Full_Throttle`'s `visEffects`, `gnome`'s `myeffects2` —
    and all three masks are **fully opaque**, so reading that as "no key" left `clippingMask`'s
    source-alpha test keeping every pixel and the node drew its whole rectangle. On HueShifter that
    was `body_lower.jpg`, a 213x66 lavender plate boxed hard-edged across the bottom of the player
    with the skin's green bottom candy behind it. The colour is the mask's corner — the same
    derivation `auto` uses, and white in all three files, which is the `clippingColor="white"` their
    sibling layers state by hand. **Only for a mask with no transparency of its own**: one that
    authored alpha has already said what it cuts, and a corner key would cut it twice.
  - **`clippingColor` keys the *clipping image*, never the node's own artwork (W169).** The two keys
    were read as one list, which is harmless while they name the same colour and destructive when
    they do not — and it is the largest single defect this engine has had by reach. A JPEG keys with
    `WMPColorKey.jpegComponentTolerance`, so on the skins writing `clippingColor="white"` every tone
    within 64 components of white was deleted from the picture: **`Plus! Plasma Ball`'s
    `eq_panel_normal.jpg` 85.7% of its pixels, `Plus! HueShifter`'s `hueshifter_top.bmp` 76%,
    `Plus! SlimLine`'s `perfect_body_normal.jpg` 47.5%, `TDK`'s `info_bg.jpg` 52.1%, `elvis`'s
    `elvis_tray.jpg` 39%, and `Plus! Hard Boiled`'s `Egg_Body_Normal.jpg` 27%.** Reported as *"you
    made the high res graphics low res"* and then *"fix the other skins that were addressed with plus
    egg commit"*, and **W160 had already chased the same pixels as a resampling defect** — a quarter
    of the egg was not being upscaled badly, it was being erased. A node with no `clippingImage`
    keeps the old reading, because there `clippingColor` is the only thing shaping it. Measure the
    class by keying each node's artwork against its own declared clipping colour at the format's
    tolerance and reporting the share hit; 13 of 535 corpus views move and every one is a gain.
  - **`clippingColor="auto"` is a colour, not an absence (W167).** Four declarations across three
    archives — `Plus! Plasma Ball` twice, `Compact` and `digitaldj` once each — and the parser
    rejecting the word is not the same thing as the author declaring no key. `Plus! Plasma Ball`'s
    `mainButtons` states `clippingImage="screen_MASK.gif" clippingColor="auto"` over a mask with
    **zero** transparent pixels, so an unresolved key cut nothing and the whole 242x299
    `screen_normal.jpg` drew opaque over the plasma globe — reported as *"a gray box background"*.
    WMP takes it from the bitmap the declaration governs and the corner is where all four authors
    put it: `screen_MASK.gif` and `playlist_vid_panel_MASK.gif` are white at 0,0, the same
    `clippingColor="white"` their four sibling layers in the same file state by hand, and
    `digitaldj/preview.bmp` is `#FF0000` there over 10% of the file. `clippingColor` reads the
    clipping image, every other key the node's own artwork; `WMPImageStore.cornerColor` is nil for a
    corner that is already transparent, because a file that authored its own alpha has said what is
    see-through and there is no matte to infer.
- **A clipping shape shapes the element's *contents*, not only the element (W168).** A `<SUBVIEW>`
  or `<VIEW>` in WMP is a window region and its children are inside it, so every paint command in
  the subtree carries its ancestors' shapes (`WMPSceneClipMask`, applied against the *container's*
  frame rather than the command's). `Combat_Flight_Simulator_3` hangs its whole 584x321 body off
  `<subview id="mainBody" backgroundImage="main_bg_mask.png" clippingColor="#ffffff">` and draws
  `main_bg.jpg` inside it as a child that declares **no key of its own** — so the flat `#88A4B9`
  matte filling 67% of that JPEG had nothing to cut it away and the window was a rectangular slab.
  `Melvin` is the same rule seen the other way: its two eye sockets are `clip.gif` subviews, and
  before the shape reached their children a head-coloured sibling covered both eyes.
  - **`transparencyColor` states the shape too, on the background-image path only (W172).** A
    `<SUBVIEW>` whose whole ground *is* a two-tone mask has said the same thing whichever attribute
    names the key. `Plus! HueShifter` writes `transparencyColor` on all five of its subviews over
    `body_Mask.gif`, `playlist_tray_wholemask.gif`, `eq_tray_wholemask.gif`,
    `video_tray_wholeMASK.bmp` and `body_lower_wholeMASK.gif`, and reading only `clippingColor` left
    every one of them a plain rectangle: its bottom candy hung 22 px below the player's silhouette
    and the body's own edge was fringed with keying speckle, because `bodyNormalMask.gif` is a
    dithered 254-colour GIF whose white region carries 2,108 px of near-white noise. **127 nodes
    across 17 archives qualify**, every one naming a file `…mask`, under the same three guards —
    untiled, authored at the node's own size, two-toned. `clippingImage` is deliberately **not**
    widened the same way: a node that names a mask file outright has one key attribute for it.
    **Cerulean is not this case and never was** — its `face.bmp` subview writes
    `clippingColor="#FF0000"` beside `transparencyColor="#FF00FF"`, so the shape comes from the
    clipping colour either way, and the bitmap is 18,601 colours, which `isShapeMask` rejects. The
    rule that said otherwise cited Cerulean and was wrong on its own evidence.
  - **A container's shape is a *region*, not a clipping image (W172).** `WMPSceneClipMask` renders
    through `regionMask` — in the region wherever the pixel is not the key, **whatever its alpha**.
    The two readings differ only on a mask that carries transparency of its own, and there the
    difference is total: `Ice`'s `Clip.png` is 379x183 in exactly two values, 17,558 px of opaque
    `#FF00FF` outside the player and 51,799 px of **alpha-zero** white over it, so honouring the
    mask's own alpha cut the keep region and the key alike and both of its `Frost` layers vanished.
    Every other mask in the corpus is opaque and reads the same either way. A `<BUTTONGROUP>`'s own
    `clippingImage` still honours alpha — that is an authored mask bitmap, not a container's ground.
  - **A `backgroundImage` is a shape only when it is untiled, authored at the node's own size, and
    two-toned.** 84 `<SUBVIEW>`s across 38 archives and 26 `<VIEW>`s across 17 declare a
    `clippingColor` with no `clippingImage`, and they are two authoring idioms the attribute cannot
    tell apart. *A mask*: `main_bg_mask.png` is 584x321 in three colours — 71% white, 29% black, one
    stray pixel. *Artwork with a keyed hole*: `YIL!OMA2K`'s `yMain Body.bmp` is 530x440 in **34,688**
    colours with a 246x179 rectangle of `#6699FF` cut out for the video and a `<subview zIndex="-2">`
    of solid black parked behind the body to show through it — shaping children by that clips the
    backdrop away and leaves the display empty. `WMPImageStore.isShapeMask` asks the question as a
    *share* rather than a colour count, because a mask's own edges are antialiased:
    `main_vismask.png` is 10 colours at 100.0% in its top two. The size and tiling test is
    `Gorillaz`: its `noodle` view is 781x467 over a `background.gif` that is a 50x28 swatch of solid
    `#33CC66` with `backgroundTiled="true"`, and its `clippingColor="#33CC66"` says *my ground is
    invisible*, not *my window is empty* — reading the tile as a shape erased the whole skin, all
    143,248 px of it, and it was the only total loss this rule produced anywhere in the corpus.
- **A mask buffer's row zero is the authored top row.** A `CGImage` drawn into a bitmap context
  arrives that way round — `WMPMappingImage` says so in as many words — so "correcting for
  CoreGraphics" by reversing the rows mirrors the mask and clips the half it should keep. That is
  W47 arriving by a second route, and only a **top/bottom** fixture can see it: a left/right one is
  identical under a vertical flip, and so is a horizontal position ramp.
- **`cursor` names a shape, not a file, in 2,246 of its 2,319 non-empty uses.** Classifying them all
  as artwork made every named cursor a *missing bitmap* (`BITMAPS … missing=hand sizenwse` across
  145 skins) and hid the name from the builder, which reads literals. `WMPAttributeParser` decides
  from the value; the ~70 `.cur`/`.ani` files stay resources and resolve to no cursor (W67).
- **Animation lives in the renderer, not the scene.** `WMPRenderer.render(clock:)` picks the frame,
  so a 10 fps GIF costs a re-render rather than a rebuild — a rebuild runs the skin's script
  transaction, which must not happen ten times a second. 90 of the 180 archives carry a multi-frame
  GIF (2,166 files). `animationCadence(for:)` gives the repaint loop its period *and* the union of
  only the animated frames, because repainting a whole window for one blinking LED is the difference
  between a skin that animates and one that burns a core. **A render dump is a still, so without
  `WMP_RENDER_CLOCK` an animation is unfalsifiable** — frame zero looks exactly like an engine that
  never animates.
- **The rate a user sees is not the rate `ANIMATION` reports, and nothing headless can tell them
  apart (W142).** Reported live as "the animation fps is low in general". `WMP_ANIM_TRACE=1`
  separated two independent causes on its first line — `want=25.0fps got=20.0fps frames=21
  restarts=10 sleep=42.3ms render=4.5ms` — and both are about *when* a frame is drawn, so a dump,
  a cadence line and a corpus sweep are all blind to them. **It also closed W69, the one reported
  *flicker*, and that is the row's sharpest lesson.** `Xbox Live Skin`'s 145-frame intro was filed
  with three written-down compositing candidates — a whole-`NSImage` replacement against a sub-rect
  invalidation, an animated `bounds` union computed once, and a 64 MiB LRU thrashing — and **none of
  them was implemented, because none of them was the cause.** Frames arriving at an irregular rate
  look exactly like a bad composite. Suspect the clock before the compositor whenever the symptom is
  a picture that will not settle; confirmed gone live on 2026-09-12.
  * **A rebuild must not restart the repaint loop.** `startAnimation` runs on every rebuild and a
    `.wmz` rebuilds constantly — AlienMorph's 100 ms view timer alone restarted it ten times a
    second — and each cancel discarded a partly-elapsed sleep, so a 40 ms frame period inside a
    100 ms rebuild window landed exactly two frames per window. The loop now keeps running while
    `WMPViewPresentation.animationCadence` compares equal to the new one, and renders
    `activeScene` rather than the scene it was started with: a rebuild replaces *what* it draws
    without interrupting *when*. **That equality is the fix**, so anything that makes an unchanged
    animation produce an unequal cadence silently restores the defect.
  * **Frames are scheduled against the animation epoch, not "now + period".** `Task.sleep`
    overshoots and the render after it is serial, so a period per frame accumulated both into
    every interval. Deadlines off the epoch absorb them and are the same clock
    `WMPImageAnimation.frame(at:)` picks a frame with; falling a whole period behind skips to the
    next boundary rather than bursting.
- **A GIF delay of 0 or 1 cs means "as fast as possible", and the browser's answer to it is not
  this corpus's answer (W142).** `WMPImageStore.animationFloor` floors them at 0.0667s (15 fps);
  the browser convention of 0.1s was the largest single cause of "the animations are slow".
  **768 of the 2,166 multi-frame GIFs, across 62 of the 90 skins that animate, author a minimum
  delay of 0 or 1 cs, and 625 of those author nothing else** — at 0.1s `AlienMorph`'s 119-frame
  shutter took 11.9 seconds to open. **679 of the 768 are one-shot**, so this number is choosing
  how long a *transition* takes, not how fast a loop spins, and only one endless corpus GIF is
  short enough for the rate to read as a flicker. The floor itself is set **by eye against the
  running app** and there is no measurement that can set it — the file said "as fast as possible".
  0.04s was tried first, argued from the delays the corpus authors when it names one, and was
  reported too fast on sight. Do not re-derive it from the corpus; that argument is what produced
  0.04.
- **A `<POPUP>` is an equaliser preset menu and its items come from the skin's own script.** All four
  corpus popups call `appendItem` in an `onLoad` and apply the choice through
  `eq.currentPreset`; `WMPScriptOutput.listItems` carries them out of the transaction, because the
  markup names none of them. The four hardcoded entries that used to be shown were in no skin.
- **An `<EDITBOX>`'s `value` is a string.** Nine of the corpus's ten are `plSearchEdit`, a playlist
  search field whose `onKeyUp` reads it straight back, so it needs its own text path
  (`setWidgetText`) rather than the numeric `setWidgetValue`.

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
  own artwork is gone (W9). WMP plug-ins, ActiveX, DLLs, and arbitrary media surfaces remain denied.
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
