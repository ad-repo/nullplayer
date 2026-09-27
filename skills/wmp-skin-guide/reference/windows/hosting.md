# `.wmz` windows: the hosting contract

Moved verbatim from `reference/windows.md` on 2026-09-25; that file is the router. Read it first.

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
  unconditionally. Its chrome (`SonosWindowChrome`) branches on `SkinnedSurfaceChrome.hidesPaletteTitleBar`
  ahead of the `.wal` palette: `.wmz`, and since 2026-09-26 `.wal` once its palette has loaded, take
  the titleless gloss path; Classic and Original never reach it. Reported 2026-09-23 as the
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
  and since 2026-09-26 `.wal` once its palette has loaded — never a flag); `paletteMetrics` turns every fallback into a uniform `glossBorder` (6pt), and
  layout, drawing and `HostedWindowBorderLayout` all read it so the three agree.
  `drawGlossFrame` is the one painter: a rounded rim graded light-to-dark from the palette's
  `barBackground`, a white sheen and specular edge, the outline in `style.border` unaltered, an inset
  shadow at the hole. The spectrum family and Sonos reach it through `drawSpectrumFamilyWindow`; the
  playlist, library and EQ call it from their own palette painters. The close is the same
  un-drawn 40×26 corner hit area a borrowed frame gets (`closeButtonRect`), so views whose content
  is a subview that eats clicks (Audio Analyzer's SwiftUI panes, Sonos's status line) override
  `hitTest` to claim it; the library moves its server-bar right-edge items in by `cornerCloseInset`.
  The EQ is a fixed 275x116 layout, so its old band stays as ground inside a thinner rim, clipped
  to `glossOutline` so it does not show as square corners outside the rounded rim.
  `hostedGroundRect` returns the gloss hole, not `bounds`: PeppyMeter (and Cava, Flow) paint their
  ground through it, and a full-window fill showed as square black corners outside the rounded rim. `.wal`
  shares every one of these painters and, since 2026-09-26, the gate too: it is true in `.wal` once
  the skin's palette has loaded (see `winamp-modern-skin-guide/reference/components.md` §
  *NullPlayer-owned hosted windows are lazy*). Classic and Original never reach it.
- **A player the skin gives no close gets an invisible one (2026-09-26).** WMP drew a Windows title
  bar around a view unless it wrote `titleBar="false"` (about 30 archives do), so a skin that
  relied on that frame authors no close — `Classic` is a rectangle with a "Return to Full Mode"
  toggle and nothing else, and here every `.wmz` window is borderless. The reporter rejected a macOS
  title bar and asked for *"a buttonless target area"*: `WMPCloseControl.authorsClose` scans the
  definition and every script for any close (`<id>.close(`, bare `close()`, `closeView(`,
  `<closeButton>`; `player.close()` is not one) and, when there is none, the **player** view sets
  `WMPMainView.closeTargetEnabled` — an undrawn 16x16 top-right corner, claimed in
  `WMPSkinWindow.sendEvent` ahead of the edge band, that runs `closeViewWindow` on a press and
  release inside it. A skin control in that corner keeps the press. The scan is skin-wide because a
  close is often indirect (the Skins Factory preference relay). Of 185 installed archives it fires
  on `Classic`, `Alpine7618_v09`, `Cubist`, `Stealth` and the excluded `Darkling`.
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
[architecture analysis](../../../../docs/wmp-skin/hosted-window-architecture-analysis.md) first proposed a
`WMPHostedSurfaceContainer` owning composition, placement and hit testing for all eight windows, with
a content protocol, adapters, a presentation state machine, a second border coordinator and a
migration of `PlexBrowserView`. **It is withdrawn, and re-proposing it needs new evidence.** It was
priced against a defect population nobody had measured, its state/identity work landed in
`App/Skinning/` — shared with Winamp Modern and with playlist/EQ, which it did not migrate — and it
would have made the failures uniform rather than fewer. What the document now carries is WMP-local
incremental correction plus **one narrowly named helper under `Windows/WMPSkin/` where several WMP
call sites need the same conversion corrected**. That helper is in scope; the framework is not.
It does not replace the implemented contract above. The mechanism notes in `windows/hosted-chrome.md` retain measured
counterexamples and rejected approaches.
