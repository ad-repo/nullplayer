# `.wmz` views: sizing, opening, switching and closing

Moved verbatim from `reference/rendering.md` § *Static scene and image contracts* on 2026-09-25; the router is
`reference/rendering.md`. Before an engine-wide change here, check the counter-evidence table in
`reference/skins/README.md`.

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

- **A view the skin never shows can still have to keep running, and a view it only covered has to come back as it was left.** Two different things this engine used to treat the same way — "not the presented view, therefore gone" — and each is a whole class of dead controls. **A windowless view that declares `timerInterval` + `onTimer` is a *dispatcher*** (W89): 24 of the 180 archives author `<view id="controlView" timerInterval="100" onTimer="checkRemoteViewStatus()">` and route their panel, minimize and close buttons through it — the button does not call the host at all, it writes `theme.savePreference('remoteCallPl','true')` and that handler reads it back. Real WMP keeps it open beside the player. `WMPMainWindowController.adoptDispatcher` **scans** for it after presenting; keying it off the candidate walk works only on a profile with no persisted view, because `wmpSkinViewID` is written on every present and the walk then stops at the player. **The same skip hid its `onLoad` (W299)**: the family's `onLoadSkin()` is where the panels the user left open are re-opened from `plViewer`/`eqViewer`/…, so from the second launch on they never opened while the preference still said `"true"`, and each panel button's `toggleView` took two clicks. `adoptDispatcher` now runs the dispatcher's `load` itself when the walk did not visit it (`runSkippedDispatcherLoad`) and applies its commands against the player minus the player's own `openView` — the route the walk's deferred commands take. `launch.sh` deletes `wmpSkinViewID`, so it can only reach the first-launch path; to see the second, launch with the persisted view left in place. It runs through `WMPScriptRuntime.dispatch`, which commits no overrides and does not consume the observable-property changes — a dispatcher has no window, so it has no scene — and its elements are swapped in and the presented view's swapped back, objects and all, because every view root is called `view`. **And `theme.openView` opens a *second window*: the opener is never touched** (W90). That used to be simulated — the covered view's overrides, its timer period and its animation clock were stashed and a `closeView` return was a *restore* rather than a load, because rebuilding it discarded the overrides its script had accumulated and reinstated the markup `timerInterval` the script had overridden. On `Alienware Invader` that returned to `commands=0` and let the markup's 500 ms re-fire `toggleShutter()` with `introStatus` already true, shuttering the whole player; reported as "closing an interior window closes the whole UI". **The simulation is gone and so is everything built on it** — `CoveredView`, `openedViewStack`, `switchView(to:restoring:)` and `WMPScriptRuntime.prepareForRestore` — because the opener is now genuinely still running in its own window, which is what the restore was imitating. What survives is the primitive underneath: `WMPScriptContext.restoreElements(for:)` swaps each window's live elements in for the length of its own transaction, since one `JSContext` serves them all and every view root is called `view`. A genuine view change still loads exactly like a launch (W46).

- **A view arrived at by a switch loads exactly like one arrived at by launch, and a `.wmz` compact mode is built entirely out of that.** `switchView(to:)` raises `load` on the new view, applies the host commands the handler posts — *after* `apply`, which sets the view timer from markup, so the script's `setViewTimerInterval` is the override and not the other way round — and schedules its `timerRequests`. It did none of the three for a long time (W46), and Corona's `viewTiny` is authored `timerInterval="0"` and animates itself into the mini player from `OnTinyLoad` alone: the switch happened, nothing ran, and the compact view drew **the same artwork at the same size as the player**. The only visible symptom was the playlist and equaliser drawers going away, because `viewTiny`'s markup does not have them. Two consequences bind: the initial-load `collapsed` guard applies here too, since a view can now blank itself in an `onLoad` this path finally runs; and `viewchange` is dispatched only when the markup authors a handler, because a transaction's `timerRequests` are what *that* transaction registered and an unconditional binding-only one posts an empty set that cancels what `load` just scheduled.

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

- **`visible` is not a `<VIEW>` attribute (W281).** The root's authored `visible="false"` is
  ignored; a script override still applies. `gnome` is the only corpus view that authors it, never
  shows itself from script, and loads in WMP — honouring it drew 0 nodes and an empty window.
  **This is not proven WMP behaviour and the corpus argues both ways** — `portals` and
  `modernblue` also show children inside closed containers (a pane choice in a shut tray, a play
  button on a hidden compact face) where inheritance is what the skin wants. The before/after sweep
  moved 3 of 529 images (`portals/mode1`, `modernblue/myview`, `US Army/MainPlayer`); the reporter
  reviewed all three and accepted them, the one visible cost being W264. Most of this pattern fires
  only on a click or play-state change, so a clean load-time sweep does not clear it — check a
  reported stray pane against this rule first. **Both of those two are now bounded (2026-09-26):**
  an authored-hidden container the skin's own code can show (`WMPLoadedSkin.scriptShowableIDs`)
  closes its subtree until it is shown, which took `modernblue`'s small pause off the large display
  and `portals`' EQ out of its shut drawer; `help`, only ever hidden by script, still passes
  through. See `skins/modernblue.md`.

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
