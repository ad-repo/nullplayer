# `.wmz` windows: the skin's own, and NullPlayer's beside it

Moved verbatim from `SKILL.md` on 2026-09-24. Read `SKILL.md` first; its isolation rule binds every
section here.

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
- **Where the skin lends no frame, the window has no title bar and wears the gloss frame
  (2026-09-25).** The reporter's words: no title bar, *"similar to original no titlebars"*, no
  setting, keep the top-right close, and — because *"the skins all have shine to them"* — glossy, in
  *"the theme colors"*. `SkinnedSurfaceChrome.hidesPaletteTitleBar` is the gate (the WMP family,
  never a flag); `paletteMetrics` turns every fallback into a uniform `glossBorder` (6pt), and
  layout, drawing and `HostedWindowBorderLayout` all read it so the three agree.
  `drawGlossFrame` is the one painter: a rounded rim graded light-to-dark from the palette's
  `barBackground`, a white sheen and specular edge, the outline in `style.border` unaltered, an inset
  shadow at the hole. The spectrum family and Sonos reach it through `drawSpectrumFamilyWindow`; the
  playlist, library and EQ call it from their own palette painters. The close is the same
  un-drawn 40×26 corner hit area a borrowed frame gets (`closeButtonRect`), so views whose content
  is a subview that eats clicks (Audio Analyzer's SwiftUI panes, Sonos's status line) override
  `hitTest` to claim it; the library moves its server-bar right-edge items in by `cornerCloseInset`.
  The EQ is a fixed 275x116 layout, so its old band stays as ground inside a thinner rim.
  `hostedGroundRect` returns the gloss hole, not `bounds`: PeppyMeter (and Cava, Flow) paint their
  ground through it, and a full-window fill showed as square black corners outside the rounded rim. `.wal`
  shares every one of these painters and is unchanged — the gate is false there.
- Borrowed rings use whole-donor rendering with subtraction; fixed panels use nine-slicing.
- **A ring wears the colour the donor's own `onLoad` chose, not its markup's (W145).** `xsn_sports`
  stacks eight colours of its frame in `plView` and reveals one from `htcpStartupPl()` by writing
  `alphaBlend`, keyed on its `htcpID` preference, which its own colour cycle rewrites every few
  seconds. `WMPHostedFrameProvider.refreshScriptedAppearance` runs the donor's `load` in a throwaway
  `WMPScriptRuntime` over `WMPPreferenceStore(copying:)` — a copy, because `loadPlPrefs()` saves
  `plViewer = "true"` and that write must not reach the session — and keeps only `alphaBlend` and
  `backgroundImage` on nodes the frame does not subtract (`WMPHostedFrameTemplate.appearing`):
  colour, never layout. It runs before `stage` at skin load and again from the runtime's
  `setPreferencesChangedHandler`, one run at a time, and rebuilds only when the appearance moved,
  through the staged switch below — so our windows change colour with the skin, in one step, with no
  cross-fade. Cost with a hosted window open and the cycle running: one ring render per open window
  per colour change (~200 ms each, off the main thread). `WMP_FRAME_APPEARANCE=0` is the A/B switch.
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
  returns the nearest render of the **current** skin *re-laid out* (`WMPHostedFrameRelayout`) —
  never a proportional stretch, and with no distance limit; see *A hosted window never shows a
  transitional state* below. `wasScaledToFit` is not a readiness flag.
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
  words were *"it loaded chrome and then the skin with no resize"*. **The 15% half is superseded
  (2026-09-23)**: a stand-in is now re-laid out rather than stretched, so it needs no tolerance —
  see *A hosted window never shows a transitional state*. The presize half stands.
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
- **The player itself is held transparent until the first skin load settles (2026-09-24).** Reported
  as *on launch into WMP mode the unskinned player shows for a second or two*. `init` presents
  `WMPUnskinnedMainView` so the window has content, and the launch path orders it front at once —
  several callers through `window.makeKeyAndOrderFront`, not `showWindow` — so the hold is
  `alphaValue = 0` on the window, not a guard on any one reveal. `releaseLaunchHold` ends it on the
  skin (after the view walk presents), on a missing or failed selection (which *want* the unskinned
  player), or on a 5 s timeout so a load that never returns cannot leave the app windowless. It is
  once per controller: a later skin switch never touches the alpha, which `WMPVideoSurface` also
  owns. The same launch surfaced the **fallback playlist and equalizer** — restored open, they were
  shown before the skin had said it draws its own, and stood beside the hidden player until
  `dismissWMPFallbackSurfacesTheSkinProvides` put them away. `showPlaylist`/`showEqualizer` now hand
  their open to `WMPMainWindowController.deferUntilLaunchSettles` during the hold, and it is replayed
  on release, where `routeWMPSkinSurface` routes it to the skin's copy. Checked on `pharaoh` with a
  `screencapture` every ~0.2 s from launch: nothing on screen until skin and library appear together.
