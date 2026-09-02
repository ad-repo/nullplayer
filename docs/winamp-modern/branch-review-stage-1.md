# Branch review — Stage 1: blast radius of shared code

**Scope:** `feat/winamp-modern` at `3e871eb9` against `origin/main` at `56c198ec`.
**Ran:** 2026-09-02. **Plan:** `~/.claude/plans/i-am-getting-ready-reactive-brooks.md` §Stage 1.

This is the record Stage 1 exists to produce: every shared-code change outside
`WinampModern/` and `Windows/WinampModern/`, classified as **gated**, **inert-by-construction**,
or **ungated**, with a disposition for each ungated item.

---

## Premise (the `git fetch` the plan owed)

`git fetch origin` was run for the first time in this review cycle. The remote is unchanged and
every number in the plan held exactly:

| | |
|---|---|
| `origin/main` | `56c198ec` (unchanged) |
| ahead / behind | **256 / 0**, merge-base *is* `origin/main` |
| diffstat | **348 files, +98,602 / −1,498** |
| shared files outside the engine | **34** (32 `.swift` + 2 notices) |
| hunks at `-U0` | WindowManager **180**, ContextMenuBuilder **24**, EQView **23** |
| `swift test` | **1688 tests, 12 skipped, 0 failures, 22.4 s** |

**Stage 0 was not run.** Its corpus baseline (`/tmp/sweep/base`, the self-diff noise floor) does
not exist. Stage 1 does not need it — nothing here changes rendering, and its gate is a live pass
in Classic and Original. **Stage 2 must not start until Stage 0 is captured.**

---

## Method

Two mechanisms turned out to gate this branch's shared code, not one:

1. **A mode gate** — `uiMode.controllerFamily == .winampModern`, the one the plan and `CLAUDE.md`
   name.
2. **`hostedContext != nil`** — an ivar on seven shared window views, set *only* by
   `configureForHostedSurface(context:)`. That method has **8 call sites, all in
   `WinampModern/WinampModernHostedWindows.swift`**. It is therefore nil in Classic, Original and
   Metal, and every branch behind it is unreachable there. The plan's §1.5 did not name it.

Every added line in the three big shared files was mapped to its enclosing member by brace-tracked
parse, and each member checked for either mechanism. The residue was read by hand.

`git diff` line coverage: 1103 / 1504 added lines in `WindowManager.swift` fall inside members that
carry a gate; 442 / 500 in `ContextMenuBuilder.swift`; 236 / 326 in `EQView.swift`. The rest is the
list below.

---

## Dispositions — applied 2026-09-02

The product decision was made after this review was written: **Winamp Modern must not change Classic
or Original, full stop.** Every ungated item below was therefore gated or reverted rather than
argued, and the placement work that motivated it now lives behind one predicate:

```swift
// WindowManager
var appliesWinampModernPlacement: Bool { uiMode.controllerFamily == .winampModern }
```

| Finding | What was done |
|---|---|
| 1 — `correctedRestoredFrames(force:)` | Gated **at the call site** (`AppStateManager:923`) so the function stays pure and directly testable. Classic and Original restore their saved frames verbatim. |
| 2 — `snapToDefaultPositions` | Classic/Original limb **reverted to `origin/main`**: `screen.frame` restored, stack measurement, side-window clamps and the `applied()` rescue removed. The `.wal` recovery is unaffected — it lives in `snapWinampModernToDefaultPositions`, reached by the early return. `clearSavedWindowFramePositions()` and the six window accessors were **kept**, both having been verified behavior-identical. |
| 3 — `bringAllWindowsToFront` | Explicit stacking order restored; the function no longer reads its z-order from `managedWindowRecords`. Now byte-identical to `origin/main` apart from a comment explaining why. |
| 4 — Compact Mode restore | New `restoreCentreStackWindow(_:controller:window:show:)` prefers the per-feature controller and falls back to the routed path only when there is none — i.e. only for hosted `.wal` surfaces. Classic and Original are back on `restore(_:controller:)`. |
| 5 — the universal sweep | Gated at all four call sites **and** inside `ensureAllWindowsOnScreen` itself, so a caller added later cannot reintroduce it. `restoreWindowPositions`'s `onScreen()` helper is gated too. The three `ContextMenuBuilder` call sites were already inside `uiMode == .winampModern` blocks. |
| 6 — `mainFrameForModeSwitch` | Left universal. It is not a placement correction; it fixes an incoming window being drawn into the outgoing mode's box, which is a real bug in Classic ↔ Original switches too. Still to be confirmed in the live pass. |

