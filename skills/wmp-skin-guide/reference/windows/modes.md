# `.wmz` windows: mode switching and presentation

Moved verbatim from `reference/windows.md` on 2026-09-25; that file is the router. Read it first.

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
   one. See *A restored `.wmz` window keeps the size it saved* in `windows/sizing.md`.
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

**What is still there and was deliberately not taken**: `selectClassicSkin` (`ContextMenuBuilder.swift`)
branches on the same two-way predicate, so in WMP it takes the "already in classic mode" branch and
loads a classic skin without switching family — the user picks a skin and nothing visible happens.
Same class, one more site, and W214's own rule says not to gate it in the same sweep.
(`loadDefaultClassicSkin` had the same defect; it was deleted with the Default Skin menu entries.)

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