- **A hosted window never shows a transitional state — not during a drag, not across a skin switch
  (2026-09-23).** Reported as *resizing any `.wmz`-framed window goes skin → palette chrome → skin,
  and after a skin change a resize can leave windows wearing the previous skin*. Four causes, all
  confirmed by `WMP_FRAME_TRACE` before the fix, and one answer each:
  - **Every drag pixel started its own full donor render, all at once.** ~30 concurrent builds on
    `ALXVortex`, each 2–4.7 s instead of 0.3–1.3 s alone, finishing out of order, each posting
    `hostedSurfaceStyleDidChange`. **The drag is now a signal**: `HostedWindowBorderLayout` tells the
    provider when a hosted window starts and stops being dragged (`hostedSurfaceLiveResize`, a
    `.wmp`-only family switch), and while one is, a miss queues **one build at a time**, the latest
    size waiting behind the one in flight. The end of the drag `demand`s the size it came to rest
    at, and the prewarm is skipped mid-drag (it would name the drag's passing size).
    **NullPlayer's windows are `ResizableWindow`s, which resize by hand and never enter AppKit's
    live resize** — `willStartLiveResizeNotification` is never posted for them. `ResizableWindow`
    posts `.windowEdgeResizeDidBegin`/`DidEnd` itself; the layout listens to both families.
  - **The stand-in was one stretched global slot, refused past 15%** — and a drag crosses 15% in
    a few pixels, so the window drew palette chrome until a build landed: the flicker. **The
    stand-in is now the nearest render of the current skin, re-laid out** (`WMPHostedFrameRelayout`):
    each axis is cut once per half, inside the longest run of columns (rows) that match their
    neighbour across the border bands — where the skin stretches or spans an edge piece — and
    grown by repeating a column there or shrunk by removing columns there. Everything else is
    copied 1:1, so the border keeps its thickness, corners and edge-anchored details stay put, and
    a centred ornament stays centred. **Not cut at the client-hole insets**: these corners are
    decorative and run far past the border (190pt on `Halo 2`), and a slice at the insets
    stretches half of each corner. No tolerance applies, because nothing distorts. The measuring
    seam (`renderedArtwork`) never sees a relaid frame.
  - **The old skin's frames (W248's `outgoing`) were never retired.** Borders differ between skins,
    so windows land points off their old size and the entry stayed for the session, checked
    *before* anything else within 15% — any later miss near an old size drew the previous skin.
    `outgoing` is **gone**, replaced by the staged switch below.
  - **A drag evicted the resting windows' frames** (`cacheLimit = 12`). Drag sizes are now
    `transient`: evicted first, and dropped when the drag ends except the final one.

  **The staged switch.** `configure` no longer retires the old skin the moment the new one
  arrives. When a hosted window is on screen (`hasVisibleHostedWindows` — held windows at alpha 0
  do not count, so a launch is not delayed), the new skin is built in a `staged` slot: insets first,
  then — serially — the size every open hosted window will be under the new border
  (`HostedWindowBorderLayout.openTargets(border:)`), while the live slot keeps answering with the old
  skin's exact frames. **The player joins it**: `WMPMainWindowController` awaits
  `hostedFrames.stage(skin:playerViewID:)` after rendering the player's scene and before
  materializing it, so the old player stays up too, and the `configure` from that same present
  **commits** — slot swap, new `donorInsets`, one `hostedSurfaceStyleDidChange`, whose `apply()`
  resizes every window to exactly the size that was pre-rendered. A present that was not staged
  (a view switch) stages in the background and commits itself. A skin lending no frame commits
  at once. Budget: `WMP_HOSTED_HOLD_MS` (default 4000), then `commit reason=budget`, which is the
  switch failing. Each slot is an object a build captures, so a render landing after its skin is
  gone is dropped by identity — no generation counter.
  **`hostedSurfaceBordersAreSettled` reads true during a switch while the live skin still lends a
  frame**, because what is on screen is that skin with its own border; a drag during staging is
  read against it (or the next `apply()` would put the window back), and its end size is added to
  the staged targets.

  Measured on `ALXVortex`, library dragged 180pt, screen captured every ~55 ms: before, **1004**
  `standin=out-of-scale` (chrome) and 749 stretched frames from ~30 concurrent builds; after,
  **0 / 0**, every miss `standin=relaid`, **2** serial builds. AlienMorph → ALXVortex then a drag:
  **451** `standin=outgoing` before, 0 after. The switch itself with library, Cava and Spectrum
  open: `commit reason=ready ms=1953`, and every window — player included — changes in the **same
  capture**. `WMP_FRAME_LIVE_RESIZE=0` restores the flicker in the same binary (1032 chrome, 900
  stretched, 24 builds). **Residual, unmeasured across the corpus:** a half with no uniform run
  (a tiled or noisy edge) is cut at its middle, and the exact render replacing the relaid one can
  shift detail there. `ALXVortex`'s relaid mid-drag frame matched its exact render by eye; if a
  skin shows a snap when a drag ends, compare a `WMP_HOSTED_FRAME_DUMP` of the rest size against a
  capture taken mid-drag at that size.