**Tests:** `Tests/NullPlayerAppTests/WinampModernPlacementGatingTests.swift` — 6 tests. Three pin the
behavior the gate exists to contain (the forced correction moving a reachable parked session by
+180 pt and −135 pt, and a **Dock resize alone** tripping `savedScreenIsMissing`); one pins the
unforced path; one asserts the predicate is false in every mode but `.winampModern`, and fails rather
than passing vacuously if the edition refuses a mode assignment; one pins that docking-membership
order and stacking order are different lists.

`swift test`: **1694 tests, 12 skipped, 0 failures** (1688 + 6). `swift build` clean.

**What Classic gives up:** the off-screen-window rescue `f0e5dc14` shipped for it. That was a real
fix, and gating takes it back out. It should be re-proposed on its own PR against `main`, made
corner-consistent (see Finding 1), with its own Classic tests and live pass — not carried in under a
`.wal` branch. Recorded here so it is not simply lost.

**Still owed:** the live pass. Every claim above is static reading, `diff`, and unit tests; the
findings are window-geometry and window-ordering claims, and per `winampModern-never-affects-classic`
those have no useful armchair form.

---

## Findings

### FINDING 1 — `correctedRestoredFrames(force:)` re-places windows that are not stranded

**Ungated. Runs in all four modes. The one item here that is a defect rather than a judgment call.**

`AppStateManager.swift:1264`, reached from restore at `:919–921`.

The placement rule this branch introduces is defined on a window's **top-left corner**
(`WindowPlacement.isReachable`), and `WindowPlacement.swift` is explicit about why:

> it leaves the classic habit of parking a window mostly past the bottom or right edge intact —
> that window is *placed*, not stranded, and a sweep that yanked it back would be the bug.

The `force` path breaks that rule. `force` comes from `savedScreenIsMissing`, which compares the
saved `visibleFrame` to the current ones with **exact `NSRect` equality**. When it fires, the
correction runs over frames that are all perfectly reachable and routes them through
`WindowPlacement.rescued`, which uses **whole-rect containment** — so it moves them.

**Measured, not reasoned** (probe run against `3e871eb9`, then deleted):

```
screen = 1440×850
dock resize alone (visibleFrame 850 → 800) ⇒ savedScreenIsMissing = TRUE
force=true, both windows already reachable:
  main     {100, 400} 275×116  →  {100, 580}     cluster shifted +180
  playlist {100,-180} 275×232  →  {100,   0}
force=true, right-parked, already reachable:
  main     {1300, 700} 275×116 →  {1165, 700}    shifted −135
```

So: **a Classic user who resizes or hides their Dock has their whole saved layout moved on the next
launch**, undoing deliberate parking. This is B56's exact shape — a screen-measurement change made
for `.wal` placement moving Classic's windows.

Two things bound the blast radius, and neither removes it:

- `mainScreenVisibleFrame` is a new key, so the *first* launch after upgrade has `nil` and
  `savedScreenIsMissing` correctly answers `false`. It fires from the second launch on.
- **The `force: true` path has no test.** All three existing `correctedRestoredFrames` tests in
  `Tests/NullPlayerAppTests/WindowRestoreGeometryTests.swift:385,404,433` pass `force: false`;
  `testAMissingSavedScreenForcesTheCorrection` only exercises `savedScreenIsMissing` itself, never
  the correction it gates.

**Disposition — for the user to decide, and the one blocking decision in this stage.** Three options:

1. **Gate `force` on `.winampModern`.** Smallest change; satisfies the branch rule outright. Costs
   Classic a bugfix that `f0e5dc14` deliberately shipped for it.
2. **Fix the inconsistency, keep it universal.** Make the `force` path corner-based like every other
   path — i.e. under `force`, still only move frames that fail `isReachable`. This is the option
   that makes the code agree with its own documented rule. Note it narrows what `force` does to
   almost nothing, since a session saved on a screen that is genuinely gone already has unreachable
   frames and trips `stranded` without help from `force`.
3. **Keep as is** and accept that a Dock resize re-lays-out a Classic session.

Recommendation: **(2)**, with a regression test on the `force: true` path either way.

### FINDING 2 — `snapToDefaultPositions` changes Classic's Snap To Default in four ways

**Ungated for the classic/original limb.** `WindowManager.swift`, 27 hunks / 72 lines — the most
heavily edited shared function on the branch.

The Winamp Modern limb is cleanly separated (`if uiMode.controllerFamily == .winampModern { … return }`
at the top, into `snapWinampModernToDefaultPositions`). Everything below that early return is the
path Classic and Original still run, and it changed:

