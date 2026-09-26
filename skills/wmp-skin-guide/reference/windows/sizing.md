# `.wmz` windows: who sizes a window

Moved verbatim from `reference/windows.md` on 2026-09-25; that file is the router. Read it first.

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
validating a rectangle that does not survive the next statement. See `windows/placement.md` § *Window placement and
recovery* for the two seams that own reachability instead.