- **The stand-in is primed before any window opens, so a first open is never unskinned (W230).**
  Learning a ring donor's borders *is* composing a ring — `WMPHostedFrameTemplate.border` does it at
  the reference size when the skin loads — and the composition used to be discarded, so the first
  hosted window found `mostRecent` nil, was answered no artwork, and drew palette chrome until a
  render at its own size landed. It is now adopted as `mostRecent`, never into `cache`: a cache hit
  promises the frame was built for the size asked for, and this one was built for the donor's.
  **Rings only** — a panel's borders are four constants of its own bitmap, read without composing
  anything. The primed ring is now re-laid out to a window rather than stretched onto it. The current static frame probe does not exercise live
  child composition or animation; verify those through live-host captures.

**Every rule above is a rule each hosting view has to apply for itself, and that is the standing
weakness of this contract.** Relayout on artwork arrival, the correct ground fill, the overlay
policy, the metrics, the growth registration — each is centralised as a value or a helper and each
remains *optional at the call site*. Flow, Cava and PeppyMeter each carry their own borrowed-frame
fast path; the library computes its content rectangle somewhere else again. A frame dump can be
clean while the window is wrong, so nothing headless catches a view that simply did not call.
When a hosted defect reproduces on several windows at once, suspect the call sites before the frame.

**Rejected approach, 2026-09-18: the hosted-window container.** The
[architecture analysis](../../../docs/wmp-skin/hosted-window-architecture-analysis.md) first proposed a
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
  artwork, re-laid out from the nearest render rather than scaled. `wasScaledToFit`
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
  is otherwise the signature of that window's own layout (`reference/harness.md` § *Capturing the hosted windows*).
- **A rail that is mostly hole is still a rail, and a stretch baseline read through an expression
  is read at the authored canvas (2026-09-23).** Two defects kept `Back to the Future Trilogy`'s
  right edge bare on any window taller than about 300pt, and 21 skins' bottom bars bare on tall
  windows. `authoredDimension` read `height="jscript:view.height"` at the live canvas, so a
  `stretch` child of that container never grew; that bug was in the skin's own window too. And
  `ringRender`'s furniture test dropped wide side tiles that carry the list's colour baked in
  beside a thin rail. A bitmap subview authored to stretch along a side that runs out past the
  hole is now kept (`railsDownNodeIDs`/`railsAcrossNodeIDs`). **Probe a hosted frame at a tall
  size, not only at 357x238 and 550x464**: a script- or expression-sized rail's bare run grows
  with height and is invisible below it. The measurements are in
  [the dossier](skins/back-to-the-future-trilogy.md).
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
   covers the ring. With no frame lent the window is titleless (§ *Current hosting contract*): read
   the fallback through `SkinnedSurfaceChrome.paletteMetrics`, and make sure the corner close hit
   area wins over any subview under it.
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
   `screencapture` of the live window are the instruments — `SKILL.md` § *Debugging a live defect*.

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
  distinct marks: the highlight bar is `selectedRows` (the user's selection; `selectedIndex` is only the
  arrow-key cursor inside it — see W272 below) and the `▶` prefix plus
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
- **The pane's right-click is NullPlayer's own playlist menu, because no skin authors one (W272).**
  WMP skins left queue management to WMP's own menus, so the corpus draws no Remove/Sort/Clear
  controls against a `<PLAYLIST>`. `WMPPlaylistSurfaceView.menu(for:)` returns
  `PlaylistMenuBuilder`'s menu (`App/PlaylistMenuBuilder.swift`), the one the Modern playlist shows —
  lifted into `App/` because this engine may not reach into `ModernPlaylistView`, and the Modern
  view now builds its menu there too. Queue edits go straight to `WindowManager.shared.audioEngine`,
  as the Modern playlist's do; the next host refresh redraws the rows. Four rules hold it:
  - **The selection is a set.** `selectedRows` takes Shift-click (a range from `selectionAnchor`),
    Cmd-click (toggle) and Shift+↑/↓, so Remove, Crop and Invert act on more than one row; Delete
    removes every selected row, highest index first. `selectedIndex` stays the cursor.
  - **One highlighted row follows the playing track; several do not.** The `nvidia` rule above
    re-homes a selection of one row on a track change. A selection of several is the user's and
    survives it — otherwise the next track change would shrink it to one before the menu acted.
    An empty selection (Select None) is not re-seeded by a refresh either: only a cursor of `-1`
    (first load, a new library list) seeds from the playing row.
  - **A library preview is read-only (W136).** While the pane shows a library playlist every row that
    edits the queue is disabled; Play and the selection rows still apply to what the pane shows.
  - **The pane's menu sets `autoenablesItems = false`; the Modern playlist's keeps the default.**
    Neither view validates these rows, so under AppKit's default every row with an implemented action
    is enabled and `isEnabled` is ignored — which is how the Modern playlist has always behaved, and
    the builder keeps it. The pane needs its disabled rows to hold, so it opts out.
  A right-click on an unselected row selects that row alone first; on a selected row it keeps the
  selection. Verified live 2026-09-24; `WMPPlaylistMenuTests`. **A contextual menu cannot be driven
  synthetically** (`app-control` Route D), so verify a change here with the user driving.
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