1. **`screen.frame` → `screen.visibleFrame`.** This reverses a deliberate prior choice whose comment
   said so — *"Use full screen frame (not visibleFrame) so windows aren't constrained by menu
   bar/dock."* Every Classic Snap To Default result now lands inside the visible frame. **This is the
   single most B56-shaped line in the diff.**
2. **Stack-overrun top-anchoring.** `visibleCenterStackHeightBelowMain()` is measured up front, and
   when the stack would not fit the main window anchors to the visible top instead of centring.
   Changes Classic's snap layout whenever the stack is tall.
3. **Side-window clamps.** The Plex browser is clamped to `screenFrame.maxX - w` and the visualizer
   to `screenFrame.minX`; previously both were pure arithmetic off `mainFrame`.
4. **An `applied()` rescue** wrapped around every frame before it is set.

All four are defensible as bugfixes for the same "windows with no way back" class. None is gated.

**Verified safe within this function:** the six accessor swaps
(`spectrumWindowController?.window` → `spectrumWindow`, and the same for waveform, audioAnalysis,
peppyMeter, networkMonitor, cava) are **inert-by-construction** — each is doubly guarded
(`winampModernHostedController` is itself `guard uiMode.controllerFamily == .winampModern`) and falls
through to the original controller window in every other mode. And the extracted
`clearSavedWindowFramePositions()` key set is **byte-identical** to the inline list at `origin/main`
(11 keys, verified by diff).

**Disposition:** these are the items Verification §3's live Classic pass exists to catch. Decide with
Finding 1 — the same question (universal bugfix vs gated) with the same answer.

### FINDING 3 — the managed-window registry reorders `bringAllWindowsToFront`

**Ungated. User-visible in Classic.**

`allWindows()`, `dockableWindows()`, `snapTargetWindows()`, `isDockableWindow()` and
`bringAllWindowsToFront()` were rewritten to read from a new `managedWindowRecords` registry
(`WindowManager.swift:634`) instead of hardcoded controller lists.

**Membership is preserved exactly** — verified against `origin/main` member by member:

| | old | new | verdict |
|---|---|---|---|
| `dockableWindows()` | 9 windows | `centerStack && isVisible` → same 9, same order | identical |
| `snapTargetWindows()` | 11 | `snapTarget && isVisible` → same 11, same order | identical |
| `isDockableWindow()` | 9 explicit identity checks | `centerStack` → same 9 | identical |
| `allWindows()` | 12 | same 12, **different order** | **changed** |

`bringAllWindowsToFront` orders windows front in sequence, so the sequence *is* the z-order, and its
own comment calls it load-bearing (*"Keep a predictable base order"*). It changed:

```
old: main, EQ, playlist, spectrum, audioAnalysis, peppy, network, cava, waveform, video, projectM, library
new: main, playlist, EQ, spectrum, audioAnalysis, peppy, network, cava, waveform, library, projectM, video
```

Two swaps that a Classic user can see: **the equalizer now raises above the playlist** where it used
to sit below it, and **the video window now raises above the visualizer and the library** where it
used to sit below both.

**Disposition:** almost certainly unintended — the registry refactor was for the `.wal` managed
graph, and the reordering is a side effect of the declaration order in `managedWindowRecords`.
Cheapest correct fix: give `bringAllWindowsToFront` an explicit order rather than the registry's, or
reorder the `add(…)` calls to match the old list. Confirm in a live Classic session (open EQ +
playlist overlapping, click the main window).

### FINDING 4 — Compact Mode exit routes six Classic windows through a different restore path

**Ungated.** `restoreRegularWindowSnapshot`, `WindowManager.swift:2243`.

The inner `restore(_:controller:)` helper is **byte-identical** to `origin/main`. But spectrum,
audioAnalysis, peppyMeter, networkMonitor, cava and waveform were moved off it onto a new
`restoreRouted(_:window:show:)`, in **all** modes:

- old: `restore(snapshot.spectrum, controller: spectrumWindowController)` — `setFrame` then `orderFront`.
- new: `restoreRouted(snapshot.spectrum, window: spectrumWindow, show: showSpectrum)` — calls the
  full `showSpectrum(at:)` path.

The equalizer keeps the old path in Classic (`if equalizerWindowController != nil` picks `restore`).
The six visualization-family windows do not.

`show…(at:)` does more than `setFrame` + `orderFront` — it can re-register, restart rendering, post
layout notifications and re-dock. Plausibly an improvement; it is still a Classic behavior change on
a path the plan's Verification §3 explicitly covers.

**Disposition:** exercise Compact Mode enter/exit in Classic with all six windows open, and confirm
frames and docking come back as before. Note this is also the path Stage 3's `WindowManager`
extraction will move — take the reading **before** those commits, per the plan's §3 note.

### FINDING 5 — the universal on-screen sweep (accepted, ungated, well-behaved)

`ensureAllWindowsOnScreen()` (`:5318`), `rescuedOrigin(for:)` (`:1534`),
`restoreWindowPositions()` (`:7391`), and the new `ensureAllWindowsOnScreen()` call at the end of
`applyUIScaleLevelChangeIfNeeded` (`:4309`). Also wired to
`NSApplication.didChangeScreenParametersNotification` via a coalesced
`handleScreenParametersDidChange` (`:817`).

All ungated, all running in Classic. **Read and cleared**: unlike Finding 1, every one of these is
consistently **corner-based** — `ensureAllWindowsOnScreen` skips any window that already passes
`isReachable`, and `rescuedOrigin` returns `nil` for one, so the per-member rescue loop cannot yank a
deliberately parked window. `restoreWindowPositions`'s `onScreen()` helper does the same. These obey
the rule Finding 1 breaks.

Residual, accepted by design: when *one* window in a docked cluster is stranded, the whole cluster
takes the offset, deliberately parked members included. That is the documented docking-preservation
tradeoff and it is the same in every mode.

**Disposition:** keep universal. This is the shape Finding 1 should be fixed into.

### FINDING 6 — `mainFrameForModeSwitch` applies to every mode switch

`WindowManager.swift:6751`. Ungated static. Keeps the outgoing window's origin and substitutes the
incoming mode's own size, anchored top-left. Affects Classic ↔ Original switches too, not only
switches involving `.wal`.

**Disposition:** intended and correct — the bug it fixes (a 275×116 classic skin drawn inside a
197×297 window) is not `.wal`-specific. Confirm in the live pass by switching Classic ↔ Original at
100% UI Size.

---

## Cleared — read and found safe

| Plan item | Verdict |
|---|---|
| **§1.1 `VisualizationContextMenu.swift`** (368 lines, 0 mode gates) | **Clean.** See below. |
| **§1.3 `SkinLoadingOverlay`** (150 lines, 0 gates) | **Clean.** See below. |
| **§1.5 the repeated chrome branch** (7 views) | **Inert-by-construction ×2.** See below. |
| **§1.6 the isolation rule** | **Holds.** See below. |
| `EQView.swift` (+326, 23 hunks) | **Zero ungated behavior changes.** Every addition sits behind `hostedContext != nil`; `metrics` returns `.classic` when not hosted, so `hitTestSlider` / `updateSlider` / `convertToOriginalCoordinates` / `scaleFactor` keep every classic constant. The `WinampModernHostedSurface` extension is reachable only through the hosted registry. |
| `ContextMenuBuilder.swift` (+500, 24 hunks) | Ungated residue is **only** the `SkinLoadingOverlay.shared.run { … }` wrappers around the existing skin/mode loads and three `ensureAllWindowsOnScreen()` calls — i.e. Findings 3/5 and §1.3, nothing new. |
| `stepProjectMPreset`, `restorableProjectMPresetIndex` | Additive `else if let visView = hostedProjectMView?…` fallback; the classic first branch is unchanged. |
| `toggleLocalProjectMWindow`, `showOrToggleLocalVideoWindow` | New private helpers, called only from `.wal` surface routing. |
| `UIScaleLevel.nearest(toScaleFactor:)` | New static for a `.wal` skin's `setScale`; no classic caller. |
| `toggleHideTitleBars`, `effectiveHideTitleBars` | Guarded by `isRunningModernUI`; the added lines are the `managedWindowRecords` swap (see Finding 3 — membership preserved). |

### §1.1 — `VisualizationContextMenu.swift`: the plan's prior was right to be lowered

The plan flagged this as possibly the sharpest item: 368 ungated shared lines created while deleting
319 from `ProjectMView` and 319 from `ModernProjectMView`. Read line by line, **it is a faithful
extraction and nothing was lost.**

- **The two deleted bodies were byte-identical to each other** — `diff` over both gives only the
  class name, five trailing-whitespace lines, and one function's position in the file. Classic and
  Original were already running the same menu code, duplicated. There was no asymmetric merge for
  anything to be lost in.
- `build()` is that body with mechanical substitutions only: `self` → `target`,
  `visualizationGLView` → `glView`, `presetRatingsStore` → `ratingsStore`
  (both `ProjectMPresetRatingsStore.shared`), `presetCycleMode/Interval` → `options.…`, and
  selectors qualified to the protocol. Every item title, order, `keyEquivalent`, `tag`,
  `representedObject`, `state` and `isEnabled` is unchanged. `starString(for:)` is character-identical
  to the deleted private copy.