**A drag reaches the screen top with the skin's first drawn row, not its frame (W303).** A `.wmz`
frame keeps transparent room for drawers — `Alpine7618_v09`'s 412-tall view draws only its bottom
~150 while they are shut — and both AppKit's `constrainFrameRect` (which clamps even a borderless
window) and `applySnapping`'s hard clamp measured the frame, parking the faceplate ~260 pt down.
`WMPMainView.transparentTopInset` is the empty rows read off the composite on a full or structural
present; `WMPSkinWindow.constrainFrameRect` and `WindowManager.transparentTopOverhang` (zero for
every window that is not a `WMPSkinWindow`, so no other family moves) let that much hang above the
visible top, and the top snap aligns the drawn top. When the inset shrinks — a drawer opening into
the hidden part — the view re-constrains the window down. **The recovery sweep below still judges the
frame's corner**, so a session restored or a display changed with the window parked up there brings
it back down to frame-top; that was left alone deliberately.

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
`SKILL.md` § *Debugging a live defect*.

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
`defaults write NullPlayer rememberStateEnabled -bool true` and launch with `launch.sh <skin> --restore`
(restoration is off in every other launch, which is exactly why this class was invisible), size the window with
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

### Raising the skin's windows together (W273, closed 2026-09-25)

**Clicking any NullPlayer window raises every one of them, a skin's `theme.openView` panels
included, with the clicked window on top.** `WindowManager.bringAllWindowsToFront` raises a fixed
list of NullPlayer's controllers. The panels are not controllers, so `WindowManager.raiseOrder`
appends `materializedAuxiliaryWindows` after that list, in the order the skin opened them. It does
this in `.wmz` only; every other family raises the list unchanged. Before this, clicking `WoW`'s
player left its EQ, vis and info panels behind whatever other app covered them.

Adding the panels to the list was not enough, and the live loop showed why. With a cover window from
another app over the player's edge and two panels, a click on the player ran the raise with the
right list and a nil key window, because the activation had not settled. The window server applied
only some of the reorders: the panels stayed under the cover. Two changes fix it, both limited to
WMP:

- **Both WMP `windowDidBecomeKey`s defer the raise one main-loop turn** (in `WMPMainWindowController`
  and `WMPViewWindowMaterializer`). The deferred call runs only if its window is still key.
- **In `.wmz`, the raise orders the other windows front with `orderFrontRegardless`**; the clicked
  window keeps `orderFront`. Deferral alone still left the panels behind the cover, while the key
  window, the list and the ordering were all correct in `NSApp.orderedWindows` immediately after
  the raise. `orderFrontRegardless` is what put them on top, confirmed by pixels.

What the live check showed, so it isn't re-investigated:

- **A docked panel sits above the player in the window list.** `updateDockedChildWindows` makes
  every docked window a child of the main window, and AppKit keeps a child above its parent. This
  is true in every mode, and docked windows don't overlap, so it can't be seen on screen.
- **Z-order between windows that don't overlap has no visible effect.** `NSApp.orderedWindows`
  settled 0.3 s after the raise with the panels above the player. That order is harmless, because
  the panels don't overlap the player. **Judge a raise by sampling pixels where a cover window
  overlaps each window, never by the window list alone.**
- **Covering the test area with your own windows is dangerous**: a click meant for the player
  landed on a Finder sidebar and navigated the reporter's window. Use a throwaway cover window
  (a 15-line `NSWindow` script) and hide other apps (`set visible of process … to false`), which
  leaves their state untouched.

The ordering itself needs a window server, so `WMPWindowRaiseTests` pins only the gate and the list.

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