- `addGeissEffects` / `addTripexEffects` are line-for-line the deleted
  `addGeissEffectsMenuItems` / `addTripexEffectsMenuItems`.
- **The only behavioral delta** is that Fullscreen and Close became `Options.showsFullscreen` /
  `showsClose`, both defaulting to `true`. Both the `ProjectMView` and `ModernProjectMView` call sites
  omit them, so Classic and Original get the identical menu. Only
  `WinampModernVisualizationSurfaceView` passes them explicitly.

Still owed: the live right-click check in Classic and Original (Verification §3).

### §1.3 — `SkinLoadingOverlay`

Ungated by design (it shows for any skin or mode switch, in any mode; `ed41847e` says so). It
**cannot linger and cannot steal a click**: `run` is `rethrows` with `defer { hide() }` so a throwing
load still hides it; `ignoresMouseEvents = true`; `.nonactivatingPanel` + `orderFrontRegardless` so it
never takes focus; re-entrant via a depth counter. Only caveat: `run` is synchronous, so a load that
schedules further async work hides the overlay early — cosmetic. **Confirmed intended, no action.**

### §1.5 — the repeated chrome branch: do **not** factor it yet

The `if let style = WindowManager.shared.winampModernSurfaceStyle { … } else { …classic… }` shape
appears in all seven views, and both limbs are safe:

- `winampModernSurfaceStyle` (`:940`) is **doubly guarded** — `controllerFamily == .winampModern`
  *and* a successful cast to `WinampModernMainWindowController`. It is `nil` in every other mode.
- The `else` limbs were checked against `origin/main` in all seven files. Every difference is
  re-wrapping (`let renderer = X; renderer.f(…)` collapsed to `X.f(…)`, arguments reflowed) or a
  dropped comment. Same call, same arguments, same order, in all seven.
- The related additions behind `hostedContext != nil` are inert as described under *Method*.
- The `.winampModernThemeDidChange` observer these views register in every mode is inert: the
  notification is posted only from `Windows/WinampModern/`.

**Judgment: leave it.** The plan's §1.5 says to factor it "if it is" byte-identical, and it is not —
each view calls a different renderer entry point (`drawSpectrumAnalyzerWindow` vs
`…ChromeOverlay`), with a different title, a different `pressedButton` expression, and in Cava's case
`currentRenderer()`; the modern limb differs by `metrics` and `fillBackground`. Factoring it is a real
refactor with a modest payoff and no sweep coverage of these windows. It belongs in Stage 3's
restructuring, not here.

### §1.6 — the isolation rule holds

`CLAUDE.md`'s rule binds `ModernSkin/` and `Windows/Modern*/`. Grepped for `Skin/` and
`Windows/MainWindow/` types in both: **every hit is a comment** (seven files whose headers assert
"ZERO dependencies on the classic skin system"). The branch adds no new reference — diffing only the
added lines in those directories for `SkinRenderer|SkinLoader|SkinElements|SkinManager|MainWindow*`
returns nothing.

**Recorded, not a violation:** `WinampModern/` *itself* references `Skin/`'s `SkinElements` in three
files — `WinampModernHostedWindows.swift` (21), `WinampModernChrome.swift` (9),
`WinampModernSurfaceStyle.swift` (4). The rule does not bind `WinampModern/`, and the use is
deliberate: the hosted-window registry reuses classic window geometry constants so a hosted surface
matches its standalone counterpart. Worth knowing before Stage 3 moves any of it. No
`Windows/MainWindow/` type is referenced anywhere in the engine.

---

## What Stage 1 leaves owed

1. **A decision on Finding 1**, and with it Finding 2 — gate, fix, or accept. This is the one item
   that should not be carried into the cut undecided.
2. **Finding 3** is a probable unintended regression with a one-line-ish fix.
3. **The live pass** in Classic and Original (Verification §3). Nothing in Stage 1 was proved in a
   running app — every claim above is a static reading, a `diff`, or a unit-level probe. Findings 2,
   3 and 4 are window-geometry and window-ordering claims, and per
   `winampModern-never-affects-classic` those have no useful armchair form. Specifically:
   - Snap To Default in Classic, with a tall stack and with the Plex browser open (Finding 2).
   - EQ + playlist overlapping, click the main window, observe z-order (Finding 3).
   - Compact Mode enter/exit with all six visualization-family windows open (Finding 4).
   - The visualization right-click menu in Classic and Original (§1.1).
   - Classic ↔ Original switch at 100% UI Size (Finding 6).
   - Restore after a Dock resize, in Classic (Finding 1).
4. **Stage 0** — still not captured. Required before Stage 2.
